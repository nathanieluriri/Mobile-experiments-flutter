import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/library.dart';
import '../../helpers/fold_geometry.dart';
import '../../painting/fold_painter.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../theme/shadows.dart';
import '../../theme/springs.dart';
import '../../widgets/action_dock.dart';
import '../../widgets/press_fade.dart';
import 'document_card.dart';

/// The four things you can do to a card without opening it.
enum DeskAction { read, sign, dogEar, remove }

/// The dock under a lifted card, in the order it is laid out.
const kDeskActions = <DeskAction>[
  DeskAction.read,
  DeskAction.sign,
  DeskAction.dogEar,
  DeskAction.remove,
];

/// How far the corner must travel before the card is treated as picked up.
///
/// Below this a peel is somebody looking at the back of a card; above it they
/// have decided to do something with it, and the desk gets out of the way.
const kCardLiftTravel = 40.0;

/// How far the card jumps either side when it refuses a drop, and how long the
/// refusal takes.
const kRefusalShake = 2.0;
const kRefusalDuration = Duration(milliseconds: 180);

/// Where the fold point comes from, frame by frame.
enum _Phase {
  /// Sitting at the rest inset, or following the finger.
  idle,

  /// Springing back to the rest inset after a release over nothing.
  snapping,
}

/// A card you can turn the corner of.
///
/// Hold the bottom right corner for [kPeelLongPress] and the paper folds under
/// the finger, showing the file's true detail on the back. Past
/// [kCardLiftTravel] the rest of the desk stands down and a dock of four
/// targets rises below the card.
class CardPeel extends StatefulWidget {
  const CardPeel({
    super.key,
    required this.cardKey,
    required this.entry,
    required this.store,
    required this.lifted,
    required this.dimmed,
    required this.hidden,
    required this.onFocus,
    required this.onBlur,
    required this.onAction,
    required this.onOpen,
    this.query = '',
  });

  /// The boundary the dissolve snapshots. Owned above, because the card is
  /// gone by the time its dust needs a picture of it.
  final GlobalKey cardKey;

  final LibraryEntry entry;
  final DocumentStore? store;

  /// True while this is the card the desk is standing around.
  final bool lifted;

  /// True while some other card is.
  final bool dimmed;

  /// True once the card has been snapshotted and is coming apart.
  final bool hidden;

  final VoidCallback onFocus;
  final VoidCallback onBlur;
  final void Function(DeskAction action) onAction;
  final VoidCallback onOpen;

  /// The desk search, marked wherever it appears in the title.
  final String query;

  @override
  State<CardPeel> createState() => _CardPeelState();
}

class _CardPeelState extends State<CardPeel> with TickerProviderStateMixin {
  late final AnimationController _lift;
  late final AnimationController _snap;
  late final AnimationController _dockEnter;
  late final AnimationController _dockExit;
  late final AnimationController _refuse;
  late final SpringCurve _snapCurve;

  _Phase _phase = _Phase.idle;

  /// How far the finger has carried the fold away from its rest inset. Kept as
  /// a translation rather than a point, so the corner is always this card's own
  /// corner.
  Offset _drag = Offset.zero;
  Offset _from = Offset.zero;
  int _hovered = -1;
  int _triggered = -1;
  bool _dockMounted = false;

  static const _restX = kCardWidth - kCardFoldRestInset;
  static const _restY = kCardHeight - kCardFoldRestInset;

  double get _foldX => switch (_phase) {
        _Phase.idle => _restX + _drag.dx,
        _Phase.snapping =>
          lerpDouble(_from.dx, _restX, _snapCurve.transform(_snap.value))!,
      };

  double get _foldY => switch (_phase) {
        _Phase.idle => _restY + _drag.dy,
        _Phase.snapping =>
          lerpDouble(_from.dy, _restY, _snapCurve.transform(_snap.value))!,
      };

  /// True while the corner is far enough from rest for the back of the card to
  /// be worth painting.
  bool get _peeling => _phase == _Phase.snapping || _drag != Offset.zero;

  @override
  void initState() {
    super.initState();
    _lift = AnimationController(vsync: this, duration: kLift);
    final snapDuration =
        springDuration(AppSprings.peelSnap, clampOvershoot: true);
    _snap = AnimationController(vsync: this, duration: snapDuration);
    _snapCurve = SpringCurve(
      AppSprings.peelSnap,
      duration: snapDuration,
      clampOvershoot: true,
    );
    _snap.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _phase = _Phase.idle;
          _drag = Offset.zero;
        });
      }
    });
    _dockEnter = AnimationController(
      vsync: this,
      duration: kDockEnter + kDockEnterStagger * (kDeskActions.length - 1),
    );
    _dockExit = AnimationController(vsync: this, duration: kDockExit);
    _dockExit.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _dockMounted = false);
      }
    });
    _refuse = AnimationController(vsync: this, duration: kRefusalDuration);
  }

  @override
  void dispose() {
    _lift.dispose();
    _snap.dispose();
    _dockEnter.dispose();
    _dockExit.dispose();
    _refuse.dispose();
    super.dispose();
  }

  void _showDock() {
    if (_dockMounted) return;
    _dockExit.value = 0;
    _dockEnter.forward(from: 0);
    setState(() => _dockMounted = true);
  }

  void _hideDock() {
    if (!_dockMounted) return;
    _dockExit.forward(from: 0);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _snap.stop();
    setState(() {
      _phase = _Phase.idle;
      _drag = Offset.zero;
      _hovered = -1;
      _triggered = -1;
    });
    HapticFeedback.selectionClick();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final drag = details.offsetFromOrigin;
    final lifted = drag.distance >= kCardLiftTravel;
    final foldX = _restX + drag.dx;
    final foldY = _restY + drag.dy;
    final dockY = dockRowCenterY(kCardHeight);
    // A target is only under the drag point once the target is on screen. A
    // button that arrives already hovered never gets to say so, because it has
    // no previous state to have changed from.
    final aiming = _dockMounted;
    var hovered = -1;
    if (aiming) {
      for (var i = 0; i < kDeskActions.length; i++) {
        final dx =
            foldX - dockButtonCenterX(i, kCardWidth, kDeskActions.length);
        final dy = foldY - dockY;
        if (math.sqrt(dx * dx + dy * dy) < kDockHoverRadius) hovered = i;
      }
    }
    final changed = hovered != _hovered;
    setState(() {
      _drag = drag;
      _hovered = hovered;
    });
    if (lifted && !widget.lifted) {
      _lift.animateTo(1, duration: kLift, curve: easeOutQuad);
      _showDock();
      widget.onFocus();
    }
    if (changed && hovered >= 0) HapticFeedback.selectionClick();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final index = _hovered;
    if (index < 0) {
      _settleBack();
      return;
    }
    final action = kDeskActions[index];
    if (!_enabled(action)) {
      _refuse.forward(from: 0);
      _settleBack();
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _triggered = index);
    HapticFeedback.mediumImpact();
    if (action == DeskAction.remove) {
      // The card has to be whole in the frame the snapshot is taken from, or
      // the dust would be dust of a peeled card rather than of a card.
      setState(() {
        _phase = _Phase.idle;
        _drag = Offset.zero;
        _hovered = -1;
        _dockMounted = false;
      });
      _lift.value = 0;
      widget.onBlur();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onAction(action);
      });
      return;
    }
    _settleBack();
    widget.onAction(action);
  }

  /// The gesture died without a normal release: the pointer was cancelled, or
  /// the press never lasted long enough to peel anything. Either way the card
  /// has to be put back, or it would stay lifted with nothing able to drop it.
  void _onLongPressCancel() {
    if (_triggered < 0) _settleBack();
  }

  void _settleBack() {
    setState(() {
      _hovered = -1;
      _phase = _Phase.snapping;
      _from = Offset(_foldX, _foldY);
    });
    _snap.forward(from: 0);
    _lift.animateBack(0, duration: kLift, curve: easeOutQuad);
    _hideDock();
    widget.onBlur();
  }

  /// SIGN is the one target that can refuse: only a page file can carry a
  /// drawn mark, and hiding the target on the other four formats would leave a
  /// hole where a target used to be.
  bool _enabled(DeskAction action) =>
      action != DeskAction.sign || widget.entry.format == DocFormat.pdf;

  IconData _icon(DeskAction action) => switch (action) {
        DeskAction.read => LucideIcons.bookOpen,
        DeskAction.sign => LucideIcons.penLine,
        DeskAction.dogEar => LucideIcons.bookmark,
        DeskAction.remove => LucideIcons.trash2,
      };

  String _label(DeskAction action) => switch (action) {
        DeskAction.read => 'READ',
        DeskAction.sign => 'SIGN',
        DeskAction.dogEar => 'DOG EAR',
        DeskAction.remove => 'REMOVE',
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation:
          Listenable.merge(<Listenable>[_lift, _snap, _refuse, _dockExit]),
      builder: (context, _) {
        final lift = easeOutQuad.transform(_lift.value);
        final shake = math.sin(_refuse.value * math.pi * 4) *
            kRefusalShake *
            (1 - _refuse.value);
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            Transform.translate(
              offset: Offset(shake, 0),
              child: Transform.scale(
                scale: 1 + kLiftScaleDelta * lift,
                child: Opacity(
                  opacity: widget.hidden
                      ? 0
                      : (widget.dimmed ? kDimmedCardOpacity : 1),
                  child: _card(lift),
                ),
              ),
            ),
            if (_dockMounted)
              Positioned(
                top: kCardHeight + kDockGap,
                left: 0,
                right: 0,
                child: ActionDock(
                  actions: <DockAction>[
                    for (final action in kDeskActions)
                      DockAction(
                        icon: _icon(action),
                        label: _label(action),
                        enabled: _enabled(action),
                      ),
                  ],
                  hovered: _hovered,
                  triggered: _triggered,
                  enter: _dockEnter,
                  exit: _dockExit,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _card(double lift) {
    final face = CardFacePainter(
      title: widget.entry.title,
      meta: cardMeta(widget.entry, widget.store),
      letters: widget.entry.mark,
      chroma: chromaFor(widget.entry.format),
    );
    return PaperPress(
      onTap: widget.onOpen,
      semanticLabel: widget.entry.title,
      borderRadius: kPeelableCorner,
      child: RepaintBoundary(
        key: widget.cardKey,
        child: SizedBox(
          width: kCardWidth,
          height: kCardHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DocumentCard(
                entry: widget.entry,
                store: widget.store,
                query: widget.query,
                shadows: lift > 0
                    ? AppShadows.leafLift(AppShadows.leafLiftAlpha * lift)
                    : const <BoxShadow>[],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: kPeelableCorner,
                    child: CustomPaint(
                      painter: FoldPainter(
                        dragX: _foldX,
                        dragY: _foldY,
                        corner: Corner.bottomRight,
                        background: AppColors.deskGround,
                        flapColor: AppColors.leafFlap,
                        backLayer: _peeling
                            ? CardBackPainter(
                                lines: cardBackLines(
                                  widget.entry,
                                  widget.store,
                                ),
                              )
                            : null,
                        showThrough: _peeling ? face : null,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                width: kCornerHandle,
                height: kCornerHandle,
                child: _handle(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle() {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: kPeelLongPress),
          (instance) => instance
            ..onLongPressStart = _onLongPressStart
            ..onLongPressMoveUpdate = _onLongPressMoveUpdate
            ..onLongPressEnd = _onLongPressEnd
            ..onLongPressCancel = _onLongPressCancel,
        ),
      },
    );
  }
}
