/// Moves the references in a formula, the way a spreadsheet does when a
/// formula is filled down or across.
///
/// A workbook stores a formula filled over a range once, on the first cell,
/// and every other cell of the range only points back at it. What those
/// cells actually hold is the first cell's formula with every reference that
/// is not anchored by a `$` moved by as many rows and columns as the cell is
/// from the first one.
library;

/// A reference to one cell: an optional `$` and letters, then an optional
/// `$` and digits, not part of a longer name and not a function call.
final _reference = RegExp(
  r'(?<![A-Za-z0-9_.$])(\$?)([A-Za-z]{1,3})(\$?)([0-9]{1,7})(?![A-Za-z0-9_(])',
);

/// [formula] as it reads from a cell [rows] below and [columns] to the right
/// of the cell it was written in.
///
/// Text in double quotes and sheet names in single quotes are left as they
/// are. A reference moved off the top or the left of the sheet becomes
/// `#REF!`, which is what a spreadsheet shows for it.
String shiftFormula(String formula, int rows, int columns) {
  if (rows == 0 && columns == 0) return formula;
  final out = StringBuffer();
  var i = 0;
  while (i < formula.length) {
    final quote = formula[i];
    if (quote == '"' || quote == "'") {
      final end = formula.indexOf(quote, i + 1);
      final stop = end < 0 ? formula.length : end + 1;
      out.write(formula.substring(i, stop));
      i = stop;
      continue;
    }
    var next = formula.length;
    final doubled = formula.indexOf('"', i);
    final single = formula.indexOf("'", i);
    if (doubled >= 0 && doubled < next) next = doubled;
    if (single >= 0 && single < next) next = single;
    out.write(_shiftPlain(formula.substring(i, next), rows, columns));
    i = next;
  }
  return out.toString();
}

String _shiftPlain(String text, int rows, int columns) =>
    text.replaceAllMapped(_reference, (match) {
      final columnFixed = match.group(1)!.isNotEmpty;
      final letters = match.group(2)!.toUpperCase();
      final rowFixed = match.group(3)!.isNotEmpty;
      final number = int.parse(match.group(4)!);
      final column = columnFixed ? _index(letters) : _index(letters) + columns;
      final row = rowFixed ? number : number + rows;
      if (column < 0 || row < 1) return '#REF!';
      return '${match.group(1)}${_letters(column)}${match.group(3)}$row';
    });

int _index(String letters) {
  var value = 0;
  for (final unit in letters.codeUnits) {
    value = value * 26 + (unit - 64);
  }
  return value - 1;
}

String _letters(int index) {
  var n = index + 1;
  final units = <int>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    units.insert(0, 65 + rem);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(units);
}
