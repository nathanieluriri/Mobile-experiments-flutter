import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/document.dart';
import '../pdf/encodings.dart' show winAnsiHigh;

/// A parsed CSV file, plus what the parser had to decide to read it.
///
/// The delimiter and the encoding are carried rather than discarded because a
/// reader that guessed wrong should be able to say so on screen instead of
/// quietly showing one column of nonsense.
class CsvTable {
  CsvTable(this.rows, this.delimiter, this.encodingNote);

  /// Every row, header included, in file order.
  final List<List<String>> rows;

  /// The delimiter that was used, sniffed unless one was supplied.
  final String delimiter;

  /// How the bytes were decoded, for example 'utf-8 (BOM)'.
  final String encodingNote;

  /// The widest row. Cells are padded out to this so the grid is rectangular.
  int get columnCount => rows.fold(0, (m, r) => r.length > m ? r.length : m);

  /// Rows that do not have exactly [columnCount] fields.
  ///
  /// A ragged file is not an error, it is a fact about the file, and the
  /// reader shows the count rather than silently padding in the dark.
  int get raggedRowCount {
    final width = columnCount;
    var count = 0;
    for (final r in rows) {
      if (r.length != width) count++;
    }
    return count;
  }
}

const _quote = 0x22; // "
const _cr = 0x0D;
const _lf = 0x0A;

/// Decodes bytes, stripping a UTF-8 or UTF-16 BOM, and falling back to latin1
/// when the bytes are not valid UTF-8.
///
/// Returns the text and a human readable note about which path was taken, so
/// a mis decoded file can be explained instead of just looking wrong.
(String, String) decodeCsvBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return (utf8.decode(bytes.sublist(3), allowMalformed: true), 'utf-8 (BOM)');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final sb = StringBuffer();
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      sb.writeCharCode(bytes[i] | (bytes[i + 1] << 8));
    }
    return (sb.toString(), 'utf-16le (BOM)');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final sb = StringBuffer();
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      sb.writeCharCode((bytes[i] << 8) | bytes[i + 1]);
    }
    return (sb.toString(), 'utf-16be (BOM)');
  }
  try {
    return (const Utf8Decoder(allowMalformed: false).convert(bytes), 'utf-8');
  } on FormatException {
    return (decodeWindows1252(bytes), 'windows-1252 fallback');
  }
}

/// Bytes as Windows-1252, the single-byte encoding Excel writes on Western
/// Windows, and which the web reads any file labelled Latin-1 as. The five
/// bytes it leaves undefined stand for themselves, so every byte comes back.
String decodeWindows1252(List<int> bytes) =>
    String.fromCharCodes(<int>[for (final b in bytes) winAnsiHigh[b] ?? b]);

/// [text] in Windows-1252, or null when a character in it has no byte there.
Uint8List? encodeWindows1252(String text) {
  final out = Uint8List(text.length);
  for (var i = 0; i < text.length; i++) {
    final u = text.codeUnitAt(i);
    final b = u < 0x80 || (u >= 0xA0 && u <= 0xFF) ? u : _windows1252Bytes[u];
    if (b == null) {
      // The five undefined bytes read back as themselves.
      if (u == 0x81 || u == 0x8D || u == 0x8F || u == 0x90 || u == 0x9D) {
        out[i] = u;
        continue;
      }
      return null;
    }
    out[i] = b;
  }
  return out;
}

final Map<int, int> _windows1252Bytes = <int, int>{
  for (final e in winAnsiHigh.entries) e.value: e.key,
};

/// Picks the delimiter that yields the most consistent field count over the
/// first few rows, breaking ties towards more columns.
///
/// Consistency beats frequency: a comma inside quoted prose is common, and
/// counting occurrences would choose it over the real separator. A candidate
/// is marked down for what reading with it makes odd: quotes that open or
/// close in the middle of a field, and unquoted fields holding another
/// candidate, which is what a row looks like split at the wrong character.
/// A comma between digits, as in 1,50, is a decimal mark and not odd.
String sniffDelimiter(String text, {List<String> candidates = const [',', ';', '\t', '|']}) {
  var best = ',';
  var bestScore = double.negativeInfinity;
  final sample = text.length > 20000 ? text.substring(0, 20000) : text;
  for (final d in candidates) {
    final odd = CsvOddities(<String>[for (final c in candidates) if (c != d) c]);
    final rows = <List<String>>[
      for (final row in parseCsv(sample, delimiter: d, maxRows: 20, odd: odd))
        if (!(row.length == 1 && row.first.isEmpty)) row,
    ];
    if (rows.isEmpty) continue;
    final first = rows.first.length;
    if (first < 2) continue;
    final consistent = rows.where((r) => r.length == first).length / rows.length;
    final fields = rows.fold<int>(0, (a, r) => a + r.length);
    final score = consistent * 100 + math.min(first, 20) - (odd.quotes * 3 + odd.split) * 100 / fields;
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return best;
}

/// What reading with one delimiter found odd, for choosing between them.
class CsvOddities {
  CsvOddities(this.others);
  final List<String> others;
  int quotes = 0;
  int split = 0;

  static final RegExp _decimal = RegExp(r'^\s*[-+]?\d+,\d+\s*$');

  void field(String value, bool quoted) {
    if (quoted) return;
    for (final other in others) {
      if (value.contains(other) && !(other == ',' && _decimal.hasMatch(value))) {
        split++;
        return;
      }
    }
  }
}

/// RFC 4180 field scanner.
///
/// It walks characters rather than splitting on newlines, which is the whole
/// point: a quoted field may contain the delimiter, a doubled quote, and line
/// breaks of any flavour, and a line splitting parser tears those files apart.
List<List<String>> parseCsv(
  String text, {
  String delimiter = ',',
  int maxRows = -1,
  CsvOddities? odd,
}) {
  final d = delimiter.codeUnitAt(0);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var fieldWasQuoted = false;
  var i = 0;
  final n = text.length;

  void endField() {
    odd?.field(field.toString(), fieldWasQuoted);
    row.add(field.toString());
    field.clear();
    fieldWasQuoted = false;
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (i < n) {
    final c = text.codeUnitAt(i);
    if (inQuotes) {
      if (c == _quote) {
        if (i + 1 < n && text.codeUnitAt(i + 1) == _quote) {
          field.writeCharCode(_quote);
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        // A quote that closes anywhere but at the end of its field.
        if (odd != null && i < n) {
          final next = text.codeUnitAt(i);
          if (next != d && next != _cr && next != _lf) odd.quotes++;
        }
        continue;
      }
      field.writeCharCode(c);
      i++;
      continue;
    }
    if (c == _quote && field.isEmpty && !fieldWasQuoted) {
      inQuotes = true;
      fieldWasQuoted = true;
      i++;
      continue;
    }
    if (c == _quote && odd != null) odd.quotes++;
    if (c == d) {
      endField();
      i++;
      continue;
    }
    if (c == _cr || c == _lf) {
      endRow();
      if (c == _cr && i + 1 < n && text.codeUnitAt(i + 1) == _lf) {
        i += 2;
      } else {
        i++;
      }
      if (maxRows > 0 && rows.length >= maxRows) return rows;
      continue;
    }
    field.writeCharCode(c);
    i++;
  }
  // Trailing content, or a file that does not end in a newline.
  if (field.isNotEmpty || row.isNotEmpty || fieldWasQuoted) {
    endRow();
  }
  return rows;
}

/// Decodes and parses one CSV file.
CsvTable readCsv(Uint8List bytes, {String? delimiter}) {
  final (text, note) = decodeCsvBytes(bytes);
  final d = delimiter ?? sniffDelimiter(text);
  return CsvTable(parseCsv(text, delimiter: d), d, note);
}

/// True when a field looks like a number but must stay text.
///
/// A leading zero is meaningful in the world the file came from: 0412 is a
/// membership number, not four hundred and twelve, and reading it as a number
/// would delete a digit the reader can see in the file.
bool _isTextualNumber(String v) =>
    v.length > 1 && v.codeUnitAt(0) == 0x30 && v[1] != '.';

/// Bridges a table into the shared model: one section, one grid [TableBlock],
/// with a frozen header row when the first row is a header.
QuireDocument csvToDocument(CsvTable table, String title,
    {bool firstRowIsHeader = true}) {
  final cols = table.columnCount;
  final numericCol = List<bool>.filled(cols, true);
  for (var r = firstRowIsHeader ? 1 : 0; r < table.rows.length; r++) {
    for (var c = 0; c < table.rows[r].length; c++) {
      final v = table.rows[r][c].trim();
      if (v.isEmpty) continue;
      if (_isTextualNumber(v) || num.tryParse(v.replaceAll(',', '')) == null) {
        numericCol[c] = false;
      }
    }
  }
  final rows = <DocRow>[];
  for (var r = 0; r < table.rows.length; r++) {
    final header = firstRowIsHeader && r == 0;
    final cells = <DocCell>[];
    for (var c = 0; c < cols; c++) {
      final v = c < table.rows[r].length ? table.rows[r][c] : '';
      final numeric = !header && numericCol[c];
      cells.add(DocCell(
        [
          ParagraphBlock([DocSpan(v, bold: header)],
              align: numeric ? DocAlign.end : DocAlign.start)
        ],
        numeric: numeric,
        align: numeric ? DocAlign.end : DocAlign.start,
        raw: numeric ? num.tryParse(v.replaceAll(',', '')) : v,
      ));
    }
    rows.add(DocRow(cells, header: header));
  }
  return QuireDocument(
    title: title,
    sections: [
      DocSection(title, [
        TableBlock(rows,
            columns: List.generate(cols, (_) => const DocColumn()),
            frozenRows: firstRowIsHeader ? 1 : 0,
            grid: true)
      ], kind: 'sheet')
    ],
    sourceFormat: 'csv',
  );
}
