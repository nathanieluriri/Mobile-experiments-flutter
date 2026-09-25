import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/ooxml_patch.dart';
import 'package:quire/edit/text_patch.dart';
import 'package:quire/edit/xlsx_patch.dart';
import 'package:quire/edit/zip_patch.dart';
import 'package:quire/format/docx_parser.dart';
import 'package:quire/format/pptx_parser.dart';
import 'package:quire/format/xlsx_parser.dart';
import 'package:quire/model/document.dart';

import 'support/fixtures.dart';

/// Every part of [zip] by name, decompressed.
Map<String, List<int>> _parts(Uint8List zip) => <String, List<int>>{
      for (final file in ZipDecoder().decodeBytes(zip).files)
        if (file.isFile) file.name: file.content as List<int>,
    };

/// The raw bytes each entry of [zip] occupies, local header and compressed
/// data, by name.
Map<String, List<int>> _rawEntries(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  final out = <String, List<int>>{};
  var at = 0;
  final starts = <int>[];
  while (at + 30 <= zip.length && data.getUint32(at, Endian.little) == 0x04034b50) {
    starts.add(at);
    final compressed = data.getUint32(at + 18, Endian.little);
    final name = data.getUint16(at + 26, Endian.little);
    final extra = data.getUint16(at + 28, Endian.little);
    at += 30 + name + extra + compressed;
    if (data.getUint16(starts.last + 6, Endian.little) & 8 != 0) break;
  }
  for (var i = 0; i < starts.length; i++) {
    final s = starts[i];
    final nameLength = data.getUint16(s + 26, Endian.little);
    final name = utf8.decode(zip.sublist(s + 30, s + 30 + nameLength));
    final end = i + 1 < starts.length ? starts[i + 1] : at;
    out[name] = zip.sublist(s, end);
  }
  return out;
}

void main() {
  group('a save with no edits is the file that was read', () {
    for (final name in [kHouseStyle, kPressRunCosts, kPressDayBriefing]) {
      test(name, () async {
        final bytes = await documentBytes(name);
        final saved = switch (name) {
          kHouseStyle => DocxPatch(bytes).write(),
          kPressRunCosts => XlsxPatch(bytes).write(),
          _ => PptxPatch(bytes).write(),
        };
        expect(saved, same(bytes));
      });
    }

    for (final name in [kBinderyNotes, kSubscribers]) {
      test(name, () async {
        final bytes = await documentBytes(name);
        final patch = TextPatch.read(bytes);
        expect(patch.write(patch.text), bytes);
      });
    }

    test('setting a paragraph to the text it has is not an edit', () async {
      final bytes = await documentBytes(kHouseStyle);
      final patch = DocxPatch(bytes);
      final first = patch.paragraphs.indexWhere((p) => p.isNotEmpty);
      patch.setParagraph(first, patch.paragraphs[first]);
      expect(patch.write(), same(bytes));
    });
  });

  group('patching a package', () {
    test('copies every part it was not asked to change byte for byte', () async {
      final bytes = await documentBytes(kHouseStyle);
      final out = patchZip(bytes, {'word/document.xml': utf8.encode('<x/>')});
      final before = _rawEntries(bytes);
      final after = _rawEntries(out);
      expect(after.keys, before.keys);
      for (final name in before.keys) {
        if (name == 'word/document.xml') continue;
        expect(after[name], before[name], reason: name);
      }
      expect(utf8.decode(_parts(out)['word/document.xml']!), '<x/>');
    });

    test('adds a part it did not hold', () async {
      final bytes = await documentBytes(kHouseStyle);
      final out = patchZip(bytes, {'quire/note.txt': utf8.encode('kept')});
      final parts = _parts(out);
      expect(utf8.decode(parts['quire/note.txt']!), 'kept');
      expect(parts.length, _parts(bytes).length + 1);
    });

    test('refuses what is not a zip rather than guessing', () {
      expect(
        () => patchZip(Uint8List.fromList(List.filled(64, 7)), {'a': [1]}),
        throwsA(isA<ZipPatchError>()),
      );
    });
  });

  group('Word', () {
    test('an edited paragraph reads back, and everything else is kept', () async {
      final bytes = await documentBytes(kHouseStyle);
      final patch = DocxPatch(bytes);
      final at = patch.paragraphs.indexWhere((p) => p.length > 20);
      final was = patch.paragraphs[at];
      patch.setParagraph(at, 'A sentence quire wrote.');
      final out = patch.write();

      expect(DocxPatch(out).paragraphs[at], 'A sentence quire wrote.');
      final document = DocxParser(out).parse();
      final text = document.sections
          .expand((s) => s.blocks)
          .map((b) => switch (b) {
                ParagraphBlock() => b.text,
                HeadingBlock() => b.text,
                ListItemBlock() => b.text,
                _ => '',
              })
          .join('\n');
      expect(text, contains('A sentence quire wrote.'));
      expect(text, isNot(contains(was)));

      final before = _parts(bytes);
      final after = _parts(out);
      for (final name in before.keys) {
        if (name == 'word/document.xml') continue;
        expect(after[name], before[name], reason: name);
      }
    });

    test('the first run keeps its look, and tabs and breaks survive', () async {
      final bytes = await documentBytes(kHouseStyle);
      final patch = DocxPatch(bytes);
      final at = patch.paragraphs.indexWhere((p) => p.length > 20);
      patch.setParagraph(at, 'one\ttwo\nthree');
      expect(DocxPatch(patch.write()).paragraphs[at], 'one\ttwo\nthree');
    });
  });

  group('PowerPoint', () {
    test('text in a shape changes, and the slide keeps everything else', () async {
      final bytes = await documentBytes(kPressDayBriefing);
      final patch = PptxPatch(bytes);
      expect(patch.slideCount, greaterThan(1));
      final at = patch.paragraphs.indexWhere((p) => p.text.length > 5);
      final slide = patch.paragraphs[at].slide;
      patch.setParagraph(at, 'Retitled by quire');
      final out = patch.write();
      expect(PptxPatch(out).paragraphs[at].text, 'Retitled by quire');
      final deck = PptxParser(out).parse();
      final shapes = deck.sections[slide].blocks.whereType<SlideBlock>().single;
      expect(
        shapes.shapes.map((s) => s.text).join(' '),
        contains('Retitled by quire'),
      );
    });

    test('a line break becomes a break between runs', () async {
      final bytes = await documentBytes(kPressDayBriefing);
      final patch = PptxPatch(bytes);
      final at = patch.paragraphs.indexWhere((p) => p.text.length > 5);
      patch.setParagraph(at, 'first\nsecond');
      expect(PptxPatch(patch.write()).paragraphs[at].text, 'first\nsecond');
    });
  });

  group('Excel', () {
    Future<(XlsxPatch, String)> costs() async {
      final bytes = await documentBytes(kPressRunCosts);
      final patch = XlsxPatch(bytes);
      return (patch, patch.sheetNames.first);
    }

    SheetCell? cellAt(Uint8List bytes, String sheet, String ref) =>
        XlsxParser(bytes).parse().sheets.firstWhere((s) => s.name == sheet).cell(ref);

    test('a number, a word and a truth are stored as what they are', () async {
      final (patch, sheet) = await costs();
      patch
        ..setCell(sheet, 'B2', '1250.5')
        ..setCell(sheet, 'C2', 'Ink, black')
        ..setCell(sheet, 'D2', 'true');
      final out = patch.write();
      expect(cellAt(out, sheet, 'B2')?.kind, CellKind.number);
      expect(cellAt(out, sheet, 'C2')?.raw, 'Ink, black');
      expect(cellAt(out, sheet, 'D2')?.kind, CellKind.boolean);
    });

    test('a formula keeps its text, carries no value, and asks for a '
        'calculation on open', () async {
      final (patch, sheet) = await costs();
      patch.setCell(sheet, 'E9', '=SUM(B2:B4)');
      final out = patch.write();
      final workbook = utf8.decode(_parts(out)['xl/workbook.xml']!);
      expect(workbook, contains('fullCalcOnLoad="1"'));
      final cell = cellAt(out, sheet, 'E9');
      expect(cell?.formula, 'SUM(B2:B4)');
      expect(cell?.formatted, '=SUM(B2:B4)');
    });

    test('a cell far outside the sheet is made where it belongs', () async {
      final (patch, sheet) = await costs();
      patch.setCell(sheet, 'AA300', '7');
      final out = patch.write();
      expect(cellAt(out, sheet, 'AA300')?.raw, 7);
    });

    test('a reference that is not a cell is refused', () async {
      final (patch, sheet) = await costs();
      expect(() => patch.setCell(sheet, 'nowhere', '1'), throwsArgumentError);
      expect(() => patch.setCell('No such sheet', 'A1', '1'), throwsArgumentError);
    });
  });

  group('Markdown and CSV', () {
    test('keep their line endings, their mark and their last newline', () {
      final crlf = Uint8List.fromList(
        [0xEF, 0xBB, 0xBF, ...utf8.encode('# Title\r\n\r\nBody\r\n')],
      );
      final patch = TextPatch.read(crlf);
      expect(patch.text, '# Title\n\nBody');
      final out = patch.write('# Title\n\nNew body');
      expect(out, [0xEF, 0xBB, 0xBF, ...utf8.encode('# Title\r\n\r\nNew body\r\n')]);

      final bare = TextPatch.read(Uint8List.fromList(utf8.encode('a,b\n1,2')));
      expect(utf8.decode(bare.write('a,b\n3,4')), 'a,b\n3,4');
    });
  });
}
