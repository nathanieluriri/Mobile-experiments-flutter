import 'dart:convert';
import 'dart:typed_data';

import '../model/document.dart';
import '../pdf/display_list.dart';
import '../pdf/compose.dart';
import '../pdf/document.dart';
import '../pdf/interpreter.dart';
import 'office_writer.dart';
import 'pdf_structure.dart';

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
      case SlideBlock():
        for (final shape in block.shapes) {
          _blocksAsText(shape.blocks, out);
        }
        // The notes come out too, under their own heading. A deck written out
        // without them loses the half of it that was put down for the one
        // person reading this.
        if (block.notes.isNotEmpty) {
          out.writeln();
          out.writeln('Notes');
          _blocksAsText(block.notes, out);
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
      case SlideBlock():
        final named = block.title;
        if (named != null && named.isNotEmpty) {
          out.writeln('## ${_escapeMarkdown(named)}');
          out.writeln();
        }
        for (final shape in block.shapes) {
          if (shape.role == SlideRole.title) continue;
          _blocksAsMarkdown(shape.blocks, out);
        }
        // Notes are set as a quotation, because that is the one Markdown
        // shape that says a passage belongs to the document without being
        // part of what it shows.
        final said = StringBuffer();
        _blocksAsMarkdown(block.notes, said);
        for (final line in said.toString().trimRight().split('\n')) {
          out.writeln(line.isEmpty ? '>' : '> $line');
        }
        if (block.notes.isNotEmpty) out.writeln();
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

/// Every page of [file] as its own run of text, in reading order.
///
/// It interprets each page here rather than asking the reader for its text
/// layer, because a document can be converted from the desk without ever
/// having been opened, and a converter that only worked on what you had
/// already scrolled past would be a converter you could not trust.
///
/// A page that will not interpret contributes nothing rather than stopping the
/// conversion: one broken content stream in a hundred pages is a page missing
/// from the result, not a result nobody gets.
List<String> pdfPageText(PdfFile file) {
  final out = <String>[];
  for (var page = 0; page < file.pageCount; page++) {
    try {
      final list = ContentInterpreter(file).run(file.pages[page]);
      out.add(mergeRuns(list.texts).map((run) => run.text).join('\n'));
    } on Object {
      out.add('');
    }
  }
  return out;
}

/// True when a run of page text carries so little that the file was almost
/// certainly scanned rather than set.
///
/// A scan converted to a text file is an empty text file, and handing one over
/// without a word about it is the app pretending it did the job.
bool looksScanned(List<String> pages) {
  if (pages.isEmpty) return true;
  var words = 0;
  for (final page in pages) {
    words += page.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }
  return words < pages.length * 8;
}

/// Text as the bytes of a file, with the byte order mark left off.
Uint8List utf8Bytes(String text) =>
    Uint8List.fromList(const Utf8Encoder().convert(text));

/// What a document made of [source] can honestly be turned into.
///
/// A target is left off when the source cannot supply what it needs, rather
/// than offered and then refused: a PDF has no grid to make a spreadsheet out
/// of, and a spreadsheet turned into a Word file is a spreadsheet nobody can
/// use. The source's own format is never offered either, because converting a
/// thing into itself is a copy, and the menu already has one of those.
List<ConvertTarget> targetsFor(String source, {required bool hasGrid}) {
  final out = <ConvertTarget>[];
  for (final target in ConvertTarget.values) {
    if (target.extension == source) continue;
    // A csv and a txt are both plain text; offering both for a csv is
    // offering the same file twice.
    if (target == ConvertTarget.text && source == 'csv') continue;
    switch (target) {
      case ConvertTarget.csv:
      case ConvertTarget.xlsx:
        if (hasGrid) out.add(target);
      case ConvertTarget.docx:
        if (!hasGrid) out.add(target);
      case ConvertTarget.text:
      case ConvertTarget.markdown:
      case ConvertTarget.pdf:
        out.add(target);
    }
  }
  return out;
}

/// What a conversion is being run from: a parsed document, or a page file, or
/// both when the source is a PDF somebody has also had parsed.
class ConvertSource {
  const ConvertSource({required this.title, this.document, this.pdf});

  final String title;
  final QuireDocument? document;
  final PdfFile? pdf;

  /// True when the source has a grid a spreadsheet could be made from.
  bool get hasGrid {
    final held = document;
    if (held == null) return false;
    for (final section in held.sections) {
      for (final block in section.blocks) {
        if (block is TableBlock) return true;
      }
    }
    return false;
  }
}

/// Turns [source] into [target], or returns null when it cannot.
///
/// Null is for a target this build does not write yet. Everything else that
/// can go wrong comes back as a [ConvertResult] with a warning on it, because
/// a conversion that dropped something and finished is still a file the reader
/// wanted, and a conversion that dropped something quietly is a lie.
ConvertResult? runConvert(
  ConvertSource source,
  ConvertTarget target, {
  ConvertFaces? faces,
}) {
  var document = source.document;
  final pdf = source.pdf;
  final warnings = <ConvertWarning>[];
  final fromPages = document == null && pdf != null;

  List<String>? pages;
  if (fromPages) {
    pages = pdfPageText(pdf);
    if (looksScanned(pages)) {
      warnings.add(
        const ConvertWarning(
          'This file carries almost no text of its own, so it was very likely '
          'scanned. What comes out will be close to empty.',
        ),
      );
    } else {
      // A page file does not say what its lines were, so the shape is read
      // back out of how the type is set. It is inference, and the warning
      // below says so.
      document = pdfAsDocument(pdf, source.title);
    }
  }

  switch (target) {
    case ConvertTarget.text:
      final text = document != null
          ? documentAsText(document)
          : pagesAsText(pages ?? const <String>[]);
      return ConvertResult(bytes: utf8Bytes(text), warnings: warnings);
    case ConvertTarget.markdown:
      if (fromPages) warnings.add(_inferred);
      final text = document != null
          ? documentAsMarkdown(document)
          : pagesAsMarkdown(pages ?? const <String>[]);
      return ConvertResult(bytes: utf8Bytes(text), warnings: warnings);
    case ConvertTarget.csv:
      if (document == null) return null;
      final grids = documentGrids(document);
      if (grids.length > 1) {
        warnings.add(
          ConvertWarning(
            'CSV holds one grid, so only ${grids.first.$1} was written. The '
            'other ${grids.length - 1} were left behind.',
          ),
        );
      }
      return ConvertResult(
        bytes: utf8Bytes(documentAsCsv(document)),
        warnings: warnings,
      );
    case ConvertTarget.xlsx:
      if (document == null) return null;
      final sheets = <SheetOut>[
        for (final (name, table) in documentGrids(document))
          SheetOut(name, <List<String>>[
            for (final row in table.rows)
              <String>[
                for (final cell in row.cells)
                  if (!cell.merged) cell.text,
              ],
          ]),
      ];
      return ConvertResult(bytes: writeXlsx(sheets), warnings: warnings);
    case ConvertTarget.docx:
      final made =
          document ??
          QuireDocument(
            title: source.title,
            sections: <DocSection>[
              for (var i = 0; i < (pages?.length ?? 0); i++)
                DocSection('', <DocBlock>[
                  for (final line in pages![i].split('\n'))
                    ParagraphBlock(<DocSpan>[DocSpan(line)]),
                ], kind: 'page'),
            ],
          );
      if (fromPages) warnings.add(_inferred);
      return ConvertResult(bytes: writeDocx(made), warnings: warnings);
    case ConvertTarget.pdf:
      final made = document;
      if (made == null || faces == null) return null;
      final composer = PdfComposer.of(faces.regular, faces.bold);
      final bytes = composer.compose(made);
      for (final line in composer.warnings.toSet()) {
        warnings.add(ConvertWarning(line));
      }
      return ConvertResult(bytes: bytes, warnings: warnings);
  }
}

/// What is said about anything read back out of a page file's geometry.
const _inferred = ConvertWarning(
  'A page file states where its words sit, not what they were. The headings, '
  'the paragraphs and the columns here were read back out of how the type is '
  'set: bigger type is a heading, a line that fills its column and does not '
  'end a sentence carries on into the next one. It is a good reading of the '
  'page, and it is a reading, so check anything that matters.',
);

/// The two faces a composed page is set in.
///
/// They are handed in rather than read here, because the parsing side of this
/// app never touches the bundle: a converter that loaded its own fonts would
/// be a converter that could only run inside a running app.
class ConvertFaces {
  const ConvertFaces({required this.regular, required this.bold});
  final Uint8List regular;
  final Uint8List bold;
}
