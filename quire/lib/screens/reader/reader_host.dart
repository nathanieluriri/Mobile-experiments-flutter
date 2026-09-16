import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../../painting/signature_painter.dart';
import '../../painting/overflow_dots_painter.dart';
import '../../pdf/pdf_search.dart';
import '../../pdf/writer.dart' show PdfWriteError;
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/feedback.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../sign/placement_layer.dart';
import '../sign/sign_screen.dart';
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
    _menu.animations.addListener(_onMenuMoved);
    _frames.addListener(_onFramesMoved);
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

  /// What this document can have done to it from inside itself.
  List<ReaderAction> get _actions => <ReaderAction>[
        if (widget.store.isPdf) ReaderAction.sign,
        if (widget.store.isPdf && widget.store.signed)
          ReaderAction.shareSigned,
        widget.store.dogEared.contains(widget.store.position)
            ? ReaderAction.undogEar
            : ReaderAction.dogEar,
        if (widget.store.dogEared.isNotEmpty) ReaderAction.dogEars,
        ReaderAction.find,
        ReaderAction.view,
        ReaderAction.lock,
      ];

  void _act(ReaderAction action) {
    _closeMenu();
    switch (action) {
      case ReaderAction.sign:
        _sign();
      case ReaderAction.dogEar:
      case ReaderAction.undogEar:
        widget.store.toggleDogEar(widget.store.position);
      case ReaderAction.dogEars:
        _dogEars();
      case ReaderAction.shareSigned:
        _shareSigned();
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
          position: Tween<Offset>(
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
            note: 'Back does nothing and every bar leaves the screen. You can '
                'still scroll. Tap the page for the way out.',
            onTap: () => Navigator.of(context).pop(ReaderLock.back),
          ),
          DeskSheetRow(
            label: 'Lock to this page',
            icon: LucideIcons.squareDashedBottom,
            note: 'Pins the reading where it is and takes every bar off the '
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
      return PdfBody(store: store, pages: pages, frames: _frames);
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
      overlay: find == null || !find.isOpen ? null : FindLayer(controller: find),
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
