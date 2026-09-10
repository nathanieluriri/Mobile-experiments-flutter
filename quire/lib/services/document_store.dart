import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/library.dart';
import '../format/document_loader.dart';
import '../model/document.dart';
import '../model/search.dart';
import '../pdf/display_list.dart';
import '../pdf/document.dart';
import '../pdf/writer.dart';
import 'library_catalogue.dart';
import 'picture.dart';
import 'reading_time.dart';
import 'render_plan.dart';

/// Where a document is in its journey from bytes to something readable.
enum ParseState { loading, ready, failed }

/// The three shelves on the desk.
enum Shelf { all, reading, signed }

/// A signature that has been set into a page.
///
/// The strokes are normalised inside [rect] rather than stored in page points,
/// so a mark keeps its shape when a page is drawn at any scale, and a page
/// that has not been laid out yet can still hold one.
class PlacedSignature {
  const PlacedSignature({
    required this.pageIndex,
    required this.rect,
    required this.strokes,
    this.encoded,
    this.picture,
  });

  /// The page the mark belongs to, zero based.
  final int pageIndex;

  /// Where the mark sits in page space, in logical points.
  final ui.Rect rect;

  /// Each stroke as points in the unit square of [rect]. Empty for a mark
  /// that is a picture.
  final List<List<ui.Offset>> strokes;

  /// The picture's own file, for a mark that is one.
  final Uint8List? encoded;

  /// That picture decoded, once somebody has decoded it. A mark read back
  /// from an earlier run arrives without one and gets it a moment later,
  /// which is a moment the page spends drawing everything else.
  final ui.Image? picture;

  /// The same mark, now that its picture has been decoded.
  PlacedSignature withPicture(ui.Image decoded) => PlacedSignature(
        pageIndex: pageIndex,
        rect: rect,
        strokes: strokes,
        encoded: encoded,
        picture: decoded,
      );

  /// The mark as plain numbers, for the desk to write down.
  Map<String, Object?> toJson() => <String, Object?>{
        'page': pageIndex,
        'rect': <double>[rect.left, rect.top, rect.width, rect.height],
        'strokes': <Object?>[
          for (final stroke in strokes)
            <Object?>[
              for (final point in stroke) <double>[point.dx, point.dy],
            ],
        ],
        if (encoded != null) 'picture': base64Encode(encoded!),
      };

  /// The mark read back, or null for numbers that do not make one.
  static PlacedSignature? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final page = json['page'];
    final rect = json['rect'];
    final strokes = json['strokes'];
    if (page is! int || rect is! List<Object?> || strokes is! List<Object?>) {
      return null;
    }
    final box = _doubles(rect);
    if (box == null || box.length != 4) return null;
    final picture = json['picture'];
    Uint8List? bytes;
    if (picture is String && picture.isNotEmpty) {
      try {
        bytes = base64Decode(picture);
      } on FormatException {
        return null;
      }
    }
    final marks = <List<ui.Offset>>[];
    for (final stroke in strokes) {
      if (stroke is! List<Object?>) return null;
      final points = <ui.Offset>[];
      for (final point in stroke) {
        final pair = point is List<Object?> ? _doubles(point) : null;
        if (pair == null || pair.length != 2) return null;
        points.add(ui.Offset(pair[0], pair[1]));
      }
      marks.add(points);
    }
    return PlacedSignature(
      pageIndex: page,
      rect: ui.Rect.fromLTWH(box[0], box[1], box[2], box[3]),
      strokes: marks,
      encoded: bytes,
    );
  }

  static List<double>? _doubles(List<Object?> raw) {
    final out = <double>[];
    for (final value in raw) {
      if (value is! num) return null;
      out.add(value.toDouble());
    }
    return out;
  }
}

/// One open document: what was parsed, where the reader is in it, and what
/// they have done to it.
///
/// It is a [ChangeNotifier] rather than something smaller because the reader,
/// the fore edge, the folio chip and the desk card all watch the same position
/// and must never disagree about it.
/// What a reader has fastened down while they read.
///
/// Reading is done in places where the screen is being touched by more than
/// the one finger doing the reading: on a bus, lying down, handing the phone
/// to somebody else. Both of these exist so that a reading survives that.
enum ReaderLock {
  /// Nothing is fastened. The reading behaves as it always has.
  none,

  /// The way out. Back does nothing and the edge swipe does nothing, so the
  /// document cannot be closed by the heel of a hand.
  back,

  /// The page as well. The reading is pinned where it is, every bar goes, and
  /// what is left on the screen is the page and nothing else.
  page;

  /// True when leaving the document is fastened.
  bool get holdsBack => this != ReaderLock.none;

  /// True when the page itself is fastened, which is also what clears the
  /// screen: a bar you cannot use is a bar in the way.
  bool get holdsPage => this == ReaderLock.page;
}

/// How big the page is drawn, said as an intention rather than a number.
///
/// A named fit survives a page of a different size, which a number does not:
/// a document whose pages change shape halfway through still fits its width
/// on every one of them.
enum FitMode {
  /// The page fills the width it is given. The reading default, because a
  /// line of type you have to scroll sideways to finish is not a line you can
  /// read.
  width,

  /// The whole page on screen at once, however small that makes it. What you
  /// want when the shape of the page is the thing you are looking at.
  page,

  /// One point of the page to one point of the screen, which is the size the
  /// page was drawn to be printed at.
  actual,

  /// Whatever the last pinch left it at.
  free;

  /// True when the reader set the size by hand and no rule should take it
  /// back off them.
  bool get byHand => this == FitMode.free;
}

/// The smallest and largest a page may be drawn, as a multiple of its fit to
/// the width.
///
/// The floor is a whole page still being worth looking at. The ceiling is set
/// by what a phone can hold: past about six times, a line of type is a few
/// words long and the reading is all thumb.
const kZoomMin = 0.5;
const kZoomMax = 6.0;

/// What a double tap takes the page to, and back from.
const kZoomDoubleTap = 2.4;

/// The range the type may be scaled over for a document with no pages.
const kTextScaleMin = 0.8;
const kTextScaleMax = 2.2;
const kTextScaleStep = 0.1;

class DocumentStore extends ChangeNotifier {
  DocumentStore(this.entry);

  /// A store already holding a parsed document, for tests and for fixtures.
  factory DocumentStore.ready(LibraryEntry entry, Uint8List bytes) =>
      DocumentStore(entry)..loadFrom(bytes);

  /// The desk entry this document came from.
  final LibraryEntry entry;

  /// What is fastened down, which is not remembered between runs.
  ///
  /// A document that opened locked, with nothing on screen saying why and no
  /// memory of having done it, would be a document that looked broken.
  ReaderLock _lock = ReaderLock.none;

  /// How the page is sized, and the number behind it when the reader set it
  /// by hand.
  FitMode _fit = FitMode.width;
  double _zoom = 1;

  /// How large the type is set for a document with no pages of its own.
  double _textScale = 1;

  /// True while the loupe is following the finger.
  bool _magnifier = false;

  ParseState _state = ParseState.loading;
  LoadedDocument? _loaded;
  DocSearch? _search;
  PdfLocked? _locked;
  PdfFile? _pdf;
  int _position = 0;
  int _pdfPageCount = 0;
  bool _opened = false;
  int _opens = 0;
  int _lastOpened = 0;
  final Map<int, int> _pageWords = <int, int>{};
  final Set<int> _dogEared = <int>{};
  final List<PlacedSignature> _signatures = <PlacedSignature>[];

  /// Parses [bytes] and moves the store to [ParseState.ready] or
  /// [ParseState.failed]. Every exception the parsers raise is already caught
  /// at the loader boundary, so this never throws.
  ///
  /// [password] is only ever the one somebody typed into the password sheet.
  /// The engine tries the empty password on its own first, every time, so a
  /// file that carries only an owner password opens here with nobody asked
  /// for anything.
  void loadFrom(Uint8List bytes, {String password = ''}) {
    _loaded = DocumentLoader.load(bytes, entry.fileName);
    _search = null;
    _locked = null;
    _pdf = null;
    _state = _loaded!.failed ? ParseState.failed : ParseState.ready;
    if (_loaded!.isPdf && !_loaded!.failed) _openPdf(bytes, password);
    // A place remembered from an earlier run was remembered against a
    // document that could be laid out. If this one has fewer units now, the
    // place is pulled back inside it; if it cannot be laid out at all, which
    // is a locked file waiting for its password, the place is kept for when
    // it can.
    if (_state == ParseState.ready && _locked == null && unitCount > 0) {
      _position = _position.clamp(0, unitCount - 1);
    }
    notifyListeners();
    unawaited(decodePictures());
  }

  /// Tries [password] against a document that asked for one.
  ///
  /// It is a whole reload rather than a patch to the open file, because the
  /// key decides how every byte in the document is read: an object resolved
  /// while the file was locked was resolved in cipher text, and keeping it
  /// would leave a page that opens to noise.
  void unlock(String password) {
    final bytes = _loaded?.bytes;
    if (bytes == null || bytes.isEmpty) return;
    loadFrom(bytes, password: password);
  }

  /// Opens a page file and reads its page count from its own page tree.
  ///
  /// It happens here rather than in the reader so a PDF nobody has opened
  /// still prints `6 PAGES` on its card. Only the count is taken: the pages
  /// themselves are not run, because six documents' worth of content streams
  /// is not a price the first frame of the desk should pay.
  ///
  /// The open file is kept, and that is what makes the password flow work.
  /// A password opens a file, not a document, and reopening the bytes later
  /// would need the password again: keeping the file instead means quire
  /// never has to hold on to what somebody typed.
  void _openPdf(Uint8List bytes, String password) {
    try {
      final file = PdfFile.open(bytes, password: password);
      _pdf = file;
      _pdfPageCount = file.pageCount;
    } on PdfLocked catch (locked) {
      // Not a failure. The file is intact and this reader simply does not hold
      // the key yet, which is a question rather than an error.
      _locked = locked;
      _pdf = null;
      _pdfPageCount = 0;
    } on Object {
      // A file that opens as bytes but not as a page tree keeps no count, and
      // the card prints its format and its size alone. The reader decides
      // what a page nobody can lay out looks like.
      _pdf = null;
      _pdfPageCount = 0;
    }
  }

  /// Records a failure that happened outside the loader, for instance a bundle
  /// that could not hand over the bytes at all.
  void fail(Object error) {
    _loaded = LoadedDocument(
      name: entry.fileName,
      format: entry.format.extension,
      bytes: Uint8List(0),
      error: error,
    );
    _state = ParseState.failed;
    notifyListeners();
  }

  ReaderLock get lock => _lock;
  set lock(ReaderLock value) {
    if (value == _lock) return;
    _lock = value;
    notifyListeners();
  }

  FitMode get fit => _fit;

  /// The size the page is drawn at as a multiple of its fit to the width,
  /// which only means anything while the reader is holding the size by hand.
  double get zoom => _zoom;

  /// Puts the page at a named size, and forgets whatever number was there.
  set fit(FitMode value) {
    if (value == _fit) return;
    _fit = value;
    notifyListeners();
  }

  /// Puts the page at a size the reader chose, which is what a pinch does.
  void zoomTo(double value) {
    final wanted = value.clamp(kZoomMin, kZoomMax);
    if (wanted == _zoom && _fit == FitMode.free) return;
    _zoom = wanted;
    _fit = FitMode.free;
    notifyListeners();
  }

  double get textScale => _textScale;
  set textScale(double value) {
    final wanted = value.clamp(kTextScaleMin, kTextScaleMax);
    if ((wanted - _textScale).abs() < 0.001) return;
    _textScale = wanted;
    notifyListeners();
  }

  bool get magnifier => _magnifier;
  set magnifier(bool value) {
    if (value == _magnifier) return;
    _magnifier = value;
    notifyListeners();
  }

  ParseState get state => _state;

  /// The parsed document, or null for a PDF and for a failure.
  QuireDocument? get document => _loaded?.document;

  /// The original bytes, which is what a PDF is opened from.
  Uint8List get bytes => _loaded?.bytes ?? Uint8List(0);

  /// What went wrong, or null.
  Object? get error => _loaded?.error;

  /// True when this document belongs to the page engine.
  bool get isPdf => _loaded?.isPdf ?? entry.format == DocFormat.pdf;

  /// The page file, open and decrypted, or null for anything that is not a
  /// readable PDF.
  PdfFile? get pdf => _pdf;

  /// The encryption this document is behind, or null when there is none or
  /// when a password has already opened it.
  PdfLocked? get locked => _locked;

  /// True when a password was supplied and turned down, which is the one thing
  /// that separates the sheet's two messages.
  bool get wrongPassword => _locked?.wrongPassword ?? false;

  /// What sealed the file, for the sheet that has to name it. Empty when
  /// nothing did.
  String get cipher =>
      _locked?.cipher ??
      (_loaded?.error is ProtectedPackage
          ? (_loaded!.error! as ProtectedPackage).cipher
          : '');

  /// The rung this whole document is on, before any single page is looked at.
  ///
  /// A failed parse is [RenderPlan.damaged] here; a PDF's per page rung is
  /// decided later by `planFor` once its display list exists.
  RenderPlan get plan {
    final locked = _locked;
    if (locked != null) return planForLocked(locked);
    // A sealed Office package is intact, so it is never damage. There is no
    // password field for it either, because this version does not decrypt the
    // mechanism at all and a field would be an offer the app cannot keep.
    if (_loaded?.protected ?? false) return RenderPlan.unsupportedCipher;
    return _state == ParseState.failed ? RenderPlan.damaged : RenderPlan.rich;
  }

  /// The page engine's page count, which only the reader can supply.
  int get pdfPageCount => _pdfPageCount;
  set pdfPageCount(int value) {
    if (value == _pdfPageCount) return;
    _pdfPageCount = value;
    notifyListeners();
  }

  /// Pages for a PDF, rows for a grid, blocks for prose. It is the scale the
  /// fore edge and the position label are drawn against.
  int get unitCount {
    if (isPdf) return _pdfPageCount;
    final doc = document;
    if (doc == null) return 0;
    if (isGrid) {
      var rows = 0;
      for (final section in doc.sections) {
        for (final block in section.blocks) {
          if (block is TableBlock) rows += block.rows.length;
        }
      }
      return rows;
    }
    var blocks = 0;
    for (final section in doc.sections) {
      blocks += section.blocks.length;
    }
    return blocks;
  }

  /// True when the document is a spreadsheet or a CSV.
  bool get isGrid {
    final doc = document;
    if (doc == null) return false;
    for (final section in doc.sections) {
      for (final block in section.blocks) {
        if (block is TableBlock && block.grid) return true;
      }
    }
    return false;
  }

  /// Where the reader is, in units.
  int get position => _position;
  set position(int value) {
    final max = unitCount == 0 ? 0 : unitCount - 1;
    final next = value.clamp(0, max);
    if (next == _position) return;
    _position = next;
    _opened = true;
    notifyListeners();
  }

  /// True once the document has been opened, which is what puts it on the
  /// READING shelf and draws its progress track.
  bool get opened => _opened;

  /// How many times the document has been opened, which is what the back of
  /// its card prints. Moving the reader inside a document already open is not
  /// another opening, so only an arrival counts.
  int get opens => _opens;

  /// When the document was last opened, in milliseconds since the epoch, or
  /// 0 for one that never has been. Nothing draws it; the desk orders by it.
  int get lastOpened => _lastOpened;

  /// Marks the document as opened without moving the reader.
  void markOpened() {
    _opens++;
    _opened = true;
    _lastOpened = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// Everything the reader has done with this document, as plain numbers.
  Map<String, Object?> toJson() => <String, Object?>{
        'position': _position,
        'opens': _opens,
        'opened': _opened,
        'lastOpened': _lastOpened,
        'dogEared': _dogEared.toList()..sort(),
        'signatures': <Object?>[
          for (final mark in _signatures) mark.toJson(),
        ],
      };

  /// Takes back what [toJson] wrote, before or after the document has been
  /// read: a place beyond the end is pulled inside it once the file is known.
  void restore(Map<String, Object?> json) {
    final position = json['position'];
    final opens = json['opens'];
    final opened = json['opened'];
    final lastOpened = json['lastOpened'];
    final dogEared = json['dogEared'];
    final signatures = json['signatures'];
    if (position is int) _position = position < 0 ? 0 : position;
    if (opens is int) _opens = opens;
    if (opened is bool) _opened = opened;
    if (lastOpened is int) _lastOpened = lastOpened;
    if (dogEared is List<Object?>) {
      _dogEared
        ..clear()
        ..addAll(dogEared.whereType<int>());
    }
    if (signatures is List<Object?>) {
      _signatures.clear();
      for (final item in signatures) {
        final mark = PlacedSignature.fromJson(item);
        if (mark != null) _signatures.add(mark);
      }
    }
    if (_state == ParseState.ready && _locked == null && unitCount > 0) {
      _position = _position.clamp(0, unitCount - 1);
    }
    notifyListeners();
  }

  /// How far through the document the reader is, 0 to 1.
  double get progress {
    if (unitCount <= 1) return _opened ? 1 : 0;
    return (_position + 1) / unitCount;
  }

  /// What the card and the folio chip print: `4 / 6` for a PDF, `24 / 73` for
  /// a grid, `38%` for prose, because a block index means nothing to a reader
  /// while a percentage of a flowing document does.
  String get positionLabel {
    if (unitCount == 0) return '';
    if (isPdf || isGrid) return '${_position + 1} / $unitCount';
    return '${(progress * 100).round()}%';
  }

  /// The pages the reader has caught a corner on.
  Set<int> get dogEared => Set<int>.unmodifiable(_dogEared);

  /// Catches or releases the corner of [page].
  void toggleDogEar(int page) {
    if (!_dogEared.remove(page)) _dogEared.add(page);
    notifyListeners();
  }

  /// Every signature set into this document.
  List<PlacedSignature> get signatures =>
      List<PlacedSignature>.unmodifiable(_signatures);

  /// True when the document carries a signature, which is what puts it on the
  /// SIGNED shelf and draws the chip on its card.
  bool get signed => _signatures.isNotEmpty;

  /// Sets a signature into the document.
  void placeSignature(PlacedSignature signature) {
    _signatures.add(signature);
    notifyListeners();
  }

  /// Decodes the pictures of any marks that arrived as bytes alone.
  ///
  /// Restoring a document reads its signatures back as numbers and files;
  /// a picture has to be turned into something drawable before the page can
  /// show it, and that is the one part of a restore that cannot be done in
  /// the same breath as the rest.
  Future<void> decodePictures() async {
    var changed = false;
    for (var i = 0; i < _signatures.length; i++) {
      final mark = _signatures[i];
      final bytes = mark.encoded;
      if (bytes == null || mark.picture != null) continue;
      try {
        _signatures[i] = mark.withPicture(await decodePicture(bytes));
        changed = true;
      } on Object {
        // A picture that will not decode is a mark that cannot be drawn.
        // Dropping the bytes stops the app trying again on every restore.
        _signatures[i] = PlacedSignature(
          pageIndex: mark.pageIndex,
          rect: mark.rect,
          strokes: mark.strokes,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// The whole PDF with every signature written into its pages, or null when
  /// there is no open PDF or nothing has been signed.
  ///
  /// Throws [PdfWriteError] for a file the writer cannot add to, with the
  /// reason in words.
  Uint8List? signedPdf({Map<int, PdfImage> pictures = const <int, PdfImage>{}}) {
    final file = _pdf;
    if (file == null || _signatures.isEmpty) return null;
    return PdfSignatureWriter.signed(file, <PlacedInk>[
      for (var i = 0; i < _signatures.length; i++)
        PlacedInk(
          pageIndex: _signatures[i].pageIndex,
          rect: _signatures[i].rect,
          outlines: _signatures[i].strokes,
          image: pictures[i],
        ),
    ]);
  }

  /// Every picture among the signatures, read into the planes a PDF wants.
  ///
  /// It is done here rather than in the writer because reading pixels off a
  /// decoded picture is asynchronous and writing a PDF is not.
  Future<Map<int, PdfImage>> signaturePictures() async {
    final out = <int, PdfImage>{};
    for (var i = 0; i < _signatures.length; i++) {
      final picture = _signatures[i].picture;
      if (picture == null) continue;
      final planes = await picturePlanes(picture);
      if (planes == null) continue;
      out[i] = PdfImage(
        width: planes.width,
        height: planes.height,
        rgb: planes.rgb,
        alpha: planes.opaque ? null : planes.alpha,
      );
    }
    return out;
  }

  /// Removes the most recent signature, if there is one.
  void removeLastSignature() {
    if (_signatures.isEmpty) return;
    _signatures.removeLast();
    notifyListeners();
  }

  /// The search over this document, built on the first query and kept.
  ///
  /// It is built here rather than in the find layer so a find that is closed
  /// and reopened does not pay for the walk twice.
  DocSearch? get search {
    final doc = document;
    if (doc == null) return null;
    return _search ??= searchFor(doc);
  }

  /// Records how many words the engine found on [page].
  ///
  /// A page file holds no block model, so its words only exist once the pages
  /// have been run and their runs merged back into lines. The count is kept
  /// per page rather than summed on arrival so a page the reader visits twice
  /// is not counted twice.
  void recordPageWords(int page, PageDisplayList list) {
    final words = countWords(
      mergeRuns(list.texts).map((run) => run.text).join(' '),
    );
    if (_pageWords[page] == words) return;
    _pageWords[page] = words;
    notifyListeners();
  }

  /// Every word in the document, or 0 for a failure.
  ///
  /// For a page file it is the words on every page the engine has run so far,
  /// which is why a PDF's contribution to the colophon grows as it is read
  /// rather than arriving whole.
  int get wordCount {
    if (isPdf) {
      var total = 0;
      for (final words in _pageWords.values) {
        total += words;
      }
      return total;
    }
    return document?.wordCount ?? 0;
  }

  /// How long the document takes to read.
  int get minutes => readingMinutes(wordCount);
}

/// The desk: the six bundled documents, the shelf, the query, and whatever has
/// been removed but not yet forgotten.
class LibraryStore extends ChangeNotifier {
  LibraryStore({
    List<LibraryEntry> entries = libraryEntries,
    this._catalogue,
  }) : _entries = List<LibraryEntry>.of(entries);

  /// The desk in order, shipped documents and brought in ones together.
  final List<LibraryEntry> _entries;

  /// Where brought in documents are kept between runs, or null for a desk
  /// that only ever holds the shipped six, which is what a test builds.
  final LibraryCatalogue? _catalogue;

  /// Documents the reader has starred.
  final Set<String> _starred = <String>{};

  /// Which folder each document is in, by path. A document not in one is not
  /// in here.
  final Map<String, String> _inFolder = <String, String>{};

  /// Every folder the reader has made, in the order they made them.
  ///
  /// Kept apart from [_inFolder] so a folder can be empty. A folder that
  /// vanished when you took the last document out of it would be a folder you
  /// could not fill in the order you wanted to.
  final List<String> _folders = <String>[];

  /// What the reader has renamed, by path. A shipped document cannot carry its
  /// new name in a file of its own, so every rename is remembered here and the
  /// index is written as well for the ones that have a file.
  final Map<String, String> _titles = <String, String>{};

  /// Documents taken off the desk and waiting in the bin.
  final Set<String> _binned = <String>{};

  /// Documents deleted for good. A brought in one is gone from the list as
  /// well; a shipped one cannot be, since it is part of the app, so it is
  /// hidden here instead and stays hidden.
  final Set<String> _gone = <String>{};

  /// A write of the desk's state that is waiting to happen.
  ///
  /// Writes are gathered rather than made on every change, because a reader
  /// scrolling a page moves the position on every unit and a file written
  /// at every unit would be the app spending its time on the wrong thing.
  Timer? _pendingSave;

  static const _saveAfter = Duration(milliseconds: 500);
  final Map<String, DocumentStore> _stores = <String, DocumentStore>{};
  final Set<String> _removed = <String>{};
  Shelf _shelf = Shelf.all;
  String _query = '';
  LibraryEntry? _lastRemoved;

  /// Everything on the desk, removals included, except what is gone for good.
  List<LibraryEntry> get allEntries => List<LibraryEntry>.unmodifiable(
        _entries.where((e) => !_gone.contains(e.path)).toList(),
      );

  /// True when the desk can take a file in from the phone.
  bool get canImport => _catalogue != null;

  /// Everything still on the desk, in shelf order.
  List<LibraryEntry> get entries => _entries
      .where(
        (e) =>
            !_removed.contains(e.path) &&
            !_binned.contains(e.path) &&
            !_gone.contains(e.path),
      )
      .toList();

  /// What is waiting in the bin, in desk order.
  List<LibraryEntry> get binned => _entries
      .where((e) => _binned.contains(e.path) && !_gone.contains(e.path))
      .toList();

  bool isBinned(LibraryEntry entry) => _binned.contains(entry.path);

  bool isStarred(LibraryEntry entry) => _starred.contains(entry.path);

  /// Stars [entry], or takes the star off it.
  void toggleStar(LibraryEntry entry) {
    if (!_starred.remove(entry.path)) _starred.add(entry.path);
    _scheduleSave();
    notifyListeners();
  }

  /// Puts a binned [entry] back on the desk.
  void restore(LibraryEntry entry) {
    if (!_binned.remove(entry.path)) return;
    _scheduleSave();
    notifyListeners();
  }

  /// Deletes [entry] for good.
  ///
  /// A brought in document loses its copy and its place in the index. A
  /// shipped one cannot lose anything, being part of the app, so it is hidden
  /// from every list from now on, which from the desk is the same thing.
  void deleteForever(LibraryEntry entry) {
    _binned.remove(entry.path);
    _removed.remove(entry.path);
    _starred.remove(entry.path);
    _gone.add(entry.path);
    _stores.remove(entry.path)
      ?..removeListener(_onDocumentChanged)
      ..dispose();
    final catalogue = _catalogue;
    if (entry.source == DocSource.file) {
      _entries.remove(entry);
      _gone.remove(entry.path);
      if (catalogue != null) {
        catalogue.save(_entries);
        catalogue.forget(entry);
      }
    }
    _scheduleSave();
    notifyListeners();
  }

  /// The selected shelf.
  Shelf get shelf => _shelf;
  set shelf(Shelf value) {
    if (value == _shelf) return;
    _shelf = value;
    notifyListeners();
  }

  /// The desk search query, matched against title and format.
  String get query => _query;
  set query(String value) {
    if (value == _query) return;
    _query = value;
    notifyListeners();
  }

  /// The cards the desk actually draws.
  List<LibraryEntry> get visible => visibleOf(entries);

  /// Those of [pool] the shelf and the query let through.
  List<LibraryEntry> visibleOf(Iterable<LibraryEntry> pool) {
    final needle = _query.trim().toLowerCase();
    return pool.where((e) {
      if (!_onShelf(e, _shelf)) return false;
      if (needle.isEmpty) return true;
      return e.title.toLowerCase().contains(needle) ||
          e.format.mark.toLowerCase().contains(needle) ||
          e.format.extension.contains(needle);
    }).toList();
  }

  /// How many cards a shelf would show, ignoring the query.
  ///
  /// The chips need this to render an empty shelf at reduced alpha rather than
  /// letting a reader tap into nothing.
  int countOn(Shelf shelf) =>
      entries.where((e) => _onShelf(e, shelf)).length;

  bool _onShelf(LibraryEntry entry, Shelf shelf) {
    switch (shelf) {
      case Shelf.all:
        return true;
      case Shelf.reading:
        final store = _stores[entry.path];
        return store != null && store.opened;
      case Shelf.signed:
        final store = _stores[entry.path];
        return store != null && store.signed;
    }
  }

  /// The store for [entry], created on first use.
  ///
  /// Stores are kept rather than rebuilt so a document remembers its place,
  /// its dog ears and its search index for as long as the app is running.
  DocumentStore storeFor(LibraryEntry entry) =>
      _stores.putIfAbsent(entry.path, () {
        final store = DocumentStore(entry);
        store.addListener(_onDocumentChanged);
        return store;
      });

  /// A document changed, so the desk repaints and, in a moment, writes.
  void _onDocumentChanged() {
    notifyListeners();
    _scheduleSave();
  }

  /// Writes the desk's state after a short quiet, unless the desk has nowhere
  /// to write it, which is a desk built by a test.
  void _scheduleSave() {
    final catalogue = _catalogue;
    if (catalogue == null) return;
    _pendingSave?.cancel();
    _pendingSave = Timer(_saveAfter, () {
      _pendingSave = null;
      catalogue.saveState(_stateJson());
    });
  }

  /// Everything the desk remembers, as plain data.
  Map<String, Object?> _stateJson() => <String, Object?>{
        'folders': _folders,
        'inFolder': _inFolder,
        'titles': _titles,
        'starred': _starred.toList(),
        'binned': _binned.toList(),
        'gone': _gone.toList(),
        'documents': <String, Object?>{
          for (final entry in _stores.entries) entry.key: entry.value.toJson(),
        },
      };

  /// Takes back what [_stateJson] wrote, for the documents now on the desk.
  void _applyState(Map<String, Object?> state) {
    final known = <String>{for (final entry in _entries) entry.path};
    void fill(Set<String> into, Object? list) {
      if (list is! List<Object?>) return;
      into.addAll(list.whereType<String>().where(known.contains));
    }

    final folders = state['folders'];
    if (folders is List<Object?>) {
      _folders.addAll(folders.whereType<String>());
    }
    final inFolder = state['inFolder'];
    if (inFolder is Map<String, Object?>) {
      for (final filed in inFolder.entries) {
        final folder = filed.value;
        if (folder is! String || !_folders.contains(folder)) continue;
        if (!known.contains(filed.key)) continue;
        _inFolder[filed.key] = folder;
      }
    }
    final titles = state['titles'];
    if (titles is Map<String, Object?>) {
      for (final named in titles.entries) {
        final title = named.value;
        if (title is! String || title.isEmpty) continue;
        if (!known.contains(named.key)) continue;
        _titles[named.key] = title;
        final at = _entries.indexWhere((e) => e.path == named.key);
        if (at >= 0) _entries[at] = _entries[at].renamed(title);
      }
    }
    fill(_starred, state['starred']);
    fill(_binned, state['binned']);
    fill(_gone, state['gone']);
    final documents = state['documents'];
    if (documents is! Map<String, Object?>) return;
    for (final entry in _entries) {
      final saved = documents[entry.path];
      if (saved is Map<String, Object?>) storeFor(entry).restore(saved);
    }
  }

  /// The store for [entry] if one has been made, without making one.
  DocumentStore? peek(LibraryEntry entry) => _stores[entry.path];

  /// Reads every bundled document and parses it.
  ///
  /// The desk draws its first frame from the manifest alone, so this runs
  /// after that frame rather than before it: the cards are already on the
  /// ground, and the page counts, row counts and word counts land on them as
  /// each file comes back. A file the bundle cannot hand over fails on its own
  /// store and leaves the other five alone.
  Future<void> hydrate() async {
    for (final entry in List<LibraryEntry>.of(_entries)) {
      await _hydrateOne(entry);
    }
  }

  Future<void> _hydrateOne(LibraryEntry entry) async {
    final store = storeFor(entry);
    if (store.state != ParseState.loading) return;
    try {
      store.loadFrom(await _read(entry));
    } on Object catch (error) {
      store.fail(error);
    }
  }

  /// The bytes behind [entry], from the bundle or from the phone.
  Future<Uint8List> _read(LibraryEntry entry) async {
    switch (entry.source) {
      case DocSource.asset:
        final data = await rootBundle.load(entry.path);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      case DocSource.file:
        return File(entry.path).readAsBytes();
    }
  }

  /// Brings back the documents the reader opened in earlier runs, ahead of
  /// the shipped ones, then reads everything.
  ///
  /// The shipped six are on the desk from the first frame; these arrive a
  /// moment later, once the index has been read, which is a moment the desk
  /// already knows how to spend: it is the same moment the page counts land.
  Future<void> boot() async {
    final catalogue = _catalogue;
    if (catalogue != null) {
      final imported = await catalogue.load();
      if (imported.isNotEmpty) _entries.insertAll(0, imported);
      _applyState(await catalogue.loadState());
      notifyListeners();
    }
    await hydrate();
  }

  /// Writes [entry]'s signed PDF to a file the phone can hand to another app,
  /// or returns null when there is nothing to write or nowhere to write it.
  ///
  /// Throws [PdfWriteError] when the file cannot be added to.
  Future<File?> exportSigned(LibraryEntry entry) async {
    final catalogue = _catalogue;
    final store = _stores[entry.path];
    if (catalogue == null || store == null) return null;
    final bytes = store.signedPdf(pictures: await store.signaturePictures());
    if (bytes == null) return null;
    final title = entry.title.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]+'), '');
    return catalogue.writeExport('$title signed.pdf', bytes);
  }

  /// Puts a file called [name] holding [bytes] onto the desk and opens it for
  /// reading.
  ///
  /// Returns the new entry, or null when there is nowhere to keep it or the
  /// file is a kind quire does not read. The card goes on the desk before the
  /// file has been parsed, at the top, because it is the newest thing there.
  Future<LibraryEntry?> importFile(String name, Uint8List bytes) async {
    final catalogue = _catalogue;
    if (catalogue == null) return null;
    final entry = await catalogue.import(name, bytes);
    if (entry == null) return null;
    _entries.insert(0, entry);
    notifyListeners();
    await catalogue.save(_entries);
    await _hydrateOne(entry);
    return entry;
  }

  /// Every folder, in the order they were made.
  List<String> get folders => List<String>.unmodifiable(_folders);

  /// The folder [entry] is in, or null when it is on the open desk.
  String? folderOf(LibraryEntry entry) => _inFolder[entry.path];

  /// What is in [folder], in desk order.
  List<LibraryEntry> inFolder(String folder) =>
      entries.where((e) => _inFolder[e.path] == folder).toList();

  /// How many documents are in [folder].
  int countIn(String folder) => inFolder(folder).length;

  /// Makes a folder called [name], or returns the one already called that.
  ///
  /// Names are what a reader files by, so two folders with the same name would
  /// be a filing system that cannot answer where a thing is.
  String makeFolder(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return clean;
    for (final folder in _folders) {
      if (folder.toLowerCase() == clean.toLowerCase()) return folder;
    }
    _folders.add(clean);
    _scheduleSave();
    notifyListeners();
    return clean;
  }

  /// Puts [entry] in [folder], or back on the open desk when it is null.
  void moveTo(LibraryEntry entry, String? folder) {
    if (folder == null) {
      if (_inFolder.remove(entry.path) == null) return;
    } else {
      final made = makeFolder(folder);
      if (made.isEmpty || _inFolder[entry.path] == made) return;
      _inFolder[entry.path] = made;
    }
    _scheduleSave();
    notifyListeners();
  }

  /// Takes a folder away. What was in it goes back on the open desk rather
  /// than anywhere near the bin: a folder is a place to put documents, and
  /// removing the place must never remove the documents.
  void removeFolder(String folder) {
    if (!_folders.remove(folder)) return;
    _inFolder.removeWhere((_, held) => held == folder);
    _scheduleSave();
    notifyListeners();
  }

  /// Gives [entry] a new title.
  ///
  /// The path does not move, because the path is what the reading position,
  /// the stars, the dog ears and every placed signature are filed under. A
  /// rename changes what the document is called and nothing about what the
  /// desk knows about it.
  void rename(LibraryEntry entry, String title) {
    final clean = title.trim();
    if (clean.isEmpty || clean == entry.title) return;
    final at = _entries.indexWhere((e) => e.path == entry.path);
    if (at < 0) return;
    _entries[at] = _entries[at].renamed(clean);
    _titles[entry.path] = clean;
    _catalogue?.save(_entries);
    _scheduleSave();
    notifyListeners();
  }

  /// Puts a second copy of [entry] on the desk, with its own file behind it.
  ///
  /// A real copy rather than a second card pointing at one file, because two
  /// cards over one file would be two readings of one document fighting over
  /// the same reading position, and a signature placed on one would appear on
  /// the other.
  Future<LibraryEntry?> duplicate(LibraryEntry entry) async {
    final catalogue = _catalogue;
    if (catalogue == null) return null;
    final Uint8List bytes;
    try {
      bytes = await _read(entry);
    } on Object {
      return null;
    }
    final copy = await catalogue.import(entry.fileName, bytes);
    if (copy == null) return null;
    final named = copy.renamed(_freeTitle(entry.title));
    _entries.insert(0, named);
    _titles[named.path] = named.title;
    notifyListeners();
    await catalogue.save(_entries);
    await _hydrateOne(named);
    return named;
  }

  /// `Field Guide To Paper copy`, then `copy 2`, and so on for as long as the
  /// desk already holds one.
  String _freeTitle(String title) {
    final taken = <String>{for (final entry in _entries) entry.title};
    var wanted = '$title copy';
    var n = 2;
    while (taken.contains(wanted)) {
      wanted = '$title copy $n';
      n++;
    }
    return wanted;
  }

  /// Takes [entry] off the desk.
  ///
  /// The desk only records that the document has gone. What it looked like
  /// while it was there is the list's business: the pixels a row comes apart
  /// into belong to whatever drew the row, and a model that held an image
  /// would be a model that could not be tested without a rasteriser.
  void remove(LibraryEntry entry) {
    if (!_removed.add(entry.path)) return;
    _lastRemoved = entry;
    notifyListeners();
  }

  /// The entry the undo pill is offering to bring back, or null.
  LibraryEntry? get lastRemoved => _lastRemoved;

  /// Puts the last removed entry back.
  void undoRemove() {
    final entry = _lastRemoved;
    if (entry == null) return;
    _removed.remove(entry.path);
    _lastRemoved = null;
    notifyListeners();
  }

  /// Forgets the last removal, which is what happens when the pill runs out.
  ///
  /// Whatever is still holding that document's pixels watches this: once the
  /// offer is withdrawn there is nothing left to gather back together.
  void commitRemoval() {
    final entry = _lastRemoved;
    if (entry == null) return;
    _lastRemoved = null;
    // Once the offer to undo has run out the document goes to the bin, where
    // it waits to be put back or deleted for good. Nothing is lost by
    // letting the pill drain, which is what lets the pill be short.
    _removed.remove(entry.path);
    _binned.add(entry.path);
    _scheduleSave();
    notifyListeners();
  }

  /// The colophon's first number.
  int get documentCount => entries.length;

  /// The words in [shown]: real extracted words from every one of them that
  /// has been parsed. A document nobody has opened contributes nothing,
  /// because counting it would mean parsing all six to draw the first frame.
  ///
  /// It counts what it is given rather than the whole library, because the
  /// colophon sits under a list and not under the desk: a tab or a search
  /// that leaves two documents on screen has to be a colophon of two.
  int wordsIn(Iterable<LibraryEntry> shown) {
    var total = 0;
    for (final entry in shown) {
      total += _stores[entry.path]?.wordCount ?? 0;
    }
    return total;
  }

  /// [wordsIn] at the reading speed the app assumes.
  int minutesIn(Iterable<LibraryEntry> shown) => readingMinutes(wordsIn(shown));

  /// The colophon's second number for the whole desk.
  int get wordCount => wordsIn(entries);

  /// The colophon's third number for the whole desk.
  int get minutes => readingMinutes(wordCount);

  @override
  void dispose() {
    _pendingSave?.cancel();
    for (final store in _stores.values) {
      store.removeListener(_onDocumentChanged);
      store.dispose();
    }
    super.dispose();
  }
}
