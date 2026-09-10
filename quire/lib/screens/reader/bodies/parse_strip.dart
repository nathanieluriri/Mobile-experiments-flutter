import 'package:flutter/widgets.dart';

import '../../../format/csv_parser.dart';
import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/press_fade.dart';

/// What the CSV reader had to decide before it could show you anything.
///
/// A delimited file has no header telling anyone how to read it, so every one
/// of these numbers is a guess the reader made. Printing them is what lets a
/// reader who is looking at one column of nonsense see why, instead of
/// concluding the file is broken.
class ParseFacts {
  const ParseFacts({
    required this.delimiter,
    required this.rows,
    required this.columns,
    required this.raggedRows,
  });

  /// The delimiter, named rather than printed: `COMMA`, `TAB`.
  final String delimiter;

  /// Data rows, the header row excluded.
  final int rows;

  /// How wide the grid is, which is the widest row in the file.
  final int columns;

  /// Rows whose field count did not match the header's, by model index.
  final Set<int> raggedRows;

  /// The first row that does not match its header, or null.
  int? get firstRagged {
    if (raggedRows.isEmpty) return null;
    var first = raggedRows.first;
    for (final row in raggedRows) {
      if (row < first) first = row;
    }
    return first;
  }

  /// The line the strip prints on its left.
  String get line =>
      'CSV · $delimiter · $rows ROWS · $columns COLUMNS';

  /// The count the strip prints on its right, or null when nothing is ragged.
  String? get raggedLabel =>
      raggedRows.isEmpty ? null : '${raggedRows.length} RAGGED';
}

/// The name of a delimiter, so the strip never prints bare punctuation.
String delimiterName(String delimiter) {
  switch (delimiter) {
    case ',':
      return 'COMMA';
    case ';':
      return 'SEMICOLON';
    case '\t':
      return 'TAB';
    case '|':
      return 'PIPE';
    default:
      return 'CUSTOM';
  }
}

/// Counts a parsed CSV, measuring raggedness against the header rather than
/// against the widest row.
///
/// The header is the file's own claim about its shape, so a row that does not
/// match it is the row that is wrong, even when a hundred rows agree with each
/// other and disagree with the header.
ParseFacts csvFacts(CsvTable table, {bool firstRowIsHeader = true}) {
  final width = table.rows.isEmpty ? 0 : table.rows.first.length;
  final ragged = <int>{};
  for (var r = firstRowIsHeader ? 1 : 0; r < table.rows.length; r++) {
    if (table.rows[r].length != width) ragged.add(r);
  }
  return ParseFacts(
    delimiter: delimiterName(table.delimiter),
    rows: table.rows.length - (firstRowIsHeader ? 1 : 0),
    columns: table.columnCount,
    raggedRows: ragged,
  );
}

/// The twenty point band above a CSV that says how the file was read.
class ParseStrip extends StatelessWidget {
  const ParseStrip({super.key, required this.facts, this.onJumpToRagged});

  final ParseFacts facts;

  /// Jumps the grid to the first row that did not match its header.
  final VoidCallback? onJumpToRagged;

  @override
  Widget build(BuildContext context) {
    final ragged = facts.raggedLabel;
    return SizedBox(
      height: kParseStripHeight,
      child: Container(
        decoration: const BoxDecoration(color: AppColors.surfaceHigh),
        foregroundDecoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kCellPaddingX),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  facts.line,
                  style: AppText.micro.copyWith(color: AppColors.inkFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (ragged != null)
                PaperPress(
                  onTap: onJumpToRagged,
                  enabled: onJumpToRagged != null,
                  child: Text(
                    ragged,
                    style: AppText.micro.copyWith(color: AppColors.damage),
                    maxLines: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
