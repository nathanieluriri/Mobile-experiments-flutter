import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';

const _dashWidth = 4.0;
const _dashGap = 5.0;
const _dashPeriod = _dashWidth + _dashGap;
const _dashSpeed = 14.0;
const _dashTravel = 60000.0;
const _dashCount = 80;

/// The unplayed part of the progress bar: a row of dashes creeping left while
/// the track runs, frozen where they are the moment it stops.
class MarchingDashes extends StatefulWidget {
  const MarchingDashes({
    super.key,
    required this.playing,
    required this.height,
  });

  final bool playing;

  /// The thickness of the bar the dashes run along.
  final double height;

  @override
  State<MarchingDashes> createState() => _MarchingDashesState();
}

class _MarchingDashesState extends State<MarchingDashes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) {
      _march();
    }
  }

  @override
  void didUpdateWidget(MarchingDashes old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) {
      return;
    }
    if (widget.playing) {
      _march();
    } else {
      _phase.stop();
    }
  }

  void _march() {
    _phase.animateTo(
      _phase.value - _dashTravel,
      duration: Duration(
        milliseconds: (_dashTravel / _dashSpeed * 1000).round(),
      ),
      curve: Curves.linear,
    );
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: AnimatedBuilder(
            animation: _phase,
            builder: (context, child) => Transform.translate(
              offset: Offset(_phase.value.remainder(_dashPeriod), 0),
              child: child,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _dashCount; i++) ...[
                  if (i > 0) const SizedBox(width: _dashGap),
                  Container(
                    width: _dashWidth,
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: AppColors.handle,
                      borderRadius: BorderRadius.circular(_dashWidth / 2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
