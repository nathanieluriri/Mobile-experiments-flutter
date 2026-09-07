import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import '../../state/player_scope.dart';
import '../../theme/colors.dart';
import '../../widgets/story_artwork.dart';
import 'expanded_player_view.dart';
import 'mini_player_row.dart';
import 'sheet_transition.dart';

/// How far past the pill the handle still answers a tap.
const _handleHitSlop = 14.0;

/// The mini player and the full player: one sheet, one progress value.
class PlayerSheet extends StatefulWidget {
  const PlayerSheet({super.key});

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  double _travelled = 0;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final media = MediaQuery.of(context);
    return AnimatedBuilder(
      animation: player.sheetProgress,
      builder: (context, _) {
        final sheet = SheetTransition(
          progress: player.sheetProgress.value,
          window: media.size,
          insets: media.padding,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            _Backdrop(sheet: sheet),
            Positioned(
              left: 0,
              right: 0,
              bottom: sheet.bottom,
              height: sheet.height,
              child: GestureDetector(
                // Measured from where the finger went down, so the distance
                // that woke the drag counts toward it.
                dragStartBehavior: DragStartBehavior.down,
                onVerticalDragStart: (_) {
                  _travelled = 0;
                  player.onDragStart();
                },
                onVerticalDragUpdate: (details) {
                  _travelled += details.delta.dy;
                  player.onDragUpdate(_travelled, sheet.dragRange);
                },
                onVerticalDragEnd: (details) =>
                    player.onDragEnd(details.velocity.pixelsPerSecond.dy),
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(sheet.topRadius),
                  ),
                  child: Container(
                    color: AppColors.white,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: Opacity(
                            opacity: sheet.miniOpacity,
                            child: IgnorePointer(
                              ignoring: !sheet.miniTakesTaps,
                              child: const MiniPlayerRow(),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Opacity(
                            opacity: sheet.expandedOpacity,
                            child: Transform.translate(
                              offset: Offset(0, sheet.expandedTranslateY),
                              child: IgnorePointer(
                                ignoring: !sheet.expandedTakesTaps,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                  ),
                                  child: ExpandedPlayerView(
                                    artworkSpacerHeight:
                                        sheet.artworkSpacerHeight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: sheet.artworkTop,
                          left: sheet.artworkLeft,
                          width: sheet.artworkSize,
                          height: sheet.artworkSize,
                          child: IgnorePointer(
                            child: StoryArtwork(
                              asset: player.track.artwork,
                              size: sheet.artworkSize,
                              borderRadius: sheet.artworkRadius,
                              placeholder: player.track.tint,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: sheet.handleTop - _handleHitSlop,
                          child: Center(
                            child: GestureDetector(
                              onTap: player.toggleSheet,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.all(_handleHitSlop),
                                width: 40 + _handleHitSlop * 2,
                                height: 5 + _handleHitSlop * 2,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.handle,
                                    borderRadius: BorderRadius.circular(2.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Blurs and washes out whatever is behind the sheet.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.sheet});

  final SheetTransition sheet;

  @override
  Widget build(BuildContext context) {
    if (sheet.progress <= 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: sheet.blurSigma,
            sigmaY: sheet.blurSigma,
          ),
          child: ColoredBox(
            color: AppColors.white.withValues(alpha: sheet.tintOpacity),
            child: ColoredBox(
              color: AppColors.canvas.withValues(alpha: sheet.scrimOpacity),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
