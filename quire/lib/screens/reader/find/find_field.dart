import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/edges.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/press_fade.dart';

/// The magnifier closed, in the reader's own search pill, and open, once the
/// words being typed are what should lead.
const kFindGlyphClosed = 20.0;
const kFindGlyphOpen = 16.0;

/// How far in from the field's left edge the magnifier sits.
const kFindGlyphInset = 12.0;

/// How wide the cancel is. It sits inside the field rather than beside it, so
/// the field keeps the whole width the head band has to give.
const kFindCancelWidth = 34.0;

/// What the field says before anyone has typed.
const kFindPlaceholder = 'Find in document';

/// What the cancel says. Written in the literal string, never uppercased by a
/// transform, so a golden reads what the source says.
const kFindCancelLabel = 'Done';

/// The field's top edge, shared with the pill it grows out of so the two are
/// the same object moving rather than one replacing another.
const kFindFieldTop = kHeadBandTop + (kHeadBandHeight - kFindFieldHeight) / 2;

/// The same edge on a phone whose own chrome ends at [safeTop].
double findFieldTop(double safeTop) =>
    safeTop + (kHeadBandHeight - kFindFieldHeight) / 2;

/// The least of the query a reader is left to see their own typing in before
/// whatever sits beside it steps out of the way.
const kFindQueryMin = 48.0;

/// Everything in the field that is not the query or what sits beside it: the
/// magnifier, the query's inset, and Done.
const kFindFieldFixed =
    kFindGlyphInset + kFindGlyphOpen + kSpace8 + kFindCancelWidth;

/// The field's right edge: the screen margin, where the search pill already
/// ends.
const kFindFieldRight = kScreenWidth - kScreenPadding;

/// Where the field's left edge is at [open], 0 closed and 1 open.
///
/// The right edge never moves, so the field reads as the pill stretching
/// leftward across the band rather than as a new object arriving.
double findFieldLeft(double open) {
  const closed = kFindFieldRight - kHeaderButtonSize;
  return closed + (kScreenPadding - closed) * open.clamp(0.0, 1.0);
}

/// The reader's search pill, and the field it grows into.
///
/// At [open] 0 this is the 38.5 square in the corner of the head band. At 1 it
/// has reached the whole way across, taken a caret, and dropped its glyph back
/// so the query leads.
class FindField extends StatelessWidget {
  const FindField({
    super.key,
    required this.open,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
    this.onSubmitted,
    this.tint = 0,
    this.accessory,
    this.accessoryWidth = 0,
  });

  /// 0 closed, 1 open. Already eased by whatever is driving it.
  final double open;

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  /// The search key on the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// How far the fill has gone from paper toward [AppColors.damageTint], which
  /// is the whole of what a search finding nothing does to the field. No
  /// shake, no icon, no sound: a search that finds nothing is a keystroke on
  /// the way somewhere.
  final double tint;

  /// What sits between the query and Done, [accessoryWidth] wide: the count
  /// and the arrows, once there is a query to count.
  ///
  /// It is part of the field rather than a line under it, so it is always
  /// drawn on the field's own fill. Over a white page a count on nothing is a
  /// count nobody can read.
  final Widget? accessory;
  final double accessoryWidth;

  @override
  Widget build(BuildContext context) {
    final ground = Color.lerp(
      AppColors.surfaceHigh,
      AppColors.damageTint,
      tint.clamp(0.0, 1.0),
    )!;
    return Container(
      height: kFindFieldHeight,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(kFieldRadius),
        border: AppEdges.all(context),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => _row(constraints.maxWidth),
      ),
    );
  }

  Widget _row(double width) {
    // The field is only as wide as it has grown. What sits beside the query
    // comes in once there is room for it and the query both, and fades up
    // across the rest of the way, so it arrives and leaves with the field
    // rather than popping in at some width along it.
    final room = width - kFindFieldFixed - kFindQueryMin;
    final full =
        kFindFieldRight - kScreenPadding - kFindFieldFixed - kFindQueryMin;
    final beside = accessory;
    final fits = beside != null && room >= accessoryWidth;
    final shown = full <= accessoryWidth
        ? 1.0
        : ((room - accessoryWidth) / (full - accessoryWidth)).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: kFindGlyphInset + kFindGlyphOpen,
          child: Align(
            alignment: Alignment.centerRight,
            child: Icon(
              LucideIcons.search,
              size:
                  kFindGlyphClosed - (kFindGlyphClosed - kFindGlyphOpen) * open,
              color: Color.lerp(AppColors.ink, AppColors.inkFaint, open),
            ),
          ),
        ),
        Expanded(child: _query()),
        if (fits) Opacity(opacity: shown * open, child: beside),
        Opacity(
          opacity: open,
          child: PaperPress(
            onTap: open <= 0 ? null : onClose,
            semanticLabel: 'Close find',
            child: SizedBox(
              width: kFindCancelWidth,
              height: kFindFieldHeight,
              child: Center(
                child: Text(
                  kFindCancelLabel,
                  style: AppText.label.copyWith(color: AppColors.accentBright),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The query itself, with the placeholder sitting on the same metrics so no
  /// glyph moves when the first character lands.
  Widget _query() {
    return Opacity(
      opacity: open,
      child: Padding(
        padding: const EdgeInsets.only(left: kSpace8),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            if (controller.text.isEmpty)
              Text(
                kFindPlaceholder,
                style: AppText.label.copyWith(color: AppColors.inkFaint),
              ),
            EditableText(
              controller: controller,
              focusNode: focusNode,
              style: AppText.label.copyWith(color: AppColors.ink),
              cursorColor: AppColors.accentBright,
              backgroundCursorColor: AppColors.hairline,
              cursorWidth: 1.5,
              cursorRadius: const Radius.circular(1),
              selectionColor: AppColors.foundWash,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
