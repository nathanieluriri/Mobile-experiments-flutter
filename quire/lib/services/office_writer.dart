import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/document.dart';

/// Writes the two Office packages quire can produce honestly.
///
/// Both are zip containers of XML, and both are written by hand rather than
/// through a builder, because what makes a package open elsewhere is the exact
/// set of parts and relationships it carries, and that is worth reading in one
/// place rather than assembling out of calls.
///
/// Neither writer produces styling. A spreadsheet gets values and a header row
/// in bold; a Word file gets paragraphs and headings. Anything richer would be
/// this app guessing at a design the source never stated.

/// One sheet of a workbook being written.
class SheetOut {
  const SheetOut(this.name, this.rows);

  /// The tab's name. Excel refuses several characters and anything over 31
  /// letters, so [_sheetName] is what actually reaches the file.
  final String name;

  /// The cells, row by row. A row may be shorter than the one above it.
  final List<List<String>> rows;
}

/// A workbook holding [sheets], as the bytes of an xlsx file.
Uint8List writeXlsx(List<SheetOut> sheets) {
  final named = <String>{};
  final out = <SheetOut>[
    for (var i = 0; i < sheets.length; i++)
      SheetOut(_freeSheetName(sheets[i].name, i, named), sheets[i].rows),
  ];
  if (out.isEmpty) {
    out.add(const SheetOut('Sheet1', <List<String>>[]));
  }
  final archive = Archive();
  void put(String path, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  put('[Content_Types].xml', _contentTypes(out.length));
  put('_rels/.rels', _rootRels);
  put('xl/workbook.xml', _workbook(out));
  put('xl/_rels/workbook.xml.rels', _workbookRels(out.length));
  for (var i = 0; i < out.length; i++) {
    put('xl/worksheets/sheet${i + 1}.xml', _sheet(out[i].rows));
  }
  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped);
}

/// A Word file holding [document]'s paragraphs and headings.
Uint8List writeDocx(QuireDocument document) {
  final archive = Archive();
  void put(String path, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  put('[Content_Types].xml', _docxContentTypes);
  put('_rels/.rels', _docxRootRels);
  put('word/document.xml', _docxBody(document));
  put('word/styles.xml', _docxStyles);
  put('word/_rels/document.xml.rels', _docxDocumentRels);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

// ---------------------------------------------------------------------------
// The spreadsheet.

/// Excel's own rules: no `[ ] : * ? / \`, at most 31 characters, and no two
/// sheets sharing a name.
String _freeSheetName(String wanted, int index, Set<String> taken) {
  var name = wanted.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (name.isEmpty) name = 'Sheet${index + 1}';
  if (name.length > 31) name = name.substring(0, 31);
  var unique = name;
  var n = 2;
  while (!taken.add(unique.toLowerCase())) {
    final tail = ' $n';
    final head = name.length + tail.length > 31
        ? name.substring(0, 31 - tail.length)
        : name;
    unique = '$head$tail';
    n++;
  }
  return unique;
}

String _contentTypes(int sheets) {
  final parts = StringBuffer();
  for (var i = 1; i <= sheets; i++) {
    parts.write(
      '<Override PartName="/xl/worksheets/sheet$i.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument'
      '.spreadsheetml.worksheet+xml"/>',
    );
  }
  return '$_xmlHead'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats'
      '-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd'
      '.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '$parts'
      '</Types>';
}

const _rootRels =
    '$_xmlHead'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(List<SheetOut> sheets) {
  final tabs = StringBuffer();
  for (var i = 0; i < sheets.length; i++) {
    tabs.write(
      '<sheet name="${_attr(sheets[i].name)}" sheetId="${i + 1}" '
      'r:id="rId${i + 1}"/>',
    );
  }
  return '$_xmlHead'
      '<workbook xmlns="$_spreadsheetNs" xmlns:r="$_relsNs">'
      '<sheets>$tabs</sheets>'
      '</workbook>';
}

String _workbookRels(int sheets) {
  final rels = StringBuffer();
  for (var i = 1; i <= sheets; i++) {
    rels.write(
      '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet$i.xml"/>',
    );
  }
  return '$_xmlHead'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">$rels</Relationships>';
}

String _sheet(List<List<String>> rows) {
  final body = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    final cells = rows[r];
    body.write('<row r="${r + 1}">');
    for (var c = 0; c < cells.length; c++) {
      final value = cells[c];
      if (value.isEmpty) continue;
      final ref = '${_columnName(c)}${r + 1}';
      final number = _asNumber(value);
      if (number != null) {
        body.write('<c r="$ref"><v>$number</v></c>');
      } else {
        // Inline rather than a shared string table, because a table would be a
        // second part to keep in step for no gain at these sizes.
        body.write(
          '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
          '${_text(value)}</t></is></c>',
        );
      }
    }
    body.write('</row>');
  }
  return '$_xmlHead'
      '<worksheet xmlns="$_spreadsheetNs">'
      '<sheetData>$body</sheetData>'
      '</worksheet>';
}

/// The value as a number if a spreadsheet would read it as one, else null.
///
/// A leading zero is kept as text on purpose: a postcode, a phone number and a
/// part code all lose their meaning the moment a spreadsheet decides they were
/// arithmetic.
String? _asNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (!RegExp(r'^-?\d+(\.\d+)?([eE][-+]?\d+)?$').hasMatch(trimmed)) return null;
  if (RegExp(r'^-?0\d').hasMatch(trimmed)) return null;
  return double.tryParse(trimmed) == null ? null : trimmed;
}

/// A, B, ... Z, AA, AB, and so on.
String _columnName(int index) {
  var n = index;
  final out = StringBuffer();
  while (true) {
    out.write(String.fromCharCode(65 + n % 26));
    if (n < 26) break;
    n = n ~/ 26 - 1;
  }
  return String.fromCharCodes(out.toString().codeUnits.reversed);
}

// ---------------------------------------------------------------------------
// The Word file.

const _docxContentTypes =
    '$_xmlHead'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
    'content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats'
    '-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd'
    '.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd'
    '.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const _docxRootRels =
    '$_xmlHead'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/>'
    '</Relationships>';

const _docxDocumentRels =
    '$_xmlHead'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

/// Six heading styles and a body style, which is the whole vocabulary this
/// writer has and the whole vocabulary it claims.
const _docxStyles =
    '$_xmlHead'
    '<w:styles xmlns:w="$_wordNs">'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name '
    'w:val="heading 1"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name '
    'w:val="heading 2"/><w:pPr><w:outlineLvl w:val="1"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3"><w:name '
    'w:val="heading 3"/><w:pPr><w:outlineLvl w:val="2"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>'
    '</w:styles>';

String _docxBody(QuireDocument document) {
  final body = StringBuffer();
  for (final section in document.sections) {
    if (document.sections.length > 1 && section.title.isNotEmpty) {
      body.write(_docxParagraph(section.title, style: 'Heading1'));
    }
    _docxBlocks(section.blocks, body);
  }
  return '$_xmlHead'
      '<w:document xmlns:w="$_wordNs"><w:body>$body</w:body></w:document>';
}

void _docxBlocks(List<DocBlock> blocks, StringBuffer body) {
  for (final block in blocks) {
    switch (block) {
      case SlideBlock():
        // One slide becomes one run of paragraphs under its own heading,
        // which is what a deck turned into a document actually is.
        final named = block.title;
        if (named != null && named.isNotEmpty) {
          body.write(_docxParagraph(named, style: 'Heading1'));
        }
        for (final shape in block.shapes) {
          if (shape.role == SlideRole.title) continue;
          _docxBlocks(shape.blocks, body);
        }
        _docxBlocks(block.notes, body);
      case HeadingBlock():
        body.write(
          _docxParagraph(
            block.text,
            style: 'Heading${block.level.clamp(1, 3)}',
          ),
        );
      case ParagraphBlock():
        body.write(_docxRuns(block.spans));
      case ListItemBlock():
        final indent = '  ' * block.level;
        final bullet = block.ordered ? '' : '• ';
        body.write(_docxParagraph('$indent$bullet${block.text}'));
      case CodeBlock():
        for (final line in block.text.split('\n')) {
          body.write(_docxParagraph(line, mono: true));
        }
      case DividerBlock():
        body.write(_docxParagraph(''));
      case ImageBlock():
        final alt = block.alt;
        if (alt != null && alt.isNotEmpty) body.write(_docxParagraph('[$alt]'));
      case TableBlock():
        // A table becomes tab separated lines rather than a Word table,
        // because a Word table needs a grid, widths and borders this writer
        // does not carry, and a wrong table reads worse than a straight run.
        for (final row in block.rows) {
          body.write(
            _docxParagraph(
              <String>[
                for (final cell in row.cells)
                  if (!cell.merged) cell.text.replaceAll('\n', ' '),
              ].join('\t'),
              mono: true,
            ),
          );
        }
    }
  }
}

String _docxParagraph(String text, {String? style, bool mono = false}) {
  final properties = StringBuffer('<w:pPr>');
  if (style != null) properties.write('<w:pStyle w:val="$style"/>');
  properties.write('</w:pPr>');
  final run = text.isEmpty
      ? ''
      : '<w:r>'
            '${mono ? '<w:rPr><w:rFonts w:ascii="Consolas" '
                  'w:hAnsi="Consolas"/></w:rPr>' : ''}'
            '<w:t xml:space="preserve">${_text(text)}</w:t>'
            '</w:r>';
  return '<w:p>$properties$run</w:p>';
}

/// A paragraph whose runs keep the bold and italic the source stated.
String _docxRuns(List<DocSpan> spans) {
  if (spans.isEmpty) return '<w:p/>';
  final runs = StringBuffer();
  for (final span in spans) {
    if (span.text.isEmpty) continue;
    final properties = StringBuffer();
    if (span.bold) properties.write('<w:b/>');
    if (span.italic) properties.write('<w:i/>');
    if (span.underline) properties.write('<w:u w:val="single"/>');
    if (span.strike) properties.write('<w:strike/>');
    if (span.mono) {
      properties.write('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>');
    }
    runs.write(
      '<w:r>'
      '${properties.isEmpty ? '' : '<w:rPr>$properties</w:rPr>'}'
      '<w:t xml:space="preserve">${_text(span.text)}</w:t>'
      '</w:r>',
    );
  }
  return '<w:p>$runs</w:p>';
}

// ---------------------------------------------------------------------------

const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const _spreadsheetNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _relsNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _wordNs =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// Text as it may appear between two tags.
String _text(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    // A control character is not legal XML at all, and a file holding one does
    // not open. Tab, newline and return are the three that are.
    .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '');

/// Text as it may appear inside an attribute.
String _attr(String value) => _text(value).replaceAll('"', '&quot;');
