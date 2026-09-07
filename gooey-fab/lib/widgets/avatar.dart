import 'package:flutter/widgets.dart';

const _avatarDiameter = 56.0;
const _gradientBegin = Alignment(-0.8, -1);
const _gradientEnd = Alignment(0.8, 1);

/// Round chat avatar filled with the conversation's gradient.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: _avatarDiameter,
        height: _avatarDiameter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: _gradientBegin,
              end: _gradientEnd,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }
}
