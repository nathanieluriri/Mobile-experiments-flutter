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
const kFindFieldTop =
    kHeadBandTop + (kHeadBandHeight - kFindFieldHeight) / 2;

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
    this.tint = 0,
  });

  /// 0 closed, 1 open. Already eased by whatever is driving it.
  final double open;

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  /// How far the fill has gone from paper toward [AppColors.damageTint], which
  /// is the whole of what a search finding nothing does to the field. No
  /// shake, no icon, no sound: a search that finds nothing is a keystroke on
  /// the way somewhere.
  final double tint;

  @override
  Widget build(BuildContext context) {
    final ground = Color.lerp(
      AppColors.surface,
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
      child: Row(
        children: [
          SizedBox(
            width: kFindGlyphInset + kFindGlyphOpen,
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(
                LucideIcons.search,
                size: kFindGlyphClosed -
                    (kFindGlyphClosed - kFindGlyphOpen) * open,
                color: Color.lerp(AppColors.ink, AppColors.inkFaint, open),
              ),
            ),
          ),
          Expanded(child: _query()),
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
      ),
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
              textInputAction: TextInputAction.search,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
