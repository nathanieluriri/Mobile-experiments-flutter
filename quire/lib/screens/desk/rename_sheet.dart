import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/typography.dart';
import 'desk_sheet.dart';

/// The field's own measurements.
const kRenameFieldHeight = 48.0;
const kRenameFieldRadius = 12.0;
const kRenameFieldPadX = 14.0;
const kRenameGap = 12.0;

/// The sheet the app asks for a name on.
///
/// A name is the one thing about a document the desk owns rather than the
/// file: the reading position, the stars and the signatures are all filed
/// under where the bytes are, so renaming changes what it is called and
/// nothing else. It is a sheet rather than a field on the row, because a row
/// at the bottom of the list would be under the keyboard the moment you
/// tapped it.
class RenameSheet extends StatefulWidget {
  const RenameSheet({
    super.key,
    required this.title,
    this.heading = 'Rename',
    this.note = 'The document keeps its place, its stars and its signatures.',
    this.action = 'Save the name',
    this.capitalization = TextCapitalization.words,
  });

  /// What it is called now, which is what the field opens holding, selected,
  /// so typing replaces it and a tap puts the caret where you want.
  final String title;

  /// What the sheet is called, for the other things that need a name.
  final String heading;
  final String note;
  final String action;
  final TextCapitalization capitalization;

  @override
  State<RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<RenameSheet> {
  late final TextEditingController _field = TextEditingController(
    text: widget.title,
  )..selection = TextSelection(
    baseOffset: 0,
    extentOffset: widget.title.length,
  );

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The keyboard comes with the sheet. A rename sheet you have to tap into
    // is a sheet that has asked a question and then looked away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final wanted = _field.text.trim();
    Navigator.of(context).pop(wanted.isEmpty ? null : wanted);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The keyboard is what this sheet is standing on.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DeskSheet(
        title: widget.heading,
        note: widget.note,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
            child: Container(
              height: kRenameFieldHeight,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                horizontal: kRenameFieldPadX,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(kRenameFieldRadius),
                border: AppEdges.all(context),
              ),
              child: EditableText(
                controller: _field,
                focusNode: _focus,
                style: AppText.rowTitle.copyWith(color: AppColors.ink),
                cursorColor: AppColors.accentBright,
                backgroundCursorColor: AppColors.hairline,
                cursorWidth: 1.5,
                cursorRadius: const Radius.circular(1),
                selectionColor: AppColors.foundWash,
                textInputAction: TextInputAction.done,
                textCapitalization: widget.capitalization,
                onSubmitted: (_) => _commit(),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: kRenameGap),
          DeskSheetRow(
            label: widget.action,
            icon: LucideIcons.check,
            onTap: _commit,
          ),
        ],
      ),
    );
  }
}
