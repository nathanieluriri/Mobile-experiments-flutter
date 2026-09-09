import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The magnifier's size closed and open, and how far its ink drops as the
/// field takes over the job of saying what this is.
const kSearchGlyphClosed = 21.0;
const kSearchGlyphOpen = 18.0;
const kSearchGlyphFade = 0.75;

/// What the field says before anyone has typed.
const kSearchPlaceholder = 'Search the desk';

/// The search button, and the field it grows into.
///
/// At [open] 0 this is the 38.5 square in the corner of the header. At 1 it
/// has reached the whole way across, taken a cursor, and dropped its glyph
/// back so the words you are typing lead.
class DeskSearchField extends StatelessWidget {
  const DeskSearchField({
    super.key,
    required this.open,
    required this.controller,
    required this.focusNode,
    required this.onOpen,
    required this.onClose,
    required this.onChanged,
  });

  /// 0 closed, 1 open.
  final double open;

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(
      LucideIcons.search,
      size: kSearchGlyphClosed -
          (kSearchGlyphClosed - kSearchGlyphOpen) * open,
      color: AppColors.ink
          .withValues(alpha: 1 - (1 - kSearchGlyphFade) * open),
    );
    // Opaque, not a wash. This sits over the top card in the list and there is
    // nothing under it now to say which surface is in front, so letting a title
    // ghost through the fill would read as a rendering fault rather than as
    // depth.
    const fill = AppColors.leaf;

    if (open <= 0) {
      return PaperPress(
        onTap: onOpen,
        semanticLabel: 'Search',
        child: Container(
          width: kHeaderButtonSize,
          height: kHeaderButtonSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(kFieldRadius),
            border: AppEdges.all(context),
          ),
          child: glyph,
        ),
      );
    }

    return Container(
      height: kHeaderButtonSize,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(kFieldRadius),
        border: AppEdges.all(context),
      ),
      child: Row(
        children: [
          SizedBox(
            width: kHeaderButtonSize,
            child: Center(child: glyph),
          ),
          Expanded(child: _field()),
          Opacity(
            opacity: open,
            child: PaperPress(
              onTap: onClose,
              semanticLabel: 'Close search',
              child: const SizedBox(
                width: kHeaderButtonSize,
                height: kHeaderButtonSize,
                child: Center(
                  child: Icon(
                    LucideIcons.x,
                    size: kSearchGlyphOpen,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field() {
    final style = AppText.bodyTight.copyWith(color: AppColors.ink);
    return Opacity(
      opacity: open,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (controller.text.isEmpty)
            Text(
              kSearchPlaceholder,
              style: AppText.hint.copyWith(color: AppColors.inkFaint),
            ),
          EditableText(
            controller: controller,
            focusNode: focusNode,
            style: style,
            cursorColor: AppColors.thread,
            backgroundCursorColor: AppColors.rule,
            cursorWidth: 1.5,
            cursorRadius: const Radius.circular(1),
            selectionColor: AppColors.markerWash,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
