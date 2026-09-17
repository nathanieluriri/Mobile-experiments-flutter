import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/document.dart';
import 'number_format.dart';

/// What a worksheet cell actually holds, before any formatting is applied.
///
/// The distinction between [number] and [date] is not cosmetic: the same
/// stored double means 45000 or a Tuesday depending only on the cell's number
/// format, so the kind has to be decided while the format code is in hand.
enum CellKind { blank, number, text, date, boolean, error, formulaText }

/// One worksheet cell: what it stores, what it displays, and how it got there.
class SheetCell {
  const SheetCell({
    required this.ref,
    required this.row,
    required this.col,
    required this.kind,
    this.raw,
    this.formatted = '',
    this.formula,
    this.numFmt = 'General',
    this.bold = false,
    this.color,
    this.background,
    this.align,
  });
  final String ref;
  final int row; // 0 based
  final int col; // 0 based
  final CellKind kind;
  final Object? raw; // num | String | bool | DateTime
  final String formatted;
  final String? formula;
  final String numFmt;
  final bool bold;
  final int? color;
  final int? background;
  final DocAlign? align;
}

/// One worksheet: its cells by reference, a dense grid, and the geometry the
/// spine table needs (widths, heights, merges, frozen panes).
class SheetModel {
  SheetModel(this.name);
  final String name;
  final Map<String, SheetCell> byRef = {};
  final List<List<SheetCell?>> grid = [];
  final Map<int, double> colWidths = {}; // col index -> characters
  final Map<int, double> rowHeights = {}; // row index -> points
  final List<List<int>> merges = []; // [r1, c1, r2, c2]

  /// What has been said about a cell, by reference: `B2` to the discussion
  /// held on it.
  final Map<String, SheetNote> notes = {};
  int frozenRows = 0;
  int frozenCols = 0;
  int maxCol = 0;

  SheetCell? cell(String a1) => byRef[a1.toUpperCase()];
}

/// One discussion held on a cell: who said it, and what they said.
class SheetNote {
  const SheetNote(this.author, this.text);
  final String author;
  final String text;
}

/// A parsed workbook. [date1904] belongs here rather than on a sheet because
/// it is a whole file property and every serial in every sheet depends on it.
class XlsxWorkbook {
  XlsxWorkbook(this.sheets, {this.date1904 = false});
  final List<SheetModel> sheets;
  final bool date1904;
}

/// Pure Dart .xlsx reader.
///
/// It reads the cached value a cell carries rather than evaluating its
/// formula, because the file already holds the answer the spreadsheet computed
/// and recomputing it would mean shipping a formula engine that could disagree
/// with the source.
class XlsxParser {
  XlsxParser(this.bytes);
  final Uint8List bytes;

  late Archive _zip;
  final List<String> _shared = [];
  final Map<int, String> _numFmts = {}; // numFmtId -> code
  final List<int> _xfNumFmtId = [];
  final List<int> _xfFontId = [];
  final List<int> _xfFillId = [];
  final List<DocAlign?> _xfAlign = [];
  final List<bool> _fontBold = [];
  final List<int?> _fontColor = [];
  final List<int?> _fillColor = [];
  bool _date1904 = false;

  static String _ln(XmlElement e) => e.name.local;
  static String? _at(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  XmlElement? _kid(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (_ln(c) == local) return c;
    }
    return null;
  }

  String? _text(String path) {
    for (final f in _zip.files) {
      if (f.name == path && f.isFile) {
        return utf8.decode(f.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }

  /// "BC12" -> (row 11, col 54)
  static (int, int) refToRowCol(String ref) {
    var col = 0;
    var i = 0;
    while (i < ref.length) {
      final c = ref.codeUnitAt(i);
      if (c >= 65 && c <= 90) {
        col = col * 26 + (c - 64);
        i++;
      } else if (c >= 97 && c <= 122) {
        col = col * 26 + (c - 96);
        i++;
      } else {
        break;
      }
    }
    final row = int.tryParse(ref.substring(i)) ?? 1;
    return (row - 1, col - 1);
  }

  static String colName(int col) {
    var c = col + 1;
    final sb = StringBuffer();
    while (c > 0) {
      final rem = (c - 1) % 26;
      sb.write(String.fromCharCode(65 + rem));
      c = (c - 1) ~/ 26;
    }
    return String.fromCharCodes(sb.toString().codeUnits.reversed);
  }

  XlsxWorkbook parse() {
    _zip = ZipDecoder().decodeBytes(bytes);
    _loadSharedStrings();
    _loadStyles();
    final sheets = <SheetModel>[];

    final wbXml = _text('xl/workbook.xml');
    if (wbXml == null) throw const FormatException('no xl/workbook.xml');
    final wb = XmlDocument.parse(wbXml).rootElement;
    final wbPr = _kid(wb, 'workbookPr');
    if (wbPr != null) {
      final d = _at(wbPr, 'date1904');
      _date1904 = d == '1' || d == 'true';
    }

    final rels = <String, String>{};
    final relXml = _text('xl/_rels/workbook.xml.rels');
    if (relXml != null) {
      for (final r in XmlDocument.parse(relXml).rootElement.childElements) {
        final id = _at(r, 'Id');
        final t = _at(r, 'Target');
        if (id != null && t != null) rels[id] = t;
      }
    }

    final sheetsEl = _kid(wb, 'sheets');
    if (sheetsEl == null) return XlsxWorkbook(sheets, date1904: _date1904);
    var fallbackIndex = 0;
    for (final s in sheetsEl.childElements) {
      fallbackIndex++;
      final name = _at(s, 'name') ?? 'Sheet$fallbackIndex';
      final rid = _at(s, 'id');
      var target = rid == null ? null : rels[rid];
      target ??= 'worksheets/sheet$fallbackIndex.xml';
      final path = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceAll('../', '')}';
      final xml = _text(path);
      if (xml == null) continue;
      final sheet = _sheet(name, xml);
      _readNotes(sheet, path);
      sheets.add(sheet);
    }
    return XlsxWorkbook(sheets, date1904: _date1904);
  }

  /// Reads whatever has been said about the cells of [sheet].
  ///
  /// The comments live in a part of their own, found through the sheet's
  /// relationships. A file without them is the usual case and leaves the
  /// sheet exactly as it was.
  void _readNotes(SheetModel sheet, String sheetPath) {
    final cut = sheetPath.lastIndexOf('/');
    if (cut < 0) return;
    final folder = sheetPath.substring(0, cut);
    final file = sheetPath.substring(cut + 1);
    final relXml = _text('$folder/_rels/$file.rels');
    if (relXml == null) return;
    String? target;
    for (final r in XmlDocument.parse(relXml).rootElement.childElements) {
      final type = _at(r, 'Type') ?? '';
      if (!type.endsWith('/comments')) continue;
      target = _at(r, 'Target');
    }
    if (target == null) return;
    final path = target.startsWith('/')
        ? target.substring(1)
        : target.startsWith('../')
            ? 'xl/${target.replaceAll('../', '')}'
            : '$folder/$target';
    final xml = _text(path);
    if (xml == null) return;
    final root = XmlDocument.parse(xml).rootElement;
    final authors = <String>[];
    final authorsEl = _kid(root, 'authors');
    if (authorsEl != null) {
      for (final a in authorsEl.childElements) {
        authors.add(a.innerText.trim());
      }
    }
    final list = _kid(root, 'commentList');
    if (list == null) return;
    for (final c in list.childElements) {
      if (_ln(c) != 'comment') continue;
      final ref = _at(c, 'ref')?.toUpperCase();
      if (ref == null) continue;
      final who = int.tryParse(_at(c, 'authorId') ?? '') ?? -1;
      final said = StringBuffer();
      for (final t in c.descendantElements) {
        if (_ln(t) == 't') said.write(t.innerText);
      }
      var text = said.toString().trim();
      final author = who >= 0 && who < authors.length ? authors[who] : '';
      // Excel writes the author's name into the first line of the note as
      // well. Printing it twice would be the file's habit, not the reader's.
      if (author.isNotEmpty && text.startsWith('$author:')) {
        text = text.substring(author.length + 1).trim();
      }
      if (text.isEmpty) continue;
      sheet.notes[ref] = SheetNote(author, text);
    }
  }

  void _loadSharedStrings() {
    final xml = _text('xl/sharedStrings.xml');
    if (xml == null) return;
    for (final si in XmlDocument.parse(xml).rootElement.childElements) {
      if (_ln(si) != 'si') continue;
      // Concatenate all <t> under this <si>, skipping ruby phonetics.
      final sb = StringBuffer();
      for (final t in si.descendantElements) {
        if (_ln(t) == 't') {
          final parentName = t.parentElement == null ? '' : _ln(t.parentElement!);
          if (parentName == 'rPh') continue;
          sb.write(t.innerText);
        }
      }
      _shared.add(sb.toString());
    }
  }

  static int? _argb(String? v) {
    if (v == null) return null;
    if (v.length == 8) return int.tryParse(v, radix: 16);
    if (v.length == 6) {
      final n = int.tryParse(v, radix: 16);
      return n == null ? null : 0xFF000000 | n;
    }
    return null;
  }

  void _loadStyles() {
    final xml = _text('xl/styles.xml');
    if (xml == null) return;
    final root = XmlDocument.parse(xml).rootElement;

    final numFmts = _kid(root, 'numFmts');
    if (numFmts != null) {
      for (final n in numFmts.childElements) {
        final id = int.tryParse(_at(n, 'numFmtId') ?? '');
        final code = _at(n, 'formatCode');
        if (id != null && code != null) _numFmts[id] = code;
      }
    }
    final fonts = _kid(root, 'fonts');
    if (fonts != null) {
      for (final f in fonts.childElements) {
        _fontBold.add(_kid(f, 'b') != null);
        final c = _kid(f, 'color');
        _fontColor.add(c == null ? null : _argb(_at(c, 'rgb')));
      }
    }
    final fills = _kid(root, 'fills');
    if (fills != null) {
      for (final f in fills.childElements) {
        final pf = _kid(f, 'patternFill');
        final fg = pf == null ? null : _kid(pf, 'fgColor');
        final type = pf == null ? 'none' : (_at(pf, 'patternType') ?? 'none');
        _fillColor.add(type == 'solid' && fg != null ? _argb(_at(fg, 'rgb')) : null);
      }
    }
    final cellXfs = _kid(root, 'cellXfs');
    if (cellXfs != null) {
      for (final xf in cellXfs.childElements) {
        _xfNumFmtId.add(int.tryParse(_at(xf, 'numFmtId') ?? '0') ?? 0);
        _xfFontId.add(int.tryParse(_at(xf, 'fontId') ?? '0') ?? 0);
        _xfFillId.add(int.tryParse(_at(xf, 'fillId') ?? '0') ?? 0);
        final al = _kid(xf, 'alignment');
        _xfAlign.add(al == null
            ? null
            : switch (_at(al, 'horizontal')) {
                'center' || 'centerContinuous' => DocAlign.center,
                'right' => DocAlign.end,
                'justify' || 'distributed' => DocAlign.justify,
                'left' => DocAlign.start,
                _ => null,
              });
      }
    }
  }

  String _numFmtCode(int styleIndex) {
    if (styleIndex < 0 || styleIndex >= _xfNumFmtId.length) return 'General';
    final id = _xfNumFmtId[styleIndex];
    return _numFmts[id] ?? kBuiltinNumFmts[id] ?? 'General';
  }

  SheetModel _sheet(String name, String xml) {
    final m = SheetModel(name);
    final root = XmlDocument.parse(xml).rootElement;

    final views = _kid(root, 'sheetViews');
    if (views != null) {
      for (final v in views.childElements) {
        final pane = _kid(v, 'pane');
        if (pane != null && (_at(pane, 'state') ?? '') .startsWith('frozen')) {
          m.frozenCols = (double.tryParse(_at(pane, 'xSplit') ?? '0') ?? 0).toInt();
          m.frozenRows = (double.tryParse(_at(pane, 'ySplit') ?? '0') ?? 0).toInt();
        }
      }
    }

    final cols = _kid(root, 'cols');
    if (cols != null) {
      for (final c in cols.childElements) {
        final min = int.tryParse(_at(c, 'min') ?? '');
        final max = int.tryParse(_at(c, 'max') ?? '');
        final w = double.tryParse(_at(c, 'width') ?? '');
        if (min == null || max == null || w == null) continue;
        for (var i = min; i <= max && i <= min + 4096; i++) {
          m.colWidths[i - 1] = w;
        }
      }
    }

    final data = _kid(root, 'sheetData');
    if (data != null) {
      for (final row in data.childElements) {
        if (_ln(row) != 'row') continue;
        final rIdx = (int.tryParse(_at(row, 'r') ?? '') ?? 0) - 1;
        final ht = double.tryParse(_at(row, 'ht') ?? '');
        if (ht != null && rIdx >= 0) m.rowHeights[rIdx] = ht;
        for (final c in row.childElements) {
          if (_ln(c) != 'c') continue;
          final cell = _cell(c, rIdx);
          if (cell == null) continue;
          m.byRef[cell.ref] = cell;
          if (cell.col > m.maxCol) m.maxCol = cell.col;
        }
      }
    }

    final merges = _kid(root, 'mergeCells');
    if (merges != null) {
      for (final mc in merges.childElements) {
        final ref = _at(mc, 'ref');
        if (ref == null || !ref.contains(':')) continue;
        final parts = ref.split(':');
        final (r1, c1) = refToRowCol(parts[0]);
        final (r2, c2) = refToRowCol(parts[1]);
        m.merges.add([r1, c1, r2, c2]);
      }
    }

    // Materialise a dense grid.
    var maxRow = 0;
    for (final c in m.byRef.values) {
      if (c.row > maxRow) maxRow = c.row;
    }
    for (var r = 0; r <= maxRow; r++) {
      m.grid.add(List<SheetCell?>.filled(m.maxCol + 1, null));
    }
    for (final c in m.byRef.values) {
      if (c.row < m.grid.length && c.col < m.grid[c.row].length) {
        m.grid[c.row][c.col] = c;
      }
    }
    return m;
  }

  SheetCell? _cell(XmlElement c, int rowIdx) {
    var ref = _at(c, 'r');
    int row, col;
    if (ref == null) {
      return null;
    }
    (row, col) = refToRowCol(ref);
    if (row < 0) row = rowIdx;
    final type = _at(c, 't') ?? 'n';
    final styleIndex = int.tryParse(_at(c, 's') ?? '') ?? -1;
    final code = _numFmtCode(styleIndex);

    final fEl = _kid(c, 'f');
    final formula = fEl?.innerText;
    final vEl = _kid(c, 'v');
    final isEl = _kid(c, 'is');

    Object? raw;
    CellKind kind;
    switch (type) {
      case 's':
        final i = int.tryParse(vEl?.innerText ?? '');
        raw = (i != null && i < _shared.length) ? _shared[i] : '';
        kind = CellKind.text;
      case 'inlineStr':
        final sb = StringBuffer();
        if (isEl != null) {
          for (final t in isEl.descendantElements) {
            if (_ln(t) == 't') sb.write(t.innerText);
          }
        }
        raw = sb.toString();
        kind = CellKind.text;
      case 'str':
        raw = vEl?.innerText ?? '';
        kind = CellKind.formulaText;
      case 'b':
        raw = (vEl?.innerText ?? '0') == '1';
        kind = CellKind.boolean;
      case 'e':
        raw = vEl?.innerText ?? '#N/A';
        kind = CellKind.error;
      case 'd':
        raw = DateTime.tryParse(vEl?.innerText ?? '');
        kind = CellKind.date;
      default:
        final txt = vEl?.innerText;
        if (txt == null || txt.isEmpty) {
          raw = null;
          kind = CellKind.blank;
        } else {
          final n = num.tryParse(txt);
          raw = n;
          kind = isDateFormat(code) ? CellKind.date : CellKind.number;
        }
    }

    if (raw == null && formula == null) return null;

    String formatted;
    if (kind == CellKind.date && raw is num) {
      formatted = formatCell(raw, code, date1904: _date1904);
    } else if (kind == CellKind.date && raw is DateTime) {
      formatted = raw.toIso8601String().split('T').first;
    } else if (kind == CellKind.boolean) {
      formatted = (raw as bool) ? 'TRUE' : 'FALSE';
    } else if (kind == CellKind.error) {
      formatted = raw as String;
    } else if (raw is num) {
      formatted = formatCell(raw, code, date1904: _date1904);
    } else {
      formatted = raw?.toString() ?? '';
    }

    final fontId = styleIndex >= 0 && styleIndex < _xfFontId.length
        ? _xfFontId[styleIndex]
        : 0;
    final fillId = styleIndex >= 0 && styleIndex < _xfFillId.length
        ? _xfFillId[styleIndex]
        : 0;

    return SheetCell(
      ref: ref.toUpperCase(),
      row: row,
      col: col,
      kind: kind,
      raw: kind == CellKind.date && raw is num
          ? excelSerialToDate(raw, date1904: _date1904)
          : raw,
      formatted: formatted,
      formula: formula,
      numFmt: code,
      bold: fontId < _fontBold.length && _fontBold[fontId],
      color: fontId < _fontColor.length ? _fontColor[fontId] : null,
      background: fillId < _fillColor.length ? _fillColor[fillId] : null,
      align: styleIndex >= 0 && styleIndex < _xfAlign.length
          ? _xfAlign[styleIndex]
          : null,
    );
  }
}

/// Bridges a workbook into the shared model: one section per sheet, one grid
/// [TableBlock] each, with every cell keeping its cached value and its formula
/// so the front and the back of a sheet can show different truths.
QuireDocument xlsxToDocument(XlsxWorkbook wb, String title) {
  final sections = <DocSection>[];
  for (final s in wb.sheets) {
    final mergedAt = <String, List<int>>{};
    final continuation = <String>{};
    for (final m in s.merges) {
      mergedAt['${m[0]}:${m[1]}'] = m;
      for (var r = m[0]; r <= m[2]; r++) {
        for (var c = m[1]; c <= m[3]; c++) {
          if (r == m[0] && c == m[1]) continue;
          continuation.add('$r:$c');
        }
      }
    }
    final rows = <DocRow>[];
    for (var r = 0; r < s.grid.length; r++) {
      final cells = <DocCell>[];
      for (var c = 0; c < s.grid[r].length; c++) {
        final key = '$r:$c';
        if (continuation.contains(key)) {
          cells.add(const DocCell([], merged: true));
          continue;
        }
        final sc = s.grid[r][c];
        final span = mergedAt[key];
        final numeric = sc != null &&
            (sc.kind == CellKind.number || sc.kind == CellKind.date);
        cells.add(DocCell(
          [
            ParagraphBlock([
              DocSpan(
                sc?.formatted ?? '',
                bold: sc?.bold ?? false,
                color: sc?.color,
              )
            ], align: sc?.align ?? (numeric ? DocAlign.end : DocAlign.start))
          ],
          colSpan: span == null ? 1 : span[3] - span[1] + 1,
          rowSpan: span == null ? 1 : span[2] - span[0] + 1,
          background: sc?.background,
          numeric: numeric,
          align: sc?.align ?? (numeric ? DocAlign.end : DocAlign.start),
          raw: sc?.raw,
          formula: sc?.formula,
          comment: sc == null ? null : s.notes[sc.ref]?.text,
          commentBy: sc == null ? null : s.notes[sc.ref]?.author,
        ));
      }
      rows.add(DocRow(cells,
          header: r < s.frozenRows, height: s.rowHeights[r]));
    }
    final columns = <DocColumn>[];
    for (var c = 0; c <= s.maxCol; c++) {
      final w = s.colWidths[c];
      // Excel width is in "characters"; ~7px per character at default font.
      columns.add(DocColumn(width: w == null ? null : w * 7.0));
    }
    sections.add(DocSection(
      s.name,
      [
        TableBlock(rows,
            columns: columns,
            frozenRows: s.frozenRows,
            frozenColumns: s.frozenCols,
            grid: true)
      ],
      kind: 'sheet',
    ));
  }
  return QuireDocument(
    title: title,
    sections: sections,
    sourceFormat: 'xlsx',
    outline: [
      for (var i = 0; i < sections.length; i++)
        OutlineEntry(sections[i].title, 1, i, 0)
    ],
  );
}
