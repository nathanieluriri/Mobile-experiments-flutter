import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The brand mark, at the one size it is ever drawn in the app.
const kEmptyMarkSize = 96.0;

/// Between the mark and the name under it.
const kEmptyNameGap = 12.0;

/// How far down its own box the block starts, and the gaps inside it.
///
/// It is measured from the top of the body rather than from the top of the
/// screen, because the shell drops the tabs and the sort row when there is no
/// library for them to be about, and a block pinned to the screen would move
/// whenever that chrome did.
const kEmptyBlockTop = 222.0;
const kEmptyHeadlineGap = 14.0;
const kEmptyBodyGap = 7.0;
const kEmptyBodyWidth = 280.0;
const kEmptyPillGap = 16.0;
const kEmptyPillWidth = 148.0;
const kEmptyPillHeight = 44.0;

/// What the desk says when there is nothing on it.
///
/// No watermark and no illustration: the mark is the app's own folded sheet at
/// the size a real document's type mark is, and the rest of the screen stays
/// ground, because an empty desk is empty.
class DeskEmpty extends StatelessWidget {
  const DeskEmpty({super.key, required this.onOpen});

  /// What the pill does. Null leaves the pill drawn but inert, which is what
  /// a desk with no documents left to offer actually is.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: kEmptyBlockTop),
        // The one place in the app the mark is drawn. A desk with documents on
        // it does not need to say which app it is: the documents do that. A
        // desk with nothing on it has the room, and the reason.
        Image.asset(
          'assets/brand/quire-mark.png',
          width: kEmptyMarkSize,
          height: kEmptyMarkSize,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(height: kEmptyNameGap),
        Text('Quire', style: AppText.markName.copyWith(color: AppColors.ink)),
        const SizedBox(height: kEmptyHeadlineGap),
        Text(
          'Nothing on the desk',
          textAlign: TextAlign.center,
          style: AppText.display.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: kEmptyBodyGap),
        SizedBox(
          width: kEmptyBodyWidth,
          child: Text(
            'Documents you open live here. Every one keeps its place.',
            textAlign: TextAlign.center,
            style: AppText.bodyTight.copyWith(color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: kEmptyPillGap),
        PaperPress(
          onTap: onOpen,
          semanticLabel: 'Open a document',
          child: Container(
            width: kEmptyPillWidth,
            height: kEmptyPillHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(kPillRadius),
            ),
            child: Text(
              'Open a document',
              style: AppText.label.copyWith(color: AppColors.onAccent),
            ),
          ),
        ),
      ],
    );
  }
}
