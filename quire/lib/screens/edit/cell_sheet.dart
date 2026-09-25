import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../desk/desk_sheet.dart';
import 'edit_frame.dart';

/// The sheet one cell is changed on.
///
/// It says what a formula will do before the reader types one: quire keeps
/// the formula and does not work it out, so the cell shows the formula until
/// the workbook is opened somewhere that calculates.
class CellSheet extends StatefulWidget {
  const CellSheet({super.key, required this.reference, required this.input});

  /// `Costs!B4`.
  final String reference;

  /// What the cell holds, a formula written with its `=`.
  final String input;

  @override
  State<CellSheet> createState() => _CellSheetState();
}

class _CellSheetState extends State<CellSheet> {
  late final TextEditingController _field =
      TextEditingController(text: widget.input)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.input.length,
        );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
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

  void _commit() => Navigator.of(context).pop(_field.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DeskSheet(
        title: widget.reference,
        note: 'A number, a word, TRUE or FALSE, or = and a formula. A formula '
            'is kept, not worked out: it shows as written until the workbook '
            'is opened in a spreadsheet.',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
            child: EditField(
              controller: _field,
              focusNode: _focus,
              maxLines: 1,
              style: AppText.rowTitle.copyWith(color: AppColors.ink),
              hint: 'Empty',
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commit(),
            ),
          ),
          const SizedBox(height: kEditGap),
          DeskSheetRow(
            label: 'Save the cell',
            icon: LucideIcons.check,
            onTap: _commit,
          ),
        ],
      ),
    );
  }
}
