import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/document.dart';
import 'formula_shift.dart';
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
    this.italic = false,
    this.color,
    this.background,
    this.align,
    this.wrap = false,
    this.vertical,
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
  final bool italic;
  final int? color;
  final int? background;
  final DocAlign? align;
  final bool wrap;
  final DocVerticalAlign? vertical;
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

  /// Rows and columns the file hides.
  final Set<int> hiddenRows = {};
  final Set<int> hiddenCols = {};

  /// What the sheet gives a column or a row it says nothing else about: a
  /// width in characters, as a column's own, and a height in points.
  double? defaultColWidth;
  double baseColWidth = 8;
  double? defaultRowHeight;

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
  final List<bool> _xfWrap = [];
  final List<DocVerticalAlign> _xfVertical = [];
  final List<bool> _fontBold = [];
  final List<bool> _fontItalic = [];
  final List<int?> _fontColor = [];
  final List<int?> _fillColor = [];
  bool _date1904 = false;

  /// The workbook's theme colours, in the order a cell's `theme` index
  /// counts them: the first two pairs, light then dark, come swapped from
  /// the order the theme part writes them in.
  final List<int> _theme = [];

  /// Formulas filled over a range, by their shared index: the formula and
  /// the cell it was written in.
  final Map<String, (String, int, int)> _sharedFormulas = {};

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
    _loadTheme();
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
    String? personsPath;
    final relXml = _text('xl/_rels/workbook.xml.rels');
    if (relXml != null) {
      for (final r in XmlDocument.parse(relXml).rootElement.childElements) {
        final id = _at(r, 'Id');
        final t = _at(r, 'Target');
        if (id != null && t != null) rels[id] = t;
        if (t != null && (_at(r, 'Type') ?? '').endsWith('/person')) {
          personsPath = t.startsWith('/')
              ? t.substring(1)
              : 'xl/${t.replaceAll('../', '')}';
        }
      }
    }
    final people = _people(personsPath);

    final sheetsEl = _kid(wb, 'sheets');
    if (sheetsEl == null) return XlsxWorkbook(sheets, date1904: _date1904);
    var fallbackIndex = 0;
    for (final s in sheetsEl.childElements) {
      fallbackIndex++;
      // A sheet the file hides is not one of the sheets it shows.
      final state = _at(s, 'state') ?? 'visible';
      if (state == 'hidden' || state == 'veryHidden') continue;
      final name = _at(s, 'name') ?? 'Sheet$fallbackIndex';
      final rid = _at(s, 'id');
      var target = rid == null ? null : rels[rid];
      target ??= 'worksheets/sheet$fallbackIndex.xml';
      final path = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceAll('../', '')}';
      final xml = _text(path);
      if (xml == null) continue;
      _sharedFormulas.clear();
      final sheet = _sheet(name, xml);
      _readNotes(sheet, path, people);
      sheets.add(sheet);
    }
    return XlsxWorkbook(sheets, date1904: _date1904);
  }

  /// Reads whatever has been said about the cells of [sheet].
  ///
  /// The comments live in a part of their own, found through the sheet's
  /// relationships. A file without them is the usual case and leaves the
  /// sheet exactly as it was.
  void _readNotes(
    SheetModel sheet,
    String sheetPath,
    Map<String, String> people,
  ) {
    final cut = sheetPath.lastIndexOf('/');
    if (cut < 0) return;
    final folder = sheetPath.substring(0, cut);
    final file = sheetPath.substring(cut + 1);
    final relXml = _text('$folder/_rels/$file.rels');
    if (relXml == null) return;
    String? target;
    String? threaded;
    for (final r in XmlDocument.parse(relXml).rootElement.childElements) {
      final type = _at(r, 'Type') ?? '';
      if (type.endsWith('/comments')) target = _at(r, 'Target');
      if (type.endsWith('/threadedComment')) threaded = _at(r, 'Target');
    }
    String partPath(String target) => target.startsWith('/')
        ? target.substring(1)
        : target.startsWith('../')
        ? 'xl/${target.replaceAll('../', '')}'
        : '$folder/$target';
    if (target != null) _readLegacyNotes(sheet, partPath(target));
    // A conversation held in current Excel is kept in a part of its own,
    // with the names of the people in it. Where there is one it is the real
    // discussion, and the plain note beside it is only Excel's notice that
    // older versions cannot edit it.
    if (threaded != null) _readThreads(sheet, partPath(threaded), people);
  }

  void _readLegacyNotes(SheetModel sheet, String path) {
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
      var author = who >= 0 && who < authors.length ? authors[who] : '';
      // Excel writes the author's name into the first line of the note as
      // well. Printing it twice would be the file's habit, not the reader's.
      if (author.isNotEmpty && text.startsWith('$author:')) {
        text = text.substring(author.length + 1).trim();
      }
      // A threaded comment's stand in: an author that is only an id, and a
      // notice before the words. The words are what is kept.
      if (author.startsWith('tc=')) author = '';
      if (text.startsWith('[Threaded comment]')) {
        final at = text.indexOf('Comment:');
        text = at < 0 ? '' : text.substring(at + 'Comment:'.length).trim();
      }
      if (text.isEmpty) continue;
      sheet.notes[ref] = SheetNote(author, text);
    }
  }

  /// The people a workbook's conversations name, by their id.
  Map<String, String> _people(String? path) {
    final people = <String, String>{};
    final xml = path == null ? null : _text(path);
    if (xml == null) return people;
    for (final p in XmlDocument.parse(xml).rootElement.childElements) {
      if (_ln(p) != 'person') continue;
      final id = _at(p, 'id');
      final name = _at(p, 'displayName');
      if (id != null && name != null) people[id] = name;
    }
    return people;
  }

  /// A sheet's conversations: the first comment on a cell, who made it, and
  /// the replies after it, each on a line of its own with who made it.
  void _readThreads(SheetModel sheet, String path, Map<String, String> people) {
    final xml = _text(path);
    if (xml == null) return;
    final opened = <String, (String, StringBuffer)>{};
    for (final c in XmlDocument.parse(xml).rootElement.childElements) {
      if (_ln(c) != 'threadedComment') continue;
      final ref = _at(c, 'ref')?.toUpperCase();
      if (ref == null) continue;
      final who = people[_at(c, 'personId') ?? ''] ?? '';
      final textEl = _kid(c, 'text');
      final said = (textEl?.innerText ?? '').trim();
      if (said.isEmpty) continue;
      final thread = opened[ref];
      if (thread == null || _at(c, 'parentId') == null) {
        if (thread == null) opened[ref] = (who, StringBuffer(said));
        continue;
      }
      thread.$2.write(who.isEmpty ? '\n$said' : '\n$who: $said');
    }
    for (final entry in opened.entries) {
      sheet.notes[entry.key] = SheetNote(
        entry.value.$1,
        entry.value.$2.toString(),
      );
    }
  }

  /// The theme's colours, from the theme part the workbook names.
  void _loadTheme() {
    final xml = _text('xl/theme/theme1.xml');
    if (xml == null) return;
    final scheme = XmlDocument.parse(
      xml,
    ).descendantElements.where((e) => _ln(e) == 'clrScheme').firstOrNull;
    if (scheme == null) return;
    final byName = <String, int>{};
    for (final slot in scheme.childElements) {
      for (final colour in slot.childElements) {
        final value = _ln(colour) == 'sysClr'
            ? _at(colour, 'lastClr')
            : _ln(colour) == 'srgbClr'
            ? _at(colour, 'val')
            : null;
        final argb = _argb(value);
        if (argb != null) byName[_ln(slot)] = argb;
      }
    }
    for (final name in const <String>[
      'lt1',
      'dk1',
      'lt2',
      'dk2',
      'accent1',
      'accent2',
      'accent3',
      'accent4',
      'accent5',
      'accent6',
      'hlink',
      'folHlink',
    ]) {
      _theme.add(byName[name] ?? 0xFF000000);
    }
  }

  /// A colour however the file states it: as red, green and blue, as one of
  /// the theme's colours lightened or darkened by a tint, or as one of the
  /// old sixty four indexed colours. Null for automatic.
  int? _colour(XmlElement? element) {
    if (element == null) return null;
    final rgb = _argb(_at(element, 'rgb'));
    if (rgb != null) return rgb;
    final tint = double.tryParse(_at(element, 'tint') ?? '') ?? 0;
    final theme = int.tryParse(_at(element, 'theme') ?? '');
    if (theme != null && theme >= 0 && theme < _theme.length) {
      return tinted(_theme[theme], tint);
    }
    final indexed = int.tryParse(_at(element, 'indexed') ?? '');
    if (indexed != null && indexed >= 0 && indexed < kIndexedColours.length) {
      return tinted(kIndexedColours[indexed], tint);
    }
    return null;
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
          final parentName = t.parentElement == null
              ? ''
              : _ln(t.parentElement!);
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
        _fontBold.add(_on(_kid(f, 'b')));
        _fontItalic.add(_on(_kid(f, 'i')));
        _fontColor.add(_colour(_kid(f, 'color')));
      }
    }
    final fills = _kid(root, 'fills');
    if (fills != null) {
      for (final f in fills.childElements) {
        final pf = _kid(f, 'patternFill');
        final fg = pf == null ? null : _kid(pf, 'fgColor');
        final type = pf == null ? 'none' : (_at(pf, 'patternType') ?? 'none');
        _fillColor.add(type == 'solid' ? _colour(fg) : null);
      }
    }
    final cellXfs = _kid(root, 'cellXfs');
    if (cellXfs != null) {
      for (final xf in cellXfs.childElements) {
        _xfNumFmtId.add(int.tryParse(_at(xf, 'numFmtId') ?? '0') ?? 0);
        _xfFontId.add(int.tryParse(_at(xf, 'fontId') ?? '0') ?? 0);
        _xfFillId.add(int.tryParse(_at(xf, 'fillId') ?? '0') ?? 0);
        final al = _kid(xf, 'alignment');
        _xfWrap.add(al != null && _flag(_at(al, 'wrapText')));
        // A spreadsheet sets words at the foot of a cell unless told
        // otherwise.
        _xfVertical.add(switch (al == null ? null : _at(al, 'vertical')) {
          'top' => DocVerticalAlign.top,
          'center' || 'justify' || 'distributed' => DocVerticalAlign.center,
          _ => DocVerticalAlign.bottom,
        });
        _xfAlign.add(
          al == null
              ? null
              : switch (_at(al, 'horizontal')) {
                  'center' || 'centerContinuous' => DocAlign.center,
                  'right' => DocAlign.end,
                  'justify' || 'distributed' => DocAlign.justify,
                  'left' => DocAlign.start,
                  _ => null,
                },
        );
      }
    }
  }

  /// A flag element such as `<b/>`: on unless it says `val="0"`.
  bool _on(XmlElement? flag) {
    if (flag == null) return false;
    final value = _at(flag, 'val');
    return value == null || _flag(value);
  }

  /// A flag attribute: on when present and not `0` or `false`.
  static bool _flag(String? value) =>
      value != null && value != '0' && value != 'false';

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
        if (pane != null && (_at(pane, 'state') ?? '').startsWith('frozen')) {
          m.frozenCols = (double.tryParse(_at(pane, 'xSplit') ?? '0') ?? 0)
              .toInt();
          m.frozenRows = (double.tryParse(_at(pane, 'ySplit') ?? '0') ?? 0)
              .toInt();
        }
      }
    }

    final format = _kid(root, 'sheetFormatPr');
    if (format != null) {
      m.defaultColWidth = double.tryParse(_at(format, 'defaultColWidth') ?? '');
      m.baseColWidth =
          double.tryParse(_at(format, 'baseColWidth') ?? '') ?? m.baseColWidth;
      m.defaultRowHeight = double.tryParse(
        _at(format, 'defaultRowHeight') ?? '',
      );
    }

    final cols = _kid(root, 'cols');
    if (cols != null) {
      for (final c in cols.childElements) {
        final min = int.tryParse(_at(c, 'min') ?? '');
        final max = int.tryParse(_at(c, 'max') ?? '');
        if (min == null || max == null) continue;
        final w = double.tryParse(_at(c, 'width') ?? '');
        final hidden = _at(c, 'hidden') == '1' || _at(c, 'hidden') == 'true';
        for (var i = min; i <= max && i <= min + 4096; i++) {
          if (w != null) m.colWidths[i - 1] = w;
          if (hidden) m.hiddenCols.add(i - 1);
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
        final hidden = _at(row, 'hidden');
        if ((hidden == '1' || hidden == 'true') && rIdx >= 0) {
          m.hiddenRows.add(rIdx);
        }
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
    var formula = fEl?.innerText;
    // A formula filled down or across is written once, on the first cell of
    // the range, and every other cell of it holds only a pointer back. What
    // such a cell holds is that formula moved to where the cell is.
    if (fEl != null && _at(fEl, 't') == 'shared') {
      final index = _at(fEl, 'si') ?? '';
      if (formula != null && formula.isNotEmpty) {
        _sharedFormulas[index] = (formula, row, col);
      } else {
        final first = _sharedFormulas[index];
        formula = first == null
            ? null
            : shiftFormula(first.$1, row - first.$2, col - first.$3);
      }
    }
    if (formula != null && formula.isEmpty) formula = null;
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

    final fillId = styleIndex >= 0 && styleIndex < _xfFillId.length
        ? _xfFillId[styleIndex]
        : 0;
    final background = fillId < _fillColor.length ? _fillColor[fillId] : null;
    if (raw == null && formula == null) {
      // An empty cell still wears the fill the file gave it.
      if (background == null) return null;
      return SheetCell(
        ref: ref.toUpperCase(),
        row: row,
        col: col,
        kind: CellKind.blank,
        numFmt: code,
        background: background,
      );
    }

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
      italic: fontId < _fontItalic.length && _fontItalic[fontId],
      wrap:
          styleIndex >= 0 && styleIndex < _xfWrap.length && _xfWrap[styleIndex],
      vertical: styleIndex >= 0 && styleIndex < _xfVertical.length
          ? _xfVertical[styleIndex]
          : DocVerticalAlign.bottom,
      // A colour the number format gives this value, `[Red]` on a negative,
      // outranks the font's, as it does in the program that wrote it.
      color:
          formatColour(raw, code, palette: kIndexedColours) ??
          (fontId < _fontColor.length ? _fontColor[fontId] : null),
      background: background,
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
    // A cell somebody commented on is a cell, even with nothing in it.
    var rowCount = s.grid.length;
    var columnCount = s.maxCol + 1;
    for (final ref in s.notes.keys) {
      final (r, c) = XlsxParser.refToRowCol(ref);
      if (r + 1 > rowCount) rowCount = r + 1;
      if (c + 1 > columnCount) columnCount = c + 1;
    }
    final rows = <DocRow>[];
    for (var r = 0; r < rowCount; r++) {
      final cells = <DocCell>[];
      for (var c = 0; c < columnCount; c++) {
        final key = '$r:$c';
        if (continuation.contains(key)) {
          cells.add(const DocCell([], merged: true));
          continue;
        }
        final sc = r < s.grid.length && c < s.grid[r].length
            ? s.grid[r][c]
            : null;
        final note = s.notes['${XlsxParser.colName(c)}${r + 1}'];
        final span = mergedAt[key];
        final numeric =
            sc != null &&
            (sc.kind == CellKind.number || sc.kind == CellKind.date);
        cells.add(
          DocCell(
            [
              ParagraphBlock([
                DocSpan(
                  sc?.formatted ?? '',
                  bold: sc?.bold ?? false,
                  italic: sc?.italic ?? false,
                  color: sc?.color,
                ),
              ], align: sc?.align ?? (numeric ? DocAlign.end : DocAlign.start)),
            ],
            colSpan: span == null ? 1 : span[3] - span[1] + 1,
            rowSpan: span == null ? 1 : span[2] - span[0] + 1,
            background: sc?.background,
            numeric: numeric,
            align: sc?.align ?? (numeric ? DocAlign.end : DocAlign.start),
            raw: sc?.raw,
            formula: sc?.formula,
            comment: note?.text,
            commentBy: note?.author,
            wrap: sc?.wrap ?? false,
            verticalAlign: sc?.vertical ?? DocVerticalAlign.bottom,
          ),
        );
      }
      final points = s.rowHeights[r];
      rows.add(
        DocRow(
          cells,
          header: r < s.frozenRows,
          height: s.hiddenRows.contains(r)
              ? 0
              : points == null
              ? null
              : points * kPixelsPerPoint,
        ),
      );
    }
    final columns = <DocColumn>[];
    for (var c = 0; c < columnCount; c++) {
      final w = s.colWidths[c];
      columns.add(
        DocColumn(
          width: s.hiddenCols.contains(c)
              ? 0
              : w == null
              ? null
              : columnPixels(w),
        ),
      );
    }
    final defaultWidth = s.defaultColWidth;
    sections.add(
      DocSection(s.name, [
        TableBlock(
          rows,
          columns: columns,
          frozenRows: s.frozenRows,
          frozenColumns: s.frozenCols,
          grid: true,
          defaultColumnWidth: defaultWidth == null
              ? defaultColumnPixels(s.baseColWidth)
              : columnPixels(defaultWidth),
          defaultRowHeight: s.defaultRowHeight == null
              ? null
              : s.defaultRowHeight! * kPixelsPerPoint,
        ),
      ], kind: 'sheet'),
    );
  }
  return QuireDocument(
    title: title,
    sections: sections,
    sourceFormat: 'xlsx',
    outline: [
      for (var i = 0; i < sections.length; i++)
        OutlineEntry(sections[i].title, 1, i, 0),
    ],
  );
}

/// How many of a sheet's own measuring points a typographic point of row
/// height is: a sheet measures at 96 to the inch and type at 72.
const kPixelsPerPoint = 96 / 72;

/// A column width in characters as a sheet draws it: characters of the
/// widest digit at the default font, seven points each, with the width's own
/// rounding.
double columnPixels(double characters) =>
    ((256 * characters + (128 / 7).truncate()) / 256 * 7).truncateToDouble();

/// The width of a column nothing is said about, from the sheet's base width
/// in characters: that many digits, the padding either side and the rule,
/// rounded up to the next eight, which is how a plain column comes to be 64.
double defaultColumnPixels(double baseCharacters) =>
    ((baseCharacters * 7 + 5) / 8).ceil() * 8.0;

/// A colour lightened towards white by a positive [tint] or darkened towards
/// black by a negative one, in lightness rather than in each channel, which
/// is how a theme's paler and deeper shades are made.
int tinted(int argb, double tint) {
  if (tint == 0) return argb;
  final r = ((argb >> 16) & 0xFF) / 255;
  final g = ((argb >> 8) & 0xFF) / 255;
  final b = (argb & 0xFF) / 255;
  final most = [r, g, b].reduce((a, c) => a > c ? a : c);
  final least = [r, g, b].reduce((a, c) => a < c ? a : c);
  var l = (most + least) / 2;
  var h = 0.0;
  var s = 0.0;
  if (most != least) {
    final d = most - least;
    s = l > 0.5 ? d / (2 - most - least) : d / (most + least);
    if (most == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (most == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6;
  }
  l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint;
  double channel(double p, double q, double t) {
    var x = t;
    if (x < 0) x += 1;
    if (x > 1) x -= 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  }

  double nr, ng, nb;
  if (s == 0) {
    nr = ng = nb = l;
  } else {
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    nr = channel(p, q, h + 1 / 3);
    ng = channel(p, q, h);
    nb = channel(p, q, h - 1 / 3);
  }
  int byte(double v) => (v.clamp(0.0, 1.0) * 255).round();
  return (argb & 0xFF000000) | (byte(nr) << 16) | (byte(ng) << 8) | byte(nb);
}

/// The sixty four colours a file may still name by number, as every
/// spreadsheet since the first has kept them.
const kIndexedColours = <int>[
  0xFF000000,
  0xFFFFFFFF,
  0xFFFF0000,
  0xFF00FF00,
  0xFF0000FF,
  0xFFFFFF00,
  0xFFFF00FF,
  0xFF00FFFF,
  0xFF000000,
  0xFFFFFFFF,
  0xFFFF0000,
  0xFF00FF00,
  0xFF0000FF,
  0xFFFFFF00,
  0xFFFF00FF,
  0xFF00FFFF,
  0xFF800000,
  0xFF008000,
  0xFF000080,
  0xFF808000,
  0xFF800080,
  0xFF008080,
  0xFFC0C0C0,
  0xFF808080,
  0xFF9999FF,
  0xFF993366,
  0xFFFFFFCC,
  0xFFCCFFFF,
  0xFF660066,
  0xFFFF8080,
  0xFF0066CC,
  0xFFCCCCFF,
  0xFF000080,
  0xFFFF00FF,
  0xFFFFFF00,
  0xFF00FFFF,
  0xFF800080,
  0xFF800000,
  0xFF008080,
  0xFF0000FF,
  0xFF00CCFF,
  0xFFCCFFFF,
  0xFFCCFFCC,
  0xFFFFFF99,
  0xFF99CCFF,
  0xFFFF99CC,
  0xFFCC99FF,
  0xFFFFCC99,
  0xFF3366FF,
  0xFF33CCCC,
  0xFF99CC00,
  0xFFFFCC00,
  0xFFFF9900,
  0xFFFF6600,
  0xFF666699,
  0xFF969696,
  0xFF003366,
  0xFF339966,
  0xFF003300,
  0xFF333300,
  0xFF993300,
  0xFF993366,
  0xFF333399,
  0xFF333333,
];
