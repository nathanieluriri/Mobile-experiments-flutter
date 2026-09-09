import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The pill, and how far above the safe area its bottom edge sits.
const kUndoPillWidth = 220.0;
const kUndoPillHeight = 40.0;
const kUndoPillBottom = 22.0;
const kUndoPillPaddingX = 16.0;

/// How thick the draining line is, and how far the pill rises to arrive.
const kUndoDrainHeight = 2.0;
const kUndoPillRise = 20.0;

/// The one chance to take a removal back.
///
/// Its life is drawn rather than counted down in words: a 2pt line along the
/// bottom edge drains over exactly [kUndoPill], on an `AnimationController`
/// and never a `Timer`, so a golden at any moment is the same picture.
class UndoPill extends StatelessWidget {
  const UndoPill({
    super.key,
    required this.title,
    required this.drained,
    required this.rise,
    required this.onUndo,
  });

  /// The document that left, named so you know what you are taking back.
  final String title;

  /// 0 the moment the pill arrives, 1 the moment it has run out.
  final double drained;

  /// 0 to 1 as the pill comes up off the desk.
  final double rise;

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: rise.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(0, kUndoPillRise * (1 - rise)),
        child: SizedBox(
          width: kUndoPillWidth,
          height: kUndoPillHeight,
          // The one piece of floating chrome that carries no hairline: at
          // [AppColors.surfaceHigh] it stands a full step off the ground on
          // its own, and an outline round it would only soften that.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(kPillRadius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kPillRadius),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kUndoPillPaddingX,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Removed $title',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppText.label.copyWith(color: AppColors.ink),
                          ),
                        ),
                        const SizedBox(width: kSpace12),
                        PaperPress(
                          onTap: onUndo,
                          semanticLabel: 'Undo',
                          child: Text(
                            'UNDO',
                            style: AppText.label
                                .copyWith(color: AppColors.accentBright),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    height: kUndoDrainHeight,
                    width: kUndoPillWidth * (1 - drained).clamp(0, 1),
                    child: const ColoredBox(color: AppColors.accentBright),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
