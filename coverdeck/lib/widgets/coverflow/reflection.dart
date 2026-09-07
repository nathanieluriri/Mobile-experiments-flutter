import 'package:flutter/widgets.dart';

/// The cover mirrored below itself, fading out into the backdrop.
///
/// The full cover is flipped and pinned to the top of a shorter box, so the
/// visible band is the bottom of the cover, mirrored. The alpha mask fades
/// white from 0.42 at the fold, to 0.12 at 0.55, to nothing at the end.
class Reflection extends StatelessWidget {
  const Reflection({
    super.key,
    required this.asset,
    required this.size,
    required this.height,
  });

  final String asset;
  final double size;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: height,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.42),
            const Color(0xFFFFFFFF).withValues(alpha: 0.12),
            const Color(0xFFFFFFFF).withValues(alpha: 0),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(bounds),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: size,
            maxHeight: size,
            child: Transform.flip(
              flipY: true,
              child: Image.asset(
                asset,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
