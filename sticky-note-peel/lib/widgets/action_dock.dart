import 'package:flutter/widgets.dart';

import '../data/note_actions.dart';
import '../theme/colors.dart';
import '../theme/easings.dart';
import '../theme/metrics.dart';
import '../theme/shadows.dart';
import '../theme/springs.dart';
import '../theme/typography.dart';
import 'shimmer.dart';

/// The row of targets that appears under a lifted note.
class ActionDock extends StatelessWidget {
  const ActionDock({
    super.key,
    required this.hovered,
    required this.triggered,
    required this.enter,
    required this.exit,
  });

  /// Index of the action the drag point is over, or -1.
  final int hovered;

  /// Index of the action the note was dropped on, or -1.
  final int triggered;

  /// 0 to 1 across the staggered entrance of the whole row.
  final Animation<double> enter;

  /// 0 to 1 as the row fades out again.
  final Animation<double> exit;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < kNoteActions.length; i++)
            DockButton(
              index: i,
              hovered: hovered,
              triggered: triggered,
              enter: enter,
              exit: exit,
            ),
        ],
      ),
    );
  }
}

/// One dock target: a circle that colours in and grows while the drag point is
/// over it, with its label rising underneath.
class DockButton extends StatefulWidget {
  const DockButton({
    super.key,
    required this.index,
    required this.hovered,
    required this.triggered,
    required this.enter,
    required this.exit,
  });

  final int index;
  final int hovered;
  final int triggered;
  final Animation<double> enter;
  final Animation<double> exit;

  @override
  State<DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<DockButton>
    with TickerProviderStateMixin {
  late final AnimationController _hover;
  late final AnimationController _presence;
  late final AnimationController _shimmer;
  late final AnimationController _scale;
  late final SpringCurve _scaleCurve;

  double _scaleFrom = 1;
  double _scaleTo = 1;
  double _presenceTarget = 1;

  bool get _highlighted =>
      widget.hovered == widget.index || widget.triggered == widget.index;

  bool get _receded =>
      widget.triggered >= 0 && widget.triggered != widget.index;

  @override
  void initState() {
    super.initState();
    _hover = AnimationController(vsync: this, duration: kDockHoverDuration);
    _presence = AnimationController(
      vsync: this,
      duration: kDockRecedeDuration,
      value: 1,
    );
    _shimmer = AnimationController(vsync: this, duration: kDockShimmerDuration);
    final duration =
        springDuration(AppSprings.dockButtonScale, clampOvershoot: true);
    _scale = AnimationController(vsync: this, duration: duration, value: 1);
    _scaleCurve = SpringCurve(
      AppSprings.dockButtonScale,
      duration: duration,
      clampOvershoot: true,
    );
  }

  @override
  void didUpdateWidget(DockButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasHighlighted = oldWidget.hovered == oldWidget.index ||
        oldWidget.triggered == oldWidget.index;
    if (_highlighted != wasHighlighted) {
      _hover.animateTo(
        _highlighted ? 1 : 0,
        curve: easeOutQuad,
      );
      if (_highlighted) {
        _shimmer.forward(from: 0);
      }
    }
    final presenceTarget = _receded ? 0.0 : 1.0;
    if (presenceTarget != _presenceTarget) {
      _presenceTarget = presenceTarget;
      _presence.animateTo(presenceTarget, curve: easeInOutQuad);
    }
    _retarget();
  }

  void _retarget() {
    final target = (_highlighted ? kDockHoverScale : 1.0) +
        (widget.triggered == widget.index ? kDockTriggerScaleBoost : 0.0);
    if (target == _scaleTo) {
      return;
    }
    _scaleFrom = _currentScale;
    _scaleTo = target;
    _scale.forward(from: 0);
  }

  double get _currentScale {
    if (_scale.value >= 1) {
      return _scaleTo;
    }
    return _scaleFrom +
        (_scaleTo - _scaleFrom) * _scaleCurve.transform(_scale.value);
  }

  @override
  void dispose() {
    _hover.dispose();
    _presence.dispose();
    _shimmer.dispose();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = kNoteActions[widget.index];
    final total = kDockEnterDuration + kDockEnterStagger * 2;
    final start = kDockEnterStagger * widget.index;
    final interval = Interval(
      start.inMicroseconds / total.inMicroseconds,
      (start + kDockEnterDuration).inMicroseconds / total.inMicroseconds,
      curve: easeOutCubic,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([
        _hover,
        _presence,
        _shimmer,
        _scale,
        widget.enter,
        widget.exit,
      ]),
      builder: (context, _) {
        final hover = _hover.value;
        final presence = _presence.value;
        final entered = interval.transform(widget.enter.value);
        final opacity = presence * entered * (1 - widget.exit.value);
        return Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, kDockEnterRise * (1 - entered)),
            child: Transform.scale(
              scale: kDockRecedeScale + (1 - kDockRecedeScale) * presence,
              child: SizedBox(
                width: kDockButtonSpacing,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: _currentScale,
                      child: _circle(action, hover),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Opacity(
                        opacity: (hover * presence).clamp(0, 1),
                        child: Transform.translate(
                          offset: Offset(0, 5 * (1 - hover)),
                          child: Text(
                            action.label,
                            style: const TextStyle(
                              fontFamily: kFontFamily,
                              fontWeight: FontWeights.semiBold,
                              fontSize: 12,
                              height: kLineHeight,
                              color: AppColors.dockLabel,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _circle(NoteActionConfig action, double hover) {
    return Container(
      width: kDockButtonSize,
      height: kDockButtonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(AppColors.white, action.accent, hover),
        boxShadow: AppShadows.dockButton(),
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 1 - hover,
              child: Icon(action.icon, size: 20, color: AppColors.noteText),
            ),
            Opacity(
              opacity: hover,
              child: Icon(action.icon, size: 20, color: AppColors.white),
            ),
            Shimmer(
              progress: easeInOutQuad.transform(_shimmer.value),
              width: kDockButtonSize,
              height: kDockButtonSize,
              band: kDockShimmerBand,
              opacity: kDockShimmerOpacity,
              skew: kDockShimmerSkew,
            ),
          ],
        ),
      ),
    );
  }
}
