import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';
import '../../theme/springs.dart';
import '../../widgets/dissolve/dissolve_scope.dart';
import '../../widgets/pull_to_refresh.dart' show Hushed;
import '../../widgets/skeleton.dart';
import 'document_row.dart';

/// The list body under the same name a file that also imports Flutter's
/// widgets can use.
///
/// `ListBody` is a name Flutter already exports, so a shell that imports both
/// this file and `package:flutter/widgets.dart` cannot write the bare name
/// without hiding one of them. This alias is the same class under a name
/// nothing else claims.
typedef DeskListBody = ListBody;

/// The desk as a list: one row per document, on the ground.
///
/// It takes the documents already filtered and sorted, because deciding what
/// is on screen belongs to the shell that owns the tabs and the sort menu, and
/// a body that filtered as well would be a second opinion about the same
/// question.
///
/// One thing it decides for itself: a document leaving the library comes apart
/// into its own pixels, and a document leaving the visible set for any other
/// reason does not. A tab, a sort or a query changes which documents are shown
/// and takes nothing away, so the rows travel on the layout spring and nothing
/// dissolves. A list that disintegrated every time it was sorted would be a
/// list nobody trusts.
class ListBody extends StatefulWidget {
  const ListBody({
    super.key,
    required this.library,
    required this.entries,
    this.query = '',
    this.onOpen,
    this.onOverflow,
    this.holds,
    this.controller,
    this.padding = EdgeInsets.zero,
    this.footer,
  });

  /// The desk itself, which is what says whether a document has been taken off
  /// it and what has been read of each one.
  final LibraryStore library;

  /// The documents to draw, already filtered and sorted.
  final List<LibraryEntry> entries;

  /// The search, marked wherever it appears in a title.
  final String query;

  /// Opening a document, with the rect its row occupies on the screen at the
  /// moment it was tapped.
  ///
  /// The rect comes from here rather than from the shell because the rows are
  /// this body's, and a reader that grows out of the row you touched needs to
  /// be told by whatever knows where that row was scrolled to.
  final void Function(LibraryEntry entry, Rect rowRect)? onOpen;

  /// A row's three dots. The menu behind them belongs to the shell.
  final void Function(LibraryEntry entry, Rect rowRect, Rect target)?
  onOverflow;

  /// Which documents this body is a view of, for telling a document that has
  /// left from one that is merely not shown.
  ///
  /// The desk is the usual answer and the default. The bin is the other one:
  /// its rows are documents the desk no longer holds, so a body that took the
  /// desk's word for it would close every slot the moment it was built and
  /// show an empty bin.
  final bool Function(LibraryEntry entry)? holds;

  final ScrollController? controller;

  /// Room for whatever the shell floats over the body.
  final EdgeInsets padding;

  /// What goes under the last row, once there is a last row.
  final Widget? footer;

  @override
  State<ListBody> createState() => _ListBodyState();
}

class _ListBodyState extends State<ListBody>
    with SingleTickerProviderStateMixin {
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  final Map<String, double> _from = <String, double>{};
  final Map<String, double> _to = <String, double>{};
  final Map<String, ui.Image> _snapshots = <String, ui.Image>{};
  final Set<String> _hidden = <String>{};

  /// The documents somebody put back while their own dust was still in the
  /// air, which are gathered the moment that run lands.
  ///
  /// Two runs on one snapshot is the document blowing apart and gathering in
  /// at the same time, painted from pixels the first of the two to finish
  /// would then let go of underneath the other.
  final Set<String> _waiting = <String>{};

  /// The documents whose dust is still in the air.
  ///
  /// A run paints the very pixels this body is holding, so a snapshot cannot
  /// be let go of while its own run is still using it, however long ago the
  /// desk stopped offering the document back.
  final Set<String> _running = <String>{};

  late final AnimationController _spring;
  late final SpringCurve _curve;

  /// The rows on screen, which is the documents to draw plus any that are
  /// still closing their slot behind them.
  List<LibraryEntry> _rows = const <LibraryEntry>[];

  /// What the desk held when it was last looked at, so a document that has
  /// gone can be told from a document that is merely not shown.
  Set<String> _onDesk = const <String>{};

  @override
  void initState() {
    super.initState();
    final duration = springDuration(AppSprings.shelfLayout);
    _spring = AnimationController(vsync: this, duration: duration, value: 1);
    _curve = SpringCurve(AppSprings.shelfLayout, duration: duration);
    _spring.addStatusListener(_onSpring);
    widget.library.addListener(_onLibrary);
    _onDesk = _held();
    _rows = List<LibraryEntry>.of(widget.entries);
    for (final entry in _rows) {
      _from[entry.path] = 1;
      _to[entry.path] = 1;
    }
  }

  @override
  void didUpdateWidget(ListBody old) {
    super.didUpdateWidget(old);
    if (old.library != widget.library) {
      old.library.removeListener(_onLibrary);
      widget.library.addListener(_onLibrary);
      _onDesk = _held();
    }
    _sync();
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibrary);
    // Taking the last document off the desk replaces this body with the empty
    // state, so the body goes while the dust of that last row is still in the
    // air. The run is painted by the scope above, which outlives the body, so
    // a run in flight keeps its pixels and lets go of them in its own onDone.
    for (final path in _snapshots.keys.toList()) {
      if (_running.contains(path)) continue;
      _snapshots.remove(path)!.dispose();
    }
    _spring.dispose();
    super.dispose();
  }

  /// Everything this body counts as still here.
  Set<String> _held() {
    final holds = widget.holds;
    if (holds == null) {
      return <String>{for (final entry in widget.library.entries) entry.path};
    }
    return <String>{
      for (final entry in widget.library.allEntries)
        if (holds(entry)) entry.path,
    };
  }

  GlobalKey _keyFor(LibraryEntry entry) =>
      _keys.putIfAbsent(entry.path, GlobalKey.new);

  /// Where [entry]'s row is on the screen right now, or nothing if it has no
  /// box to measure because it has been scrolled away or not laid out yet.
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

  /// Drops the rows whose slots have finished closing, so a list that has
  /// settled holds nothing it is not drawing.
  void _onSpring(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final settled = <LibraryEntry>[
      for (final entry in _rows)
        if ((_to[entry.path] ?? 0) > 0) entry,
    ];
    if (settled.length == _rows.length) return;
    final dropped = <String>{for (final entry in _rows) entry.path}
      ..removeAll(<String>{for (final entry in settled) entry.path});
    setState(() {
      _rows = settled;
      // Nothing is drawing them any more, so nothing has to be told not to.
      _hidden.removeAll(dropped);
    });
  }

  /// Watches the desk for documents arriving and leaving.
  ///
  /// Leaving is the only thing that dissolves, and it is detected here rather
  /// than at a menu item so that every way of taking a document off the desk
  /// comes apart the same way and nothing else can.
  void _onLibrary() {
    if (!mounted) return;
    final now = _held();
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

  /// Lets go of the pixels of a document nobody is being offered back any
  /// more.
  ///
  /// A snapshot is only worth keeping for as long as undo could still ask for
  /// it. Once the desk has stopped offering a removal back there is nothing
  /// left that could gather those pixels together, so holding them would be
  /// holding a bitmap for the life of the app.
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

  /// Takes a row apart into its own pixels.
  ///
  /// The snapshot is what the dust is made of and what a document coming back
  /// gathers out of, so it is taken while the row is still laid out, which is
  /// the frame the desk announces the removal in.
  void _dissolve(String path) {
    final key = _keys[path];
    if (key?.currentContext == null) return;
    if (_hidden.contains(path)) {
      // Drawn as nothing because its pixels are already in the air: it is
      // being gathered back at this very moment. There is nothing on screen
      // to photograph, so the row simply goes, and the gather in flight ends
      // in its own time.
      _waiting.remove(path);
      return;
    }
    final image = DissolveScope.of(context).dissolve(
      key!,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      onCaptured: () => setState(() {
        _hidden.add(path);
        _running.add(path);
      }),
      onDone: () {
        if (!mounted) {
          // The body went with the last row. Nothing can be offered back to a
          // desk that is no longer showing a list, so these are the last
          // pixels of it.
          _running.remove(path);
          _snapshots.remove(path)?.dispose();
          return;
        }
        setState(() => _running.remove(path));
        if (_waiting.remove(path)) {
          setState(() => _hidden.remove(path));
          // It was put back while it was still coming apart. Now that the run
          // has landed, it can gather out of the same pixels.
          _materialize(path);
          return;
        }
        // The dust has landed. Only now is the slot allowed to close, and
        // the row stays hidden while it does: a row drawn again over its own
        // closing slot is the document flashing back for a moment after it
        // has already come apart.
        _sync();
        // And a snapshot nobody is being offered back any more has nothing
        // left to do.
        _dropUnclaimed();
      },
    );
    if (image != null) _snapshots[path] = image;
  }

  /// Gathers a document that has come back out of the dust it came apart into.
  void _materialize(String path) {
    if (_running.contains(path)) {
      // Its own dust is still falling. It is gathered when that run lands,
      // which is the only moment there is one picture and one run.
      _waiting.add(path);
      return;
    }
    final image = _snapshots.remove(path);
    if (image == null) return;
    setState(() => _hidden.add(path));
    // The slot has to be open again before there is anywhere for the dust to
    // gather into, so the run starts on the frame after the list reopens.
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
        // The document is whole again and drawing itself, so the pixels it
        // gathered out of are the last copy of a picture nothing will ask for
        // twice.
        onDone: () {
          image.dispose();
          if (mounted) setState(() => _hidden.remove(path));
        },
      );
    });
  }

  /// Points every slot at where it belongs now and springs the list there.
  ///
  /// A document the desk no longer holds closes its slot whatever the shell
  /// has passed in, because the desk announces a removal one frame before the
  /// shell can recompute what is on screen, and the row has to start closing
  /// in the frame its pixels left.
  void _sync() {
    final onDesk = _onDesk;
    final shown = <String>{
      for (final entry in widget.entries)
        if (onDesk.contains(entry.path)) entry.path,
      // A row whose dust is still in the air keeps its slot. A gap that
      // closes under falling pixels is the list moving on before the document
      // has finished leaving, and it is the one moment where the two motions
      // must not overlap: the row comes apart, and then the list closes.
      ..._running,
    };
    final rows = List<LibraryEntry>.of(widget.entries);
    final placed = <String>{for (final entry in rows) entry.path};
    for (var i = 0; i < _rows.length; i++) {
      final entry = _rows[i];
      if (!placed.add(entry.path)) continue;
      if (_factorOf(entry.path) <= 0) continue;
      rows.insert(i < rows.length ? i : rows.length, entry);
    }
    final next = <String, double>{
      for (final entry in rows)
        entry.path: shown.contains(entry.path) ? 1.0 : 0.0,
    };
    if (_sameTargets(next) && _sameRows(rows)) {
      // The same documents, in the same order, with nothing arriving or
      // leaving: the spring has no work. They are still taken, because the
      // same document is not the same object. A rename hands the desk a new
      // entry under the old path, and a body that kept the old one would go
      // on printing the old name until something else disturbed the list.
      _rows = rows;
      return;
    }
    final from = <String, double>{
      for (final path in next.keys) path: _factorOf(path),
    };
    _rows = rows;
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

  bool _sameRows(List<LibraryEntry> rows) {
    if (rows.length != _rows.length) return false;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].path != _rows[i].path) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // Scrollable even when everything fits, so a short desk can still be
      // pulled at the top. Without this the view refuses the drag outright
      // and the pull has nothing to report.
      physics: const AlwaysScrollableScrollPhysics(),
      controller: widget.controller,
      padding: widget.padding,
      child: AnimatedBuilder(
        animation: _spring,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final entry in _rows) _slot(entry),
            if (widget.footer case final footer? when _rows.isNotEmpty) footer,
          ],
        ),
      ),
    );
  }

  /// One row in its slot. A slot part way closed shows the top of its row, so
  /// the row reads as being drawn out of the list rather than squashed inside
  /// it.
  Widget _slot(LibraryEntry entry) {
    final path = entry.path;
    final factor = _factorOf(path);
    // A slot that is opening is built while it is still shut, so the row
    // inside it has a size and a place from the first frame. Undo needs both:
    // the dust has to know where it is gathering to before there is a gap to
    // see it in, or the run finds nothing to aim at and never starts.
    final opening = (_to[path] ?? 0) > 0;
    if (factor <= 0 && !opening) return const SizedBox.shrink();
    return ClipRect(
      key: ValueKey<String>(path),
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: factor.clamp(0.0, 1.0),
        child: IgnorePointer(
          // A row whose pixels have left is not something to tap. Drawn as
          // nothing and still taking touches, the empty space where it was
          // would open the document that is halfway to the bin.
          ignoring: _hidden.contains(path) || (_to[path] ?? 1) <= 0,
          child: Opacity(
            // A row whose pixels are in flight is not on the desk any more. It
            // keeps its slot only for as long as the slot takes to close.
            opacity: _hidden.contains(path) ? 0 : 1,
            child: RepaintBoundary(
              key: _keyFor(entry),
              // While the desk is being read again the row waits in its own
              // outline, so the list keeps its shape and its weight instead
              // of showing what it knew a moment ago as though it were news.
              child: Skeletal(
                quiet: Hushed.of(context),
                skeleton: const SkeletonRow(),
                child: DocumentRow(
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
      ),
    );
  }
}
