import 'dart:convert';
import 'dart:typed_data';

import '../model/document.dart';

/// What a document can be turned into.
///
/// Every one of these is written by this app from what it has actually read,
/// so the list is short on purpose: a target quire cannot produce faithfully
/// is a promise it would break at the moment somebody opened the result
/// somewhere else.
enum ConvertTarget {
  text(
    label: 'Plain text',
    extension: 'txt',
    mime: 'text/plain',
    note: 'The words, in reading order. Nothing else survives.',
  ),
  markdown(
    label: 'Markdown',
    extension: 'md',
    mime: 'text/markdown',
    note: 'Headings, lists and tables kept. Fonts and colour are not.',
  ),
  csv(
    label: 'CSV',
    extension: 'csv',
    mime: 'text/csv',
    note: 'The cells as they are. One file per sheet is not possible, so the '
        'first sheet is the one written.',
  ),
  xlsx(
    label: 'Spreadsheet',
    extension: 'xlsx',
    mime:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    note: 'The rows and their values. Formulas become the numbers they '
        'worked out to.',
  ),
  pdf(
    label: 'PDF',
    extension: 'pdf',
    mime: 'application/pdf',
    note: 'Set fresh in one typeface at one size. It will read cleanly and it '
        'will not look like the original.',
  ),
  docx(
    label: 'Word',
    extension: 'docx',
    mime:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    note: 'Paragraphs and headings only.',
  );

  const ConvertTarget({
    required this.label,
    required this.extension,
    required this.mime,
    required this.note,
  });

  final String label;
  final String extension;
  final String mime;

  /// What this target keeps and what it drops, said before it is picked.
  ///
  /// Every conversion loses something. A converter that does not say what is
  /// about to be lost is a converter that has decided on the reader's behalf
  /// that it did not matter.
  final String note;
}

/// What a conversion could not carry across, for the sheet to say plainly.
class ConvertWarning {
  const ConvertWarning(this.line);
  final String line;
}

/// A finished conversion: the bytes, and what did not make it.
class ConvertResult {
  const ConvertResult({
    required this.bytes,
    this.warnings = const <ConvertWarning>[],
  });

  final Uint8List bytes;
  final List<ConvertWarning> warnings;
}

/// The document as one run of plain text, section by section.
///
/// A table becomes tab separated rows, because a table flattened into
/// sentences is a table nobody can read and tabs are what every spreadsheet
/// and every editor already understands.
String documentAsText(QuireDocument document) {
  final out = StringBuffer();
  for (var i = 0; i < document.sections.length; i++) {
    final section = document.sections[i];
    if (document.sections.length > 1 && section.title.isNotEmpty) {
      if (i > 0) out.writeln();
      out.writeln(section.title);
      out.writeln();
    }
    _blocksAsText(section.blocks, out);
  }
  return out.toString().trimRight();
}

void _blocksAsText(List<DocBlock> blocks, StringBuffer out) {
  for (final block in blocks) {
    switch (block) {
      case HeadingBlock():
        out.writeln();
        out.writeln(block.text);
      case ParagraphBlock():
        if (block.text.trim().isEmpty) break;
        out.writeln(block.text);
      case ListItemBlock():
        final indent = '  ' * block.level;
        out.writeln('$indent${block.ordered ? '1.' : '-'} ${block.text}');
      case CodeBlock():
        out.writeln(block.text);
      case DividerBlock():
        out.writeln();
      case ImageBlock():
        final alt = block.alt;
        if (alt != null && alt.isNotEmpty) out.writeln('[$alt]');
      case TableBlock():
        for (final row in block.rows) {
          out.writeln(
            <String>[
              for (final cell in row.cells)
                if (!cell.merged) cell.text.replaceAll('\n', ' '),
            ].join('\t'),
          );
        }
        out.writeln();
    }
  }
}

/// The document as Markdown.
///
/// Markdown is the one target that keeps the shape of a document rather than
/// only its words, which is why it is worth writing by hand instead of leaning
/// on the plain text run.
String documentAsMarkdown(QuireDocument document) {
  final out = StringBuffer();
  for (var i = 0; i < document.sections.length; i++) {
    final section = document.sections[i];
    if (document.sections.length > 1 && section.title.isNotEmpty) {
      out.writeln('# ${_escapeMarkdown(section.title)}');
      out.writeln();
    }
    _blocksAsMarkdown(section.blocks, out);
  }
  return '${out.toString().trimRight()}\n';
}

void _blocksAsMarkdown(List<DocBlock> blocks, StringBuffer out) {
  for (final block in blocks) {
    switch (block) {
      case HeadingBlock():
        final hashes = '#' * block.level.clamp(1, 6);
        out.writeln('$hashes ${_spansAsMarkdown(block.spans)}');
        out.writeln();
      case ParagraphBlock():
        if (block.text.trim().isEmpty) break;
        final body = _spansAsMarkdown(block.spans);
        out.writeln(block.quote ? '> $body' : body);
        out.writeln();
      case ListItemBlock():
        final indent = '  ' * block.level;
        final bullet = block.ordered ? '1.' : '-';
        final box = switch (block.checked) {
          true => '[x] ',
          false => '[ ] ',
          null => '',
        };
        out.writeln('$indent$bullet $box${_spansAsMarkdown(block.spans)}');
      case CodeBlock():
        out.writeln('```${block.language ?? ''}');
        out.writeln(block.text);
        out.writeln('```');
        out.writeln();
      case DividerBlock():
        out.writeln('---');
        out.writeln();
      case ImageBlock():
        out.writeln('![${block.alt ?? ''}](${block.assetKey})');
        out.writeln();
      case TableBlock():
        _tableAsMarkdown(block, out);
    }
  }
}

void _tableAsMarkdown(TableBlock table, StringBuffer out) {
  if (table.rows.isEmpty) return;
  final width = table.rows
      .map((r) => r.cells.where((c) => !c.merged).length)
      .reduce((a, b) => a > b ? a : b);
  if (width == 0) return;
  List<String> cellsOf(DocRow row) {
    final cells = <String>[
      for (final cell in row.cells)
        if (!cell.merged)
          _escapeMarkdown(cell.text.replaceAll('\n', ' ')).replaceAll('|', r'\|'),
    ];
    while (cells.length < width) {
      cells.add('');
    }
    return cells;
  }

  // Markdown has one header row and no way to say a table has none, so a
  // table that starts with data gets an empty head rather than losing its
  // first row to a heading it never had.
  final first = table.rows.first;
  final head = first.header ? cellsOf(first) : List<String>.filled(width, '');
  out.writeln('| ${head.join(' | ')} |');
  out.writeln('|${List<String>.filled(width, ' --- ').join('|')}|');
  for (var i = first.header ? 1 : 0; i < table.rows.length; i++) {
    out.writeln('| ${cellsOf(table.rows[i]).join(' | ')} |');
  }
  out.writeln();
}

String _spansAsMarkdown(List<DocSpan> spans) {
  final out = StringBuffer();
  for (final span in spans) {
    var text = _escapeMarkdown(span.text);
    if (text.isEmpty) continue;
    if (span.mono) text = '`$text`';
    if (span.bold) text = '**$text**';
    if (span.italic) text = '_${text}_';
    if (span.strike) text = '~~$text~~';
    final href = span.href;
    if (href != null && href.isNotEmpty) text = '[$text]($href)';
    out.write(text);
  }
  return out.toString();
}

/// The characters that would otherwise be read as Markdown rather than as
/// themselves.
String _escapeMarkdown(String text) =>
    text.replaceAllMapped(RegExp(r'([\\`*_\[\]])'), (m) => '\\${m[1]}');

/// The first grid in the document as CSV.
///
/// Quoting follows RFC 4180: a field is wrapped when it holds a comma, a
/// quote, or a line break, and a quote inside a wrapped field is doubled.
String documentAsCsv(QuireDocument document) {
  final table = _firstGrid(document);
  if (table == null) return '';
  final out = StringBuffer();
  for (final row in table.rows) {
    out.writeln(
      <String>[
        for (final cell in row.cells)
          if (!cell.merged) _csvField(cell.text),
      ].join(','),
    );
  }
  return out.toString();
}

String _csvField(String text) {
  if (!text.contains(RegExp('[",\n\r]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

/// The first table in the document that is actually a grid, or the first table
/// of any kind if none of them says it is one.
TableBlock? _firstGrid(QuireDocument document) {
  TableBlock? fallback;
  for (final section in document.sections) {
    for (final block in section.blocks) {
      if (block is! TableBlock) continue;
      if (block.grid) return block;
      fallback ??= block;
    }
  }
  return fallback;
}

/// Every grid in the document, one per sheet, with the sheet's name.
List<(String, TableBlock)> documentGrids(QuireDocument document) {
  final out = <(String, TableBlock)>[];
  for (var i = 0; i < document.sections.length; i++) {
    final section = document.sections[i];
    for (final block in section.blocks) {
      if (block is! TableBlock) continue;
      out.add((section.title.isEmpty ? 'Sheet${i + 1}' : section.title, block));
    }
  }
  return out;
}

/// A run of PDF page text as one document, for the targets that take words.
String pagesAsText(List<String> pages) {
  final out = StringBuffer();
  for (var i = 0; i < pages.length; i++) {
    if (i > 0) {
      out.writeln();
      out.writeln();
    }
    out.write(pages[i].trimRight());
  }
  return out.toString();
}

/// The same, with a rule between pages, which is the only thing Markdown has
/// for saying a page ended.
String pagesAsMarkdown(List<String> pages) {
  final out = StringBuffer();
  for (var i = 0; i < pages.length; i++) {
    if (i > 0) {
      out.writeln();
      out.writeln('---');
      out.writeln();
    }
    for (final line in pages[i].split('\n')) {
      if (line.trim().isEmpty) {
        out.writeln();
      } else {
        out.writeln(_escapeMarkdown(line));
        out.writeln();
      }
    }
  }
  return '${out.toString().trimRight()}\n';
}

/// Text as the bytes of a file, with the byte order mark left off.
Uint8List utf8Bytes(String text) =>
    Uint8List.fromList(const Utf8Encoder().convert(text));
