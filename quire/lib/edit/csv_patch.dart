import 'dart:convert';
import 'dart:typed_data';

import '../format/csv_parser.dart' show decodeWindows1252, encodeWindows1252, parseCsv, sniffDelimiter;

/// How a CSV file's characters were written, so it is written back the same
/// way.
enum CsvEncoding { utf8, utf8Bom, utf16le, utf16be, windows1252 }

/// One row as the file holds it: its cells, which of them were quoted, the
/// text it was read from and what ended it.
class CsvRow {
  const CsvRow(this.cells, {this.quoted = const <bool>[], this.raw, this.end = '\n', this.open = false});

  final List<String> cells;
  final List<bool> quoted;

  /// The row's own text in the file, for a row nobody has touched, which is
  /// written back exactly as it was. Null once the row changes.
  final String? raw;

  /// What followed the row: its line ending, or nothing after the last row
  /// of a file that did not end with one.
  final String end;

  /// True for a last row the file ends inside a quote in, which has to be
  /// closed before anything can follow it.
  final bool open;

  bool wasQuoted(int column) => column < quoted.length && quoted[column];

  CsvRow withCells(List<String> next, {List<bool>? quoted}) =>
      CsvRow(next, quoted: quoted ?? this.quoted, end: end);

  /// The row with [next] after it. A row left inside an open quote is
  /// written out again, closed, once a line ending follows it.
  CsvRow withEnd(String next) => CsvRow(
        cells,
        quoted: quoted,
        raw: open && next.isNotEmpty ? null : raw,
        end: next,
        open: open && next.isEmpty,
      );
}

/// A CSV or TSV file opened to be edited cell by cell.
///
/// Rows nobody touched are written back as the exact text they were read
/// from, and a changed row keeps the quoting its cells had, its line ending,
/// the file's delimiter, byte order mark and encoding, so a save changes the
/// lines that were changed and nothing else.
class CsvDocument {
  CsvDocument._(this.original, this.delimiter, this.newline, this.encoding, this.rows, this._tail)
      : _read = rows;

  factory CsvDocument.read(Uint8List bytes, {String? delimiter}) {
    final (text, encoding) = _decode(bytes);
    final utf16 = encoding == CsvEncoding.utf16le || encoding == CsvEncoding.utf16be;
    // A UTF-16 file cut off in the middle of a character keeps its last byte.
    final tail = utf16 && bytes.length.isOdd ? <int>[bytes.last] : const <int>[];
    final d = delimiter ?? (text.isEmpty ? ',' : sniffDelimiter(text));
    final rows = _parse(text, d);
    var newline = '\n';
    for (final row in rows) {
      if (row.end.isNotEmpty) {
        newline = row.end;
        break;
      }
    }
    return CsvDocument._(bytes, d, newline, encoding, rows, tail);
  }

  final Uint8List original;
  final String delimiter;
  final List<int> _tail;

  /// The line ending new rows are given: the one the file used first.
  final String newline;
  final CsvEncoding encoding;

  /// The rows as they stand, which the editor replaces wholesale on every
  /// change so an old list can be kept for undo.
  List<CsvRow> rows;

  int get rowCount => rows.length;

  int get columnCount => rows.fold(0, (m, r) => r.cells.length > m ? r.cells.length : m);

  String cell(int row, int column) {
    if (row < 0 || row >= rows.length) return '';
    final cells = rows[row].cells;
    return column < cells.length ? cells[column] : '';
  }

  /// The rows as they were read. Every change replaces [rows] with a new
  /// list, and undoing all the way back hands this very list back.
  final List<CsvRow> _read;

  /// True when the file would be written differently. Empty cells and rows
  /// that typing past the edge made and clearing took back do not count,
  /// as a spreadsheet exports only what is used.
  bool get changed {
    if (identical(rows, _read)) return false;
    final used = _used(rows);
    if (used.length != _read.length) return true;
    final widened = _widened;
    for (var i = 0; i < used.length; i++) {
      if (!(widened ? _sameCells(used[i], _read[i]) : _sameRow(used[i], _read[i]))) return true;
    }
    return false;
  }

  int get _readWidth => _read.fold<int>(0, (m, r) => r.cells.length > m ? r.cells.length : m);

  /// True when something was typed past the right edge of the file and is
  /// still there, which makes every row as wide as the table.
  bool get _widened {
    final width = _readWidth;
    for (final row in rows) {
      for (var c = width; c < row.cells.length; c++) {
        if (row.cells[c].isNotEmpty) return true;
      }
    }
    return false;
  }

  /// True once anything has been done to the rows, even something that put
  /// them back as they were. Cheap enough to ask on every frame.
  bool get touched => !identical(rows, _read);

  /// Puts [value] into the cell at [row], [column], growing the table to
  /// reach it: a new row takes the file's own line ending, and a new column
  /// is added to every row so the table stays square.
  void setCell(int row, int column, String value) {
    if (row < 0 || column < 0) throw RangeError('No cell at $row, $column');
    if (cell(row, column) == value) return;
    final next = List<CsvRow>.of(rows);
    final wide = columnCount;
    while (next.length <= row) {
      _endLast(next);
      next.add(CsvRow(List<String>.filled(wide, ''), end: _lastEnd));
    }
    final width = column + 1 > wide ? column + 1 : wide;
    if (column + 1 > wide) {
      for (var i = 0; i < next.length; i++) {
        // A blank line stays a blank line.
        if (i != row && next[i].cells.every((c) => c.isEmpty) && next[i].cells.length <= 1) {
          continue;
        }
        next[i] = _padded(next[i], width);
      }
    }
    final target = _padded(next[row], width);
    final cells = List<String>.of(target.cells)..[column] = value;
    next[row] = target.withCells(cells);
    rows = next;
  }

  /// A new empty row at [at], as wide as the table.
  void insertRow(int at) {
    final next = List<CsvRow>.of(rows);
    final index = at.clamp(0, next.length);
    if (index == next.length) _endLast(next);
    final end = index == next.length ? _lastEnd : newline;
    next.insert(index, CsvRow(List<String>.filled(columnCount, ''), end: end));
    rows = next;
  }

  void deleteRow(int at) {
    if (at < 0 || at >= rows.length) return;
    final next = List<CsvRow>.of(rows);
    final wasLast = at == next.length - 1;
    final end = next[at].end;
    next.removeAt(at);
    // A file that did not end with a line ending still does not.
    if (wasLast && end.isEmpty && next.isNotEmpty) next[next.length - 1] = next.last.withEnd('');
    rows = next;
  }

  /// A new empty column at [at] in every row that reaches it. Blank lines
  /// stay blank and a short row keeps its length but for the new cell.
  void insertColumn(int at) {
    final width = columnCount;
    final index = at.clamp(0, width);
    rows = <CsvRow>[
      for (final row in rows)
        if (_blank(row) || row.cells.length < index || (row.cells.length == index && index < width))
          row
        else
          row.withCells(
            List<String>.of(row.cells)..insert(index, ''),
            quoted: List<bool>.of(_quotedOf(row, row.cells.length))..insert(index, false),
          ),
    ];
  }

  static bool _blank(CsvRow row) => row.cells.length <= 1 && row.cells.every((c) => c.isEmpty) && row.raw != null;

  void deleteColumn(int at) {
    rows = <CsvRow>[
      for (final row in rows)
        if (at < row.cells.length)
          row.withCells(
            List<String>.of(row.cells)..removeAt(at),
            quoted: at < row.quoted.length
                ? (List<bool>.of(row.quoted)..removeAt(at))
                : row.quoted,
          )
        else
          row,
    ];
  }

  /// The file as it stands, or exactly the bytes that were read when nothing
  /// changed.
  ///
  /// What is written is read back the way quire will read it, and when a
  /// row would read differently, say because the delimiter would be guessed
  /// wrong, the rows that could mislead are written again with their cells
  /// quoted until the file reads back to exactly these cells.
  Uint8List write() {
    if (!changed) return original;
    final used = _used(rows);
    var text = _text(used, quoteAll: false);
    if (!_readsBack(text, used)) text = _text(used, quoteAll: true);
    return _encode(text);
  }

  String _text(List<CsvRow> rows, {required bool quoteAll}) {
    final out = StringBuffer();
    final widened = _widened;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      // A row put back as it was is the row the file had.
      final back = i < _read.length && (widened ? _sameCells(row, _read[i]) : _sameRow(row, _read[i]));
      final kept = back ? _read[i] : row;
      final text = quoteAll && _misleads(kept) ? _format(kept, always: true) : kept.raw ?? _format(kept);
      out.write(text);
      var end = kept.end;
      // A bare CR before a blank line ending in LF would read as one CRLF,
      // and the blank line would be lost.
      if (end == '\r' && i + 1 < rows.length) {
        final after = rows[i + 1];
        if ((after.raw ?? _format(after)).isEmpty && after.end.startsWith('\n')) end = '\r\n';
      }
      out.write(end);
    }
    return out.toString();
  }

  static bool _misleads(CsvRow row) =>
      row.cells.any((cell) => _delimiters.any(cell.contains) || cell.contains('"'));

  /// True when [text], read the way quire reads a file, gives [rows].
  bool _readsBack(String text, List<CsvRow> rows) {
    final got = parseCsv(text, delimiter: text.isEmpty ? ',' : sniffDelimiter(text));
    if (got.length != rows.length) return false;
    for (var i = 0; i < rows.length; i++) {
      final a = got[i], b = rows[i].cells;
      final blankA = a.every((c) => c.isEmpty), blankB = b.every((c) => c.isEmpty);
      if (blankA && blankB && (a.length <= 1 || b.length <= 1)) continue;
      if (a.length != b.length) return false;
      for (var j = 0; j < a.length; j++) {
        if (a[j] != b[j]) return false;
      }
    }
    return true;
  }

  /// [rows] without the empty cells and rows typing past the edge of the
  /// file added and clearing emptied again.
  List<CsvRow> _used(List<CsvRow> rows) {
    var width = _readWidth;
    for (final row in rows) {
      for (var c = row.cells.length - 1; c >= width; c--) {
        if (row.cells[c].isNotEmpty) {
          width = c + 1;
          break;
        }
      }
    }
    var count = rows.length;
    while (count > _read.length && rows[count - 1].cells.every((c) => c.isEmpty)) {
      count--;
    }
    final out = <CsvRow>[
      for (var i = 0; i < count; i++)
        rows[i].cells.length > width
            ? rows[i].withCells(rows[i].cells.sublist(0, width), quoted: _quotedOf(rows[i], width))
            : rows[i],
    ];
    if (count < rows.length && out.isNotEmpty) out[out.length - 1] = out.last.withEnd(rows.last.end);
    return out;
  }

  static bool _sameCells(CsvRow a, CsvRow b) {
    if (identical(a, b)) return true;
    if (a.end != b.end || a.cells.length != b.cells.length) return false;
    for (var i = 0; i < a.cells.length; i++) {
      if (a.cells[i] != b.cells[i]) return false;
    }
    return true;
  }

  /// The same row but for empty cells at its end.
  static bool _sameRow(CsvRow a, CsvRow b) {
    if (identical(a, b)) return true;
    if (a.end != b.end) return false;
    final x = a.cells, y = b.cells;
    var n = x.length, m = y.length;
    while (n > m && x[n - 1].isEmpty) {
      n--;
    }
    while (m > n && y[m - 1].isEmpty) {
      m--;
    }
    if (n != m) return false;
    for (var i = 0; i < n; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  /// The characters a reader might take for the delimiter. A cell holding
  /// any of them is quoted, so the file reads back with the delimiter it
  /// was written with whichever one a reader guesses first.
  static const List<String> _delimiters = <String>[',', ';', '\t', '|'];

  String _format(CsvRow row, {bool always = false}) {
    // A row of one empty cell is written as an empty quoted cell, or it
    // would read back as a blank line with no cells at all.
    if (row.cells.length == 1 && row.cells.single.isEmpty) return '""';
    final parts = <String>[];
    for (var i = 0; i < row.cells.length; i++) {
      final value = row.cells[i];
      final needs = always ||
          _delimiters.any(value.contains) ||
          value.contains(delimiter) ||
          value.contains('"') ||
          value.contains('\n') ||
          value.contains('\r');
      parts.add(needs || row.wasQuoted(i) ? '"${value.replaceAll('"', '""')}"' : value);
    }
    return parts.join(delimiter);
  }

  String get _lastEnd => rows.isEmpty ? '' : rows.last.end;

  /// The last row, when it had no line ending, gets one before a row is put
  /// after it.
  void _endLast(List<CsvRow> list) {
    if (list.isEmpty || list.last.end.isNotEmpty) return;
    list[list.length - 1] = list.last.withEnd(newline);
  }

  static CsvRow _padded(CsvRow row, int width) {
    if (row.cells.length >= width) return row;
    return row.withCells(
      <String>[...row.cells, for (var i = row.cells.length; i < width; i++) ''],
      quoted: _quotedOf(row, width),
    );
  }

  static List<bool> _quotedOf(CsvRow row, int width) => <bool>[
        for (var i = 0; i < width; i++) row.wasQuoted(i),
      ];

  Uint8List _encode(String text) {
    switch (encoding) {
      case CsvEncoding.utf8:
        return Uint8List.fromList(utf8.encode(text));
      case CsvEncoding.utf8Bom:
        return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ..._utf8Escaped(text)]);
      case CsvEncoding.utf16le:
        return Uint8List.fromList(<int>[
          0xFF, 0xFE,
          for (final unit in text.codeUnits) ...<int>[unit & 0xff, unit >> 8],
          ..._tail,
        ]);
      case CsvEncoding.utf16be:
        return Uint8List.fromList(<int>[
          0xFE, 0xFF,
          for (final unit in text.codeUnits) ...<int>[unit >> 8, unit & 0xff],
          ..._tail,
        ]);
      case CsvEncoding.windows1252:
        // A character Windows-1252 cannot hold would be lost, and bytes that
        // happen to spell valid UTF-8 would be read back as it, so either is
        // written as UTF-8, marked as such.
        final bytes = encodeWindows1252(text);
        if (bytes != null && (!bytes.any((b) => b >= 0x80) || !_validUtf8(bytes))) return bytes;
        return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
    }
  }

  static bool _validUtf8(Uint8List bytes) {
    try {
      const Utf8Decoder(allowMalformed: false).convert(bytes);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// [text] as UTF-8, with every byte the file held that was not UTF-8
  /// written back as that byte.
  static List<int> _utf8Escaped(String text) {
    final out = <int>[];
    final units = text.codeUnits;
    var from = 0;
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      final lone = u >= 0xDC80 && u <= 0xDCFF && (i == 0 || units[i - 1] < 0xD800 || units[i - 1] > 0xDBFF);
      if (!lone) continue;
      out
        ..addAll(utf8.encode(text.substring(from, i)))
        ..add(u - 0xDC00);
      from = i + 1;
    }
    out.addAll(utf8.encode(text.substring(from)));
    return out;
  }

  /// UTF-8 read so nothing is lost: a byte that does not belong to a
  /// character is kept as a lone surrogate standing for that byte, the way
  /// Python's surrogateescape does, and written back as the byte.
  static String _utf8Lossless(List<int> b) {
    final out = StringBuffer();
    var i = 0;
    while (i < b.length) {
      final c = b[i];
      if (c < 0x80) {
        out.writeCharCode(c);
        i++;
        continue;
      }
      final (need, min) = c >= 0xC2 && c <= 0xDF
          ? (1, 0x80)
          : c >= 0xE0 && c <= 0xEF
              ? (2, 0x800)
              : c >= 0xF0 && c <= 0xF4
                  ? (3, 0x10000)
                  : (0, 0);
      var rune = need == 1 ? c & 0x1F : (need == 2 ? c & 0x0F : c & 0x07);
      var ok = need > 0 && i + need < b.length;
      for (var k = 1; ok && k <= need; k++) {
        if (i + k >= b.length || b[i + k] & 0xC0 != 0x80) {
          ok = false;
        } else {
          rune = (rune << 6) | (b[i + k] & 0x3F);
        }
      }
      if (ok && rune >= min && rune <= 0x10FFFF && (rune < 0xD800 || rune > 0xDFFF)) {
        out.writeCharCode(rune);
        i += need + 1;
      } else {
        out.writeCharCode(0xDC00 + c);
        i++;
      }
    }
    return out.toString();
  }

  static (String, CsvEncoding) _decode(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return (_utf8Lossless(bytes.sublist(3)), CsvEncoding.utf8Bom);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final units = <int>[
        for (var i = 2; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
      ];
      return (String.fromCharCodes(units), CsvEncoding.utf16le);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final units = <int>[
        for (var i = 2; i + 1 < bytes.length; i += 2) (bytes[i] << 8) | bytes[i + 1],
      ];
      return (String.fromCharCodes(units), CsvEncoding.utf16be);
    }
    try {
      return (const Utf8Decoder(allowMalformed: false).convert(bytes), CsvEncoding.utf8);
    } on FormatException {
      return (decodeWindows1252(bytes), CsvEncoding.windows1252);
    }
  }


  /// Rows with the text each was read from and what ended it.
  static List<CsvRow> _parse(String text, String delimiter) {
    final d = delimiter.codeUnitAt(0);
    final rows = <CsvRow>[];
    var cells = <String>[];
    var quoted = <bool>[];
    final field = StringBuffer();
    var inQuotes = false;
    var fieldQuoted = false;
    var start = 0;
    var i = 0;
    final n = text.length;

    void endField() {
      cells.add(field.toString());
      quoted.add(fieldQuoted);
      field.clear();
      fieldQuoted = false;
    }

    void endRow(int at, String end) {
      endField();
      rows.add(CsvRow(cells, quoted: quoted, raw: text.substring(start, at), end: end, open: inQuotes));
      cells = <String>[];
      quoted = <bool>[];
    }

    while (i < n) {
      final c = text.codeUnitAt(i);
      if (inQuotes) {
        if (c == 0x22) {
          if (i + 1 < n && text.codeUnitAt(i + 1) == 0x22) {
            field.writeCharCode(0x22);
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.writeCharCode(c);
        i++;
        continue;
      }
      if (c == 0x22 && field.isEmpty && !fieldQuoted) {
        inQuotes = true;
        fieldQuoted = true;
        i++;
        continue;
      }
      if (c == d) {
        endField();
        i++;
        continue;
      }
      if (c == 0x0D || c == 0x0A) {
        final crlf = c == 0x0D && i + 1 < n && text.codeUnitAt(i + 1) == 0x0A;
        final end = crlf ? '\r\n' : String.fromCharCode(c);
        endRow(i, end);
        i += end.length;
        start = i;
        continue;
      }
      field.writeCharCode(c);
      i++;
    }
    if (field.isNotEmpty || cells.isNotEmpty || fieldQuoted || start < n) {
      endRow(n, '');
    }
    return rows;
  }
}
