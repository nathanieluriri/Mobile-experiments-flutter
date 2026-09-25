import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/note.dart';
import '../data/note_actions.dart';
import '../painting/fold_painter.dart';
import '../theme/colors.dart';
import '../theme/easings.dart';
import '../theme/metrics.dart';
import '../theme/shadows.dart';
import '../theme/springs.dart';
import 'action_dock.dart';
import 'measure_size.dart';
import 'note_content.dart';
import 'shimmer.dart';

/// Where the fold point currently comes from.
enum _Phase {
  /// Sitting at the rest inset, or following the finger.
  idle,

  /// Springing back to the rest inset after a release over nothing.
  snapping,

  /// Travelling to a dock button after a release over one.
  leaving,
}

/// One note in the list. Long press its top-right corner and the paper folds
/// under the finger; release it over a dock button to file it away.
class StickyNote extends StatefulWidget {
  const StickyNote({
    super.key,
    required this.note,
    required this.width,
    required this.isActive,
    required this.isDimmed,
    required this.onFocus,
    required this.onBlur,
    required this.onRemove,
    required this.onHeight,
  });

  final Note note;
  final double width;
  final bool isActive;
  final bool isDimmed;
  final ValueChanged<String> onFocus;
  final VoidCallback onBlur;
  final void Function(String id, NoteAction action) onRemove;
  final void Function(String id, double height) onHeight;

  @override
  State<StickyNote> createState() => _StickyNoteState();
}

class _StickyNoteState extends State<StickyNote> with TickerProviderStateMixin {
  late final AnimationController _lift;
  late final AnimationController _snap;
  late final AnimationController _travel;
  late final AnimationController _removal;
  late final AnimationController _shimmer;
  late final AnimationController _dockEnter;
  late final AnimationController _dockExit;
  late final SpringCurve _snapCurve;

  /// The removal shrink starts 80 ms after the travel does, so both run off one
  /// controller with the delay folded into the interval.
  static final _shrinkTotal = kRemovalShrinkDelay + kRemovalShrinkDuration;
  static final _shrinkInterval = Interval(
    kRemovalShrinkDelay.inMicroseconds / _shrinkTotal.inMicroseconds,
    1,
    curve: easeInOutQuad,
  );

  _Phase _phase = _Phase.idle;
  double _dragX = 0;
  double _dragY = kFoldRestInset;
  double _fromX = 0;
  double _fromY = 0;
  double _toX = 0;
  double _toY = 0;
  double _removalShiftX = 0;
  double _noteHeight = kInitialNoteHeight;
  int _hovered = -1;
  int _triggered = -1;
  bool _dockMounted = false;

  double get _restX => widget.width - kFoldRestInset;

  @override
  void initState() {
    super.initState();
    _dragX = _restX;
    _lift = AnimationController(
      vsync: this,
      duration: kLiftDuration,
      reverseDuration: kSettleDuration,
    );
    final snapDuration = springDuration(
      AppSprings.snapBack,
      clampOvershoot: true,
    );
    _snap = AnimationController(vsync: this, duration: snapDuration);
    _snapCurve = SpringCurve(
      AppSprings.snapBack,
      duration: snapDuration,
      clampOvershoot: true,
    );
    _snap.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _phase = _Phase.idle;
          _dragX = _restX;
          _dragY = kFoldRestInset;
        });
      }
    });
    _travel = AnimationController(
      vsync: this,
      duration: kRemovalTravelDuration,
    );
    _removal = AnimationController(vsync: this, duration: _shrinkTotal);
    _removal.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onRemove(widget.note.id, kNoteActions[_triggered].action);
      }
    });
    _shimmer = AnimationController(vsync: this, duration: kNoteShimmerDuration);
    _dockEnter = AnimationController(
      vsync: this,
      duration: kDockEnterDuration + kDockEnterStagger * 2,
    );
    _dockExit = AnimationController(vsync: this, duration: kDockExitDuration);
    _dockExit.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _dockMounted = false);
      }
    });
  }

  @override
  void didUpdateWidget(StickyNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _dockExit.value = 0;
      _dockEnter.forward(from: 0);
      setState(() => _dockMounted = true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _dockExit.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _lift.dispose();
    _snap.dispose();
    _travel.dispose();
    _removal.dispose();
    _shimmer.dispose();
    _dockEnter.dispose();
    _dockExit.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _snap.stop();
    setState(() {
      _phase = _Phase.idle;
      _dragX = _restX;
      _dragY = kFoldRestInset;
      _hovered = -1;
    });
    _lift.animateTo(1, duration: kLiftDuration);
    HapticFeedback.mediumImpact();
    widget.onFocus(widget.note.id);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final dragX = _restX + details.offsetFromOrigin.dx;
    final dragY = kFoldRestInset + details.offsetFromOrigin.dy;
    final dockCenterY = dockRowCenterY(_noteHeight);
    var hovered = -1;
    for (var i = 0; i < kNoteActions.length; i++) {
      final dx =
          dragX - dockButtonCenterX(i, widget.width, kNoteActions.length);
      final dy = dragY - dockCenterY;
      if (math.sqrt(dx * dx + dy * dy) < kDockHoverRadius) {
        hovered = i;
      }
    }
    final changed = hovered != _hovered;
    setState(() {
      _dragX = dragX;
      _dragY = dragY;
      _hovered = hovered;
    });
    if (changed && hovered >= 0) {
      HapticFeedback.lightImpact();
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_hovered < 0) {
      _settleBack();
      return;
    }
    final index = _hovered;
    final targetX = dockButtonCenterX(index, widget.width, kNoteActions.length);
    setState(() {
      _triggered = index;
      _phase = _Phase.leaving;
      _fromX = _dragX;
      _fromY = _dragY;
      _toX = targetX;
      _toY = dockRowCenterY(_noteHeight);
      _removalShiftX = targetX - widget.width / 2;
    });
    _travel.forward(from: 0);
    _removal.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  /// The gesture died without a normal release: the pointer was cancelled, or
  /// the press never lasted long enough to peel anything. Either way the note
  /// has to be put back, or it would stay lifted with nothing able to drop it.
  void _onLongPressCancel() {
    if (_triggered < 0) {
      _settleBack();
    }
  }

  void _settleBack() {
    setState(() {
      _hovered = -1;
      _phase = _Phase.snapping;
      _fromX = _dragX;
      _fromY = _dragY;
    });
    _snap.forward(from: 0);
    _lift.animateBack(0, duration: kSettleDuration);
    _shimmer.forward(from: 0);
    widget.onBlur();
  }

  double get _foldX => switch (_phase) {
    _Phase.idle => _dragX,
    _Phase.snapping => lerpDouble(
      _fromX,
      _restX,
      _snapCurve.transform(_snap.value),
    )!,
    _Phase.leaving => lerpDouble(
      _fromX,
      _toX,
      easeInOutQuad.transform(_travel.value),
    )!,
  };

  double get _foldY => switch (_phase) {
    _Phase.idle => _dragY,
    _Phase.snapping => lerpDouble(
      _fromY,
      kFoldRestInset,
      _snapCurve.transform(_snap.value),
    )!,
    _Phase.leaving => lerpDouble(
      _fromY,
      _toY,
      easeInOutQuad.transform(_travel.value),
    )!,
  };

  @override
  Widget build(BuildContext context) {
    final flapColor = shade(widget.note.color, kNoteFlapShade);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: widget.isDimmed ? kDimmedNoteOpacity : 1.0),
      duration: kDimDuration,
      curve: easeInOutQuad,
      builder: (context, dim, child) => Opacity(opacity: dim, child: child),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _lift,
          _snap,
          _travel,
          _removal,
          _shimmer,
        ]),
        builder: (context, _) {
          final lift = easeInOutQuad.transform(_lift.value);
          final removal = _shrinkInterval.transform(_removal.value);
          final scale =
              (1 + kLiftScaleDelta * lift) * (1 - kRemovalShrink * removal);
          return Stack(
            clipBehavior: Clip.none,
            fit: StackFit.passthrough,
            children: [
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(
                    removal * _removalShiftX,
                    removal * (_noteHeight / 2 + kDockGap),
                    0,
                    1,
                  )
                  ..scaleByDouble(scale, scale, 1, 1),
                child: Opacity(
                  opacity: (1 - removal).clamp(0, 1),
                  child: Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.passthrough,
                    children: [
                      _body(lift),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: FoldPainter(
                              dragX: _foldX,
                              dragY: _foldY,
                              background: AppColors.ink,
                              flapColor: flapColor,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        width: kFoldHandleSize,
                        height: kFoldHandleSize,
                        child: _handle(),
                      ),
                    ],
                  ),
                ),
              ),
              if (_dockMounted)
                Positioned(
                  top: _noteHeight + kDockGap,
                  left: 0,
                  right: 0,
                  child: ActionDock(
                    hovered: _hovered,
                    triggered: _triggered,
                    enter: _dockEnter,
                    exit: _dockExit,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(double lift) {
    return MeasureSize(
      onChange: (size) {
        if (size.height == _noteHeight) {
          return;
        }
        setState(() => _noteHeight = size.height);
        widget.onHeight(widget.note.id, size.height);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.note.color,
          borderRadius: BorderRadius.circular(kNoteRadius),
          boxShadow: AppShadows.liftedNote(kLiftShadowOpacity * lift),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kNoteRadius),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(kNotePadding),
                child: NoteContent(note: widget.note),
              ),
              Shimmer(
                progress: easeInOutQuad.transform(_shimmer.value),
                width: widget.width,
                height: kNoteShimmerHeight,
                band: kNoteShimmerBand,
                opacity: kNoteShimmerOpacity,
                skew: kNoteShimmerSkew,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle() {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
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
