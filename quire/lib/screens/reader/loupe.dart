import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';

/// The glass itself.
const kLoupeSize = Size(148, 100);
const kLoupeCorner = 14.0;
const kLoupeScale = 2.1;

/// How far above the finger the glass sits.
///
/// Enough that the hand holding the phone is not standing on the thing it is
/// being used to read, which is the whole point of a loupe on a touch screen.
const kLoupeLift = 92.0;

/// A loupe that follows the finger over the page.
///
/// For a table, a footnote, or a figure caption set at six points: the sort of
/// thing you need to read once and do not want to rearrange the whole page
/// for. It magnifies what is painted under it rather than laying anything out
/// again, so it costs nothing until it is used and changes nothing when it is.
///
/// It is a rectangle rather than the traditional circle, because what is under
/// it is a line of type, and a circle throws away the ends of the line to show
/// more of the white space above and below it.
class Loupe extends StatelessWidget {
  const Loupe({super.key, required this.at});

  /// Where the finger is, or null when it is not down.
  final Offset? at;

  @override
  Widget build(BuildContext context) {
    final at = this.at;
    if (at == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    // The glass stays on the screen even when the finger is at the edge of it,
    // because a loupe half off the screen is a loupe showing half a word.
    final left = (at.dx - kLoupeSize.width / 2).clamp(
      0.0,
      size.width - kLoupeSize.width,
    );
    final top = (at.dy - kLoupeLift - kLoupeSize.height / 2).clamp(
      0.0,
      size.height - kLoupeSize.height,
    );
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: RawMagnifier(
          size: kLoupeSize,
          magnificationScale: kLoupeScale,
          // The glass is above the finger, so what it must show is what is
          // under the finger: the focal point is the difference between the
          // two, which is what stops the loupe magnifying itself.
          focalPointOffset: Offset(
            at.dx - (left + kLoupeSize.width / 2),
            at.dy - (top + kLoupeSize.height / 2),
          ),
          decoration: const MagnifierDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(kLoupeCorner)),
              side: BorderSide(color: AppColors.hairline, width: 1),
            ),
          ),
        ),
      ),
    );
  }
}
