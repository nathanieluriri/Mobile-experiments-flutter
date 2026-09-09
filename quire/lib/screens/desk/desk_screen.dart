import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import '../../theme/typography.dart';
import '../../widgets/dissolve/dissolve_scope.dart';
import 'card_peel.dart';
import 'desk_colophon.dart';
import 'desk_empty.dart';
import 'desk_header.dart';
import 'desk_search_field.dart';
import 'shelf_chips.dart';
import 'undo_pill.dart';

/// Where the two lines of a search that found nothing sit.
const kNoResultsTop = 300.0;
const kNoResultsGap = 8.0;

/// How long the undo pill takes to come up off the desk.
const kUndoPillIn = Duration(milliseconds: 180);

/// The slot the colophon occupies in the shelf, keyed like a card so it opens
/// and closes on the same spring the cards do.
const _kColophonSlot = 'colophon';

/// The desk: every document you have, lying on warm ground.
///
/// One scroll, one collapse, one row of shelves, and cards you can turn the
/// corner of. Everything else in quire is reached from here.
class DeskScreen extends StatefulWidget {
  const DeskScreen({
    super.key,
    required this.store,
    this.onOpen,
    this.onSign,
  });

  final LibraryStore store;

  /// Opening a document, either by tapping its card or by dropping it on READ.
  ///
  /// The card's rect on the desk comes with it, because the reader grows out
  /// of the card rather than sliding over it, and the desk is the only thing
  /// that knows where a card has been scrolled to.
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
  final Map<String, GlobalKey> _cardKeys = <String, GlobalKey>{};
  final Set<String> _hidden = <String>{};

  late final AnimationController _search;
  late final AnimationController _dim;
  late final AnimationController _shelf;
  late final AnimationController _undo;
  late final AnimationController _undoRise;
  late final SpringCurve _shelfCurve;

  /// Where every slot in the shelf was when the last change arrived, and where
  /// it is going. One controller drives all of them, because a keystroke moves
  /// the whole list at once and a removal has to close the gap on the same
  /// spring the rest of the list is riding.
  final Map<String, double> _from = <String, double>{};
  final Map<String, double> _to = <String, double>{};

  String? _lifted;
  LibraryEntry? _pill;

  @override
  void initState() {
    super.initState();
    _search = AnimationController(
      vsync: this,
      duration: kSearchOpen,
      reverseDuration: kSearchClose,
    );
    _dim = AnimationController(vsync: this, duration: kDim);
    final shelfDuration = springDuration(AppSprings.shelfLayout);
    _shelf = AnimationController(
      vsync: this,
      duration: shelfDuration,
      value: 1,
    );
    _shelfCurve = SpringCurve(AppSprings.shelfLayout, duration: shelfDuration);
    _undo = AnimationController(vsync: this, duration: kUndoPill);
    _undo.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.store.commitRemoval();
        setState(() => _pill = null);
      }
    });
    _undoRise = AnimationController(vsync: this, duration: kUndoPillIn);
    widget.store.addListener(_onStoreChanged);
    _syncSlots(animate: false);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _search.dispose();
    _dim.dispose();
    _shelf.dispose();
    _undo.dispose();
    _undoRise.dispose();
    _scroll.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    _syncSlots();
    setState(() {});
  }

  GlobalKey _keyFor(LibraryEntry entry) =>
      _cardKeys.putIfAbsent(entry.assetPath, GlobalKey.new);

  /// Where [entry]'s card is on the screen right now.
  ///
  /// A card with no box to measure, because it has been scrolled out of the
  /// shelf or has not been laid out yet, reports an empty rect, and the reader
  /// opens without growing out of anything the way a deep link does.
  Rect _rectOf(LibraryEntry entry) {
    final box = _keyFor(entry).currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _open(LibraryEntry entry) => widget.onOpen?.call(entry, _rectOf(entry));

  double _factorOf(String slot) {
    final from = _from[slot] ?? 0;
    final to = _to[slot] ?? 0;
    return from + (to - from) * _shelfCurve.transform(_shelf.value);
  }

  /// Points every slot at where it belongs now and springs the list there.
  void _syncSlots({bool animate = true}) {
    final visible =
        widget.store.visible.map((entry) => entry.assetPath).toSet();
    final next = <String, double>{
      for (final entry in widget.store.allEntries)
        entry.assetPath: visible.contains(entry.assetPath) ? 1.0 : 0.0,
      _kColophonSlot: visible.isEmpty ? 0.0 : 1.0,
    };
    if (_sameTargets(next)) return;
    if (!animate) {
      _from
        ..clear()
        ..addAll(next);
      _to
        ..clear()
        ..addAll(next);
      _shelf.value = 1;
      return;
    }
    final from = <String, double>{
      for (final slot in next.keys) slot: _factorOf(slot),
    };
    _from
      ..clear()
      ..addAll(from);
    _to
      ..clear()
      ..addAll(next);
    _shelf.forward(from: 0);
  }

  bool _sameTargets(Map<String, double> next) {
    if (next.length != _to.length) return false;
    for (final entry in next.entries) {
      if (_to[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _openSearch() {
    _search.forward();
    _queryFocus.requestFocus();
  }

  void _closeSearch() {
    _queryFocus.unfocus();
    _query.clear();
    widget.store.query = '';
    _search.reverse();
    setState(() {});
  }

  void _onQueryChanged(String value) {
    widget.store.query = value;
    setState(() {});
  }

  void _focus(LibraryEntry entry) {
    setState(() => _lifted = entry.assetPath);
    _dim.animateTo(1, duration: kDim, curve: easeOutQuad);
  }

  void _blur() {
    setState(() => _lifted = null);
    _dim.animateBack(0, duration: kDim, curve: easeOutQuad);
  }

  void _act(LibraryEntry entry, DeskAction action) {
    switch (action) {
      case DeskAction.read:
        _open(entry);
      case DeskAction.sign:
        widget.onSign?.call(entry);
      case DeskAction.dogEar:
        final store = widget.store.storeFor(entry);
        store.toggleDogEar(store.position);
      case DeskAction.remove:
        _remove(entry);
    }
  }

  /// Takes a card off the desk by taking it apart.
  ///
  /// The snapshot is what the dust is made of and what undo puts back, so it
  /// is captured before the card is hidden and kept on the store until the
  /// pill runs out.
  void _remove(LibraryEntry entry) {
    final image = DissolveScope.of(context).dissolve(
      _keyFor(entry),
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      onCaptured: () => setState(() => _hidden.add(entry.assetPath)),
      onDone: () {
        if (mounted) setState(() => _hidden.remove(entry.assetPath));
      },
    );
    widget.store.remove(entry, snapshot: image);
    setState(() => _pill = entry);
    _undoRise.forward(from: 0);
    _undo.forward(from: 0);
  }

  void _undoRemoval() {
    final entry = _pill;
    if (entry == null) return;
    final ui.Image? image = widget.store.retainedSnapshot;
    _undo.stop();
    _undoRise.value = 0;
    setState(() {
      _pill = null;
      if (image != null) _hidden.add(entry.assetPath);
    });
    widget.store.undoRemove();
    if (image == null) return;
    // The slot has to exist again before there is anywhere for the dust to
    // gather into, so the run starts on the frame after the list reopens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DissolveScope.of(context).materialize(
        _keyFor(entry),
        image,
        onDone: () {
          if (mounted) setState(() => _hidden.remove(entry.assetPath));
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final bare = store.entries.isEmpty;
    final nothingMatched = !bare && store.visible.isEmpty;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: AppColors.ground,
      child: Stack(
        children: [
          if (bare)
            const Positioned.fill(child: DeskEmpty(onOpen: null))
          else
            Positioned.fill(child: _list()),
          if (nothingMatched) _noResults(),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: kCardListTop,
            child: _chrome(bare: bare),
          ),
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
        ],
      ),
    );
  }

  Widget _chrome({required bool bare}) {
    return Stack(
      children: [
        const Positioned.fill(
          child: ColoredBox(color: AppColors.ground),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: AnimatedBuilder(
            animation:
                Listenable.merge(<Listenable>[_scroll, _search, _dim, _query]),
            builder: (context, _) => DeskHeader(
              scrollY: _scroll.hasClients ? _scroll.offset : 0,
              searchOpen: easeOutCubic.transform(_search.value),
              searchRaw: _search.value,
              dim: _dim.value,
              field: DeskSearchField(
                open: easeOutCubic.transform(_search.value),
                controller: _query,
                focusNode: _queryFocus,
                onOpen: _openSearch,
                onClose: _closeSearch,
                onChanged: _onQueryChanged,
              ),
            ),
          ),
        ),
        if (!bare)
          Positioned(
            left: kScreenPadding,
            right: kScreenPadding,
            top: kChipRowTop,
            child: AnimatedBuilder(
              animation: _dim,
              builder: (context, child) => Opacity(
                opacity: 1 - kChromeDimAmount * _dim.value,
                child: child,
              ),
              child: ShelfChips(
                selected: widget.store.shelf,
                counts: <Shelf, int>{
                  for (final shelf in Shelf.values)
                    shelf: widget.store.countOn(shelf),
                },
                onSelect: (shelf) => widget.store.shelf = shelf,
              ),
            ),
          ),
      ],
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

  Widget _list() {
    final entries = widget.store.allEntries;
    return SingleChildScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(
        top: kCardListTop,
        bottom: kDeskListBottomPadding,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_shelf, _dim]),
          builder: (context, _) {
            final lifted = _lifted;
            return _DeskColumn(
              gap: kCardGap,
              paintLast: lifted == null
                  ? null
                  : entries.indexWhere((e) => e.assetPath == lifted),
              children: [
                for (final entry in entries)
                  _DeskSlot(
                    factor: _factorOf(entry.assetPath),
                    child: CardPeel(
                      key: ValueKey<String>(entry.assetPath),
                      cardKey: _keyFor(entry),
                      entry: entry,
                      store: widget.store.peek(entry),
                      query: widget.store.query,
                      lifted: entry.assetPath == lifted,
                      dimmed: lifted != null && entry.assetPath != lifted,
                      hidden: _hidden.contains(entry.assetPath),
                      onFocus: () => _focus(entry),
                      onBlur: _blur,
                      onAction: (action) => _act(entry, action),
                      onOpen: () => _open(entry),
                    ),
                  ),
                _DeskSlot(
                  factor: _factorOf(_kColophonSlot),
                  child: Opacity(
                    opacity: 1 - (1 - kDimmedCardOpacity) * _dim.value,
                    child: DeskColophon(
                      documents: widget.store.documentCount,
                      words: widget.store.wordCount,
                      minutes: widget.store.minutes,
                      topGap: kColophonGap - kCardGap,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// How much of its own slot a card is taking. At 1 it has its full height and
/// the gap above it; at 0 it takes no room and is not drawn.
class _DeskSlotData extends ContainerBoxParentData<RenderBox> {
  double factor = 1;
}

class _DeskSlot extends ParentDataWidget<_DeskSlotData> {
  const _DeskSlot({required this.factor, required super.child});

  final double factor;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _DeskSlotData;
    if (data.factor == factor) return;
    data.factor = factor;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _DeskColumn;
}

/// The shelf: cards stacked with a fixed gap, doing two things a [Column]
/// cannot.
///
/// A lifted card paints its fold and its dock outside its own box and over the
/// cards below it, so [paintLast] pulls one child to the front of the paint
/// and hit test order without moving it. And a card arriving or leaving opens
/// and closes its own slot, so the list closes the gap rather than jumping.
class _DeskColumn extends MultiChildRenderObjectWidget {
  const _DeskColumn({
    required this.gap,
    this.paintLast,
    required super.children,
  });

  final double gap;
  final int? paintLast;

  @override
  _RenderDeskColumn createRenderObject(BuildContext context) =>
      _RenderDeskColumn(gap, paintLast);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDeskColumn renderObject,
  ) {
    renderObject
      ..gap = gap
      ..paintLast = paintLast;
  }
}

class _RenderDeskColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DeskSlotData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DeskSlotData> {
  _RenderDeskColumn(this._gap, this._paintLast);

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  int? _paintLast;
  int? get paintLast => _paintLast;
  set paintLast(int? value) {
    if (_paintLast == value) return;
    _paintLast = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DeskSlotData) child.parentData = _DeskSlotData();
  }

  double _factorOf(RenderBox child) =>
      (child.parentData! as _DeskSlotData).factor.clamp(0.0, 1.0);

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    var y = 0.0;
    var placed = false;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _DeskSlotData;
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      final factor = _factorOf(child);
      // The gap belongs to the card below it, so a card that is not there
      // takes neither its own height nor the space above it.
      if (placed) y += _gap * factor;
      data.offset = Offset(0, y);
      y += child.size.height * factor;
      if (factor > 0) placed = true;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    var y = 0.0;
    var placed = false;
    var child = firstChild;
    while (child != null) {
      final factor = _factorOf(child);
      if (placed) y += _gap * factor;
      y += child.getDryLayout(BoxConstraints.tightFor(width: width)).height *
          factor;
      if (factor > 0) placed = true;
      child = childAfter(child);
    }
    return constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final children = getChildrenAsList();
    final last = _paintLast;
    for (var i = 0; i < children.length; i++) {
      if (i != last) _paintChild(context, children[i], offset);
    }
    if (last != null && last >= 0 && last < children.length) {
      _paintChild(context, children[last], offset);
    }
  }

  void _paintChild(PaintingContext context, RenderBox child, Offset offset) {
    final data = child.parentData! as _DeskSlotData;
    final factor = _factorOf(child);
    if (factor <= 0) return;
    if (factor >= 1) {
      context.paintChild(child, data.offset + offset);
      return;
    }
    // Half a slot shows the top half of the card, so it reads as being drawn
    // out of the list rather than squashed into it.
    context.pushClipRect(
      needsCompositing,
      offset + data.offset,
      Offset.zero & Size(child.size.width, child.size.height * factor),
      (innerContext, innerOffset) =>
          innerContext.paintChild(child, innerOffset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final children = getChildrenAsList();
    final last = _paintLast;
    if (last != null && last >= 0 && last < children.length) {
      if (_hitTestChild(result, children[last], position)) return true;
    }
    for (var i = children.length - 1; i >= 0; i--) {
      if (i == last) continue;
      if (_hitTestChild(result, children[i], position)) return true;
    }
    return false;
  }

  bool _hitTestChild(
    BoxHitTestResult result,
    RenderBox child,
    Offset position,
  ) {
    if (_factorOf(child) <= 0) return false;
    final data = child.parentData! as _DeskSlotData;
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }
}
