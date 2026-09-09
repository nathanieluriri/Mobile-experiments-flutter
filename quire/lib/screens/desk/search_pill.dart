import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// What the pill says before anyone has typed.
const kSearchPlaceholder = 'Search quire';

/// Where the words start, and how far the trailing target is held off the
/// pill's own right edge so the glyph is not sitting on the curve.
const kSearchTextLeft = 16.0;
const kSearchTrailingInset = 4.0;
const kSearchGlyph = 18.0;

/// The search pill: the widest thing on the top bar, and the only one that
/// takes a cursor.
///
/// It does not grow out of a button the way the first desk's field did. There
/// is no wordmark on this bar to make room for any more, so the pill is simply
/// there, at rest, saying what it is.
class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onBrowse,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  /// Empties the field, which is what the trailing target does once there is
  /// something to empty.
  final VoidCallback onClear;

  /// Opening a document from outside the bundled library.
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final typed = controller.text.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focusNode.requestFocus,
      child: Container(
        height: kSearchPillHeight,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(kSearchPillRadius),
        ),
        child: Row(
          children: [
            const SizedBox(width: kSearchTextLeft),
            Expanded(child: _field()),
            // The folder is the way in to a file this library does not hold.
            // Once there is a query the same target empties it instead, since
            // a field you cannot clear in one tap is a field you have to hold
            // backspace on.
            PaperPress(
              onTap: typed ? onClear : onBrowse,
              semanticLabel: typed ? 'Clear search' : 'Open a file',
              child: SizedBox(
                width: kSearchFolderTarget,
                height: kSearchFolderTarget,
                child: Center(
                  child: Icon(
                    typed ? LucideIcons.x : LucideIcons.folder,
                    size: kSearchGlyph,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ),
            const SizedBox(width: kSearchTrailingInset),
          ],
        ),
      ),
    );
  }

  Widget _field() {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        if (controller.text.isEmpty)
          Text(
            kSearchPlaceholder,
            style: AppText.search.copyWith(color: AppColors.inkFaint),
          ),
        EditableText(
          controller: controller,
          focusNode: focusNode,
          style: AppText.search.copyWith(color: AppColors.ink),
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
    );
  }
}
