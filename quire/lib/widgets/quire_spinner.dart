import 'package:flutter/widgets.dart';

import '../painting/spinner_painter.dart';
import '../theme/colors.dart';

/// What the spinner tells a reader who cannot see it.
const String kSpinnerLabel = 'Opening';

/// The one indeterminate indicator in quire.
///
/// Everywhere else a wait is drawn as the thing being waited for: a page block
/// is laid out from the page tree and shimmers at its real size, so nothing
/// moves when the words land. That works because the shape is already known.
/// A file that has not been opened yet has no shape to draw, and this is what
/// stands in for it.
///
/// The loop runs off an [AnimationController] rather than a free ticker, so a
/// test can hold it at 550 ms and photograph what a reader would see there.
class QuireSpinner extends StatefulWidget {
  const QuireSpinner({
    super.key,
    this.size = kSpinnerSize,
    this.color = AppColors.accentBright,
  });

  /// The box the loop is drawn in. The wave is measured from it, so a larger
  /// spinner is a larger loop and never a clipped one.
  final double size;

  final Color color;

  @override
  State<QuireSpinner> createState() => _QuireSpinnerState();
}

class _QuireSpinnerState extends State<QuireSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: kSpinnerPeriod,
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: kSpinnerLabel,
      liveRegion: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _turn,
            builder: (context, _) => CustomPaint(
              painter: SpinnerPainter(turns: _turn.value, color: widget.color),
            ),
          ),
        ),
      ),
    );
  }
}

/// The whole screen while a document is being opened: the ground, and the loop
/// in the middle of it.
///
/// Nothing else. A file being opened has no title yet worth printing and no
/// page count worth guessing at, and a skeleton of a document quire has not
/// read would be an invention rather than a wait.
class QuireLoading extends StatelessWidget {
  const QuireLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: ColoredBox(
        color: AppColors.ground,
        child: Center(child: QuireSpinner()),
      ),
    );
  }
}
