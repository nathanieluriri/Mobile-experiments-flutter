import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../constants/gooey_fab.dart';
import '../../data/library.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import '../../theme/typography.dart';
import '../../widgets/gooey_fab/gooey_fab.dart';
import 'desk_colophon.dart';
import 'desk_empty.dart';
import 'desk_top_bar.dart';
import 'destination_panel.dart';
import 'grid_body.dart';
// Named for the list it draws, under the alias that keeps it clear of the
// ListBody Flutter exports for laying children out one after another.
import 'list_body.dart' show DeskListBody;
import 'nav_drawer.dart';
import 'overflow_menu.dart';
import 'search_pill.dart';
import 'shell_model.dart';
import 'sort_menu.dart';
import 'sort_row.dart';
import 'tab_strip.dart';
import 'undo_pill.dart';

/// Where the two lines of a search that found nothing sit.
const kNoResultsTop = 300.0;
const kNoResultsGap = 8.0;

/// How long the undo pill takes to come up off the desk.
const kUndoPillIn = Duration(milliseconds: 180);

/// The chrome above the body: the top bar, the tabs and the sort row.
const kShellChrome = kTopBarHeight + kTabStripHeight + kSortRowHeight;

/// How fast a finger has to be going for its direction to decide the drawer,
/// in points a second. Below this the drawer goes wherever it is nearest.
const kDrawerFlingVelocity = 300.0;

/// How much room the body keeps under the last row.
const kBodyBottomPadding = 96.0;

/// The desk: a top bar, the format tabs, the sort row, and the library.
///
/// The four parts are stacked and none of them scrolls under another, so the
/// only thing that moves when you scroll is the documents. A drawer comes in
/// over all four from the left, and the hamburger that opens it is a readout
/// of where it has got to rather than an animation of its own.
class DeskScreen extends StatefulWidget {
  const DeskScreen({
    super.key,
    required this.store,
    this.onOpen,
    this.onSign,
  });

  final LibraryStore store;

  /// Opening a document.
  ///
  /// The row's rect on the desk comes with it, because the reader grows out of
  /// the row rather than sliding over it, and the desk is the only thing that
  /// knows where a row has been scrolled to.
  final void Function(LibraryEntry entry, Rect cardRect)? onOpen;

  /// Taking a document to the signature pad.
  final void Function(LibraryEntry entry)? onSign;

  @override
  State<DeskScreen> createState() => _DeskScreenState();
}

class _DeskScreenState extends State<DeskScreen> with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  late final AnimationController _drawer;
  late final AnimationController _menu;
  late final AnimationController _overflow;
  late final AnimationController _undo;
  late final AnimationController _undoRise;

  /// Which end the drawer was last sent to, so a spring that stops inside its
  /// own tolerance can be put exactly on it. A panel resting a hundredth of a
  /// point short is a panel whose glyph is a hundredth of a degree short, and
  /// the two are only ever the same object if both land.
  bool _drawerOpen = false;

  DrawerDestination _destination = DrawerDestination.recent;
  DeskTab _tab = DeskTab.recent;
  SortField _sortField = SortField.dateModified;
  SortOrder _sortOrder = SortOrder.newToOld;
  DeskView _view = DeskView.list;
  LibraryEntry? _pill;

  /// The document whose overflow menu is open, and where its row was when the
  /// three dots were tapped, which is what the menu is hung off.
  LibraryEntry? _acting;
  Rect _actingRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    // The drawer is driven by a simulation, so its duration is only what a
    // stopped controller falls back to. Its bounds are what clamp the spring's
    // overshoot, so the panel never opens past its own edge.
    _drawer = AnimationController(vsync: this, duration: kChromeIn);
    _drawer.addStatusListener((status) {
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.reverse) {
        return;
      }
      final rest = _drawerOpen ? 1.0 : 0.0;
      if (_drawer.value != rest) _drawer.value = rest;
    });
    _menu = AnimationController(vsync: this, duration: kSortMenuIn);
    _overflow = AnimationController(vsync: this, duration: kSortMenuIn);
    _undo = AnimationController(vsync: this, duration: kUndoPill);
    _undo.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.store.commitRemoval();
        setState(() => _pill = null);
      }
    });
    _undoRise = AnimationController(vsync: this, duration: kUndoPillIn);
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _drawer.dispose();
    _menu.dispose();
    _overflow.dispose();
    _undo.dispose();
    _undoRise.dispose();
    _scroll.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _onStoreChanged() => setState(() {});

  // The drawer.

  double get _drawerWidth => drawerWidth(MediaQuery.sizeOf(context).width);

  void _toggleDrawer() => _settleDrawer(open: _drawer.value < 0.5, velocity: 0);

  void _dragDrawer(double delta) {
    _drawer
      ..stop()
      ..value = (_drawer.value + delta / _drawerWidth).clamp(0.0, 1.0);
  }

  void _endDrawerDrag(double velocity) {
    final open = velocity.abs() > kDrawerFlingVelocity
        ? velocity > 0
        : _drawer.value > 0.5;
    _settleDrawer(open: open, velocity: velocity / _drawerWidth);
  }

  /// Sends the drawer to whichever end it is going to, on the one spring that
  /// also turns the hamburger.
  ///
  /// Handing the finger's own velocity to the simulation is what makes a flick
  /// and a tap the same motion at two speeds rather than two behaviours.
  void _settleDrawer({required bool open, required double velocity}) {
    _drawerOpen = open;
    _drawer.animateWith(
      SpringSimulation(
        AppSprings.drawer,
        _drawer.value,
        open ? 1 : 0,
        velocity,
      ),
    );
  }

  void _select(DrawerDestination destination) {
    setState(() => _destination = destination);
    _settleDrawer(open: false, velocity: 0);
  }

  // The sort menu.

  void _openMenu() => _menu.forward();

  void _closeMenu() => _menu.reverse();

  void _setField(SortField field) {
    setState(() => _sortField = field);
    _closeMenu();
  }

  void _setOrder(SortOrder order) {
    setState(() => _sortOrder = order);
    _closeMenu();
  }

  // Search.

  void _onQueryChanged(String value) {
    widget.store.query = value;
    setState(() {});
  }

  /// The way in to a file by name, which is what the folder glyph on the pill
  /// and the button's first action both mean.
  ///
  /// Every document quire can open is already in the library, so opening one
  /// is a matter of finding it. The field takes the focus and the destination
  /// widens to everything, so nothing typed into it is held back by wherever
  /// the drawer had left you standing.
  void _browse() {
    setState(() => _destination = DrawerDestination.allFiles);
    _queryFocus.requestFocus();
  }

  /// What the action button's three pills do, in the order [kFabActions] lists
  /// them.
  void _fabAction(int index) {
    switch (index) {
      // Open a file.
      case 0:
        _browse();
      // Sign a PDF. Which PDF is a question only the library can answer, so
      // this narrows the desk to the two documents that can carry a signature
      // and leaves the choosing where the choosing belongs.
      case 1:
        setState(() {
          _destination = DrawerDestination.allFiles;
          _tab = DeskTab.pdf;
        });
      // Recent.
      case 2:
        setState(() {
          _destination = DrawerDestination.recent;
          _tab = DeskTab.recent;
        });
        if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _clearQuery() {
    _query.clear();
    widget.store.query = '';
    _queryFocus.unfocus();
    setState(() {});
  }

  // What a document can have done to it.

  /// Opens the overflow menu against the row that asked for it.
  void _openOverflow(LibraryEntry entry, Rect rect) {
    setState(() {
      _acting = entry;
      _actingRect = rect;
    });
    _overflow.forward(from: 0);
  }

  void _closeOverflow() {
    _overflow.value = 0;
    setState(() => _acting = null);
  }

  void _act(LibraryEntry entry, DeskAction action) {
    _closeOverflow();
    switch (action) {
      case DeskAction.read:
        widget.onOpen?.call(entry, _actingRect);
      case DeskAction.sign:
        widget.onSign?.call(entry);
      case DeskAction.dogEar:
        final store = widget.store.storeFor(entry);
        store.toggleDogEar(store.position);
      case DeskAction.remove:
        _remove(entry);
    }
  }

  /// Takes a document off the desk.
  ///
  /// Nothing here touches the row's pixels. The desk announces that the
  /// document has gone and the body, which drew the row, is what takes it
  /// apart: that is what makes every route out of the library crumble the same
  /// way, and what makes it impossible for a sort or a filter to crumble
  /// anything.
  void _remove(LibraryEntry entry) {
    widget.store.remove(entry);
    setState(() => _pill = entry);
    _undoRise.forward(from: 0);
    _undo.forward(from: 0);
  }

  void _undoRemoval() {
    if (_pill == null) return;
    _undo.stop();
    _undoRise.value = 0;
    setState(() => _pill = null);
    widget.store.undoRemove();
  }

  /// What the body shows: the search, then the tab, then the sort.
  List<LibraryEntry> get _entries => shellEntries(
        widget.store.visible,
        _tab,
        _sortField,
        _sortOrder,
        widget.store.peek,
      );

  /// How much each tab holds, before the search is applied, so a count is a
  /// fact about the library rather than about what you have typed.
  Map<DeskTab, int> get _counts => <DeskTab, int>{
        for (final tab in DeskTab.values)
          tab: widget.store.entries.where(tab.holds).length,
      };

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final bare = widget.store.entries.isEmpty;
    final nothingMatched =
        !bare && _destination.library && widget.store.visible.isEmpty;
    return ColoredBox(
      color: AppColors.ground,
      child: Stack(
        children: [
          Positioned.fill(child: _shell(top, bottom, bare)),
          if (nothingMatched) _noResults(),
          if (_pill case final removed?)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom + kUndoPillBottom,
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[_undo, _undoRise]),
                  builder: (context, _) => UndoPill(
                    title: removed.title,
                    drained: _undo.value,
                    rise: easeOutCubic.transform(_undoRise.value),
                    onUndo: _undoRemoval,
                  ),
                ),
              ),
            ),
          // Over the library and under everything that opens on top of it:
          // the button is the desk's own control, so a menu or the drawer
          // covers it rather than the other way round.
          GooeyFab(onSelected: _fabAction),
          if (_destination.library && !bare) _menuLayer(top),
          if (_acting case final entry?) _overflowLayer(entry),
          AnimatedBuilder(
            animation: _drawer,
            builder: (context, _) => NavDrawer(
              progress: _drawer.value,
              selected: _destination,
              onSelect: _select,
              onDismiss: () => _settleDrawer(open: false, velocity: 0),
              onDrag: _dragDrawer,
              onDragEnd: _endDrawerDrag,
            ),
          ),
          // Above the drawer, because it is the drawer's handle: the arrow it
          // turns into has to be legible over the panel it opened.
          Positioned(
            left: kTopBarPaddingX,
            top: top + kMenuButtonTop,
            child: AnimatedBuilder(
              animation: _drawer,
              builder: (context, _) => MenuButton(
                progress: _drawer.value,
                onTap: _toggleDrawer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shell(double top, double bottom, bool bare) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: top),
        AnimatedBuilder(
          animation: _query,
          builder: (context, _) => DeskTopBar(
            search: SearchPill(
              controller: _query,
              focusNode: _queryFocus,
              onChanged: _onQueryChanged,
              onClear: _clearQuery,
              onBrowse: _browse,
            ),
          ),
        ),
        // A desk with nothing on it drops the tabs and the sort row, for the
        // same reason a destination with nothing in it does: they are chrome
        // about a list, and there is no list.
        if (_destination.library && !bare) ...[
          TabStrip(
            selected: _tab,
            counts: _counts,
            onSelect: (tab) => setState(() => _tab = tab),
          ),
          SortRow(
            field: _sortField,
            order: _sortOrder,
            view: _view,
            onOpenMenu: _openMenu,
            onView: (view) => setState(() => _view = view),
          ),
        ],
        Expanded(child: _body(bottom, bare)),
      ],
    );
  }

  Widget _body(double bottom, bool bare) {
    if (!_destination.library) {
      return DestinationPanel(destination: _destination);
    }
    if (bare) return const DeskEmpty(onOpen: null);
    // Counted off what is on screen, not off the library. A tab that shows
    // two documents with `6 DOCUMENTS` set under them would be the desk
    // contradicting itself in the same glance.
    final colophon = DeskColophon(
      documents: _entries.length,
      words: widget.store.wordsIn(_entries),
      minutes: widget.store.minutesIn(_entries),
    );
    // The body is what scrolls, because the rows are its own: a slot closing
    // behind a removal has to be able to move the list under the finger. The
    // shell only says how much room to leave at the bottom for what it floats
    // over the body.
    if (_view == DeskView.list) {
      return DeskListBody(
        library: widget.store,
        entries: _entries,
        query: widget.store.query,
        onOpen: widget.onOpen,
        onOverflow: _openOverflow,
        controller: _scroll,
        padding: EdgeInsets.only(bottom: bottom + kBodyBottomPadding),
        footer: colophon,
      );
    }
    return GridBody(
      library: widget.store,
      entries: _entries,
      query: widget.store.query,
      onOpen: widget.onOpen,
      onOverflow: _openOverflow,
      controller: _scroll,
      padding: const EdgeInsets.all(kGridPadding).copyWith(
        bottom: bottom + kBodyBottomPadding,
      ),
      footer: colophon,
    );
  }

  /// The sort menu, and the tap anywhere else that closes it.
  ///
  /// It is drawn in the shell's own stack rather than pushed as a route, so
  /// the library behind it stays live and the menu cannot be left behind by a
  /// navigation.
  Widget _menuLayer(double top) {
    return AnimatedBuilder(
      animation: _menu,
      builder: (context, _) {
        // Built from the first frame of the run rather than the first frame
        // with something to see, so the arrival has a t of exactly 0.
        if (_menu.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
              ),
            ),
            Positioned(
              left: kSortRowPaddingX,
              top: top + kShellChrome + kSortMenuOffset,
              child: SortMenu(
                t: _menu.value,
                field: _sortField,
                order: _sortOrder,
                onField: _setField,
                onOrder: _setOrder,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The overflow menu, hung off the three dots that opened it.
  ///
  /// Its right edge lines up with the row's own right padding and it hangs
  /// just under the row, so it reads as belonging to that document rather than
  /// to the screen. Like the sort menu it is drawn in the shell's own stack
  /// rather than pushed as a route, so the library behind it stays live.
  Widget _overflowLayer(LibraryEntry entry) {
    return AnimatedBuilder(
      animation: _overflow,
      builder: (context, _) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeOverflow,
              ),
            ),
            Positioned(
              right: kListRowPaddingX,
              top: _actingRect.bottom + kOverflowMenuOffset,
              child: OverflowMenu(
                t: _overflow.value,
                entry: entry,
                onAction: (action) => _act(entry, action),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _noResults() {
    return Positioned(
      left: kScreenPadding,
      right: kScreenPadding,
      top: kNoResultsTop,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nothing on the desk matches.',
            style: AppText.title.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: kNoResultsGap),
          Text(
            'for "${widget.store.query}"',
            style: AppText.docMeta.copyWith(color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}
