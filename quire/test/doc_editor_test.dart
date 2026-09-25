import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/docx_delta.dart';
import 'package:quire/edit/ooxml_patch.dart';
import 'package:quire/screens/edit/doc_editor.dart';
import 'package:quire/screens/edit/edit_frame.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

String _documentXml(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return utf8.decode(archive.findFile('word/document.xml')!.content as List<int>);
}

/// The first element [tag] opens in [xml], whole.
String _element(String xml, String tag) {
  final start = xml.contains('<$tag>') ? xml.indexOf('<$tag>') : xml.indexOf('<$tag ');
  final end = xml.indexOf('</$tag>', start);
  return xml.substring(start, end + tag.length + 3);
}

/// The document as lines of text with the attributes each line carries.
List<(String, Map<String, Object?>)> _lines(Uint8List bytes) {
  final out = <(String, Map<String, Object?>)>[];
  final text = StringBuffer();
  for (final op in DocxDelta.read(bytes).ops) {
    final insert = op['insert'];
    if (insert is! String) {
      text.write('￼');
      continue;
    }
    final parts = insert.split('\n');
    for (var i = 0; i < parts.length; i++) {
      text.write(parts[i]);
      if (i < parts.length - 1) {
        out.add((text.toString(), (op['attributes'] as Map<String, Object?>?) ?? const <String, Object?>{}));
        text.clear();
      }
    }
  }
  return out;
}

void main() {
  late Uint8List original;
  Uint8List? saved;

  Future<DocEditorState> open(WidgetTester tester) async {
    original = (await tester.runAsync(() => documentBytes(kHouseStyle)))!;
    saved = null;
    await pumpScreen(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: DocEditor(
          title: 'House style',
          bytes: original,
          onBack: () {},
          onSave: (bytes, note) async {
            saved = bytes;
            return null;
          },
        ),
      ),
    );
    await settle(tester);
    return tester.state<DocEditorState>(find.byType(DocEditor));
  }

  int offsetOf(DocEditorState state, String words) => state.controller.document.toPlainText().indexOf(words);

  void pickWords(DocEditorState state, String words) {
    final at = offsetOf(state, words);
    expect(at, isNonNegative, reason: words);
    state.controller.updateSelection(
      TextSelection(baseOffset: at, extentOffset: at + words.length),
      ChangeSource.local,
    );
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('SAVE'));
    await settle(tester);
    expect(saved, isNotNull);
  }

  testWidgets('opens on the document\'s own words, headings and looks', (tester) async {
    final state = await open(tester);
    final ops = state.controller.document.toDelta().toJson();
    expect(ops.first['insert'], 'House Style');
    expect((ops.first['attributes'] as Map)['font'], 'Georgia');
    expect(ops[1]['attributes'], {'header': 1});
    expect(find.byKey(const ValueKey<String>('doc-format-bar')), findsOneWidget);
    for (final label in [
      'Bold', 'Italic', 'Underline', 'Text colour', 'Highlight colour', 'Alignment',
      'Bulleted list', 'Numbered list', 'Decrease indent', 'Increase indent', 'Text format',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    final save = tester.widget<EditButton>(find.ancestor(of: find.text('SAVE'), matching: find.byType(EditButton)));
    expect(save.enabled, isFalse);
  });

  testWidgets('words typed into a paragraph are saved, and every other paragraph is written back as it was', (tester) async {
    final state = await open(tester);
    final at = offsetOf(state, 'Most of what follows');
    state.controller.replaceText(at, 0, 'Quite simply: ', TextSelection.collapsed(offset: at + 14));
    await settle(tester);
    await save(tester);
    final before = DocxPatch(original).paragraphs;
    final after = DocxPatch(saved!).paragraphs;
    expect(after.length, before.length);
    final changed = before.indexWhere((p) => p.startsWith('Most of what follows'));
    expect(after[changed], startsWith('Quite simply: Most of what follows'));
    for (var i = 0; i < before.length; i++) {
      if (i != changed) expect(after[i], before[i], reason: 'paragraph $i');
    }
    // A paragraph nobody touched keeps its own XML.
    final xml = _documentXml(saved!);
    expect(xml, contains(_element(_documentXml(original), 'w:tbl')));
    // The changed paragraph is written in as few runs as its looks need.
    final paragraph = RegExp(r'<w:p\b(?:(?!</w:p>).)*Quite simply(?:(?!</w:p>).)*</w:p>', dotAll: true).firstMatch(xml)![0]!;
    expect(RegExp('<w:r>').allMatches(paragraph).length + RegExp('<w:r ').allMatches(paragraph).length, lessThanOrEqualTo(3));
  });

  testWidgets('bold, italic and underline from the bar are written into the runs', (tester) async {
    final state = await open(tester);
    pickWords(state, 'restraint');
    await tester.tap(find.bySemanticsLabel('Bold'));
    await tester.tap(find.bySemanticsLabel('Underline'));
    await settle(tester);
    expect(tester.widget<Semantics>(find.bySemanticsLabel('Bold')).properties.label, 'Bold');
    await save(tester);
    final op = DocxDelta.read(saved!).ops.firstWhere((o) => o['insert'] == 'restraint');
    final attributes = op['attributes']! as Map<String, Object?>;
    expect(attributes['bold'], isTrue);
    expect(attributes['underline'], isTrue);
    expect(attributes['font'], 'Georgia');
  });

  testWidgets('a heading, a numbered list and centring from the bar and the text sheet', (tester) async {
    final state = await open(tester);
    pickWords(state, 'Ellipses get the proper character');
    await tester.tap(find.bySemanticsLabel('Text format'));
    await settle(tester);
    await tester.tap(find.text('Heading 2'));
    await settle(tester);
    await tester.tapAt(const Offset(200, 100));
    await settle(tester);
    pickWords(state, 'Numerals follow the company');
    await tester.ensureVisible(find.bySemanticsLabel('Numbered list'));
    await tester.tap(find.bySemanticsLabel('Numbered list'));
    await settle(tester);
    pickWords(state, 'A margin is a straight line');
    await tester.ensureVisible(find.bySemanticsLabel('Alignment'));
    await tester.tap(find.bySemanticsLabel('Alignment'));
    await settle(tester);
    await tester.tap(find.text('Align centre'));
    await settle(tester);
    await save(tester);
    final lines = _lines(saved!);
    expect(lines.firstWhere((l) => l.$1.startsWith('Ellipses get')).$2['header'], 2);
    expect(lines.firstWhere((l) => l.$1.startsWith('Numerals follow')).$2['list'], 'ordered');
    expect(lines.firstWhere((l) => l.$1.startsWith('A margin is')).$2['align'], 'center');
    expect(_documentXml(saved!), contains('<w:jc w:val="center"/>'));
  });

  testWidgets('text colour and highlight come from their palettes', (tester) async {
    final state = await open(tester);
    pickWords(state, 'restraint');
    await tester.tap(find.bySemanticsLabel('Text colour'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Dark red'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Highlight colour'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Yellow'));
    await settle(tester);
    await save(tester);
    final op = DocxDelta.read(saved!).ops.firstWhere((o) => o['insert'] == 'restraint');
    final attributes = op['attributes']! as Map<String, Object?>;
    expect(attributes['color'], '#CC0000');
    expect(attributes['background'], isNotNull);
  });

  testWidgets('find and replace finds every match and replaces them all', (tester) async {
    final state = await open(tester);
    final count = RegExp('measure').allMatches(state.controller.document.toPlainText().toLowerCase()).length;
    expect(count, greaterThan(1));
    await tester.tap(find.bySemanticsLabel('More options'));
    await settle(tester);
    await tester.tap(find.text('Find and replace'));
    await settle(tester);
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey<String>('doc-find-field')), matching: find.byType(EditableText)),
      'measure',
    );
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Next match'));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey<String>('doc-find-count'))).data, '1 of $count');
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey<String>('doc-replace-field')), matching: find.byType(EditableText)),
      'width',
    );
    await tester.tap(find.bySemanticsLabel('Replace all'));
    await settle(tester);
    expect(state.controller.document.toPlainText().toLowerCase(), isNot(contains('measure')));
    await save(tester);
    expect(DocxPatch(saved!).paragraphs.join(' ').toLowerCase(), isNot(contains('measure')));
  });

  testWidgets('the word count and the outline', (tester) async {
    final state = await open(tester);
    await tester.tap(find.bySemanticsLabel('More options'));
    await settle(tester);
    await tester.tap(find.text('Word count'));
    await settle(tester);
    final (words, _, _) = WordCountSheet.count(state.controller.document.toPlainText());
    expect(words, greaterThan(300));
    expect(find.text('$words'), findsOneWidget);
    await tester.tapAt(const Offset(200, 100));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More options'));
    await settle(tester);
    await tester.tap(find.text('Document outline'));
    await settle(tester);
    expect(find.text('House Style'), findsWidgets);
    expect(find.text('Choosing leading'), findsOneWidget);
    await tester.tap(find.text('Choosing leading'));
    await settle(tester);
    expect(state.controller.selection.baseOffset, offsetOf(state, 'Choosing leading'));
  });

  testWidgets('undo takes a change back all the way, and redo brings it back', (tester) async {
    final state = await open(tester);
    pickWords(state, 'restraint');
    await tester.tap(find.bySemanticsLabel('Italic'));
    await settle(tester);
    expect(tester.widget<EditButton>(find.ancestor(of: find.text('SAVE'), matching: find.byType(EditButton))).enabled, isTrue);
    await tester.tap(find.bySemanticsLabel('Undo'));
    await settle(tester);
    expect(tester.widget<EditButton>(find.ancestor(of: find.text('SAVE'), matching: find.byType(EditButton))).enabled, isFalse);
    await tester.tap(find.bySemanticsLabel('Redo'));
    await settle(tester);
    await save(tester);
    final op = DocxDelta.read(saved!).ops.firstWhere((o) => o['insert'] == 'restraint');
    expect((op['attributes']! as Map)['italic'], isTrue);
  });

  testWidgets('the formatting bar rides on the keyboard', (tester) async {
    await open(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
    addTearDown(tester.view.resetViewInsets);
    await settle(tester);
    final bar = tester.getRect(find.byKey(const ValueKey<String>('doc-format-bar')));
    expect(bar.bottom, closeTo(kPhone.logical.height - 300, 0.5));
  });

  testWidgets('the table and the picture are shown, and kept whole', (tester) async {
    final state = await open(tester);
    expect(find.bySemanticsLabel('Table, kept as it is'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    final at = offsetOf(state, 'Tables are where');
    state.controller.replaceText(at, 0, 'Note: ', null);
    await settle(tester);
    await save(tester);
    final before = _documentXml(original);
    final after = _documentXml(saved!);
    expect(after, contains(_element(before, 'w:tbl')));
    expect(after, contains(_element(before, 'w:drawing')));
  });
}
