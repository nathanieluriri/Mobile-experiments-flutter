import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../format/document_loader.dart';
import '../../helpers/fold_geometry.dart';
import '../../services/document_store.dart';
import '../../services/render_plan.dart';
import '../../theme/colors.dart';
import '../../theme/feedback.dart';
import '../../theme/easings.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/springs.dart';
import 'corner_peel.dart';
import 'document_states.dart';
import 'folio_chip.dart';
import 'fore_edge.dart';
import 'password_sheet.dart';
import 'loupe.dart';
import 'reader_chrome.dart';
import 'reader_route.dart';
import 'unlock_chip.dart';
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
    this.wrongPassword,
    this.cipher,
    this.onUnlock,
    this.placement,
    this.overlay,
    this.riffleItems,
    this.matches = const <double>[],
    this.liveMatch,
    this.matchOpacity = 1,
    this.matchCounts = const <int>[],
    this.onFind,
    this.onMenu,
    this.menu,
    this.menuOpen = 0,
    this.notice,
    this.placing = false,
    this.onConfirmPlacement,
    this.onCancelPlacement,
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

  /// Overrides whether the password sheet is showing its second message.
  final bool? wrongPassword;

  /// Overrides what sealed the file, for the sheet that names it.
  final String? cipher;

  /// Handed a typed password. It defaults to the store's own retry, which
  /// reopens the document with it.
  final ValueChanged<String>? onUnlock;

  /// What is being placed on the page, if anything.
  final Widget? placement;

  /// The find layer, when it is open.
  final Widget? overlay;

  /// Opens the menu behind the band's three dots.
  final VoidCallback? onMenu;

  /// That menu, when it is open. It is drawn over the chrome, since the band
  /// is what it belongs to.
  final Widget? menu;

  /// 0 with the menu shut and 1 with it open, which the band's dots read to
  /// draw themselves together.
  final double menuOpen;

  /// A line for the band to say in place of the title.
  final String? notice;

  /// True while a signature is loose over the page, which holds the band in
  /// place and turns it into the two answers that state has.
  final bool placing;

  final VoidCallback? onConfirmPlacement;
  final VoidCallback? onCancelPlacement;

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

  /// The chip a locked page offers when it is asked for the way out.
  late final AnimationController _unlockChip = AnimationController(
    vsync: this,
    duration: kUnlockChipFade,
  )..addListener(_repaint);

  /// The clock that takes the chip away again.
  Timer? _chipGone;

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
    _opening?.removeListener(_repaint);
    _still?.cancel();
    _chipGone?.cancel();
    _chrome.dispose();
    _unlockChip.dispose();
    _foldMove.dispose();
    _riffle.dispose();
    _riffleCommit.dispose();
    _slide.dispose();
    super.dispose();
  }

  /// What was fastened last time the store spoke, so a lock going on can be
  /// noticed rather than merely drawn.
  ReaderLock _lockWas = ReaderLock.none;

  /// The route bringing this document in, which is what the corner button's
  /// turn is measured against.
  ///
  /// The desk's three lines turn into an arrow as the drawer arrives, and the
  /// same three lines turn into the same arrow as a document arrives, because
  /// it is the same button making the same journey away from the desk.
  /// Reading the route rather than running a second animation is what keeps
  /// the glyph from ever disagreeing with the thing it describes, and it
  /// turns the arrow back into the menu on the way out for nothing.
  ///
  /// Null when nothing pushed this screen, which is a test, and then the
  /// arrow is simply an arrow.
  Animation<double>? _opening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (identical(route, _opening)) return;
    _opening?.removeListener(_repaint);
    _opening = route;
    _opening?.addListener(_repaint);
  }

  void _repaint() {
    if (!mounted) return;
    final now = _store.lock;
    if (now != _lockWas) {
      final was = _lockWas;
      _lockWas = now;
      // A page lock takes the band away, and the band is where the reader is
      // told things. So the chip introduces itself: it comes up once, says
      // what it is for, and goes.
      if (now.holdsBack && !was.holdsBack) _askUnlock();
    }
    setState(() {});
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

  /// A tap on the page puts the band away, or brings it back.
  ///
  /// Scrolling down was the only way to be rid of it, which meant that at the
  /// top of a document there was no way at all: there is nothing above the
  /// first line to scroll towards. A tap is the whole gesture, and it is the
  /// one every reader already tries.
  void _tapChrome() {
    Feel.tap.ring();
    if (_chrome.value > 0) {
      _chrome.reverse();
    } else {
      _chrome.forward();
    }
  }

  /// Reading takes the band away and looking for something brings it back.
  ///
  /// Down is reading on, so the band goes and the page has the screen. Up is
  /// somebody going back for something, and what they are most likely going
  /// back for is the way out or the search, so the band returns at the first
  /// hint of it.
  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > kChromeHideDelta) {
        _hideChrome();
      } else if (delta < -kChromeHideDelta) {
        _showChrome();
      }
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
    Feel.turn.ring();
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
      Feel.turn.ring();
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
        if (landed != page) Feel.tap.ring();
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

  /// How far the folio chip has tinted from the sheet toward the accent: it
  /// runs with the distance the scrub has travelled past the nub it last
  /// caught.
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
    Feel.turn.ring();
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
      Feel.tap.ring();
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

  /// Where the finger is while the loupe is out, or null when it is up.
  Offset? _loupeAt;

  void _magnifierAt(PointerEvent event) {
    if (!_store.magnifier) return;
    setState(() => _loupeAt = event.localPosition);
  }

  void _magnifierGone() {
    if (_loupeAt == null) return;
    setState(() => _loupeAt = null);
  }

  /// A tap on a locked page, which is the one thing a locked page answers.
  void _askUnlock() {
    Feel.tap.ring();
    _chipGone?.cancel();
    _unlockChip.forward();
    _chipGone = Timer(kUnlockChipHold, () {
      if (mounted) _unlockChip.reverse();
    });
  }

  /// Takes the lock off, whichever kind it was.
  void _unlock() {
    Feel.commit.ring();
    _chipGone?.cancel();
    _unlockChip.reverse();
    _store.lock = ReaderLock.none;
  }

  /// What happens when something asks to leave a document that is fastened.
  ///
  /// A refusal has to be felt, or a lock is indistinguishable from a phone
  /// that has stopped answering, and it brings the chip up, since a locked
  /// reading has nothing else on screen to point at.
  void _refuseToLeave(ReaderLock lock) {
    Feel.commit.ring();
    _askUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.bodyBuilder(context);
    final plan = widget.plan ?? _store.plan;
    final unitCount = math.max(body.unitCount, 1);
    final track = _foldTrack;
    final foldPoint = track != null ? track.value : _foldPoint;
    final slide = _slideTrack?.value ?? _slideX;
    final lock = _store.lock;
    // How far the paper still is from home because the document is arriving,
    // which is the route's own animation read through the arrival curve. Zero
    // for a reader nothing pushed, which is a test.
    final opening = _opening;
    final arrival = opening == null
        ? 0.0
        : kScreenWidth *
              (1 - kDocumentArrival.transform(opening.value.clamp(0.0, 1.0)));
    // A page lock takes the band with it, so the chrome is gone outright
    // rather than merely scrolled away: there is nothing to bring it back
    // while the lock is on.
    // Either lock takes the band away outright. A band left up over a locked
    // reading is a row of buttons that will not do what they say, and the only
    // control a locked reading has is the one that unlocks it.
    final hidden = lock.holdsBack ? 1.0 : _chrome.value;
    final dogEars = <double>[
      for (final page in _store.dogEared) _fractionOf(page, unitCount),
    ];
    final signatures = <double>[
      for (final mark in _store.signatures)
        _fractionOf(mark.pageIndex, unitCount),
    ];
    final position = _fractionOf(_store.position, unitCount);
    // A protected or damaged document has no position to be in, so it carries
    // neither the strip nor the chip: an empty pill floating over a torn sheet
    // would be the app insisting on chrome it cannot fill.
    const unreadable = <RenderPlan>{
      RenderPlan.needsPassword,
      RenderPlan.unsupportedCipher,
      RenderPlan.damaged,
    };
    final readable = !unreadable.contains(plan);

    return PopScope(
      // Pressing back while the riffle is up closes the riffle rather than
      // putting the document down: browsing has to be free, and a reader who
      // opened the page block did not ask to leave.
      // A lock is a lock. It answers back before the riffle does, because a
      // reader who fastened the way out did so to stop exactly this.
      // A reader handed its own way out takes system back through it too,
      // so the button in the corner and the phone's back gesture can never
      // disagree about where leaving goes.
      canPop:
          _riffle.value == 0 && !lock.holdsBack && widget.onLeave == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (lock.holdsBack) {
          _refuseToLeave(lock);
          return;
        }
        if (_riffle.value > 0) {
          _closeRiffle();
          return;
        }
        _leave();
      },
      child: Listener(
        // A listener rather than a recogniser: the loupe watches where the
        // finger is without taking the finger off whatever it was doing, so
        // the page still scrolls and every control still works underneath it.
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: _magnifierAt,
        onPointerMove: _magnifierAt,
        onPointerUp: (_) => _magnifierGone(),
        onPointerCancel: (_) => _magnifierGone(),
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
                      color: AppColors.ground.withValues(
                        // However far off home the paper is, by arriving or by
                        // being dragged away, is how much of the desk is
                        // showing and how little of it should be dark.
                        alpha:
                            kDeskDim *
                            (1 -
                                ((slide + arrival) / kScreenWidth).clamp(0, 1)),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(slide, 0),
                  child: Stack(
                    children: [
                      // The paper, and everything drawn on the paper. This is
                      // what travels when a document arrives; the band above
                      // it does not, because the band is where the desk's own
                      // corner button is turning into the way back.
                      Positioned.fill(
                        child: Transform.translate(
                          offset: Offset(arrival, 0),
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: ColoredBox(color: AppColors.ground),
                              ),
                              Positioned.fromRect(
                                rect: kSheetRect,
                                child: _sheetFor(plan, body, foldPoint),
                              ),
                              if (readable && !lock.holdsBack)
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
                                      kScreenWidth -
                                      kForeEdgeLeft +
                                      kForeEdgeBubbleGap,
                                  top: _scrubY - kForeEdgeBubble / 2,
                                  child: IgnorePointer(
                                    child: ForeEdgeBubble(
                                      label: 'p. ${body.positionLabel}',
                                      matches: _matchesHere,
                                    ),
                                  ),
                                ),
                              if (readable && !lock.holdsBack)
                                Positioned(
                                  left:
                                      kSheetLeft +
                                      kSheetWidth -
                                      kFolioChipInset -
                                      kFolioChipWidth,
                                  top:
                                      kReadableBottom -
                                      kFolioChipInset -
                                      kFolioChipHeight +
                                      kFolioChipHidden * hidden,
                                  child: IgnorePointer(
                                    child: FolioChip(
                                      label: body.positionLabel,
                                      hidden: hidden,
                                      dogEared: _store.dogEared.contains(
                                        _store.position,
                                      ),
                                      tint: _folioTint,
                                    ),
                                  ),
                                ),
                              Positioned.fill(
                                child: PlacementSlot(child: widget.placement),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ReaderChrome(
                        title: _store.entry.title,
                        hidden: hidden,
                        showingBack: _side == SheetSide.back,
                        backMorph: opening == null
                            ? 1
                            : kDocumentArrival.transform(
                                opening.value.clamp(0.0, 1.0),
                              ),
                        onBack: _leave,
                        onFind: widget.onFind,
                        onMenu: widget.onMenu,
                        menuOpen: widget.menuOpen,
                        // Under a lock the band stays gone even with
                        // something to say, since saying it would bring every
                        // button in the band back with it.
                        notice: lock.holdsBack ? null : widget.notice,
                        placing: widget.placing,
                        onConfirm: widget.onConfirmPlacement,
                        onCancel: widget.onCancelPlacement,
                      ),
                      ?widget.menu,
                      ?widget.overlay,
                      if (lock.holdsBack)
                        UnlockChip(
                          progress: _unlockChip.value,
                          onUnlock: _unlock,
                          label: lock.holdsPage
                              ? 'Unlock the page'
                              : 'Unlock the reading',
                        ),
                      // Last of all, because a magnifier under something is a
                      // magnifier of nothing.
                      if (_store.magnifier) Loupe(at: _loupeAt),
                      if (_riffle.value > 0)
                        Positioned.fill(
                          child: RiffleSheet(
                            items: _riffleShowing,
                            initialIndex: _riffleFrom,
                            kindLabel: _riffleLabel(_riffleShowing.length),
                            progress:
                                _riffle.value *
                                (1 -
                                    easeOutQuad.transform(_riffleCommit.value)),
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
                                color: AppColors.surface,
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
      case RenderPlan.needsPassword:
        return PasswordSheet(
          rejected: widget.wrongPassword ?? _store.wrongPassword,
          onSubmit: widget.onUnlock ?? _store.unlock,
          onLeave: _leave,
        );
      case RenderPlan.unsupportedCipher:
        final cipher = widget.cipher ?? _store.cipher;
        return UnsupportedCipherSheet(
          cipher: cipher,
          office: cipher == kOfficeCipher,
          onLeave: _leave,
        );
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
        widget.overlay == null &&
        !_store.lock.holdsBack;
    final locked = _store.lock;
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
                // The back is made ready on the arm rather than on the first
                // move, so the frame the corner lifts on is already a frame
                // with something under it.
                recognizer.onArm = (at) {
                  body.prepareBack();
                  _peelArm(at);
                };
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
      // A locked page has one gesture and this is it: a tap asks for the way
      // out, which arrives as a chip and leaves again on its own.
      if (locked.holdsBack)
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (recognizer) {
                recognizer.onTap = _askUnlock;
              },
            )
      else if (reading)
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (recognizer) {
                recognizer.onTap = _tapChrome;
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
