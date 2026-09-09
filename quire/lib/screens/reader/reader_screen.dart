import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../helpers/fold_geometry.dart';
import '../../services/document_store.dart';
import '../../services/render_plan.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import 'corner_peel.dart';
import 'document_states.dart';
import 'folio_chip.dart';
import 'fore_edge.dart';
import 'reader_chrome.dart';
import 'riffle_sheet.dart';
import 'sheet_surface.dart';

/// How far a scroll has to move before the chrome gets out of the way.
const kChromeHideDelta = 6.0;

/// How far a finger may wander inside the fore edge before it stops being a
/// tap for the riffle and becomes a scrub.
///
/// It is small because the strip moves a page every 2.6 points: a slop the
/// size of the usual touch slop would mean a scrub could not begin until
/// seven pages had already gone by, and the document would jump.
const kForeEdgeTapSlop = 4.0;

/// How close to a dog ear nub a scrub has to come before it snaps onto it.
const kNubSnapDistance = 4.0;

/// How far past a nub a scrub travels before the folio chip is fully tinted.
const kFolioTintTravel = 40.0;

/// How dark the desk is held while the reader is over it. The desk comes back
/// to full as a back drag carries the reader off.
const kDeskDim = 0.6;

/// The strip a scrub or a riffle tap owns. It stops 72 points above the
/// sheet's bottom edge, which is what gives the corner peel a corner.
const kForeEdgeRegion = Rect.fromLTRB(
  kForeEdgeHitLeft,
  kForeEdgeTop,
  kScreenWidth,
  kForeEdgeHitBottom,
);

/// The band a back drag has to start inside.
const kBackEdgeRegion = Rect.fromLTRB(0, 0, kBackEdgeZone, kScreenHeight);

/// The strip a scrub or a riffle tap owns in front of [body].
///
/// The hit region reaches 21 points inside the sheet, which is what makes the
/// strip catchable with a thumb rather than only with a stylus. Over a grid
/// that overlap would swallow the last two columns of spines, and a body that
/// answers a finger to its own right edge gets the strip pushed off the sheet
/// instead. Nothing about the strip's drawing changes: it is only the arena
/// that moves.
Rect foreEdgeRegionFor(ReaderBody body) => body.ownsRightEdge
    ? const Rect.fromLTRB(
        kSheetLeft + kSheetWidth,
        kForeEdgeTop,
        kScreenWidth,
        kForeEdgeHitBottom,
      )
    : kForeEdgeRegion;

/// The 72 point handle over the sheet's folding corner.
///
/// It follows the fold: once a sheet has been turned over, the corner that
/// folds is the top left one, and so is the handle.
Rect cornerRegion(Corner corner) => Rect.fromLTWH(
  corner.mirrorsX ? kSheetLeft : kSheetLeft + kSheetWidth - kCornerHandle,
  corner.mirrorsY ? kSheetTop + kSheetHeight - kCornerHandle : kSheetTop,
  kCornerHandle,
  kCornerHandle,
);

/// The reader: one sheet, one strip, one chip, three floating buttons, and the
/// arbiter that decides which of them a finger belongs to.
///
/// Every gesture in the reader is a raw recognizer in one arena rather than a
/// nested detector, because nested detectors mean the scroll view wins
/// everything and a page that does not answer a finger reads as dead rather
/// than as buggy.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.store,
    required this.bodyBuilder,
    this.plan,
    this.damageReason,
    this.placement,
    this.overlay,
    this.riffleItems,
    this.matches = const <double>[],
    this.liveMatch,
    this.matchOpacity = 1,
    this.matchCounts = const <int>[],
    this.onFind,
    this.onOpenAsText,
    this.onLeave,
  });

  /// The open document: where the reader is, what they have turned down, and
  /// what they have signed.
  final DocumentStore store;

  /// Builds the format's own body. It is a builder rather than a widget so a
  /// change to the store, such as a scrub moving the position, reaches the
  /// body's [ReaderBody.positionLabel] in the same frame it reaches the chip.
  final ReaderBody Function(BuildContext context) bodyBuilder;

  /// Overrides the rung the store reports, for the states that are decided
  /// per page rather than per document.
  final RenderPlan? plan;

  /// The one honest line a damaged sheet prints.
  final String? damageReason;

  /// What is being placed on the page, if anything.
  final Widget? placement;

  /// The find layer, when it is open.
  final Widget? overlay;

  /// Overrides what the riffle holds, for a format that knows better than the
  /// document model does.
  final List<RiffleItem>? riffleItems;

  /// Where the current query's matches sit, 0 to 1 down the document.
  final List<double> matches;

  /// The match the chevrons are standing on.
  final double? liveMatch;

  /// How far the ticks have faded in.
  final double matchOpacity;

  /// How many matches sit on each unit of the document, which is what the
  /// scrub bubble prints when a search is live. Empty when nothing is being
  /// searched for.
  final List<int> matchCounts;

  final VoidCallback? onFind;

  /// What the damaged sheet's second button does. It is only offered when the
  /// raw bytes decode as text, so the button never appears unless there is
  /// something behind it.
  final VoidCallback? onOpenAsText;

  /// What leaving does. Defaults to popping the route the reader was pushed
  /// on.
  final VoidCallback? onLeave;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with TickerProviderStateMixin {
  static const Size _sheet = Size(kSheetWidth, kSheetHeight);

  late final AnimationController _chrome = AnimationController(
    vsync: this,
    duration: kChromeOut,
    reverseDuration: kChromeIn,
  )..addListener(_repaint);

  late final AnimationController _foldMove = AnimationController(
    vsync: this,
    duration: kFlipCommit,
  )..addListener(_repaint);

  late final AnimationController _riffle = AnimationController(
    vsync: this,
    duration: kRiffleIn,
    reverseDuration: kRiffleOut,
  )..addListener(_repaint);

  late final AnimationController _riffleCommit = AnimationController(
    vsync: this,
    duration: kRiffleCommit,
  )..addListener(_repaint);

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: kCloseDocument,
  )..addListener(_repaint);

  /// Where the fold is, in sheet coordinates, or null when it is at rest.
  Offset? _foldPoint;
  Animation<Offset>? _foldTrack;

  /// Which run of the fold animation is current.
  ///
  /// Stopping a controller completes its ticker future as a cancellation, and
  /// a cancelled run's tail would otherwise put the sheet back to rest under a
  /// finger that has just started a new peel.
  int _foldRun = 0;
  int _slideRun = 0;
  SheetSide _side = SheetSide.front;
  bool _catching = false;
  Timer? _still;

  /// How far the reader has been slid off toward the desk.
  double _slideX = 0;
  Animation<double>? _slideTrack;

  bool _scrubbing = false;
  double _scrubY = 0;
  double _scrubFromY = 0;
  int _scrubFrom = 0;
  double _tintFrom = double.nan;

  List<RiffleItem> _riffleShowing = const <RiffleItem>[];
  int _riffleFrom = 0;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_repaint);
  }

  @override
  void didUpdateWidget(ReaderScreen old) {
    super.didUpdateWidget(old);
    if (old.store != widget.store) {
      old.store.removeListener(_repaint);
      widget.store.addListener(_repaint);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_repaint);
    _still?.cancel();
    _chrome.dispose();
    _foldMove.dispose();
    _riffle.dispose();
    _riffleCommit.dispose();
    _slide.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  DocumentStore get _store => widget.store;

  Corner get _corner => _side.restCorner;

  /// Where a unit sits down the document, 0 at the first and 1 at the last.
  double _fractionOf(int unit, int unitCount) =>
      unitCount <= 1 ? 0 : (unit / (unitCount - 1)).clamp(0, 1);

  // The chrome.

  void _hideChrome() {
    if (_chrome.value == 1) return;
    _chrome.forward();
  }

  void _showChrome() {
    if (_chrome.value == 0) return;
    _chrome.reverse();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta.abs() > kChromeHideDelta) _hideChrome();
    }
    return false;
  }

  // The corner peel, the dog ear, and the flip.

  void _peelArm(Offset at) {
    _foldMove.stop();
    _foldRun++;
    _foldTrack = null;
    setState(() {
      _catching = false;
      _foldPoint = at - kSheetRect.topLeft;
    });
  }

  void _peelUpdate(Offset at) {
    if (_catching) return;
    final point = at - kSheetRect.topLeft;
    setState(() => _foldPoint = point);
    _still?.cancel();
    final travelled = (point - foldCornerOf(_corner, _sheet)).distance;
    if (travelled > dogEarCatchDistance(_sheet)) {
      _still = Timer(kDogEarCatchHold, _catchDogEar);
    }
  }

  /// The fold stops following the finger and settles at [kDogEarInset]. The
  /// same drag makes a flip or a bookmark, separated only by whether the
  /// finger paused, which is why there is no bookmark button in the app.
  void _catchDogEar() {
    if (!mounted || _foldPoint == null) return;
    _catching = true;
    HapticFeedback.selectionClick();
    _store.toggleDogEar(_store.position);
    _runFold(
      to: foldRestPoint(_corner, _sheet, kDogEarInset),
      spring: AppSprings.peelSnap,
      clamp: true,
    );
  }

  void _peelEnd(bool completed) {
    _still?.cancel();
    final point = _foldPoint;
    if (point == null) return;
    if (_catching) {
      _catching = false;
      return;
    }
    final travelled = (point - foldCornerOf(_corner, _sheet)).distance;
    if (completed && travelled > flipCommitDistance(_sheet)) {
      _runFold(
        to: foldOppositeOf(_corner, _sheet),
        duration: kFlipCommit,
        spring: AppSprings.pageSettle,
        onDone: () => setState(() {
          _side = _side == SheetSide.front ? SheetSide.back : SheetSide.front;
        }),
      );
      return;
    }
    _runFold(
      to: foldRestPoint(_corner, _sheet, _restInset),
      spring: AppSprings.peelSnap,
      clamp: true,
    );
  }

  /// Runs the fold from where it is to [to] on a spring, then hands the sheet
  /// back to its resting state.
  void _runFold({
    required Offset to,
    required SpringDescription spring,
    Duration? duration,
    bool clamp = false,
    VoidCallback? onDone,
  }) {
    final from = _foldPoint;
    if (from == null) return;
    final length = duration ?? springDuration(spring, clampOvershoot: clamp);
    _foldMove.duration = length;
    _foldTrack = Tween<Offset>(begin: from, end: to).animate(
      CurvedAnimation(
        parent: _foldMove,
        curve: SpringCurve(spring, duration: length, clampOvershoot: clamp),
      ),
    );
    final run = ++_foldRun;
    _foldMove.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || run != _foldRun) return;
      _foldTrack = null;
      setState(() => _foldPoint = null);
      onDone?.call();
    });
    setState(() {});
  }

  /// The fold's rest inset: a page with its corner turned rests further in
  /// than one that has never been touched, which is what a dog ear is.
  double get _restInset =>
      _store.dogEared.contains(_store.position) ? kDogEarInset : kFoldRestInset;

  // The fore edge.

  void _scrubStart(Offset at) {
    setState(() {
      _scrubbing = true;
      _scrubY = at.dy;
      _scrubFromY = at.dy;
      _scrubFrom = _store.position;
      _tintFrom = double.nan;
    });
  }

  void _scrubUpdate(Offset at, int unitCount) {
    final target = scrubTarget(_scrubFrom, at.dy - _scrubFromY, unitCount);
    var landed = target;
    for (final page in _store.dogEared) {
      final y =
          kForeEdgeTop +
          _fractionOf(page, unitCount) * (kForeEdgeHeight - kPageRule);
      if ((at.dy - y).abs() <= kNubSnapDistance) {
        if (landed != page) HapticFeedback.selectionClick();
        landed = page;
        _tintFrom = y;
        break;
      }
    }
    setState(() {
      _scrubY = at.dy;
      _store.position = landed;
    });
  }

  void _scrubEnd() {
    setState(() {
      _scrubbing = false;
      _tintFrom = double.nan;
    });
  }

  /// The match a scrubbing thumb is standing on, which widens so a reader can
  /// see what they are about to land on.
  double? get _scrubbedMatch {
    if (!_scrubbing || widget.matches.isEmpty) return null;
    final at = ((_scrubY - kForeEdgeTop) / kForeEdgeHeight).clamp(0.0, 1.0);
    var nearest = widget.matches.first;
    for (final match in widget.matches) {
      if ((match - at).abs() < (nearest - at).abs()) nearest = match;
    }
    return nearest;
  }

  /// How many matches sit on the unit the reader is standing on, or null when
  /// nothing is being searched for.
  int? get _matchesHere {
    if (widget.matchCounts.isEmpty) return null;
    final at = _store.position;
    if (at < 0 || at >= widget.matchCounts.length) return null;
    return widget.matchCounts[at];
  }

  /// How far the folio chip has tinted from leaf toward thread: it runs with
  /// the distance the scrub has travelled past the nub it last caught.
  double get _folioTint {
    if (!_scrubbing || _tintFrom.isNaN) return 0;
    return ((_scrubY - _tintFrom).abs() / kFolioTintTravel).clamp(0, 1);
  }

  // The riffle.

  void _openRiffle() {
    if (_riffle.value > 0) return;
    final items = widget.riffleItems ?? riffleItemsFor(_store);
    if (items.isEmpty) return;
    setState(() {
      _riffleShowing = items;
      _riffleFrom = _store.position.clamp(0, items.length - 1);
      _committing = false;
    });
    _riffleCommit.value = 0;
    _riffle.forward();
  }

  /// Browsing is free: dismissing the riffle returns the reader to the item
  /// they came in on, never the one they scrolled past.
  void _closeRiffle() {
    _riffle.reverse();
  }

  void _commitRiffle(int index) {
    if (_committing) return;
    setState(() => _committing = true);
    _riffleCommit.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) return;
      _store.position = index;
      _riffle.value = 0;
      setState(() => _committing = false);
    });
  }

  // Leaving.

  /// A new drag takes the reader back off whatever the last one left running.
  void _backDragStart(DragStartDetails details) {
    _slide.stop();
    _slideRun++;
    setState(() => _slideTrack = null);
  }

  void _backDragUpdate(DragUpdateDetails details) {
    setState(() {
      _slideX = math.max(0, _slideX + details.delta.dx);
    });
  }

  void _backDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (_slideX > kBackDragCommit || velocity > kBackDragVelocity) {
      _slideTo(kScreenWidth, then: _leave);
    } else {
      _slideTo(0);
    }
  }

  void _slideTo(double to, {VoidCallback? then}) {
    final length = springDuration(AppSprings.pageSettle);
    _slide.duration = length;
    _slideTrack = Tween<double>(begin: _slideX, end: to).animate(
      CurvedAnimation(
        parent: _slide,
        curve: SpringCurve(AppSprings.pageSettle, duration: length),
      ),
    );
    final run = ++_slideRun;
    _slide.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || run != _slideRun) return;
      _slideTrack = null;
      setState(() => _slideX = to);
      then?.call();
    });
  }

  void _leave() {
    final leave = widget.onLeave;
    if (leave != null) {
      leave();
      return;
    }
    Navigator.of(context).maybePop<void>();
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.bodyBuilder(context);
    final plan = widget.plan ?? _store.plan;
    final unitCount = math.max(body.unitCount, 1);
    final track = _foldTrack;
    final foldPoint = track != null ? track.value : _foldPoint;
    final slide = _slideTrack?.value ?? _slideX;
    final hidden = _chrome.value;
    final dogEars = <double>[
      for (final page in _store.dogEared) _fractionOf(page, unitCount),
    ];
    final signatures = <double>[
      for (final mark in _store.signatures)
        _fractionOf(mark.pageIndex, unitCount),
    ];
    final position = _fractionOf(_store.position, unitCount);
    // A locked or damaged document has no position to be in, so it carries
    // neither the strip nor the chip: an empty pill floating over a torn sheet
    // would be the app insisting on chrome it cannot fill.
    final readable = plan != RenderPlan.locked && plan != RenderPlan.damaged;

    return PopScope(
      // Pressing back while the riffle is up closes the riffle rather than
      // putting the document down: browsing has to be free, and a reader who
      // opened the page block did not ask to leave.
      canPop: _riffle.value == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeRiffle();
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: _gestures(unitCount, hidden, body),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: AppColors.deskGround.withValues(
                      alpha:
                          kDeskDim * (1 - (slide / kScreenWidth).clamp(0, 1)),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(slide, 0),
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: AppColors.deskGround),
                    ),
                    Positioned.fromRect(
                      rect: kSheetRect,
                      child: _sheetFor(plan, body, foldPoint),
                    ),
                    if (readable)
                      Positioned(
                        left: kForeEdgeLeft,
                        top: kForeEdgeTop,
                        child: IgnorePointer(
                          child: ForeEdge(
                            marks: body.foreEdgeMarks,
                            position: position,
                            dogEars: dogEars,
                            damaged: body.damagedMarks,
                            signatures: signatures,
                            matches: widget.matches,
                            liveMatch: widget.liveMatch,
                            scrubbedMatch: _scrubbedMatch,
                            matchOpacity: widget.matchOpacity,
                          ),
                        ),
                      ),
                    if (_scrubbing)
                      Positioned(
                        right:
                            kScreenWidth - kForeEdgeLeft + kForeEdgeBubbleGap,
                        top: _scrubY - kForeEdgeBubble / 2,
                        child: IgnorePointer(
                          child: ForeEdgeBubble(
                            label: 'p. ${body.positionLabel}',
                            matches: _matchesHere,
                          ),
                        ),
                      ),
                    if (readable)
                      Positioned(
                        left:
                            kSheetLeft +
                            kSheetWidth -
                            kFolioChipInset -
                            kFolioChipWidth,
                        top:
                            kSheetTop +
                            kSheetHeight -
                            kFolioChipInset -
                            kFolioChipHeight +
                            kFolioChipHidden * hidden,
                        child: IgnorePointer(
                          child: FolioChip(
                            label: body.positionLabel,
                            hidden: hidden,
                            dogEared: _store.dogEared.contains(_store.position),
                            tint: _folioTint,
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: PlacementSlot(child: widget.placement),
                    ),
                    ReaderChrome(
                      title: _store.entry.title,
                      hidden: hidden,
                      showingBack: _side == SheetSide.back,
                      onBack: _leave,
                      onFind: widget.onFind,
                    ),
                    ?widget.overlay,
                    if (_riffle.value > 0)
                      Positioned.fill(
                        child: RiffleSheet(
                          items: _riffleShowing,
                          initialIndex: _riffleFrom,
                          kindLabel: _riffleLabel(_riffleShowing.length),
                          progress:
                              _riffle.value *
                              (1 - easeOutQuad.transform(_riffleCommit.value)),
                          onSelect: _commitRiffle,
                          onClose: _closeRiffle,
                        ),
                      ),
                    if (_committing)
                      Positioned.fromRect(
                        rect: Rect.lerp(
                          _riffleSlotRect,
                          kSheetRect,
                          easeOutCubic.transform(_riffleCommit.value),
                        )!,
                        child: IgnorePointer(
                          // The same leaf and the same hairline the sheet
                          // itself wears, so the slot growing into the reader
                          // is one object changing size, not two swapping.
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.leaf,
                              borderRadius: kPeelableCorner,
                              border: AppEdges.all(context),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Where the item a reader tapped sits before it grows into the sheet.
  ///
  /// A page riffles as a picture of itself and a section riffles as a card, so
  /// the thing that grows is whichever of the two was under the finger.
  Rect get _riffleSlotRect {
    final card =
        _riffleShowing.isNotEmpty &&
        _riffleShowing[_riffleFrom.clamp(0, _riffleShowing.length - 1)].title !=
            null;
    return Rect.fromCenter(
      center: const Offset(kScreenWidth / 2, kSheetTop + kSheetHeight / 2),
      width: card ? kRiffleCardWidth : kRiffleThumbWidth,
      height: card ? kRiffleCardHeight : kRiffleThumbHeight,
    );
  }

  String _riffleLabel(int count) {
    if (_store.isPdf) return '$count PAGES';
    if (_store.isGrid) return '$count SHEETS';
    return '$count SECTIONS';
  }

  /// The sheet, or the designed state that stands in for it.
  Widget _sheetFor(RenderPlan plan, ReaderBody body, Offset? foldPoint) {
    switch (plan) {
      case RenderPlan.locked:
        return LockedSheet(onLeave: _leave);
      case RenderPlan.damaged:
        return DamagedSheet(
          reason: widget.damageReason ?? damageReasonFor(_store.error),
          onLeave: _leave,
          onOpenAsText: decodesAsText(_store.bytes)
              ? widget.onOpenAsText
              : null,
        );
      case RenderPlan.rich:
      case RenderPlan.textOnly:
      case RenderPlan.scan:
      case RenderPlan.scanUnreadable:
        return SheetSurface(
          side: _side,
          foldPoint: foldPoint,
          restInset: _restInset,
          caught: _catching || _store.dogEared.contains(_store.position),
          front: body.buildFront(context),
          back: body.buildBack(context),
        );
    }
  }

  /// Which recognizers are in the arena this frame.
  ///
  /// The three region recognizers stand down whenever something is over the
  /// reader: the riffle, the find field, or a mark being set into the page.
  /// Each of those is a layer over the whole screen, and a strip that still
  /// answered a finger through one would be a control reaching through a wall.
  /// It is not a nicety either: the strip accepts a pointer outright anywhere
  /// past x 360, which is where find's own next chevron stands.
  Map<Type, GestureRecognizerFactory> _gestures(
    int unitCount,
    double hidden,
    ReaderBody body,
  ) {
    final reading =
        _riffle.value == 0 &&
        widget.placement == null &&
        widget.overlay == null;
    return <Type, GestureRecognizerFactory>{
      if (reading)
        _ForeEdgeRecognizer:
            GestureRecognizerFactoryWithHandlers<_ForeEdgeRecognizer>(
              _ForeEdgeRecognizer.new,
              (recognizer) {
                recognizer.region = foreEdgeRegionFor(body);
                recognizer.onScrubStart = _scrubStart;
                recognizer.onScrubUpdate = (at) => _scrubUpdate(at, unitCount);
                recognizer.onScrubEnd = _scrubEnd;
                recognizer.onTap = _openRiffle;
              },
            ),
      if (reading)
        _CornerPeelRecognizer:
            GestureRecognizerFactoryWithHandlers<_CornerPeelRecognizer>(
              _CornerPeelRecognizer.new,
              (recognizer) {
                recognizer.region = cornerRegion(_corner);
                recognizer.onArm = _peelArm;
                recognizer.onUpdate = _peelUpdate;
                recognizer.onEnd = _peelEnd;
              },
            ),
      if (reading)
        _BackEdgeRecognizer:
            GestureRecognizerFactoryWithHandlers<_BackEdgeRecognizer>(
              _BackEdgeRecognizer.new,
              (recognizer) {
                recognizer.region = kBackEdgeRegion;
                recognizer.onStart = _backDragStart;
                recognizer.onUpdate = _backDragUpdate;
                recognizer.onEnd = _backDragEnd;
              },
            ),
      if (reading && hidden > 0)
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (recognizer) {
                recognizer.onTap = _showChrome;
              },
            ),
    };
  }
}

/// The fore edge owns every pointer that lands in its band, outright.
///
/// It accepts the moment a finger goes down rather than waiting for slop,
/// because the band belongs to no one else: a scroll view that wins here has
/// stolen the only control the reader has.
class _ForeEdgeRecognizer extends OneSequenceGestureRecognizer {
  Rect region = Rect.zero;
  void Function(Offset at)? onScrubStart;
  void Function(Offset at)? onScrubUpdate;
  VoidCallback? onScrubEnd;
  VoidCallback? onTap;

  Offset _down = Offset.zero;
  bool _scrubbing = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      region.contains(event.localPosition) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    _down = event.localPosition;
    _scrubbing = false;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (!_scrubbing &&
          (event.localPosition - _down).distance > kForeEdgeTapSlop) {
        _scrubbing = true;
        onScrubStart?.call(_down);
      }
      if (_scrubbing) onScrubUpdate?.call(event.localPosition);
      return;
    }
    if (event is PointerUpEvent) {
      if (_scrubbing) {
        onScrubEnd?.call();
      } else {
        onTap?.call();
      }
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (_scrubbing) onScrubEnd?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _scrubbing = false;
  }

  @override
  String get debugDescription => 'fore edge';
}

/// The corner handle: a hold, and then a drag.
///
/// It does not accept until the hold is up, so a finger that sets off from the
/// corner straight away is scrolling the page, which is what a finger moving
/// immediately means everywhere else in the app.
class _CornerPeelRecognizer extends OneSequenceGestureRecognizer {
  Rect region = Rect.zero;
  void Function(Offset at)? onArm;
  void Function(Offset at)? onUpdate;
  void Function(bool completed)? onEnd;

  Timer? _hold;
  bool _armed = false;
  Offset _down = Offset.zero;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      region.contains(event.localPosition) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _down = event.localPosition;
    _armed = false;
    _hold = Timer(kPeelLongPress, _arm);
  }

  void _arm() {
    _hold = null;
    _armed = true;
    resolve(GestureDisposition.accepted);
    onArm?.call(_down);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (_armed) {
        onUpdate?.call(event.localPosition);
        return;
      }
      if ((event.localPosition - _down).distance > kTouchSlop) {
        _release(event.pointer, completed: false);
      }
      return;
    }
    if (event is PointerUpEvent) {
      _release(event.pointer, completed: true);
    } else if (event is PointerCancelEvent) {
      _release(event.pointer, completed: false);
    }
  }

  void _release(int pointer, {required bool completed}) {
    _hold?.cancel();
    _hold = null;
    if (_armed) {
      _armed = false;
      onEnd?.call(completed);
    } else {
      resolve(GestureDisposition.rejected);
    }
    stopTrackingPointer(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _hold?.cancel();
    _hold = null;
    if (_armed) {
      _armed = false;
      onEnd?.call(false);
    }
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _hold?.cancel();
    _hold = null;
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  String get debugDescription => 'corner peel';
}

/// Leaving a document: a horizontal drag that has to start inside the edge
/// zone, so it can never be mistaken for anything the sheet itself does.
class _BackEdgeRecognizer extends HorizontalDragGestureRecognizer {
  Rect region = Rect.zero;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      region.contains(event.localPosition) && super.isPointerAllowed(event);
}
