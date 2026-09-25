import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../../painting/signature_painter.dart';
import '../../painting/overflow_dots_painter.dart';
import '../../model/document.dart'
    show CodeBlock, DocBlock, HeadingBlock, ListItemBlock, ParagraphBlock, TableBlock;
import '../../pdf/pdf_search.dart';
import '../../pdf/writer.dart' show PdfAnnotator, PdfWriteError;
import '../../data/library.dart' show DocFormat, DocSource;
import '../../edit/xlsx_patch.dart';
import '../../format/document_loader.dart';
import '../../services/document_store.dart';
import '../../services/native_pdf.dart';
import '../../theme/colors.dart';
import '../../theme/feedback.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../edit/cell_sheet.dart';
import '../edit/doc_editor.dart';
import '../edit/grid_editor.dart';
import '../edit/markup_screen.dart';
import '../edit/paragraph_editor.dart';
import '../edit/slides/slide_editor.dart';
import '../edit/revisions_sheet.dart';
import '../edit/text_editor.dart';
import '../sign/placement_layer.dart';
import '../sign/sign_screen.dart';
import 'bodies/deck_body.dart';
import 'bodies/page_states.dart';
import 'bodies/pdf_body.dart';
import 'bodies/prose_body.dart';
import 'bodies/sheet_body.dart';
import 'bodies/spine_table.dart';
import 'find/find_layer.dart';
import '../../widgets/goo_menu.dart';
import '../../widgets/gooey_fab/gooey_fab_controller.dart';
import 'page_frames.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../desk/desk_sheet.dart';
import 'reader_menu.dart';
import 'dog_ears_sheet.dart';
import 'view_sheet.dart';
import 'present_screen.dart';
import 'reader_screen.dart';
import 'seal_sheet.dart';
import 'sheet_surface.dart';

/// The reader, assembled: one document, the body its format asks for, the find
/// overlay, and whatever is being set into the page.
///
/// The shell knows nothing about formats and a body knows nothing about the
/// shell, so something has to hold the two together and own what outlives a
/// frame: the page engine for a PDF, the search index behind find, and the
/// mark a signature is carrying in from the pad. That is all this is.
class ReaderHost extends StatefulWidget {
  const ReaderHost({
    super.key,
    required this.store,
    this.library,
    this.placing,
    this.onPlaced,
    this.onLeave,
  });

  /// The open document.
  final DocumentStore store;

  /// The desk this document is on, for the one thing the reader asks of it:
  /// writing the signed copy out to a file the phone can pass along.
  final LibraryStore? library;

  /// A signature waiting to be set into the page, straight from the pad.
  final SignatureMark? placing;

  /// Called once the mark has been absorbed into the page, so whoever is
  /// holding it can let it go.
  final VoidCallback? onPlaced;

  /// What leaving does. Null pops the route the reader was pushed on.
  final VoidCallback? onLeave;

  @override
  State<ReaderHost> createState() => _ReaderHostState();
}

/// What the band says once a change has been kept.
const kEditSaved = 'Saved as a new revision.';

/// Whether the line about tapping a slide has been said.
///
/// Once in the life of the app. A reader who has been told does not need
/// telling again every time they open a deck.
bool _deckHintSaid = false;

/// Forgets that the line has been said, for a test that needs it again.
@visibleForTesting
void resetDeckHint() => _deckHintSaid = false;

class _ReaderHostState extends State<ReaderHost> with TickerProviderStateMixin {
  /// A signature drawn from inside this document, as opposed to one carried
  /// in from the desk. Either way there is only ever one loose at a time.
  SignatureMark? _drawn;

  /// The mark waiting to be set into the page, whichever door it came in by.
  SignatureMark? get _loose => _drawn ?? widget.placing;

  /// The layer holding that mark, so the band's tick can set it down. The
  /// placement owns the animation and the snapping; the band only asks it to
  /// finish.
  final GlobalKey<PlacementLayerState> _placementKey =
      GlobalKey<PlacementLayerState>();

  /// Where the body says it has drawn the page the reader is on.
  final PageFrames _frames = PageFrames();

  /// The menu behind the band's three dots, on the action button's own
  /// springs, so every menu in the app moves the same way.
  late final GooeyFabController _menu = GooeyFabController(
    vsync: this,
    actionCount: ReaderAction.values.length,
  );

  bool _menuOpen = false;

  /// What the band is saying instead of the title, and the clock taking it
  /// back off again.
  String? _notice;
  Timer? _noticeGone;

  /// The page engine, held for the life of the route rather than rebuilt with
  /// the body, so a page interpreted once stays interpreted and the fore edge,
  /// the folio chip and the block all count the same pages.
  PdfPages? _pages;

  /// Find is built on the first press of the search pill, because the index it
  /// stands on costs a walk of the whole document and most readings never ask
  /// for it.
  FindController? _find;

  /// Which match the find was standing on last, so a grid is moved to a
  /// match only when the match it stands on changes.
  int _steppedTo = 0;

  /// True once the mark has gone into the page, which is what takes the layer
  /// down. The reader drops it itself rather than waiting to be handed a new
  /// widget, because the absorb has already finished by then and a stamp left
  /// standing over its own signature is the one frame that would give the
  /// trick away.
  bool _placed = false;

  /// The block a flowing document opens at, taken once.
  ///
  /// It is the anchor the sheet lands on, not where the reader is now: the
  /// sheet follows the store's position itself once it is up, and handing it a
  /// moving anchor would have it chasing its own scroll.
  late int _openedAt = widget.store.position;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _menu.animations.addListener(_onMenuMoved);
    _frames.addListener(_onFramesMoved);
    _openPages();
    _hintDeck();
  }

  @override
  void didUpdateWidget(ReaderHost old) {
    super.didUpdateWidget(old);
    if (old.store != widget.store) {
      old.store.removeListener(_onStore);
      widget.store.addListener(_onStore);
      _pages?.dispose();
      _pages = null;
      _find?.dispose();
      _find = null;
      _placed = false;
      _openedAt = widget.store.position;
      _openPages();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _pages?.dispose();
    _find?.dispose();
    _menu.animations.removeListener(_onMenuMoved);
    _menu.dispose();
    _frames.removeListener(_onFramesMoved);
    _frames.dispose();
    _noticeGone?.cancel();
    super.dispose();
  }

  // The menu, and what is on it.

  /// Rebuilds when the paper moves, but only while there is a mark loose over
  /// it: the rest of the time nothing on this screen is measured against the
  /// page's own edges.
  void _onFramesMoved() {
    if (!mounted || _loose == null || _placed) return;
    setState(() {});
  }

  /// Repaints while the pills move, and takes the menu down once the last of
  /// them has settled back on the dots.
  void _onMenuMoved() {
    if (!mounted) return;
    setState(() {});
    if (_menuOpen && !_menu.isOpen && !_menuMoving) {
      _menuOpen = false;
    }
  }

  bool get _menuMoving {
    bool moving(Animation<double> a) =>
        a.status == AnimationStatus.forward ||
        a.status == AnimationStatus.reverse;
    if (moving(_menu.progress)) return true;
    for (var i = 0; i < _menu.actionCount; i++) {
      if (moving(_menu.actionDrive(i))) return true;
    }
    return false;
  }

  void _openMenu() {
    setState(() => _menuOpen = true);
    if (!_menu.isOpen) _menu.toggle();
  }

  void _closeMenu() {
    if (_menu.isOpen) _menu.toggle();
  }

  /// True when this document already has a password on it: one still waiting
  /// for the password that opens it, and one that opened on nothing because
  /// what it carries is an owner password alone.
  ///
  /// Either way a second seal on top of the first would leave a file with
  /// neither, so the offer is not made rather than made and then taken back
  /// with a line in the band.
  bool get _protected =>
      widget.store.locked != null || (widget.store.pdf?.encrypted ?? false);

  /// True when this document can be changed and the change kept: the desk
  /// keeps revisions, and the document is open, read and not waiting on a
  /// password.
  bool get _editable {
    final store = widget.store;
    return (widget.library?.canEdit ?? false) &&
        store.state == ParseState.ready &&
        store.locked == null &&
        store.bytes.isNotEmpty;
  }

  /// What this document can have done to it from inside itself.
  List<ReaderAction> get _actions => <ReaderAction>[
    if (_editable && widget.store.isPdf && _commentable) ReaderAction.markUp,
    if (_editable && widget.store.isGrid &&
        widget.store.entry.format == DocFormat.xlsx)
      ReaderAction.editCell,
    if (_editable && !widget.store.isPdf &&
        widget.store.entry.format != DocFormat.xlsx)
      ReaderAction.edit,
    if (widget.library?.canEdit ?? false) ReaderAction.revisions,
    if (widget.store.isDeck) ReaderAction.present,
    if (widget.store.isPdf) ReaderAction.sign,
    if (widget.store.isPdf && widget.store.signed) ReaderAction.shareSigned,
    if (widget.store.isPdf && !_protected) ReaderAction.seal,
    widget.store.dogEared.contains(widget.store.position)
        ? ReaderAction.undogEar
        : ReaderAction.dogEar,
    if (widget.store.dogEared.isNotEmpty) ReaderAction.dogEars,
    if (_hasComments) ReaderAction.comments,
    ReaderAction.find,
    ReaderAction.view,
    ReaderAction.lock,
  ];

  void _act(ReaderAction action) {
    _closeMenu();
    switch (action) {
      case ReaderAction.edit:
        _edit();
      case ReaderAction.markUp:
        _markUp();
      case ReaderAction.editCell:
        _editCell();
      case ReaderAction.revisions:
        _revisions();
      case ReaderAction.present:
        _present(widget.store.position);
      case ReaderAction.sign:
        _sign();
      case ReaderAction.dogEar:
      case ReaderAction.undogEar:
        widget.store.toggleDogEar(widget.store.position);
      case ReaderAction.dogEars:
        _dogEars();
      case ReaderAction.shareSigned:
        _shareSigned();
      case ReaderAction.seal:
        _seal();
      case ReaderAction.comments:
        _comments();
      case ReaderAction.find:
        _openFind();
      case ReaderAction.view:
        showDeskSheet<void>(
          context,
          (context) => ViewSheet(store: widget.store),
        );
      case ReaderAction.lock:
        _lock();
    }
  }

  // Editing.

  /// Keeps [bytes] as the document's newest revision, once they have been
  /// read back and found to be a document. Returns why not, or null.
  Future<String?> _keep(Uint8List bytes, String note) async {
    final library = widget.library;
    if (library == null) return 'This desk cannot keep changes.';
    final entry = widget.store.entry;
    final LoadedDocument check;
    try {
      check = DocumentLoader.load(bytes, entry.fileName);
    } on Object {
      return 'The changed file would not open again, so it was not saved.';
    }
    if (check.failed) {
      return 'The changed file would not open again, so it was not saved.';
    }
    try {
      await library.saveEdit(entry, bytes, note: note);
    } on Object {
      return 'The change could not be written to this phone.';
    }
    return null;
  }

  /// Opens an editor over the reader, and once it has saved, calls
  /// [landed] to take the reader to what was edited.
  Future<void> _openEditor(
    Widget Function(BuildContext context, SaveEdit save, VoidCallback back)
    build, {
    VoidCallback? landed,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: kPadArrival,
        reverseTransitionDuration: kPadArrival,
        pageBuilder: (context, animation, secondary) => build(
          context,
          (bytes, note) async {
            final problem = await _keep(bytes, note);
            if (problem == null && context.mounted) {
              Navigator.of(context).pop(true);
            }
            return problem;
          },
          () => Navigator.of(context).pop(false),
        ),
        transitionsBuilder: (context, animation, secondary, child) =>
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: easeOutCubic)),
              child: child,
            ),
      ),
    );
    if (saved == true && mounted) {
      landed?.call();
      _say(kEditSaved);
    }
  }

  /// The words of a Word document or a deck, or the text of Markdown or a
  /// CSV, each opened where the reader is, and the reader taken to what was
  /// edited once it is saved.
  void _edit() {
    final store = widget.store;
    final bytes = store.bytes;
    switch (store.entry.format) {
      case DocFormat.docx:
        DocPlace? place;
        _openEditor(
          (context, save, back) => DocEditor(
            title: store.entry.title,
            bytes: bytes,
            onSave: save,
            onBack: back,
            openAt: _docPlace(),
            onPlace: (at) => place = at,
          ),
          landed: () {
            final at = place;
            if (at != null) store.position = _blockOf(at);
          },
        );
      case DocFormat.pptx:
        int? slide;
        _openEditor(
          (context, save, back) => SlideEditor(
            title: store.entry.title,
            bytes: bytes,
            onSave: save,
            onBack: back,
            openAt: store.position,
            onPlace: (at) => slide = at,
          ),
          landed: () {
            final at = slide;
            if (at != null) store.position = at;
          },
        );
      case DocFormat.csv:
        final sheets = SheetController.of(store);
        final picked = sheets.selected;
        (int, int?)? cell;
        _openEditor(
          (context, save, back) => GridEditor(
            title: store.entry.title,
            bytes: bytes,
            onSave: save,
            onBack: back,
            openAt: picked == null ? null : CellPick(picked.row, picked.column),
            openRow: store.position,
            onPlace: (row, column) => cell = (row, column),
          ),
          landed: () {
            final at = cell;
            if (at == null) return;
            store.position = at.$1;
            final column = at.$2;
            sheets.selected = column == null ? null : SheetCell(at.$1, column);
          },
        );
      case DocFormat.md:
        _openEditor(
          (context, save, back) => TextEditor(
            entry: store.entry,
            bytes: bytes,
            onSave: save,
            onBack: back,
          ),
        );
      case DocFormat.pdf:
      case DocFormat.xlsx:
        break;
    }
  }

  /// Words, ink, highlights, strikes and pictures on a PDF's pages.
  /// False for a PDF whose own rules forbid adding or changing comments.
  bool get _commentable {
    final file = widget.store.pdf;
    return file == null || PdfAnnotator.allowsComments(file);
  }

  void _markUp() {
    final pages = _pages;
    final file = widget.store.pdf;
    if (pages == null || file == null) return;
    int? page;
    _openEditor(
      landed: () {
        final at = page;
        if (at != null) widget.store.position = at;
      },
      (context, save, back) => MarkupScreen(
        title: widget.store.entry.title,
        pages: pages,
        openAt: widget.store.position,
        onPlace: (at) => page = at,
        onBack: back,
        onSave: (changes) async {
          final Uint8List bytes;
          try {
            bytes = PdfAnnotator.apply(
              file,
              added: changes.added,
              updates: changes.updates,
              font: changes.font,
            );
          } on PdfWriteError catch (error) {
            return error.message;
          } on Object {
            return 'The marks could not be written into this file.';
          }
          final count = changes.added.length + changes.updates.length;
          return save(bytes, count == 1 ? 'One mark' : '$count marks');
        },
      ),
    );
  }

  /// The blocks of a flowing document, in the order the reader counts them.
  List<DocBlock> get _blocks => <DocBlock>[
    for (final section in widget.store.document?.sections ?? const []) ...section.blocks,
  ];

  static String _wordsOf(DocBlock block) => switch (block) {
    ParagraphBlock() => block.text,
    HeadingBlock() => block.text,
    ListItemBlock() => block.text,
    CodeBlock() => block.text,
    _ => '',
  }.trim();

  /// Where the reader is in a flowing document, as words the editor can
  /// find: the block at the top, or the first one with words after it.
  DocPlace _docPlace() {
    final blocks = _blocks;
    if (blocks.isEmpty) return const DocPlace('', 0);
    final at = widget.store.position.clamp(0, blocks.length - 1);
    for (var i = at; i < blocks.length && i < at + 8; i++) {
      final words = _wordsOf(blocks[i]);
      if (words.isNotEmpty) return DocPlace(words, i / blocks.length);
    }
    return DocPlace('', at / blocks.length);
  }

  /// The block of the document as read again that [place] names: the one
  /// its words begin nearest its share of the way through, or the block at
  /// that share.
  int _blockOf(DocPlace place) {
    final blocks = _blocks;
    if (blocks.isEmpty) return 0;
    final estimate = (place.fraction * blocks.length).round().clamp(0, blocks.length - 1);
    final words = place.words.trim();
    if (words.isEmpty) return estimate;
    final probe = words.length > 48 ? words.substring(0, 48) : words;
    int? best;
    for (var i = 0; i < blocks.length; i++) {
      final text = _wordsOf(blocks[i]);
      if (text.isEmpty || !(text.startsWith(probe) || probe.startsWith(text))) continue;
      if (best == null || (i - estimate).abs() < (best - estimate).abs()) best = i;
    }
    return best ?? estimate;
  }

  /// The ringed cell of a workbook, or its first cell when none is.
  Future<void> _editCell() async {
    final store = widget.store;
    final document = store.document;
    if (document == null) return;
    final controller = SheetController.of(store);
    final index = controller.sheet.clamp(0, document.sections.length - 1);
    final section = document.sections[index];
    final table = section.blocks.whereType<TableBlock>().firstOrNull;
    if (table == null) return;
    final at = controller.selected ?? const SheetCell(0, 0);
    final reference = '${columnLetter(at.column)}${at.row + 1}';
    final input = await showDeskSheet<String>(
      context,
      (context) => CellSheet(
        reference: '${section.title}!$reference',
        input: cellInput(table, at),
      ),
    );
    if (input == null || !mounted || input == cellInput(table, at)) return;
    final Uint8List bytes;
    try {
      bytes = (XlsxPatch(store.bytes)..setCell(section.title, reference, input))
          .write();
    } on Object {
      _say('That cell could not be changed in this file.');
      return;
    }
    final problem = await _keep(bytes, '${section.title}!$reference changed');
    if (!mounted) return;
    _say(problem ?? kEditSaved);
  }

  Future<void> _revisions() async {
    final library = widget.library;
    if (library == null) return;
    final said = await showRevisions(context, library, widget.store.entry);
    if (said != null && mounted) _say(said);
  }

  /// Says how a deck is presented, once, on the first one that is opened.
  ///
  /// It waits for a frame because a notice set during initState is a notice
  /// set into a band that has not been built yet.
  void _hintDeck() {
    if (_deckHintSaid || !widget.store.isDeck) return;
    _deckHintSaid = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.store.isDeck) _say(kDeckHint);
    });
  }

  /// Shows the deck, from [slide], with the app out of the way.
  ///
  /// The route is raised here rather than inside the body because present mode
  /// takes the whole screen, and the body only owns the sheet. The reader is
  /// left standing underneath it, on the slide the presentation ended on.
  Future<void> _present(int slide) async {
    final document = widget.store.document;
    if (document == null || !widget.store.isDeck) return;
    await Navigator.of(context).push<void>(
      presentRoute(
        store: widget.store,
        slides: widget.store.slides,
        assets: document.assets,
        titles: <String>[for (final s in document.sections) s.title],
        openAt: slide,
      ),
    );
  }

  /// Takes a signature on the pad and comes back to this page holding it.
  ///
  /// The pad is a route over the reader rather than a screen the reader is
  /// replaced by, because the document is the thing being signed and it
  /// should still be underneath while somebody signs it.
  Future<void> _sign() async {
    final mark = await Navigator.of(context).push<SignatureMark>(
      PageRouteBuilder<SignatureMark>(
        transitionDuration: kPadArrival,
        reverseTransitionDuration: kPadArrival,
        pageBuilder: (context, animation, secondary) {
          final library = widget.library;
          if (library == null) {
            return SignScreen(
              onBack: () => Navigator.of(context).pop(),
              onCommit: (mark) => Navigator.of(context).pop(mark),
            );
          }
          // The same pad the desk opens, with the same signatures kept on it.
          return ListenableBuilder(
            listenable: library,
            builder: (context, _) => SignScreen(
              recent: library.recentSignatures,
              onForget: library.forgetSignature,
              onBack: () => Navigator.of(context).pop(),
              onCommit: (mark) {
                library.useSignature(savedOf(mark));
                Navigator.of(context).pop(mark);
              },
            ),
          );
        },
        // Up from the bottom edge, the way a pad is put down over a page.
        transitionsBuilder: (context, animation, secondary, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: easeOutCubic),
                  ),
              child: child,
            ),
      ),
    );
    if (mark == null || mark.isEmpty || !mounted) return;
    setState(() {
      _drawn = mark;
      _placed = false;
    });
  }

  /// Offers the two ways of fastening a reading down.
  ///
  /// A sheet rather than two pills, because the difference between them is
  /// the whole point and it takes a sentence each to say. A reader who picked
  /// the wrong one would be locked out of the thing they wanted.
  Future<void> _lock() async {
    final wanted = await showDeskSheet<ReaderLock>(
      context,
      (context) => DeskSheet(
        title: 'Lock the reading',
        note: 'Both kinds come off from inside the document.',
        children: <Widget>[
          DeskSheetRow(
            label: 'Lock the way out',
            icon: LucideIcons.lockKeyhole,
            note:
                'Back does nothing and every bar leaves the screen. You can '
                'still scroll. Tap the page for the way out.',
            onTap: () => Navigator.of(context).pop(ReaderLock.back),
          ),
          DeskSheetRow(
            label: 'Lock to this page',
            icon: LucideIcons.squareDashedBottom,
            note:
                'Pins the reading where it is and takes every bar off the '
                'screen. Tap the page to bring back the way out.',
            onTap: () => Navigator.of(context).pop(ReaderLock.page),
          ),
        ],
      ),
    );
    if (wanted == null || !mounted) return;
    // No line in the band: the band is the first thing either lock takes
    // away. The chip at the bottom introduces itself instead.
    widget.store.lock = wanted;
  }

  /// True when any sheet of the workbook carries a discussion in its
  /// margins.
  bool get _hasComments => _allComments().isNotEmpty;

  /// What has been said about the cells of every sheet, sheet by sheet and
  /// in reading order within each.
  List<({int sheet, SheetCell at, CellComment said})> _allComments() {
    final document = widget.store.document;
    if (document == null || !widget.store.isGrid) return const [];
    return <({int sheet, SheetCell at, CellComment said})>[
      for (var s = 0; s < document.sections.length; s++)
        for (final block in document.sections[s].blocks)
          if (block is TableBlock)
            for (final entry in commentsOn(block).entries)
              (sheet: s, at: entry.key, said: entry.value),
    ];
  }

  /// Everything said about the workbook, and a jump to the cell it was said
  /// about, on whichever sheet that is.
  Future<void> _comments() async {
    final document = widget.store.document;
    if (document == null) return;
    final controller = SheetController.of(widget.store);
    final all = _allComments();
    final picked = await showDeskSheet<int>(
      context,
      (context) => DeskSheet(
        title: 'Comments',
        note: 'Tap one to go to the cell it is about.',
        children: <Widget>[
          for (var i = 0; i < all.length; i++)
            DeskSheetRow(
              label: all[i].said.text,
              icon: LucideIcons.messageSquare,
              note: _saidWhere(
                document.sections[all[i].sheet].title,
                all[i].at,
                all[i].said.author,
              ),
              onTap: () => Navigator.of(context).pop(i),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final chosen = all[picked];
    if (chosen.sheet != controller.sheet) controller.sheet = chosen.sheet;
    controller.selected = chosen.at;
  }

  String _saidWhere(String sheetName, SheetCell at, String author) {
    final where = cellReference(sheetName, at.column, at.row);
    return author.isEmpty ? where : '$where · $author';
  }

  /// The list of dog ears, and a jump to the one picked.
  Future<void> _dogEars() async {
    final unit = await showDeskSheet<int>(
      context,
      (context) => DogEarsSheet(store: widget.store),
    );
    if (unit == null || !mounted) return;
    widget.store.position = unit;
  }

  /// Writes the signed PDF and hands it to the phone's share sheet.
  Future<void> _shareSigned() async {
    File? file;
    try {
      file = await widget.library?.exportSigned(widget.store.entry);
    } on PdfWriteError catch (error) {
      _say(error.message);
      return;
    } on Object {
      _say('The signed file could not be written.');
      return;
    }
    if (!mounted) return;
    if (file == null) {
      _say('There is nothing signed to share yet.');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        title: '${widget.store.entry.title}, signed',
        files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      ),
    );
  }

  /// Takes a password and hands the phone a copy of this document sealed
  /// with it.
  ///
  /// The seal itself runs on the frame it was asked for. Rewriting the
  /// largest document quire ships, three hundred kilobytes over six pages,
  /// takes about seven milliseconds and never more than eleven, which is
  /// inside a frame, and an isolate would cost a copy of the whole file in
  /// each direction to save nothing anybody could see.
  Future<void> _seal() async {
    final password = await showDeskSheet<String>(
      context,
      (context) => const SealSheet(),
    );
    if (password == null || password.isEmpty || !mounted) return;
    File? file;
    try {
      file = await widget.library?.exportSealed(widget.store.entry, password);
    } on PdfWriteError catch (error) {
      // Why this document cannot be sealed, in the writer's own words, which
      // are written to be read by whoever asked for it.
      _say(error.message);
      return;
    } on Object {
      _say('The protected copy could not be written.');
      return;
    }
    if (!mounted) return;
    if (file == null) {
      _say('The protected copy could not be written.');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        title: '${widget.store.entry.title}, protected',
        files: <XFile>[XFile(file.path, mimeType: 'application/pdf')],
      ),
    );
  }

  /// Has the band say [text] for a moment, then go back to the title.
  void _say(String text) {
    _noticeGone?.cancel();
    setState(() => _notice = text);
    _noticeGone = Timer(kReaderNotice, () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// Puts a loose signature away without setting it into the page.
  void _cancelPlacement() {
    setState(() {
      _drawn = null;
      _placed = true;
    });
    widget.onPlaced?.call();
  }

  void _onStore() {
    _pages?.drawnByPhone = !widget.store.quireType;
    if (!mounted) return;
    // A document opened from the desk has not been read yet when the reader is
    // built, so the deck only becomes a deck here.
    _hintDeck();
    // A document that arrives while the reader is already open gets its page
    // engine on the next frame rather than inside the notification that
    // announced it, because opening one writes the page count straight back to
    // the store that is still handing out that notification.
    final pages = _pages;
    if (pages != null &&
        widget.store.pdf != null &&
        !identical(pages.file, widget.store.pdf)) {
      // A save put a new file under the reader. The engine was reading the
      // old one.
      _pages = null;
      _find?.dispose();
      _find = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        pages.dispose();
      });
    }
    if (_pages == null && widget.store.pdf != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_openPages);
      });
    }
    setState(() {});
  }

  /// Opens the page engine, once, and tells the store how many pages there
  /// are so the folio chip and the fore edge agree before a page has been run.
  ///
  /// The file itself comes from the store, already open. Reopening the bytes
  /// here would parse the document twice, and for one that took a password it
  /// would need that password again, which is the reason quire never keeps
  /// what somebody typed.
  void _openPages() {
    final store = widget.store;
    final file = store.pdf;
    if (_pages != null || file == null) return;
    final pages = PdfPages(file, onPageRun: store.recordPageWords)
      ..drawnByPhone = !store.quireType;
    _pages = pages;
    store.pdfPageCount = pages.pageCount;
    unawaited(_drawByPhone(pages));
  }

  /// Opens the document in the phone's own renderer, so its pages can be
  /// drawn in their own print. A document already on the phone is opened
  /// where it lies; a shipped one is handed over as bytes.
  Future<void> _drawByPhone(PdfPages pages) async {
    final store = widget.store;
    final entry = store.entry;
    final inPlace = entry.source != DocSource.asset && !store.revised;
    final native = await NativePdf.open(
      path: inPlace ? entry.path : null,
      bytes: inPlace ? null : store.bytes,
    );
    if (!mounted || !identical(pages, _pages)) {
      unawaited(native?.close());
      return;
    }
    pages.attachNative(native);
  }

  // Find.

  void _openFind() {
    final find = _find ?? _buildFind();
    if (find == null) return;
    find.openField();
    setState(() {});
  }

  /// The controller and the index under it, or null for a document there is
  /// nothing to search: a failed parse, or a file still being read.
  FindController? _buildFind() {
    final store = widget.store;
    final FindSource source;
    if (store.isPdf) {
      final pages = _pages;
      if (pages == null || pages.pageCount == 0) return null;
      source = PdfFindSource(_indexPages(pages));
    } else {
      final search = store.search;
      if (search == null) return null;
      source = DocFindSource(search);
    }
    final find = FindController(
      vsync: this,
      source: source,
      readingAt: () => widget.store.position,
    )..addListener(_onFind);
    _find = find;
    return find;
  }

  /// Every page's text, handed to the index in one go.
  ///
  /// A page file holds no text until its content stream has been run, so the
  /// price of searching one is running it. It is paid here, once, on the press
  /// that opens the field, rather than on the keystroke that would otherwise
  /// have to wait for it.
  PdfSearch _indexPages(PdfPages pages) {
    final search = PdfSearch(pages.pageCount);
    for (var page = 0; page < pages.pageCount; page++) {
      pages.run(page);
      search.setPage(page, pages.pageAt(page).runs);
    }
    return search;
  }

  void _onFind() {
    final find = _find;
    if (find == null) return;
    if (find.matches.isEmpty) {
      _steppedTo = 0;
    } else if (find.current != _steppedTo) {
      _steppedTo = find.current;
      // A page file and a flowing document go to the match itself, gliding,
      // and do it from the find they are handed. Setting their position here
      // as well would jump them first and leave the glide nothing to do.
      if (widget.store.isGrid) {
        widget.store.position = _unitOf(find.matches[find.current]);
      }
    }
    // A deck goes to the slide the match is on, including the first match,
    // which is the one a find lands on without ever being stepped to. Nothing
    // else would move it: a bench does not glide to a match of its own accord,
    // and a find that reports a word on slide six while leaving the reader on
    // slide one has told somebody their word is in the document and then hidden
    // it from them.
    if (widget.store.isDeck && find.matches.isNotEmpty) {
      widget.store.position = _unitOf(find.matches[find.current]);
    }

    // Sent to the match again, by the search key or a chevron: a grid goes
    // back to it even if it has been there before.
    final again = find.reveals != _revealed;
    _revealed = find.reveals;
    _ringMatch(find, again: again);
    setState(() {});
  }

  /// How many times find had sent the reader to its match when it last
  /// spoke.
  int _revealed = 0;

  /// The match last ringed in a spreadsheet, so typing another letter that
  /// finds the same cell does not ring it again.
  SheetMatch? _ringed;

  /// In a spreadsheet a row is not a place, a cell is: the match the find is
  /// on is ringed as well as scrolled to, so the grid goes across to it as
  /// well as down, and the cell bar reads it out in full. That includes the
  /// first match, which the find lands on without being stepped to.
  void _ringMatch(FindController find, {bool again = false}) {
    if (!widget.store.isGrid || find.matches.isEmpty) {
      _ringed = null;
      return;
    }
    final match = find.matches[find.current];
    if (match.path.length < 3) return;
    final cell = SheetCell(match.path[1], match.path[2]);
    final found = (sheet: match.section, cell: cell);
    final sheets = SheetController.of(widget.store);
    // Typing on while the same cell stays found leaves it be, even when the
    // reader has let it go since. Asked for again, it is gone back to.
    final changed = found != _ringed;
    _ringed = found;
    if (!changed && !again) return;
    final standing = sheets.sheet == match.section && sheets.selected == cell;
    if (standing && !again) return;
    // Asked for again while still chosen: chosen afresh, which brings it
    // back into view wherever the grid has been taken since.
    if (standing) sheets.selected = null;
    // The sheet the match is on, which is not the sheet showing when the
    // first match of a find is on another one.
    if (match.section != sheets.sheet) {
      widget.store.position = _unitOf(match);
    }
    sheets.selected = cell;
  }

  /// Where in the document a match sits, in the units the store counts in.
  ///
  /// A page file and the index over it count the same pages, so the match's
  /// own page is exact. A prose index counts the strings it walked, which is
  /// not the same as the blocks the sheet lays out, so there the match's share
  /// of the document is what carries across.
  int _unitOf(FindMatch match) {
    final units = widget.store.unitCount;
    if (units <= 1) return 0;
    if (_find?.source.unitCount == units) return match.unit;
    return (match.position * (units - 1)).round().clamp(0, units - 1);
  }

  /// The cells the current query found, each with the sheet it is on.
  ///
  /// A grid match carries the path the model gave it, block then row then
  /// column, and the sheet body addresses a cell by the last two. The sheet
  /// is kept with it, because the same row and column on another sheet is
  /// another cell.
  Set<SheetMatch> get _matchedCells {
    final find = _find;
    // Put away, a find lights nothing: a wash left on a cell afterwards would
    // look like a fill the file itself gave it.
    if (find == null || !find.isOpen) return const <SheetMatch>{};
    return <SheetMatch>{
      for (final match in find.matches)
        if (match.path.length >= 3)
          (sheet: match.section, cell: SheetCell(match.path[1], match.path[2])),
    };
  }

  // The body.

  ReaderBody _body(BuildContext context) {
    final store = widget.store;
    final pages = _pages;
    if (store.isPdf) {
      if (pages == null) return _NoBody(store: store);
      return PdfBody(store: store, pages: pages, frames: _frames, find: _find);
    }
    final document = store.document;
    if (document == null) return _NoBody(store: store);
    if (store.isGrid) {
      return SheetBody(store: store, matches: _matchedCells);
    }
    if (store.isDeck) {
      return DeckBody(
        store: store,
        document: document,
        onPresent: _present,
      );
    }
    return ProseBody(
      store: store,
      document: document,
      source: _markdownSource(),
      anchorBlock: _openedAt,
      find: _find,
    );
  }

  /// A Markdown file's own text, for the back of the sheet.
  ///
  /// Only Markdown has a source worth showing: a Word file's back carries the
  /// style names it actually stored, which the body reads from the model.
  String? _markdownSource() {
    final store = widget.store;
    if (store.document?.sourceFormat != 'md') return null;
    return utf8.decode(store.bytes, allowMalformed: true);
  }

  // The placement.

  /// The page a mark is being set into, once it has been run.
  ///
  /// The layer snaps to the page's own baselines, so it cannot be put up until
  /// the page it is snapping to exists. A page the reader has not reached yet
  /// is run here rather than waited for, because the mark arrived from the pad
  /// and there is nothing else for this frame to be.
  Widget? _placement() {
    final mark = _loose;
    final pages = _pages;
    if (_placed || mark == null || pages == null || pages.pageCount == 0) {
      return null;
    }
    final index = widget.store.position;
    if (!pages.holds(index)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) pages.run(index);
      });
      return null;
    }
    final list = pages.pageAt(index).list;
    if (list == null) return null;
    final safeArea = MediaQuery.paddingOf(context);
    final frame = _frames.value;
    return PlacementLayer(
      key: _placementKey,
      mark: mark,
      page: list,
      pageIndex: index,
      // Where the paper is, as the body last drew it. Without this the layer
      // works the page out from the sheet, which is only ever right at the top
      // of the first page: everywhere else the mark is recorded as far down
      // the page as the reader had scrolled, and far enough down it is
      // recorded past the last line and drawn nowhere at all.
      paper: frame != null && frame.index == index ? frame.rect : null,
      // The readable part of the screen, which is what the mark is dimmed and
      // held inside.
      sheet: Rect.fromLTRB(
        kSheetLeft,
        kSheetTop + readerContentTop(safeArea),
        kSheetLeft + kSheetWidth,
        kSheetTop +
            MediaQuery.sizeOf(context).height -
            readerContentBottom(safeArea),
      ),
      onPlace: (signature) {
        setState(() {
          _placed = true;
          _drawn = null;
        });
        widget.store.placeSignature(signature);
        widget.onPlaced?.call();
      },
    );
  }

  /// The scrim, and the pills coming out of the dots.
  Widget _menuLayer() {
    final actions = _actions;
    final safeArea = MediaQuery.paddingOf(context);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Feel.tap.ring();
              _closeMenu();
            },
            child: ColoredBox(
              color: AppColors.scrim.withValues(
                alpha: AppColors.scrim.a * _menu.scrim.value,
              ),
            ),
          ),
        ),
        GooMenu(
          drives: <double>[
            for (var i = 0; i < _menu.actionCount; i++)
              _menu.actionDrive(i).value,
          ],
          items: <GooMenuItem>[for (final a in actions) gooItemOf(a)],
          onPick: (i) => _act(actions[i]),
          anchor: readerMenuAnchor(safeArea),
          bounds: readerMenuBounds(safeArea, MediaQuery.sizeOf(context).height),
        ),
        // The dots again, over the goo. The band draws them under it, and a
        // body that swallowed the control it came out of leaves nothing to
        // read and nothing to aim at.
        Positioned.fromRect(
          rect: readerMenuAnchor(safeArea),
          child: IgnorePointer(
            child: CustomPaint(
              painter: OverflowDotsPainter(
                t: _menu.progress.value.clamp(0.0, 1.0),
                colour: AppColors.ink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final find = _find;
    final placement = _placement();
    return ReaderScreen(
      store: widget.store,
      bodyBuilder: _body,
      placement: placement,
      overlay: find == null || !find.isOpen
          ? null
          : FindLayer(controller: find),
      overlayHead: find == null || !find.isOpen ? 0 : find.titleFade,
      matches: find?.positions ?? const <double>[],
      liveMatch: find?.livePosition,
      matchOpacity: find?.railOpacity ?? 1,
      matchCounts: find?.unitCounts ?? const <int>[],
      onFind: _openFind,
      onMenu: _openMenu,
      menu: !_menuOpen ? null : _menuLayer(),
      menuOpen: _menu.progress.value.clamp(0.0, 1.0),
      notice: _notice,
      placing: placement != null,
      onConfirmPlacement: () => _placementKey.currentState?.commit(),
      onCancelPlacement: _cancelPlacement,
      onLeave: widget.onLeave,
    );
  }
}

/// The body of a document there is nothing to draw yet: one that is still
/// being read, or one whose parse failed and which the shell is about to put
/// the torn sheet up for.
///
/// It exists so the shell always has a body to ask, and it claims nothing: no
/// units, no marks, and a label the chip never gets to print, because a
/// document in either state carries neither chip nor strip.
///
/// Both faces are the loading band. A file that has not been read yet holds
/// nothing on either side of itself, so turning its corner has to uncover the
/// same answer the front is already giving rather than blank paper.
class _NoBody extends ReaderBody {
  const _NoBody({required this.store});

  final DocumentStore store;

  @override
  Widget buildFront(BuildContext context) => const _UnreadSheet();

  @override
  Widget buildBack(BuildContext context) => const _UnreadSheet();

  @override
  int get unitCount => 0;

  @override
  String get positionLabel => store.positionLabel;

  @override
  List<double> get foreEdgeMarks => const <double>[];
}

/// The sheet of a document that is still being read, on either face.
///
/// It is the same band a page of a PDF shows while its content stream is being
/// run, held at the frame a page first appears on, because there is no
/// controller to sweep it and a document waits for its bytes rather than for a
/// clock.
class _UnreadSheet extends StatelessWidget {
  const _UnreadSheet();

  @override
  Widget build(BuildContext context) => const PageShimmer(
    size: Size(kSheetWidth, kSheetHeight),
    progress: kShimmerFirstFrame,
  );
}
