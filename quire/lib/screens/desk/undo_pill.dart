import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/feedback.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The pill, and how far above the safe area its bottom edge sits.
const kUndoPillWidth = 220.0;
const kUndoPillHeight = 40.0;
const kUndoPillBottom = 22.0;
const kUndoPillPaddingX = 16.0;

/// A pill with nothing to press is wider, because the words are all it has.
const kNoticePillWidth = 300.0;

/// How thick the draining line is, and how far the pill rises to arrive.
const kUndoDrainHeight = 2.0;
const kUndoPillRise = 20.0;

/// The one chance to take a removal back, and the one place the desk says a
/// thing in words when it has to.
///
/// Its life is drawn rather than counted down in words: a 2pt line along the
/// bottom edge drains over exactly [kUndoPill], on an `AnimationController`
/// and never a `Timer`, so a golden at any moment is the same picture.
///
/// With [message] set it is a notice instead: the same pill, the same drain,
/// no button, wider, because a desk that has to say why something did not
/// happen should say it in the one voice it already has rather than in a
/// dialog borrowed from somewhere else.
class UndoPill extends StatelessWidget {
  const UndoPill({
    super.key,
    required this.title,
    required this.drained,
    required this.rise,
    required this.onUndo,
    this.message,
    this.actionLabel = 'UNDO',
  });

  /// The document that left, named so you know what you are taking back.
  final String title;

  /// 0 the moment the pill arrives, 1 the moment it has run out.
  final double drained;

  /// 0 to 1 as the pill comes up off the desk.
  final double rise;

  /// What UNDO does, or null for a pill with nothing to undo.
  final VoidCallback? onUndo;

  /// Words instead of a removal, when the pill is a notice.
  final String? message;

  /// What the button says, when there is one.
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final undo = onUndo;
    // A notice is wider whether or not it has a button: its words are a
    // sentence, where a removal's are a name.
    final width = message == null ? kUndoPillWidth : kNoticePillWidth;
    return Opacity(
      opacity: rise.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(0, kUndoPillRise * (1 - rise)),
        child: SizedBox(
          width: width,
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
                  // Filled rather than left to size itself, because a Stack
                  // gives a loose child its own height and then hangs it off
                  // the top: the row has to be told it owns the pill before
                  // centring inside it means anything. The drain is held out
                  // of that height so the words sit in the middle of the face
                  // above the line rather than in the middle of the pill.
                  Positioned.fill(
                    bottom: kUndoDrainHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(width: kUndoPillPaddingX),
                        Expanded(
                          child: Align(
                            alignment: undo == null
                                ? Alignment.center
                                : Alignment.centerLeft,
                            child: Text(
                              message ?? 'Removed $title',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: undo == null
                                  ? TextAlign.center
                                  : TextAlign.left,
                              style:
                                  AppText.label.copyWith(color: AppColors.ink),
                            ),
                          ),
                        ),
                        if (undo != null) ...[
                          const SizedBox(width: kSpace12),
                          // The padding is inside the press rather than
                          // around it, so the whole right end of the pill
                          // takes the tap. Wrapped round the word alone the
                          // target was the width of five letters.
                          PaperPress(
                            onTap: undo,
                            semanticLabel: actionLabel,
                            feel: Feel.commit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: kUndoPillPaddingX,
                              ),
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  actionLabel,
                                  style: AppText.label
                                      .copyWith(color: AppColors.accentBright),
                                ),
                              ),
                            ),
                          ),
                        ] else
                          const SizedBox(width: kUndoPillPaddingX),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    height: kUndoDrainHeight,
                    width: width * (1 - drained).clamp(0, 1),
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
