import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../painting/glyphs.dart';
import '../../theme/colors.dart';
import '../../theme/springs.dart';
import '../../widgets/glyph_icon.dart';

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
      spacing: 52,
      children: [
        _ControlButton(glyph: Glyph.backwardFill, size: 26, onPressed: () => onSkip(-1)),
        _ControlButton(
          glyph: playing ? Glyph.pauseFill : Glyph.playFill,
          size: 38,
          onPressed: onTogglePlay,
        ),
        _ControlButton(glyph: Glyph.forwardFill, size: 26, onPressed: () => onSkip(1)),
      ],
    );
  }
}

/// A control that springs inward while it is held.
class _ControlButton extends StatefulWidget {
  const _ControlButton({required this.glyph, required this.size, required this.onPressed});

  final Glyph glyph;
  final double size;
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
    return GestureDetector(
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
          width: 44,
          height: 44,
          child: Center(
            child: GlyphIcon(glyph: widget.glyph, size: widget.size, color: AppColors.label),
          ),
        ),
      ),
    );
  }
}
