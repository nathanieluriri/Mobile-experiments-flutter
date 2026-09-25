import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/feedback.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The sheet's own measurements.
const kDeskSheetCorner = 22.0;
const kDeskSheetPadX = 20.0;
const kDeskSheetTopPad = 18.0;
const kDeskSheetBottomPad = 10.0;
const kDeskSheetRowHeight = 54.0;
const kDeskSheetRowGlyph = 20.0;
const kDeskSheetRowGap = 16.0;
const kDeskSheetTitleGap = 4.0;
const kDeskSheetNoteGap = 14.0;
const kDeskSheetRowPadY = 11.0;
const kDeskSheetFactName = 116.0;
const kDeskSheetStep = 36.0;
const kDeskSheetStepRadius = 10.0;
const kDeskSheetStepGap = 8.0;
const kDeskSheetRise = Duration(milliseconds: 260);

/// The grip at the top of the sheet, which says which edge it came from.
const kDeskSheetGripWidth = 36.0;
const kDeskSheetGripHeight = 4.0;
const kDeskSheetGripGap = 14.0;

/// A panel of things to do, brought up from the bottom edge over a scrim.
///
/// The goo answers a question with the few answers worth peeling off a button.
/// This answers the ones there are too many of, and the ones that need a word
/// of explanation before you pick them, which a pill has no room for.
///
/// It is paper, like everything else here: an opaque surface with a hairline
/// where it meets the ground, and no shadow doing the separating.
class DeskSheet extends StatelessWidget {
  const DeskSheet({
    super.key,
    required this.title,
    required this.children,
    this.note,
  });

  /// What the sheet is about, which is nearly always the document's name.
  final String title;

  /// A line under the title, for a sheet that has something to say before it
  /// offers anything.
  final String? note;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(kDeskSheetCorner),
          ),
          border: Border(top: BorderSide(color: AppColors.hairline, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(
              top: kDeskSheetTopPad,
              bottom: kDeskSheetBottomPad,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: SizedBox(
                    width: kDeskSheetGripWidth,
                    height: kDeskSheetGripHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.hairline,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: kDeskSheetGripGap),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kDeskSheetPadX,
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle.copyWith(color: AppColors.ink),
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: kDeskSheetTitleGap),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kDeskSheetPadX,
                    ),
                    child: Text(
                      note,
                      style: AppText.docMeta.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: kDeskSheetNoteGap),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: children,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One thing the sheet offers.
///
/// A row rather than a pill, because a row has room for the line under the
/// label, and the sheet exists for exactly the answers that need one.
class DeskSheetRow extends StatelessWidget {
  const DeskSheetRow({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.note,
    this.destructive = false,
    this.enabled = true,
    this.trailing,
  });

  final String label;
  final String? note;

  /// A second, smaller control at the end of the row, for a list whose rows
  /// can be both gone to and taken away.
  final Widget? trailing;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;

  /// False for something this document cannot have done to it, which is drawn
  /// faint and says why on its own line rather than vanishing. A row that is
  /// not there answers no question; a row that is there and says no answers
  /// the one you were about to ask.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    final ink = !enabled
        ? AppColors.inkFaint
        : destructive
        ? AppColors.accentBright
        : AppColors.ink;
    return PaperPress(
      onTap: enabled ? onTap : null,
      semanticLabel: label,
      feel: destructive ? Feel.commit : Feel.tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
        child: SizedBox(
          height: note == null ? kDeskSheetRowHeight : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: note == null ? 0 : kDeskSheetRowPadY,
            ),
            child: Row(
              children: [
                Icon(icon, size: kDeskSheetRowGlyph, color: ink),
                const SizedBox(width: kDeskSheetRowGap),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: note == null ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.menuRow.copyWith(color: ink),
                      ),
                      if (note != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          note,
                          style: AppText.micro.copyWith(
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that changes a number without closing the sheet.
///
/// Text size is the one setting you cannot pick blind: you make it bigger,
/// look at it, and make it bigger again. A row that shut the sheet on every
/// press would make that four journeys instead of one.
class DeskSheetStepper extends StatelessWidget {
  const DeskSheetStepper({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onLess,
    required this.onMore,
  });

  final String label;

  /// Where it stands now, in the reader's terms rather than the machine's.
  final String value;

  final IconData icon;

  /// Null at the end of the range, which is what draws that side faint.
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
      child: SizedBox(
        height: kDeskSheetRowHeight,
        child: Row(
          children: [
            Icon(icon, size: kDeskSheetRowGlyph, color: AppColors.ink),
            const SizedBox(width: kDeskSheetRowGap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.menuRow.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: AppText.micro.copyWith(color: AppColors.inkFaint),
                  ),
                ],
              ),
            ),
            _Step(icon: LucideIcons.minus, onTap: onLess, label: 'Smaller'),
            const SizedBox(width: kDeskSheetStepGap),
            _Step(icon: LucideIcons.plus, onTap: onMore, label: 'Larger'),
          ],
        ),
      ),
    );
  }
}

/// One end of a stepper.
class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final live = onTap != null;
    return PaperPress(
      onTap: onTap,
      semanticLabel: label,
      washRadius: kDeskSheetStepRadius,
      child: Container(
        width: kDeskSheetStep,
        height: kDeskSheetStep,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(kDeskSheetStepRadius),
        ),
        child: Icon(
          icon,
          size: kDeskSheetRowGlyph,
          color: live ? AppColors.ink : AppColors.inkFaint,
        ),
      ),
    );
  }
}

/// One thing the sheet states, for a sheet that answers rather than offers.
class DeskSheetFact extends StatelessWidget {
  const DeskSheetFact({super.key, required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX, vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: kDeskSheetFactName,
          child: Text(
            name,
            style: AppText.docMeta.copyWith(color: AppColors.inkFaint),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppText.docMeta.copyWith(color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}

/// A rule between two runs of rows on a sheet.
class DeskSheetRule extends StatelessWidget {
  const DeskSheetRule({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: kDeskSheetPadX, vertical: 6),
    child: SizedBox(
      height: 1,
      child: DecoratedBox(decoration: BoxDecoration(color: AppColors.hairline)),
    ),
  );
}

/// Brings [builder]'s sheet up over whatever is on screen, and hands back
/// whatever the sheet was dismissed with.
///
/// A route rather than a layer in the desk, because a sheet is a place you go
/// and come back from: the phone's own way out should close it, and the desk
/// should not have to hold a controller for something it does not draw.
Future<T?> showDeskSheet<T>(
  BuildContext context,
  Widget Function(BuildContext context) builder, {
  Color barrier = AppColors.scrim,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: barrier,
      barrierDismissible: true,
      barrierLabel: 'Close',
      transitionDuration: kDeskSheetRise,
      reverseTransitionDuration: kDeskSheetRise,
      pageBuilder: (context, animation, secondary) => builder(context),
      transitionsBuilder: (context, animation, secondary, child) =>
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: easeOutCubic)),
            child: child,
          ),
    ),
  );
}
