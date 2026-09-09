import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// Floating chrome is an opaque control fill with a hairline round it.
///
/// The app draws no blur and casts no shadow, so a button that let the page
/// under it show through would have nothing left saying which surface is in
/// front. An opaque fill and one rule is how a printed page marks off a panel
/// from the text it lies on.
///
/// The fill is [AppColors.surfaceHigh] and not [AppColors.surface], because
/// chrome has to stand above every surface it can land on: a reading sheet is
/// [AppColors.surface] and the back of one is [AppColors.leafBack], so a
/// button in either of those values reads as a hole punched through the page
/// rather than as a control resting on it.

/// Where the head band goes when it leaves: its top edge at y -52, which is
/// exactly its own height above the screen.
const kHeadBandHidden = -52.0;

/// What the back pill drops to when the rest of the chrome has gone, so
/// leaving is never more than one tap.
const kBackPillFaded = 0.4;

/// The size of the glyph inside a 38.5 header button.
const kChromeIcon = 20.0;

/// The head band: a back pill, the document title, and a search pill floating
/// over the top of the reader.
///
/// There is no back chevron anywhere else in the app and no other button in
/// the reading chrome. Everything else a reader can do here is a gesture,
/// which is what keeps 714 points of the screen for the document.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.title,
    this.hidden = 0,
    this.showingBack = false,
    this.onBack,
    this.onFind,
  });

  /// The document's title, as the desk prints it.
  final String title;

  /// 0 with the chrome fully in, 1 with it gone.
  final double hidden;

  /// True once the sheet has been turned over, which adds the suffix that
  /// tells a reader which side they are on.
  final bool showingBack;

  final VoidCallback? onBack;
  final VoidCallback? onFind;

  @override
  Widget build(BuildContext context) {
    final shift = (kHeadBandHidden - kHeadBandTop) * hidden;
    final fade = 1 - hidden;
    return SizedBox(
      width: kScreenWidth,
      height: kScreenHeight,
      child: Stack(
        children: [
          Positioned(
            left: kScreenPadding,
            top: kHeadBandTop + (kHeadBandHeight - kHeaderButtonSize) / 2,
            child: Opacity(
              opacity: kBackPillFaded + (1 - kBackPillFaded) * fade,
              child: _HeaderButton(
                icon: LucideIcons.cornerUpLeft,
                onTap: onBack,
                semanticLabel: 'Back to the desk',
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: kHeadBandTop + shift,
            height: kHeadBandHeight,
            child: Opacity(
              opacity: fade,
              child: IgnorePointer(child: _Title(title, back: showingBack)),
            ),
          ),
          Positioned(
            left: kScreenWidth - kScreenPadding - kHeaderButtonSize,
            top:
                kHeadBandTop +
                (kHeadBandHeight - kHeaderButtonSize) / 2 +
                shift,
            child: Opacity(
              opacity: fade,
              child: _HeaderButton(
                icon: LucideIcons.search,
                onTap: hidden >= 1 ? null : onFind,
                semanticLabel: 'Find in document',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One 38.5 point floating button: the only shape a control takes in the
/// reader.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, this.onTap, this.semanticLabel});

  final IconData icon;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: kHeaderButtonSize,
        height: kHeaderButtonSize,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(kHeaderButtonRadius),
          border: AppEdges.all(context),
        ),
        child: Center(
          child: Icon(icon, size: kChromeIcon, color: AppColors.ink),
        ),
      ),
    );
  }
}

/// The title, centred in the band, with the suffix that names the side of the
/// sheet you are reading.
class _Title extends StatelessWidget {
  const _Title(this.title, {required this.back});

  final String title;
  final bool back;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kReaderTitleWidth),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: AppColors.ink),
              ),
            ),
            if (back)
              Padding(
                padding: const EdgeInsets.only(left: kSpace8),
                child: Text(
                  '· BACK',
                  style: AppText.micro.copyWith(color: AppColors.accentBright),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How wide the title is allowed to run before it ellipses, which is what
/// keeps it clear of both pills.
const kReaderTitleWidth = 200.0;
