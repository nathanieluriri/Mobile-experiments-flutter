import 'package:flutter/widgets.dart';

import '../theme/colors.dart';
import '../theme/easings.dart';
import '../theme/edges.dart';
import '../theme/metrics.dart';
import '../theme/springs.dart';
import '../theme/typography.dart';

/// One target in the dock under a lifted sheet.
class DockAction {
  const DockAction({
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  final IconData icon;

  /// Written uppercase in the source, never produced by a transform, so a
  /// golden reads what the source says.
  final String label;

  /// A refused action still shows, at [kDockDisabledOpacity]. Hiding it would
  /// leave a hole where a target used to be.
  final bool enabled;
}

/// How visible a target that will refuse the drop is.
const kDockDisabledOpacity = 0.3;

/// The row of targets that appears under a lifted sheet.
///
/// Nothing here colours in on hover: the colour law reserves every hue in the
/// app, so a target that is under the finger says so by growing, and by
/// raising its label.
class ActionDock extends StatelessWidget {
  const ActionDock({
    super.key,
    required this.actions,
    required this.hovered,
    required this.triggered,
    required this.enter,
    required this.exit,
  });

  final List<DockAction> actions;

  /// Index of the action the drag point is over, or -1.
  final int hovered;

  /// Index of the action the sheet was dropped on, or -1.
  final int triggered;

  /// 0 to 1 across the staggered entrance of the whole row.
  final Animation<double> enter;

  /// 0 to 1 as the row leaves again.
  final Animation<double> exit;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < actions.length; i++)
            DockButton(
              action: actions[i],
              index: i,
              count: actions.length,
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

/// One dock target: a leaf circle that grows while the drag point is over it,
/// with its label rising underneath.
class DockButton extends StatefulWidget {
  const DockButton({
    super.key,
    required this.action,
    required this.index,
    required this.count,
    required this.hovered,
    required this.triggered,
    required this.enter,
    required this.exit,
  });

  final DockAction action;
  final int index;
  final int count;
  final int hovered;
  final int triggered;
  final Animation<double> enter;
  final Animation<double> exit;

  @override
  State<DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<DockButton> with TickerProviderStateMixin {
  late final AnimationController _hover;
  late final AnimationController _scale;
  late final SpringCurve _scaleCurve;

  double _scaleFrom = 1;
  double _scaleTo = 1;

  bool get _highlighted =>
      widget.hovered == widget.index || widget.triggered == widget.index;

  @override
  void initState() {
    super.initState();
    // A button can be the hovered one on its very first build, when a drag
    // crosses onto a dock that is only now mounting. Seeding both the label
    // and the scale is what stops that button from sitting flat until some
    // later rebuild happens to notice it.
    _hover = AnimationController(
      vsync: this,
      duration: kDockHover,
      value: _highlighted ? 1 : 0,
    );
    _scaleTo = _highlighted ? kDockHoverScale : 1.0;
    _scaleFrom = _scaleTo;
    final duration = springDuration(AppSprings.dockScale, clampOvershoot: true);
    _scale = AnimationController(vsync: this, duration: duration, value: 1);
    _scaleCurve = SpringCurve(
      AppSprings.dockScale,
      duration: duration,
      clampOvershoot: true,
    );
  }

  @override
  void didUpdateWidget(DockButton old) {
    super.didUpdateWidget(old);
    final was = old.hovered == old.index || old.triggered == old.index;
    if (_highlighted != was) {
      _hover.animateTo(
        _highlighted ? 1 : 0,
        duration: kDockHover,
        curve: easeOutQuad,
      );
    }
    _retarget();
  }

  void _retarget() {
    final target = _highlighted ? kDockHoverScale : 1.0;
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
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = kDockEnter + kDockEnterStagger * (widget.count - 1);
    final start = kDockEnterStagger * widget.index;
    final window = Interval(
      start.inMicroseconds / total.inMicroseconds,
      (start + kDockEnter).inMicroseconds / total.inMicroseconds,
      curve: easeOutCubic,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_hover, _scale, widget.enter, widget.exit]),
      builder: (context, _) {
        final hover = _hover.value;
        final entered = window.transform(widget.enter.value);
        final left = easeOutQuad.transform(widget.exit.value);
        final presence = widget.action.enabled ? 1.0 : kDockDisabledOpacity;
        final opacity = presence * entered * (1 - left);
        return Opacity(
          opacity: opacity.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, kDockEnterRise * (1 - entered)),
            child: SizedBox(
              width: kDockButtonSpacing,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: _currentScale,
                    child: _circle(context),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: kSpace8),
                    child: Opacity(
                      opacity: hover.clamp(0, 1),
                      child: Transform.translate(
                        offset: Offset(0, kSpace8 * (1 - hover)),
                        child: Text(
                          widget.action.label,
                          style: AppText.chipLabel
                              .copyWith(color: AppColors.ink),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _circle(BuildContext context) {
    return Container(
      width: kDockButtonSize,
      height: kDockButtonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: AppEdges.all(context),
      ),
      child: Center(
        child: Icon(
          widget.action.icon,
          size: 20,
          color: AppColors.ink,
        ),
      ),
    );
  }
}
