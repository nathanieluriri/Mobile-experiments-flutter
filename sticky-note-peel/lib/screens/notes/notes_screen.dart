import 'package:flutter/widgets.dart';

import '../../data/note.dart';
import '../../data/note_actions.dart';
import '../../data/note_store.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import '../../theme/typography.dart';
import '../../widgets/note_column.dart';
import '../../widgets/sticky_note.dart';
import 'compose_note_button.dart';
import 'compose_sheet.dart';
import 'note_list_transition.dart';
import 'notes_drawer.dart';
import 'notes_header.dart';
import 'search_field.dart';

/// The only screen: a scrolling column of notes over a dark ground, with the
/// list of lists sliding in over it.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.store});

  final NoteStore store;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen>
    with TickerProviderStateMixin {
  final Map<String, double> _heights = <String, double>{};
  final ScrollController _scroll = ScrollController();
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  late final NoteListTransition _list;
  late final AnimationController _dim;
  late final AnimationController _reflow;
  late final AnimationController _drawer;
  late final AnimationController _search;
  late final AnimationController _compose;
  late final SpringCurve _reflowCurve;
  late final SpringCurve _drawerCurve;
  late final SpringCurve _searchCurve;
  late final SpringCurve _composeCurve;

  String? _activeNoteId;
  int? _reflowIndex;
  double _reflowSpace = 0;

  @override
  void initState() {
    super.initState();
    _list = NoteListTransition(this)..addListener(_onListChanged);
    widget.store.addListener(_onStoreChanged);
    _dim = AnimationController(vsync: this, duration: kDimDuration);

    final reflowDuration = springDuration(AppSprings.noteListLayout);
    _reflow = AnimationController(vsync: this, duration: reflowDuration);
    _reflowCurve =
        SpringCurve(AppSprings.noteListLayout, duration: reflowDuration);
    _reflow.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _reflowIndex = null);
      }
    });

    // The panel arrives on the same spring the list closes with, so the two
    // motions read as one hand.
    _drawer = AnimationController(vsync: this, duration: reflowDuration);
    _drawerCurve =
        SpringCurve(AppSprings.noteListLayout, duration: reflowDuration);
    _search = AnimationController(vsync: this, duration: reflowDuration);
    _searchCurve =
        SpringCurve(AppSprings.noteListLayout, duration: reflowDuration);
    _compose = AnimationController(vsync: this, duration: reflowDuration);
    _composeCurve =
        SpringCurve(AppSprings.noteListLayout, duration: reflowDuration);

    _list.sync(widget.store.visible);
  }

  void _onStoreChanged() {
    _list.sync(widget.store.visible);
    setState(() {});
  }

  void _onListChanged() => setState(() {});

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _list.dispose();
    _dim.dispose();
    _reflow.dispose();
    _drawer.dispose();
    _search.dispose();
    _compose.dispose();
    _scroll.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _focus(String id) {
    setState(() => _activeNoteId = id);
    _dim.animateTo(1, duration: kDimDuration, curve: easeInOutQuad);
  }

  void _blur() {
    setState(() => _activeNoteId = null);
    _dim.animateTo(0, duration: kDimDuration, curve: easeInOutQuad);
  }

  void _remove(String id, NoteAction action) {
    final index = widget.store.visible.indexWhere((note) => note.id == id);
    if (index < 0) {
      return;
    }
    final height = _heights[id] ?? kInitialNoteHeight;
    setState(() {
      _activeNoteId = null;
      _reflowIndex = index + 1;
      _reflowSpace = height + kNoteListGap;
    });
    _list.removeNow(id);
    widget.store.remove(id);
    _dim.animateTo(0, duration: kDimDuration, curve: easeInOutQuad);
    _reflow.forward(from: 0);
  }

  void _openSearch() {
    _search.forward();
    _queryFocus.requestFocus();
  }

  void _closeSearch() {
    _queryFocus.unfocus();
    _query.clear();
    widget.store.setQuery('');
    _search.reverse();
    setState(() {});
  }

  void _openCompose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _compose.forward();
  }

  void _closeCompose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _compose.reverse();
  }

  /// Files a freshly written note at the top of the list and gets out of the
  /// way so it can be seen arriving.
  void _saveComposed(
    Color color,
    String title,
    String? body,
    List<String>? checklist,
    List<String> tags,
  ) {
    widget.store.add(
      Note(
        id: widget.store.nextId(title),
        color: color,
        title: title,
        body: body,
        checklist: checklist,
        tags: tags,
      ),
    );
    _closeCompose();
  }

  void _openDrawer() => _drawer.forward();

  void _closeDrawer() => _drawer.reverse();

  void _selectTag(String? tag) {
    widget.store.setTagFilter(tag);
    _closeDrawer();
  }

  /// Drags the panel with the finger, then lets it finish in whichever
  /// direction it was already heading.
  void _dragDrawer(DragUpdateDetails details, double width) {
    _drawer.value =
        (_drawer.value + details.primaryDelta! / width).clamp(0.0, 1.0);
  }

  void _endDrawerDrag(DragEndDetails details, double width) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() > kDrawerFlingVelocity) {
      if (velocity > 0) {
        _drawer.forward();
      } else {
        _drawer.reverse();
      }
      return;
    }
    if (_drawer.value > 0.5) {
      _drawer.forward();
    } else {
      _drawer.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final noteWidth = width - kScreenHorizontalPadding * 2;
    final panelWidth = drawerWidth(width);
    final notes = _list.rendered;
    final activeIndex = notes.indexWhere((note) => note.id == _activeNoteId);

    return ColoredBox(
      color: AppColors.ink,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: padding.top),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_dim, _scroll, _search]),
                  builder: (context, _) => NotesHeader(
                    scrollY: _scrollY,
                    dim: _dim.value,
                    title: widget.store.title,
                    onMenu: _openDrawer,
                    search: SearchField(
                      open: _searchCurve.transform(_search.value),
                      controller: _query,
                      focusNode: _queryFocus,
                      onOpen: _openSearch,
                      onClose: _closeSearch,
                      onChanged: widget.store.setQuery,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: _activeNoteId == null
                        ? const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          )
                        : const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(
                      left: kScreenHorizontalPadding,
                      right: kScreenHorizontalPadding,
                      bottom: kNoteListBottomPadding,
                    ),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_reflow, _search]),
                      builder: (context, _) => NoteColumn(
                        gap: kNoteListGap,
                        paintLast: activeIndex < 0 ? null : activeIndex + 1,
                        extraSpaceIndex: _reflowIndex,
                        extraSpace: _reflowIndex == null
                            ? 0
                            : _reflowSpace *
                                (1 - _reflowCurve.transform(_reflow.value)),
                        children: [
                          NoteSlot(
                            key: const ValueKey<String>('title-slot'),
                            factor: 1 - _searchCurve.transform(_search.value),
                            child: _largeTitle(),
                          ),
                          for (final note in notes)
                            NoteSlot(
                              key: ValueKey<String>('slot-${note.id}'),
                              factor: _list.factorOf(note.id),
                              child: Opacity(
                                opacity: _list.factorOf(note.id).clamp(0, 1),
                                child: StickyNote(
                                  key: ValueKey<String>(note.id),
                                  note: note,
                                  width: noteWidth,
                                  isActive: note.id == _activeNoteId,
                                  isDimmed: _activeNoteId != null &&
                                      note.id != _activeNoteId,
                                  onFocus: _focus,
                                  onBlur: _blur,
                                  onRemove: _remove,
                                  onHeight: (id, height) =>
                                      _heights[id] = height,
                                  query: widget.store.query,
                                ),
                              ),
                            ),
                          if (notes.isEmpty)
                            _emptyState(key: const ValueKey<String>('empty')),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: padding.bottom + kComposeButtonBottomMargin,
            child: AnimatedBuilder(
              animation: _dim,
              builder: (context, _) => ComposeNoteButton(
                dim: _dim.value,
                isInteractive: _activeNoteId == null,
                onTap: _openCompose,
              ),
            ),
          ),
          _drawerLayer(panelWidth, padding),
          _composeLayer(padding),
        ],
      ),
    );
  }

  Widget _composeLayer(EdgeInsets padding) {
    return AnimatedBuilder(
      animation: _compose,
      builder: (context, _) {
        final open = _composeCurve.transform(_compose.value);
        if (open <= 0) {
          return const SizedBox.shrink();
        }
        final insets = MediaQuery.viewInsetsOf(context);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeCompose,
                child: ColoredBox(
                  color: AppColors.ink
                      .withValues(alpha: kDrawerScrimOpacity * open),
                ),
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: kScreenHorizontalPadding,
                    right: kScreenHorizontalPadding,
                    top: kComposeMargin,
                    bottom: insets.bottom + kComposeMargin,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      child: Opacity(
                        opacity: open,
                        // The sheet comes up out of the button that asked for
                        // it rather than appearing on top of everything.
                        child: Transform.translate(
                          offset: Offset(0, (1 - open) * 260),
                          child: Transform.scale(
                            scale: 0.72 + 0.28 * open,
                            alignment: Alignment.bottomCenter,
                            child: ComposeSheet(
                              onCancel: _closeCompose,
                              onSave: _saveComposed,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _drawerLayer(double panelWidth, EdgeInsets padding) {
    return AnimatedBuilder(
      animation: _drawer,
      builder: (context, _) {
        final open = _drawerCurve.transform(_drawer.value);
        if (open <= 0) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDrawer,
                child: ColoredBox(
                  color: AppColors.ink
                      .withValues(alpha: kDrawerScrimOpacity * open),
                ),
              ),
            ),
            Positioned(
              left: -panelWidth * (1 - open),
              top: 0,
              bottom: 0,
              width: panelWidth,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) =>
                    _dragDrawer(details, panelWidth),
                onHorizontalDragEnd: (details) =>
                    _endDrawerDrag(details, panelWidth),
                child: NotesDrawer(
                  notes: widget.store.notes,
                  tagCounts: widget.store.tagCounts,
                  selected: widget.store.tagFilter,
                  onSelect: _selectTag,
                  topPadding: padding.top,
                  bottomPadding: padding.bottom,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// What the list says when there is nothing in it to say.
  Widget _emptyState({Key? key}) {
    final store = widget.store;
    final String message;
    if (store.isSearching) {
      message = 'Nothing matches "${store.query.trim()}"';
    } else if (store.tagFilter != null) {
      message = 'Nothing in this list yet';
    } else {
      message = 'No notes yet';
    }
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 72),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeights.medium,
            fontSize: 14,
            height: kLineHeight,
            color: AppColors.dockLabel.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }

  double get _scrollY => _scroll.hasClients ? _scroll.offset : 0;

  Widget _largeTitle() {
    return AnimatedBuilder(
      key: const ValueKey<String>('title'),
      animation: Listenable.merge([_dim, _scroll, _search]),
      builder: (context, child) {
        final collapse = rangeProgress(_scrollY, kLargeTitleRange);
        final overscroll = rangeProgress(_scrollY, kOverscrollRange);
        final searching = _searchCurve.transform(_search.value);
        return Opacity(
          opacity: (1 - collapse) *
              (1 - searching) *
              (1 - kChromeDimAmount * _dim.value),
          child: Transform.scale(
            scale: kOverscrollScale + (1 - kOverscrollScale) * overscroll,
            child: Transform.translate(
              offset: Offset(0, -kTitleShift * collapse),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: kLargeTitleTopMargin),
        child: Text(
          widget.store.title,
          style: const TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeights.semiBold,
            fontSize: 27,
            height: kLineHeight,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}
