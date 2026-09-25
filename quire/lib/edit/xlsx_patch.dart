import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'ooxml_patch.dart';

/// A workbook opened for its cells to be changed.
///
/// A cell edited to a value holds that value and nothing else. A cell edited
/// to text beginning `=` holds that formula, with no value: quire never works
/// a formula out, because a reader that shows the values the file cached must
/// not start disagreeing with Excel about what a formula makes. The workbook
/// is marked to be calculated when it is next opened elsewhere, and until
/// then the reader shows such a cell by its formula.
class XlsxPatch {
  XlsxPatch(Uint8List bytes) : _package = OoxmlPackage(bytes) {
    const book = 'xl/workbook.xml';
    final workbook = _package.part(book);
    if (workbook == null) throw const FormatException('no workbook');
    final rels = _package.relationships(book);
    for (final sheet in workbook.rootElement.descendantElements
        .where((e) => e.name.local == 'sheet')) {
      final name = sheet.getAttribute('name');
      final rid = sheet.attributes
          .where((a) => a.name.local == 'id' && a.name.prefix == 'r')
          .firstOrNull
          ?.value;
      final part = rels[rid];
      if (name != null && part != null) _sheets[name] = part;
    }
  }

  final OoxmlPackage _package;
  final Map<String, String> _sheets = <String, String>{};

  /// The sheets by name, in workbook order.
  List<String> get sheetNames => _sheets.keys.toList();

  /// Puts [input] into cell [reference], such as `B4`, on [sheet].
  ///
  /// Text that reads as a number is stored as one, `TRUE` and `FALSE` as
  /// booleans, `=` followed by anything as a formula, empty as an empty
  /// cell, and anything else as text held in the cell itself.
  void setCell(String sheet, String reference, String input) {
    final part = _sheets[sheet];
    if (part == null) throw ArgumentError('no sheet called $sheet');
    final doc = _package.part(part);
    if (doc == null) throw ArgumentError('the sheet $sheet is not there');
    final at = _Ref.parse(reference);
    if (at == null) throw ArgumentError('$reference is not a cell');

    final root = doc.rootElement;
    final prefix = root.name.prefix;
    XmlName named(String local) => XmlName.parts(local, prefix: prefix);
    final data = root.childElements
        .where((e) => e.name.local == 'sheetData')
        .firstOrNull;
    if (data == null) throw const FormatException('a sheet with no data');

    final row = _rowFor(data, at.row, named);
    final cell = _cellFor(row, at, named);
    final style = cell.getAttribute('s');
    cell.children.clear();
    cell.attributes.removeWhere((a) => a.name.local != 'r' && a.name.local != 's');
    if (style != null && cell.getAttribute('s') == null) {
      cell.setAttribute('s', style);
    }

    final value = input.trim();
    if (value.isEmpty) {
      // Nothing, but the cell keeps its style, which is what a cleared cell
      // in a spreadsheet does.
    } else if (value.startsWith('=') && value.length > 1) {
      cell.children.add(XmlElement(named('f'), [], [XmlText(value.substring(1))]));
      _calculateOnOpen();
    } else if (_number.hasMatch(value)) {
      cell.children.add(XmlElement(named('v'), [], [XmlText(value)]));
    } else if (value.toUpperCase() == 'TRUE' || value.toUpperCase() == 'FALSE') {
      cell.setAttribute('t', 'b');
      cell.children.add(XmlElement(
        named('v'),
        [],
        [XmlText(value.toUpperCase() == 'TRUE' ? '1' : '0')],
      ));
    } else {
      cell.setAttribute('t', 'inlineStr');
      cell.children.add(XmlElement(named('is'), [], [
        XmlElement(
          named('t'),
          [XmlAttribute(XmlName.parts('space', prefix: 'xml'), 'preserve')],
          [XmlText(input)],
        ),
      ]));
    }
    // Anything that depended on this cell is out of date now.
    _calculateOnOpen();
    _package.touch(part);
  }

  Uint8List write() => _package.write();

  static final _number = RegExp(r'^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$');

  void _calculateOnOpen() {
    const book = 'xl/workbook.xml';
    final workbook = _package.part(book)!;
    final root = workbook.rootElement;
    var calc = root.childElements
        .where((e) => e.name.local == 'calcPr')
        .firstOrNull;
    if (calc == null) {
      calc = XmlElement(XmlName.parts('calcPr', prefix: root.name.prefix));
      // calcPr comes after the sheets and defined names and before what
      // follows them, which is where Excel looks for it.
      final after = root.childElements
          .where((e) => e.name.local == 'definedNames' || e.name.local == 'sheets')
          .lastOrNull;
      if (after != null) {
        root.children.insert(root.children.indexOf(after) + 1, calc);
      } else {
        root.children.add(calc);
      }
    }
    if (calc.getAttribute('fullCalcOnLoad') == '1') return;
    calc.setAttribute('fullCalcOnLoad', '1');
    _package.touch(book);
  }

  static XmlElement _rowFor(
    XmlElement data,
    int number,
    XmlName Function(String) named,
  ) {
    XmlElement? before;
    for (final row in data.childElements.where((e) => e.name.local == 'row')) {
      final r = int.tryParse(row.getAttribute('r') ?? '');
      if (r == number) return row;
      if (r != null && r > number) {
        before = row;
        break;
      }
    }
    final fresh = XmlElement(named('row'), [XmlAttribute(XmlName.parts('r'), '$number')]);
    if (before != null) {
      data.children.insert(data.children.indexOf(before), fresh);
    } else {
      data.children.add(fresh);
    }
    return fresh;
  }

  static XmlElement _cellFor(
    XmlElement row,
    _Ref at,
    XmlName Function(String) named,
  ) {
    XmlElement? before;
    for (final cell in row.childElements.where((e) => e.name.local == 'c')) {
      final ref = _Ref.parse(cell.getAttribute('r') ?? '');
      if (ref == null) continue;
      if (ref.column == at.column) return cell;
      if (ref.column > at.column) {
        before = cell;
        break;
      }
    }
    final fresh = XmlElement(named('c'), [XmlAttribute(XmlName.parts('r'), at.name)]);
    if (before != null) {
      row.children.insert(row.children.indexOf(before), fresh);
    } else {
      row.children.add(fresh);
    }
    return fresh;
  }
}

class _Ref {
  const _Ref(this.column, this.row, this.name);
  final int column;
  final int row;
  final String name;

  static _Ref? parse(String reference) {
    final m = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d{1,7})$').firstMatch(reference.trim());
    if (m == null) return null;
    var column = 0;
    for (final unit in m[1]!.toUpperCase().codeUnits) {
      column = column * 26 + unit - 64;
    }
    final row = int.parse(m[2]!);
    if (row < 1 || row > 1048576 || column > 16384) return null;
    return _Ref(column, row, '${m[1]!.toUpperCase()}$row');
  }
}
