import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/library.dart';
import '../format/document_loader.dart';
import '../model/document.dart';
import '../model/search.dart';
import '../pdf/display_list.dart';
import '../pdf/document.dart';
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
  });

  /// The page the mark belongs to, zero based.
  final int pageIndex;

  /// Where the mark sits in page space, in logical points.
  final ui.Rect rect;

  /// Each stroke as points in the unit square of [rect].
  final List<List<ui.Offset>> strokes;
}

/// One open document: what was parsed, where the reader is in it, and what
/// they have done to it.
///
/// It is a [ChangeNotifier] rather than something smaller because the reader,
/// the fore edge, the folio chip and the desk card all watch the same position
/// and must never disagree about it.
class DocumentStore extends ChangeNotifier {
  DocumentStore(this.entry);

  /// A store already holding a parsed document, for tests and for fixtures.
  factory DocumentStore.ready(LibraryEntry entry, Uint8List bytes) =>
      DocumentStore(entry)..loadFrom(bytes);

  /// The desk entry this document came from.
  final LibraryEntry entry;

  ParseState _state = ParseState.loading;
  LoadedDocument? _loaded;
  DocSearch? _search;
  int _position = 0;
  int _pdfPageCount = 0;
  bool _opened = false;
  int _opens = 0;
  final Map<int, int> _pageWords = <int, int>{};
  final Set<int> _dogEared = <int>{};
  final List<PlacedSignature> _signatures = <PlacedSignature>[];

  /// Parses [bytes] and moves the store to [ParseState.ready] or
  /// [ParseState.failed]. Every exception the parsers raise is already caught
  /// at the loader boundary, so this never throws.
  void loadFrom(Uint8List bytes) {
    _loaded = DocumentLoader.load(bytes, entry.fileName);
    _search = null;
    _state = _loaded!.failed ? ParseState.failed : ParseState.ready;
    if (_loaded!.isPdf && !_loaded!.failed) _readPageCount(bytes);
    notifyListeners();
  }

  /// Reads a page file's page count from its own page tree.
  ///
  /// It happens here rather than in the reader so a PDF nobody has opened
  /// still prints `6 PAGES` on its card. Only the count is taken: the pages
  /// themselves are not run, because six documents' worth of content streams
  /// is not a price the first frame of the desk should pay.
  void _readPageCount(Uint8List bytes) {
    try {
      _pdfPageCount = PdfFile.open(bytes).pageCount;
    } on Object {
      // A file that opens as bytes but not as a page tree keeps no count, and
      // the card prints its format and its size alone. The reader decides
      // what a page nobody can lay out looks like.
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

  ParseState get state => _state;

  /// The parsed document, or null for a PDF and for a failure.
  QuireDocument? get document => _loaded?.document;

  /// The original bytes, which is what a PDF is opened from.
  Uint8List get bytes => _loaded?.bytes ?? Uint8List(0);

  /// What went wrong, or null.
  Object? get error => _loaded?.error;

  /// True when this document belongs to the page engine.
  bool get isPdf => _loaded?.isPdf ?? entry.format == DocFormat.pdf;

  /// The rung this whole document is on, before any single page is looked at.
  ///
  /// A failed parse is [RenderPlan.damaged] here; a PDF's per page rung is
  /// decided later by `planFor` once its display list exists.
  RenderPlan get plan =>
      _state == ParseState.failed ? RenderPlan.damaged : RenderPlan.rich;

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

  /// Marks the document as opened without moving the reader.
  void markOpened() {
    _opens++;
    _opened = true;
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
  LibraryStore({List<LibraryEntry> entries = libraryEntries})
      : _entries = List<LibraryEntry>.unmodifiable(entries);

  final List<LibraryEntry> _entries;
  final Map<String, DocumentStore> _stores = <String, DocumentStore>{};
  final Set<String> _removed = <String>{};
  Shelf _shelf = Shelf.all;
  String _query = '';
  LibraryEntry? _lastRemoved;

  /// Everything on the desk, removals included.
  List<LibraryEntry> get allEntries => _entries;

  /// Everything still on the desk, in shelf order.
  List<LibraryEntry> get entries =>
      _entries.where((e) => !_removed.contains(e.assetPath)).toList();

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
  List<LibraryEntry> get visible {
    final needle = _query.trim().toLowerCase();
    return entries.where((e) {
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
        final store = _stores[entry.assetPath];
        return store != null && store.opened;
      case Shelf.signed:
        final store = _stores[entry.assetPath];
        return store != null && store.signed;
    }
  }

  /// The store for [entry], created on first use.
  ///
  /// Stores are kept rather than rebuilt so a document remembers its place,
  /// its dog ears and its search index for as long as the app is running.
  DocumentStore storeFor(LibraryEntry entry) =>
      _stores.putIfAbsent(entry.assetPath, () {
        final store = DocumentStore(entry);
        store.addListener(notifyListeners);
        return store;
      });

  /// The store for [entry] if one has been made, without making one.
  DocumentStore? peek(LibraryEntry entry) => _stores[entry.assetPath];

  /// Reads every bundled document and parses it.
  ///
  /// The desk draws its first frame from the manifest alone, so this runs
  /// after that frame rather than before it: the cards are already on the
  /// ground, and the page counts, row counts and word counts land on them as
  /// each file comes back. A file the bundle cannot hand over fails on its own
  /// store and leaves the other five alone.
  Future<void> hydrate() async {
    for (final entry in _entries) {
      final store = storeFor(entry);
      if (store.state != ParseState.loading) continue;
      try {
        final data = await rootBundle.load(entry.assetPath);
        store.loadFrom(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } on Object catch (error) {
        store.fail(error);
      }
    }
  }

  /// Takes [entry] off the desk.
  ///
  /// The desk only records that the document has gone. What it looked like
  /// while it was there is the list's business: the pixels a row comes apart
  /// into belong to whatever drew the row, and a model that held an image
  /// would be a model that could not be tested without a rasteriser.
  void remove(LibraryEntry entry) {
    if (!_removed.add(entry.assetPath)) return;
    _lastRemoved = entry;
    notifyListeners();
  }

  /// The entry the undo pill is offering to bring back, or null.
  LibraryEntry? get lastRemoved => _lastRemoved;

  /// Puts the last removed entry back.
  void undoRemove() {
    final entry = _lastRemoved;
    if (entry == null) return;
    _removed.remove(entry.assetPath);
    _lastRemoved = null;
    notifyListeners();
  }

  /// Forgets the last removal, which is what happens when the pill runs out.
  ///
  /// Whatever is still holding that document's pixels watches this: once the
  /// offer is withdrawn there is nothing left to gather back together.
  void commitRemoval() {
    if (_lastRemoved == null) return;
    _lastRemoved = null;
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
      total += _stores[entry.assetPath]?.wordCount ?? 0;
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
    for (final store in _stores.values) {
      store.removeListener(notifyListeners);
      store.dispose();
    }
    super.dispose();
  }
}
