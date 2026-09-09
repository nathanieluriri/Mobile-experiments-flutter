import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../painting/signature_painter.dart';
import '../../pdf/pdf_search.dart';
import '../../services/document_store.dart';
import '../../theme/metrics.dart';
import '../sign/placement_layer.dart';
import 'bodies/page_states.dart';
import 'bodies/pdf_body.dart';
import 'bodies/prose_body.dart';
import 'bodies/sheet_body.dart';
import 'bodies/spine_table.dart';
import 'find/find_layer.dart';
import 'reader_screen.dart';
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
    this.placing,
    this.onPlaced,
    this.onLeave,
  });

  /// The open document.
  final DocumentStore store;

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

class _ReaderHostState extends State<ReaderHost> with TickerProviderStateMixin {
  /// The page engine, held for the life of the route rather than rebuilt with
  /// the body, so a page interpreted once stays interpreted and the fore edge,
  /// the folio chip and the block all count the same pages.
  PdfPages? _pages;

  /// Find is built on the first press of the search pill, because the index it
  /// stands on costs a walk of the whole document and most readings never ask
  /// for it.
  FindController? _find;

  /// Which match the chevrons were standing on last, so a step moves the
  /// reader and a keystroke does not. The fore edge is the map; the chevrons
  /// are the step.
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
    _openPages();
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
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    // A document that arrives while the reader is already open gets its page
    // engine on the next frame rather than inside the notification that
    // announced it, because opening one writes the page count straight back to
    // the store that is still handing out that notification.
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
    final pages = PdfPages(file, onPageRun: store.recordPageWords);
    _pages = pages;
    store.pdfPageCount = pages.pageCount;
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
    final find = FindController(vsync: this, source: source)
      ..addListener(_onFind);
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
      widget.store.position = _unitOf(find.matches[find.current]);
    }
    setState(() {});
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

  /// The cells the current query found, for the spine glyphs of a grid.
  ///
  /// A grid match carries the path the model gave it, block then row then
  /// column, and the sheet body addresses a cell by the last two.
  Set<SheetCell> get _matchedCells {
    final find = _find;
    if (find == null) return const <SheetCell>{};
    return <SheetCell>{
      for (final match in find.matches)
        if (match.path.length >= 3) SheetCell(match.path[1], match.path[2]),
    };
  }

  // The body.

  ReaderBody _body(BuildContext context) {
    final store = widget.store;
    final pages = _pages;
    if (store.isPdf) {
      if (pages == null) return _NoBody(store: store);
      return PdfBody(store: store, pages: pages);
    }
    final document = store.document;
    if (document == null) return _NoBody(store: store);
    if (store.isGrid) return SheetBody(store: store, matches: _matchedCells);
    return ProseBody(
      store: store,
      document: document,
      source: _markdownSource(),
      anchorBlock: _openedAt,
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
    final mark = widget.placing;
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
    return PlacementLayer(
      mark: mark,
      page: list,
      pageIndex: index,
      onPlace: (signature) {
        setState(() => _placed = true);
        widget.store.placeSignature(signature);
        widget.onPlaced?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final find = _find;
    return ReaderScreen(
      store: widget.store,
      bodyBuilder: _body,
      placement: _placement(),
      overlay: find == null || !find.isOpen ? null : FindLayer(controller: find),
      matches: find?.positions ?? const <double>[],
      liveMatch: find?.livePosition,
      matchOpacity: find?.railOpacity ?? 1,
      matchCounts: find?.unitCounts ?? const <int>[],
      onFind: _openFind,
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
