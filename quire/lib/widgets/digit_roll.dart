import 'package:flutter/widgets.dart';

import '../theme/easings.dart';
import '../theme/metrics.dart';

/// How far a glyph travels as it rolls out, and where the new one comes from.
const kDigitRollTravel = 10.0;

/// A number that changes on screen without the whole thing flickering.
///
/// Only the characters that actually changed move: the old glyph translates up
/// [kDigitRollTravel] and fades out while the new one arrives from below, with
/// each position starting [kDigitStagger] after the one to its left. Tabular
/// figures are what make it possible, because the box never resizes mid roll.
class DigitRoll extends StatelessWidget {
  const DigitRoll(
    this.value, {
    super.key,
    required this.style,
    required this.color,
  });

  /// What the number reads now. Anything a number can carry works: `4 / 6`,
  /// `38%`, `1,410`.
  final String value;

  /// Must be a tabular style, or the box will resize under the roll.
  final TextStyle style;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final painted = style.copyWith(color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < value.length; i++)
          _RollingGlyph(
            key: ValueKey(i),
            glyph: value[i],
            index: i,
            style: painted,
          ),
      ],
    );
  }
}

/// One character position, which knows what it used to say.
class _RollingGlyph extends StatefulWidget {
  const _RollingGlyph({
    super.key,
    required this.glyph,
    required this.index,
    required this.style,
  });

  final String glyph;
  final int index;
  final TextStyle style;

  @override
  State<_RollingGlyph> createState() => _RollingGlyphState();
}

class _RollingGlyphState extends State<_RollingGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _roll = AnimationController(
    vsync: this,
    duration: kDigitStagger * widget.index + kDigitRoll,
    value: 1,
  );
  late String _outgoing = widget.glyph;

  /// The window this position rolls in, inside its own staggered controller.
  Interval get _window {
    final total = _roll.duration!.inMicroseconds;
    final start = (kDigitStagger * widget.index).inMicroseconds / total;
    return Interval(start, 1, curve: easeOutQuad);
  }

  @override
  void didUpdateWidget(_RollingGlyph old) {
    super.didUpdateWidget(old);
    if (old.glyph != widget.glyph) {
      _outgoing = old.glyph;
      _roll.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = _advance(widget.glyph, widget.style);
    final height = _lineHeight(widget.style);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _roll,
          builder: (context, _) {
            final t = _window.transform(_roll.value);
            if (t >= 1) {
              return Center(child: Text(widget.glyph, style: widget.style));
            }
            return Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 1 - t,
                  child: Transform.translate(
                    offset: Offset(0, -kDigitRollTravel * t),
                    child: Text(_outgoing, style: widget.style),
                  ),
                ),
                Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, kDigitRollTravel * (1 - t)),
                    child: Text(widget.glyph, style: widget.style),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

final _advances = <(String, TextStyle), double>{};

/// How wide one glyph sets in [style]. Measured once per pair, because a roll
/// that measured every frame would be the slowest thing on the screen.
double _advance(String glyph, TextStyle style) {
  return _advances.putIfAbsent((glyph, style), () {
    final painter = TextPainter(
      text: TextSpan(text: glyph, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  });
}

/// The line box [style] sets in, so every position is the same height.
double _lineHeight(TextStyle style) {
  final size = style.fontSize ?? 14;
  return size * (style.height ?? 1);
}
