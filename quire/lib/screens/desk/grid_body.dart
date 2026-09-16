import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import '../../widgets/dissolve/dissolve_scope.dart';
import 'document_card.dart';

/// The desk as a grid: two columns of cards, each showing its document's own
/// first page.
///
/// Like the list, it takes the documents already filtered and sorted, because
/// what is on screen is the shell's question and how it is drawn is this
/// body's.
///
/// The cards are laid out from the width they are given rather than from a
/// fixed card size, so the two columns and the gap between them always add up
/// to the body exactly, and a card is never a fraction of a point out.
///
/// A document leaving the desk comes apart into its own pixels here exactly as
/// it does in the list, and the grid closes over the space it held only once
/// the last of that card is gone. Anything else that changes which documents
/// are shown, a tab or a sort or a query, moves the cards and takes nothing
/// apart.
class GridBody extends StatefulWidget {
  const GridBody({
    super.key,
    required this.library,
    required this.entries,
    this.query = '',
    this.onOpen,
    this.onOverflow,
    this.controller,
    this.padding = const EdgeInsets.all(kGridPadding),
    this.footer,
  });

  /// The desk itself, which is what has been read of each document.
  final LibraryStore library;

  /// The documents to draw, already filtered and sorted.
  final List<LibraryEntry> entries;

  /// The search, marked wherever it appears in a title.
  final String query;

  /// Opening a document, with the rect its card occupies on the screen.
  final void Function(LibraryEntry entry, Rect cardRect)? onOpen;

  /// A card's three dots. The menu behind them belongs to the shell.
  final void Function(LibraryEntry entry, Rect cardRect, Rect target)?
  onOverflow;

  final ScrollController? controller;

  /// Room round the cards, and for whatever the shell floats over them.
  final EdgeInsets padding;

  /// What goes under the last row of cards, once there is one.
  final Widget? footer;

  @override
  State<GridBody> createState() => _GridBodyState();
}

class _GridBodyState extends State<GridBody>
    with SingleTickerProviderStateMixin {
  /// One key per document rather than one per position, so a card keeps its
  /// own boundary when the grid is sorted and a rect is always the rect of the
  /// card that was touched.
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  /// How much room each card holds, 1 for a card that is there and 0 for one
  /// the grid has closed over, with the spring carrying it between them.
  final Map<String, double> _from = <String, double>{};
  final Map<String, double> _to = <String, double>{};

  /// The pixels a card came apart into, kept while undo could still ask for
  /// them back.
  final Map<String, ui.Image> _snapshots = <String, ui.Image>{};

  /// Cards drawn as nothing because their pixels are in the air instead.
  final Set<String> _hidden = <String>{};

  /// The documents whose dust is still falling. Their cells stay open.
  final Set<String> _running = <String>{};

  late final AnimationController _spring;
  late final SpringCurve _curve;

  /// The cards on screen: the documents to draw, plus any still coming apart
  /// or closing the space they held.
  List<LibraryEntry> _cards = const <LibraryEntry>[];

  /// What the desk held when it was last looked at, so a document that has
  /// gone can be told from one that is merely not shown.
  Set<String> _onDesk = const <String>{};

  @override
  void initState() {
    super.initState();
    final duration = springDuration(AppSprings.shelfLayout);
    _spring = AnimationController(vsync: this, duration: duration, value: 1);
    _curve = SpringCurve(AppSprings.shelfLayout, duration: duration);
    _spring.addStatusListener(_onSpring);
    widget.library.addListener(_onLibrary);
    _onDesk = _deskPaths;
    _cards = List<LibraryEntry>.of(widget.entries);
    for (final entry in _cards) {
      _from[entry.path] = 1;
      _to[entry.path] = 1;
    }
  }

  @override
  void didUpdateWidget(GridBody old) {
    super.didUpdateWidget(old);
    if (old.library != widget.library) {
      old.library.removeListener(_onLibrary);
      widget.library.addListener(_onLibrary);
      _onDesk = _deskPaths;
    }
    _sync();
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibrary);
    // A run in flight is painted by the scope above, which outlives this body
    // and lets go of those pixels in its own onDone.
    for (final path in _snapshots.keys.toList()) {
      if (_running.contains(path)) continue;
      _snapshots.remove(path)!.dispose();
    }
    _spring.dispose();
    super.dispose();
  }

  Set<String> get _deskPaths => <String>{
    for (final entry in widget.library.entries) entry.path,
  };

  GlobalKey _keyFor(LibraryEntry entry) =>
      _keys.putIfAbsent(entry.path, GlobalKey.new);

  Rect _rectOf(LibraryEntry entry) {
    final box = _keys[entry.path]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  double _factorOf(String path) {
    final from = _from[path] ?? 0;
    final to = _to[path] ?? 0;
    return from + (to - from) * _curve.transform(_spring.value);
  }

  /// Drops the cards whose space has finished closing.
  void _onSpring(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final settled = <LibraryEntry>[
      for (final entry in _cards)
        if ((_to[entry.path] ?? 0) > 0) entry,
    ];
    if (settled.length == _cards.length) return;
    setState(() => _cards = settled);
  }

  /// Watches the desk for documents arriving and leaving.
  void _onLibrary() {
    if (!mounted) return;
    final now = _deskPaths;
    final gone = _onDesk.difference(now);
    final back = now.difference(_onDesk);
    _onDesk = now;
    for (final path in gone) {
      _dissolve(path);
    }
    for (final path in back) {
      _materialize(path);
    }
    _dropUnclaimed();
    _sync();
    setState(() {});
  }

  void _dropUnclaimed() {
    final offered = widget.library.lastRemoved?.path;
    for (final path in _snapshots.keys.toList()) {
      if (path == offered ||
          _onDesk.contains(path) ||
          _running.contains(path)) {
        continue;
      }
      _snapshots.remove(path)!.dispose();
    }
  }

  /// Takes a card apart into its own pixels, and holds its place until the
  /// last of them has landed.
  void _dissolve(String path) {
    final key = _keys[path];
    if (key?.currentContext == null) return;
    final image = DissolveScope.of(context).dissolve(
      key!,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      onCaptured: () => setState(() {
        _hidden.add(path);
        _running.add(path);
      }),
      onDone: () {
        if (!mounted) {
          _running.remove(path);
          _snapshots.remove(path)?.dispose();
          return;
        }
        setState(() {
          _hidden.remove(path);
          _running.remove(path);
        });
        // Only now does the grid close over the space the card held.
        _sync();
        _dropUnclaimed();
      },
    );
    if (image != null) _snapshots[path] = image;
  }

  /// Gathers a document that has come back out of the dust it came apart into.
  void _materialize(String path) {
    final image = _snapshots.remove(path);
    if (image == null) return;
    setState(() => _hidden.add(path));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        image.dispose();
        return;
      }
      final key = _keys[path];
      if (key?.currentContext == null) {
        image.dispose();
        setState(() => _hidden.remove(path));
        return;
      }
      DissolveScope.of(context).materialize(
        key!,
        image,
        onDone: () {
          image.dispose();
          if (mounted) setState(() => _hidden.remove(path));
        },
      );
    });
  }

  /// Points every cell at the room it should hold now and springs the grid
  /// there.
  void _sync() {
    final onDesk = _onDesk;
    final shown = <String>{
      for (final entry in widget.entries)
        if (onDesk.contains(entry.path)) entry.path,
      // A card still coming apart keeps its place, for the same reason a row
      // does: the grid closing under falling pixels would be the desk moving
      // on before the document had finished leaving.
      ..._running,
    };
    final cards = List<LibraryEntry>.of(widget.entries);
    final placed = <String>{for (final entry in cards) entry.path};
    for (var i = 0; i < _cards.length; i++) {
      final entry = _cards[i];
      if (!placed.add(entry.path)) continue;
      if (_factorOf(entry.path) <= 0) continue;
      cards.insert(i < cards.length ? i : cards.length, entry);
    }
    final next = <String, double>{
      for (final entry in cards)
        entry.path: shown.contains(entry.path) ? 1.0 : 0.0,
    };
    if (_sameTargets(next) && _sameCards(cards)) {
      // The same documents in the same order: the spring has no work. They
      // are still taken, because a rename hands the desk a new entry under
      // the old path and a grid holding the old one would print the old name.
      _cards = cards;
      return;
    }
    final from = <String, double>{
      for (final path in next.keys) path: _factorOf(path),
    };
    _cards = cards;
    _from
      ..clear()
      ..addAll(from);
    _to
      ..clear()
      ..addAll(next);
    _spring.forward(from: 0);
  }

  bool _sameTargets(Map<String, double> next) {
    if (next.length != _to.length) return false;
    for (final target in next.entries) {
      if (_to[target.key] != target.value) return false;
    }
    return true;
  }

  bool _sameCards(List<LibraryEntry> cards) {
    if (cards.length != _cards.length) return false;
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].path != _cards[i].path) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inside = constraints.maxWidth - widget.padding.horizontal;
        final card = (inside - kGridGap * (kGridColumns - 1)) / kGridColumns;
        return SingleChildScrollView(
          controller: widget.controller,
          padding: widget.padding,
          child: AnimatedBuilder(
            animation: _spring,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: kGridGap,
                  runSpacing: kGridGap,
                  children: <Widget>[
                    for (final entry in _cards)
                      _cell(entry, card > 0 ? card : 0),
                  ],
                ),
                if (widget.footer case final footer? when _cards.isNotEmpty)
                  footer,
              ],
            ),
          ),
        );
      },
    );
  }

  /// One card, as wide as the space it is still holding.
  ///
  /// A card that has been taken apart is drawn as nothing at all rather than
  /// as an empty card, because its pixels are in the air above the grid and a
  /// second copy of them underneath would be the document in two places.
  Widget _cell(LibraryEntry entry, double width) {
    final factor = _factorOf(entry.path).clamp(0.0, 1.0);
    final hidden = _hidden.contains(entry.path);
    return ClipRect(
      // The card keeps its own size and the space around it closes over it,
      // which is what lets the cards beside it slide along rather than
      // resizing as they go.
      child: Align(
        alignment: Alignment.topLeft,
        widthFactor: factor,
        heightFactor: factor,
        child: SizedBox(
          width: width,
          child: Opacity(
            // A card whose pixels are in the air is not drawn here as well.
            opacity: hidden ? 0 : 1,
            // The boundary is what those pixels are taken off, the same way a
            // row's are.
            child: RepaintBoundary(
              key: _keyFor(entry),
              child: DocumentCard(
                entry: entry,
                store: widget.library.peek(entry),
                query: widget.query,
                onOpen: widget.onOpen == null
                    ? null
                    : () => widget.onOpen!(entry, _rectOf(entry)),
                onOverflow: widget.onOverflow == null
                    ? null
                    : (target) =>
                        widget.onOverflow!(entry, _rectOf(entry), target),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
