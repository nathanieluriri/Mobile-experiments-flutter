import 'package:flutter/widgets.dart';

import '../../helpers/fold_geometry.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/paper_sheet.dart';
import '../../widgets/press_fade.dart';

/// The mark: a sheet with its corner turned, at the one size it is ever drawn.
const kEmptyMarkWidth = 64.0;
const kEmptyMarkHeight = 82.0;
const kEmptyMarkTop = 340.0;
const kEmptyMarkFoldInset = 18.0;

/// Where the two lines and the pill sit.
const kEmptyHeadlineTop = 436.0;
const kEmptyBodyTop = 474.0;
const kEmptyBodyWidth = 280.0;
const kEmptyPillTop = 528.0;
const kEmptyPillWidth = 148.0;
const kEmptyPillHeight = 44.0;

/// What the desk says when there is nothing on it.
///
/// No watermark and no illustration: the mark is the app's own folded sheet at
/// the size a real card's type mark is, and the rest of the screen stays warm
/// ground, because an empty desk is empty.
class DeskEmpty extends StatelessWidget {
  const DeskEmpty({super.key, required this.onOpen});

  /// What the pill does. Null leaves the pill drawn but inert, which is what
  /// a desk with no documents left to offer actually is.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: kEmptyMarkTop,
          child: const Center(
            child: PaperSheet(
              width: kEmptyMarkWidth,
              height: kEmptyMarkHeight,
              shadows: <BoxShadow>[],
              border: Border.fromBorderSide(
                BorderSide(color: AppColors.rule, width: 1),
              ),
              foldInset: kEmptyMarkFoldInset,
              foldCorner: Corner.bottomRight,
              foldBackground: AppColors.deskGround,
              foldColor: AppColors.leafFlap,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: kEmptyHeadlineTop,
          child: Text(
            'Nothing on the desk',
            textAlign: TextAlign.center,
            style: AppText.display.copyWith(color: AppColors.ink),
          ),
        ),
        Positioned(
          left: (kScreenWidth - kEmptyBodyWidth) / 2,
          top: kEmptyBodyTop,
          width: kEmptyBodyWidth,
          child: Text(
            'Documents you open live here. Every one keeps its place.',
            textAlign: TextAlign.center,
            style: AppText.bodyTight.copyWith(color: AppColors.inkSoft),
          ),
        ),
        Positioned(
          left: (kScreenWidth - kEmptyPillWidth) / 2,
          top: kEmptyPillTop,
          width: kEmptyPillWidth,
          height: kEmptyPillHeight,
          child: PaperPress(
            onTap: onOpen,
            shadow: false,
            semanticLabel: 'Open a document',
            borderRadius: BorderRadius.circular(kPillRadius),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(kPillRadius),
              ),
              child: Text(
                'Open a document',
                style: AppText.label.copyWith(color: AppColors.leaf),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
