import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../data/albums.dart';
import 'cover_card.dart';
import 'coverflow_constants.dart';
import 'coverflow_controller.dart';

/// Finger travel that starts a drag, tighter than the platform default so the
/// deck answers the first flick.
const _dragSlop = 6.0;

/// The deck: covers laid out in depth around whichever one has focus.
///
/// Dragging moves the deck one cover per [spacing] points of travel and
/// releasing projects the throw forward before snapping. Tapping a cover
/// beside the focused one brings it forward; tapping the focused one does
/// nothing.
class Coverflow extends StatelessWidget {
  const Coverflow({super.key, required this.albums, required this.controller});

  final List<Album> albums;
  final CoverflowController controller;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final size = coverSize(width);
    final spacing = size * 0.36;
    final centerGap = size * 0.3;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        gestureSettings: const DeviceGestureSettings(touchSlop: _dragSlop),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Every point of travel counts, including the slop that starts the
        // drag, so the deck never trails the finger.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragUpdate: (details) {
          controller.dragTo(controller.scrollX - details.delta.dx / spacing);
        },
        onHorizontalDragEnd: (details) {
          controller.fling(-details.velocity.pixelsPerSecond.dx / spacing);
        },
        onTapUp: (details) {
          final dx = details.localPosition.dx - width / 2;
          if (dx.abs() <= size / 2) return;
          final adjusted = dx - dx.sign * centerGap;
          controller.springTo(
            clampDouble(
              (controller.scrollX + adjusted / spacing).roundToDouble(),
              0,
              albums.length - 1,
            ).round(),
          );
        },
        child: SizedBox(
          height: size + size * reflectionRatio + reflectionGap,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final scrollX = controller.scrollX;
              // Flutter has no z index, so the covers are built in the order
              // the deck's own z index would stack them: farthest first, and
              // where two covers round to the same step the later album wins.
              final order = List.generate(albums.length, (i) => i)
                ..sort((a, b) {
                  final depth = coverZIndex(
                    a,
                    scrollX,
                  ).compareTo(coverZIndex(b, scrollX));
                  return depth != 0 ? depth : a.compareTo(b);
                });
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final index in order)
                    CoverCard(
                      key: ValueKey(albums[index].id),
                      album: albums[index],
                      index: index,
                      scrollX: scrollX,
                      size: size,
                      spacing: spacing,
                      centerGap: centerGap,
                      containerWidth: width,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
