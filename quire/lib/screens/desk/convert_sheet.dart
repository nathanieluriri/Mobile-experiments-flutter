import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/convert.dart';
import 'desk_sheet.dart';

/// The glyph each target wears, which is the glyph its own kind of file wears
/// everywhere else in the app.
IconData iconFor(ConvertTarget target) => switch (target) {
  ConvertTarget.text => LucideIcons.fileText,
  ConvertTarget.markdown => LucideIcons.hash,
  ConvertTarget.csv => LucideIcons.table,
  ConvertTarget.xlsx => LucideIcons.sheet,
  ConvertTarget.pdf => LucideIcons.fileType,
  ConvertTarget.docx => LucideIcons.fileType2,
};

/// What a document can be turned into, each saying what it will cost.
///
/// Every conversion loses something, and the sheet says what before it is
/// picked rather than after. A converter that stays quiet about the loss has
/// decided for the reader that it did not matter, which is not a decision it
/// is in any position to make.
class ConvertSheet extends StatelessWidget {
  const ConvertSheet({
    super.key,
    required this.title,
    required this.targets,
    required this.unbuilt,
  });

  final String title;
  final List<ConvertTarget> targets;

  /// Targets that are offered but that this build cannot write yet. They are
  /// drawn faint and say so, because a row that is not there answers nothing
  /// and a reader who came looking for it would only look again.
  final Set<ConvertTarget> unbuilt;

  @override
  Widget build(BuildContext context) {
    return DeskSheet(
      title: 'Convert $title',
      note: 'The new file goes on the desk. The original stays as it is.',
      children: <Widget>[
        for (final target in targets)
          DeskSheetRow(
            label: target.label,
            icon: iconFor(target),
            note: unbuilt.contains(target)
                ? 'Not built yet, so it is not offered as if it were'
                : target.note,
            enabled: !unbuilt.contains(target),
            onTap: () => Navigator.of(context).pop(target),
          ),
      ],
    );
  }
}

/// What a conversion dropped on its way out, said after the fact.
///
/// It is a sheet rather than a line on the pill because a warning worth
/// writing is usually longer than a pill, and because the reader has a file
/// now: the question is no longer whether to go ahead, it is what they are
/// holding.
class ConvertWarningSheet extends StatelessWidget {
  const ConvertWarningSheet({
    super.key,
    required this.title,
    required this.warnings,
  });

  final String title;
  final List<ConvertWarning> warnings;

  @override
  Widget build(BuildContext context) {
    return DeskSheet(
      title: title,
      note: 'It is on the desk. Here is what did not come with it.',
      children: <Widget>[
        for (final warning in warnings)
          DeskSheetRow(
            label: 'What was lost',
            icon: LucideIcons.triangleAlert,
            note: warning.line,
            onTap: () => Navigator.of(context).pop(),
          ),
        DeskSheetRow(
          label: 'Right',
          icon: LucideIcons.check,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
