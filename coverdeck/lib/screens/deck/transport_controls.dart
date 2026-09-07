import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../painting/glyphs.dart';
import '../../theme/colors.dart';
import '../../theme/springs.dart';
import '../../widgets/glyph_icon.dart';

/// Touch slop around every control.
///
/// Flutter answers touches inside the layout box and nowhere else, so the slop
/// lives in the box: each control lays out 14 points larger on every side and
/// the gaps around the row give those points back.
const controlHitSlop = 14.0;

/// Side of the visible button inside that box.
const _controlSize = 44.0;

/// Distance between the edges of two controls' touch targets.
const _controlGap = 52.0 - controlHitSlop * 2;

/// Skip back, play or pause, skip forward.
class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
    required this.playing,
    required this.onTogglePlay,
    required this.onSkip,
  });

  final bool playing;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: _controlGap,
      children: [
        _ControlButton(
          glyph: Glyph.backwardFill,
          size: 26,
          label: 'Previous track',
          onPressed: () => onSkip(-1),
        ),
        _ControlButton(
          glyph: playing ? Glyph.pauseFill : Glyph.playFill,
          size: 38,
          label: playing ? 'Pause' : 'Play',
          onPressed: onTogglePlay,
        ),
        _ControlButton(
          glyph: Glyph.forwardFill,
          size: 26,
          label: 'Next track',
          onPressed: () => onSkip(1),
        ),
      ],
    );
  }
}

/// A control that springs inward while it is held.
class _ControlButton extends StatefulWidget {
  const _ControlButton({
    required this.glyph,
    required this.size,
    required this.label,
    required this.onPressed,
  });

  final Glyph glyph;
  final double size;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);

  void _springTo(double target) {
    _scale.animateWith(SpringSimulation(pressSpring, _scale.value, target, _scale.velocity));
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _springTo(0.85),
        onTapUp: (_) => _springTo(1),
        onTapCancel: () => _springTo(1),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onPressed();
        },
        child: AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
          child: SizedBox(
            width: _controlSize + controlHitSlop * 2,
            height: _controlSize + controlHitSlop * 2,
            child: Center(
              child: GlyphIcon(glyph: widget.glyph, size: widget.size, color: AppColors.label),
            ),
          ),
        ),
      ),
    );
  }
}
