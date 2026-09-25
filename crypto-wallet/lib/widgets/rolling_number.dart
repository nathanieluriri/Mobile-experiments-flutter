import 'package:flutter/material.dart';

import '../theme/theme.dart';

enum RollingKeyMode { typed, value }

class RollingCell {
  const RollingCell(this.key, this.char);
  final String key;
  final String char;
}

/// Assigns stable identities to the characters of [value] so digits keep
/// their column while the number changes.
List<RollingCell> buildRollingCells(String value, RollingKeyMode keyMode) {
  final chars = value.split('');
  if (keyMode == RollingKeyMode.value) {
    return [
      for (var i = 0; i < chars.length; i++)
        RollingCell('p${chars.length - 1 - i}', chars[i]),
    ];
  }
  var ordinal = 0;
  final cells = <RollingCell>[];
  for (final char in chars) {
    if (char == ',') {
      cells.add(RollingCell('s$ordinal', char));
    } else {
      cells.add(RollingCell('t$ordinal', char));
      ordinal += 1;
    }
  }
  return cells;
}

/// A number whose digits roll like an odometer when they change.
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    super.key,
    required this.value,
    required this.fontSize,
    required this.color,
    this.fontWeight = FontWeight.w700,
    this.keyMode = RollingKeyMode.typed,
  });

  final String value;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;
  final RollingKeyMode keyMode;

  @override
  Widget build(BuildContext context) {
    final height = (fontSize * 1.2).round().toDouble();
    final style = text(
      fontSize,
      weight: fontWeight,
      color: color,
      lineHeight: height,
      tabular: true,
    ).copyWith(leadingDistribution: TextLeadingDistribution.even);
    final cells = buildRollingCells(value, keyMode);
    return SizedBox(
      height: height,
      child: ClipRect(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final cell in cells)
              _RollIn(
                key: ValueKey(cell.key),
                height: height,
                child: RegExp(r'\d').hasMatch(cell.char)
                    ? RollingDigit(
                        digit: int.parse(cell.char),
                        height: height,
                        style: style,
                      )
                    : Text(cell.char, style: style),
              ),
          ],
        ),
      ),
    );
  }
}

/// Slides a new cell up from below when it first appears.
class _RollIn extends StatefulWidget {
  const _RollIn({super.key, required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  State<_RollIn> createState() => _RollInState();
}

class _RollInState extends State<_RollIn> with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
    value: 1,
  )..animateWith(springTo(Springs.roll, 1, 0));

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      child: widget.child,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _offset.value * widget.height),
          child: child,
        );
      },
    );
  }
}

/// A single digit column that springs to the current digit.
class RollingDigit extends StatefulWidget {
  const RollingDigit({
    super.key,
    required this.digit,
    required this.height,
    required this.style,
  });

  final int digit;
  final double height;
  final TextStyle style;

  @override
  State<RollingDigit> createState() => _RollingDigitState();
}

class _RollingDigitState extends State<RollingDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.digit.toDouble(),
  );

  @override
  void didUpdateWidget(RollingDigit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.digit != widget.digit) {
      _position.animateWith(
        springTo(Springs.roll, _position.value, widget.digit.toDouble()),
      );
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _position,
        builder: (context, _) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Opacity(opacity: 0, child: Text('0', style: widget.style)),
              Positioned(
                left: 0,
                top: -_position.value * widget.height,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var d = 0; d < 10; d++)
                      Text('$d', style: widget.style),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
