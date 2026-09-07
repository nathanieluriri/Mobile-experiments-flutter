import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The magnifier, and the field it grows into.
///
/// At [open] 0 this is the round glyph sitting in the corner of the header. At
/// 1 it has reached across the header, taken the surface colour underneath it,
/// and put a cursor next to the glyph.
class SearchField extends StatelessWidget {
  const SearchField({
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
      size: 21 - 3 * open,
      color: AppColors.white.withValues(alpha: 1 - 0.25 * open),
    );

    if (open <= 0) {
      return PressFade(
        onTap: onOpen,
        semanticLabel: 'Search',
        child: SizedBox(
          width: kHeaderButtonSize,
          height: kHeaderButtonSize,
          child: Center(child: glyph),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: open),
        borderRadius: BorderRadius.circular(kHeaderButtonRadius),
      ),
      child: SizedBox(
        height: kHeaderButtonSize,
        child: Row(
          children: [
            SizedBox(width: kHeaderButtonSize, child: Center(child: glyph)),
            Expanded(child: _field(context)),
            Opacity(
              opacity: open,
              child: PressFade(
                onTap: onClose,
                semanticLabel: 'Close search',
                child: const SizedBox(
                  width: kHeaderButtonSize,
                  height: kHeaderButtonSize,
                  child: Center(
                    child: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: AppColors.dockLabel,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context) {
    const style = TextStyle(
      fontFamily: kFontFamily,
      fontWeight: FontWeights.medium,
      fontSize: 15,
      height: kLineHeight,
      color: AppColors.white,
    );
    return Opacity(
      opacity: open,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (controller.text.isEmpty)
            Text(
              'Search notes',
              style: style.copyWith(
                color: AppColors.dockLabel.withValues(alpha: 0.45),
              ),
            ),
          EditableText(
            controller: controller,
            focusNode: focusNode,
            style: style,
            cursorColor: AppColors.white,
            backgroundCursorColor: AppColors.surface,
            cursorWidth: 1.5,
            cursorRadius: const Radius.circular(1),
            selectionColor: AppColors.white.withValues(alpha: 0.24),
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
