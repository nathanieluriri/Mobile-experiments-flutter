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

/// The style the page draws [words] in, found in the text it rendered.
TextStyle? drawnStyle(WidgetTester tester, String words) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    TextStyle? found;
    void visit(InlineSpan span, TextStyle? inherited) {
      if (found != null || span is! TextSpan) return;
      final style = inherited == null ? span.style : inherited.merge(span.style);
      if ((span.text ?? '').contains(words)) {
        found = style;
        return;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child, style);
      }
    }

    visit(rich.text, null);
    if (found != null) return found;
  }
  return null;
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
    // The heading's look is its style's, drawn by the page, not carried by the words.
    expect(ops.first['attributes'], isNull);
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
    expect(attributes['font'], isNull);
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
    await tester.tap(find.bySemanticsLabel('Align centre'));
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
    expect(tester.widget<Text>(find.byKey(const ValueKey<String>('doc-find-count'))).data, '1 of $count');
    await tester.tap(find.bySemanticsLabel('Next match'));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey<String>('doc-find-count'))).data, '2 of $count');
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
    final (words, _, _) = WordCountSheet.count(state.countedText);
    final (withoutTables, _, _) = WordCountSheet.count(state.controller.document.toPlainText());
    expect(words - withoutTables, greaterThan(40));
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
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Table, kept as it is'), findsOneWidget);
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
  group('round two', () {
    testWidgets('the page draws the document in its own typefaces, sizes and colours', (tester) async {
      await open(tester);
      final heading = drawnStyle(tester, 'House Style')!;
      expect(heading.fontFamily, 'Georgia');
      expect(heading.fontFamilyFallback, contains('serif'));
      expect(heading.fontSize, closeTo(20 * kDocPoint, 0.01));
      expect(heading.color, const Color(0xFF1F3243));
      final body = drawnStyle(tester, 'Most of what follows')!;
      expect(body.fontFamily, 'Georgia');
      expect(body.fontSize, closeTo(10.5 * kDocPoint, 0.01));
    });

    testWidgets('a paragraph given Heading 2 looks like the other Heading 2s at once, and Normal text takes it back', (tester) async {
      final state = await open(tester);
      pickWords(state, 'Most of what follows');
      await tester.tap(find.bySemanticsLabel('Text format'));
      await settle(tester);
      await tester.tap(find.text('Heading 2'));
      await settle(tester);
      final heading = drawnStyle(tester, 'Most of what follows')!;
      final other = drawnStyle(tester, 'The measure and the leading')!;
      expect(heading.fontSize, other.fontSize);
      expect(heading.fontWeight, other.fontWeight);
      expect(heading.color, other.color);
      await tester.tap(find.text('Normal text'));
      await settle(tester);
      final body = drawnStyle(tester, 'Most of what follows')!;
      expect(body.fontSize, closeTo(10.5 * kDocPoint, 0.01));
      expect(body.fontWeight, FontWeight.w400);
      expect(state.controller.getSelectionStyle().attributes[Attribute.align.key]?.value, 'justify');
    });

    testWidgets('Enter at the end of a heading gives body text, on the page and in the file', (tester) async {
      final state = await open(tester);
      final end = offsetOf(state, 'Setting the measure') + 'Setting the measure'.length;
      state.controller.updateSelection(TextSelection.collapsed(offset: end), ChangeSource.local);
      state.controller.replaceText(end, 0, '\n', TextSelection.collapsed(offset: end + 1));
      state.controller.replaceText(end + 1, 0, 'A new paragraph under the heading.', TextSelection.collapsed(offset: end + 35));
      await settle(tester);
      final typed = drawnStyle(tester, 'A new paragraph under')!;
      expect(typed.fontSize, closeTo(10.5 * kDocPoint, 0.01));
      expect(typed.fontStyle, FontStyle.normal);
      expect(typed.fontWeight, FontWeight.w400);
      await save(tester);
      final line = _lines(saved!).firstWhere((l) => l.$1.startsWith('A new paragraph'));
      expect(line.$2['header'], isNull);
      final op = DocxDelta.read(saved!).ops.firstWhere((o) => (o['insert'] as String?)?.contains('A new paragraph') ?? false);
      expect(op['attributes'], isNull);
    });

    testWidgets('the text sheet leaves the keyboard down while it is used', (tester) async {
      final state = await open(tester);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey<String>('doc-page'))));
      await settle(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      pickWords(state, 'Most of what follows');
      await tester.tap(find.bySemanticsLabel('Text format'));
      await settle(tester);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.bySemanticsLabel('Larger'));
      await settle(tester);
      await tester.tap(find.text('Heading 1'));
      await settle(tester);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tapAt(const Offset(200, 100));
      await settle(tester);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('Heading 6'), findsNothing);
    });

    testWidgets('Replace moves on to the next match, even when the new words hold the old', (tester) async {
      final state = await open(tester);
      final before = RegExp('measure').allMatches(state.controller.document.toPlainText().toLowerCase()).length;
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Find and replace'));
      await settle(tester);
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey<String>('doc-find-field')), matching: find.byType(EditableText)),
        'measure',
      );
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey<String>('doc-replace-field')), matching: find.byType(EditableText)),
        'measures',
      );
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.bySemanticsLabel('Replace'));
        await settle(tester);
      }
      final text = state.controller.document.toPlainText().toLowerCase();
      expect(RegExp('measures').allMatches(text).length, greaterThanOrEqualTo(3));
      expect(text, isNot(contains('measuress')));
      expect(RegExp('measure').allMatches(text).length, before);
    });

    testWidgets('find marks every match as it is typed, the current one apart', (tester) async {
      final state = await open(tester);
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Find and replace'));
      await settle(tester);
      await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey<String>('doc-find-field')), matching: find.byType(EditableText)),
        'measure',
      );
      await settle(tester);
      final (marks, current) = state.findMarks;
      final count = RegExp('measure').allMatches(state.controller.document.toPlainText().toLowerCase()).length;
      expect(marks.length, count);
      expect(current, isNotNull);
      final page = tester.getRect(find.byKey(const ValueKey<String>('doc-page')));
      expect(current!.top, greaterThanOrEqualTo(-1));
      expect(current.bottom, lessThanOrEqualTo(page.height + 1));
    });

    testWidgets('the outline puts the heading at the top of the page', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Document outline'));
      await settle(tester);
      await tester.tap(find.text('Widows, orphans, and the last line'));
      await settle(tester);
      final page = tester.getRect(find.byKey(const ValueKey<String>('doc-page')));
      final heading = tester.getRect(find.textContaining('Widows, orphans, and the last line', findRichText: true).last);
      expect(heading.top - page.top, lessThan(page.height / 4));
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('clearing formatting leaves text in its paragraph style', (tester) async {
      final state = await open(tester);
      pickWords(state, 'Most of what follows is about restraint.');
      await tester.tap(find.bySemanticsLabel('Text format'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Clear formatting'));
      await settle(tester);
      final body = drawnStyle(tester, 'Most of what follows')!;
      expect(body.fontSize, closeTo(10.5 * kDocPoint, 0.01));
    });

    testWidgets('paragraphs are spaced and indented as the document sets them', (tester) async {
      final state = await open(tester);
      final render = state.renderEditor!;
      final end = offsetOf(state, 'the reader noticing the hand.') + 'the reader noticing the hand.'.length;
      final first = render.getLocalRectForCaret(TextPosition(offset: end - 1));
      final next = offsetOf(state, 'The measure and the leading');
      final lineHeight = render.preferredLineHeight(TextPosition(offset: end - 1));
      final heading = render.getLocalRectForCaret(TextPosition(offset: next));
      expect(heading.top - first.top, greaterThan(lineHeight + 18 * kDocPoint));
    });

    testWidgets('the table is drawn with its shading and its merged row', (tester) async {
      final state = await open(tester);
      final source = DocxDelta.read(original);
      final table = source.blocks.values.firstWhere((b) => b.kind == 'table').table!;
      expect(table.rows.first.first.fill, 0x1F3243);
      expect(table.rows.first.first.look.bold, isTrue);
      expect(table.rows.first.first.look.color, 0xFFFFFF);
      expect(table.rows.last.first.span, 3);
      state.reveal(offsetOf(state, 'Tables are where'));
      await settle(tester);
      expect(
        find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == const Color(0xFF1F3243)),
        findsWidgets,
      );
    });

    testWidgets('backspace at the start of a list item takes it out of the list', (tester) async {
      final state = await open(tester);
      final start = offsetOf(state, 'Letterspace small capitals');
      final before = state.controller.document.toPlainText();
      state.controller.updateSelection(TextSelection.collapsed(offset: start), ChangeSource.local);
      state.controller.replaceText(start - 1, 1, '', TextSelection.collapsed(offset: start - 1));
      await settle(tester);
      expect(state.controller.document.toPlainText(), before);
      final line = state.controller.document.queryChild(start).node!;
      expect(line.style.attributes[Attribute.list.key], isNull);
    });

    testWidgets('alignment is a pop-up of four over its button, and the keyboard stays up', (tester) async {
      final state = await open(tester);
      final at = offsetOf(state, 'A margin is a straight line');
      await tester.tapAt(tester.getCenter(find.byType(QuillEditor)));
      await settle(tester);
      state.controller.updateSelection(TextSelection.collapsed(offset: at + 3), ChangeSource.local);
      await settle(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.ensureVisible(find.bySemanticsLabel('Alignment'));
      await tester.tap(find.bySemanticsLabel('Alignment'));
      await settle(tester);
      final pop = tester.getRect(find.byKey(const ValueKey<String>('alignment-pop')));
      final button = tester.getRect(find.bySemanticsLabel('Alignment'));
      expect(pop.bottom, lessThanOrEqualTo(button.top));
      expect(find.descendant(of: find.byKey(const ValueKey<String>('alignment-pop')), matching: find.byType(Icon)), findsNWidgets(4));
      await tester.tap(find.bySemanticsLabel('Align centre'));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('alignment-pop')), findsNothing);
      expect(tester.testTextInput.isVisible, isTrue);
      final line = state.controller.document.queryChild(at).node! as Line;
      expect(line.style.attributes[Attribute.align.key], Attribute.centerAlignment);
    });

    testWidgets('Enter on an empty item in the middle of a list ends the list there', (tester) async {
      final state = await open(tester);
      final words = 'Letterspace small capitals';
      final line = state.controller.document.queryChild(offsetOf(state, words)).node! as Line;
      final end = offsetOf(state, words) + line.length - 1;
      state.controller.replaceText(end, 0, '\n', TextSelection.collapsed(offset: end + 1));
      await settle(tester);
      final empty = state.controller.document.queryChild(end + 1).node! as Line;
      expect(empty.length, 1);
      expect(empty.style.attributes[Attribute.list.key], Attribute.ul);
      final before = state.controller.document.toPlainText();
      state.controller.replaceText(end + 1, 0, '\n', TextSelection.collapsed(offset: end + 2));
      await settle(tester);
      expect(state.controller.document.toPlainText(), before);
      final plain = state.controller.document.queryChild(end + 1).node! as Line;
      expect(plain.style.attributes[Attribute.list.key], isNull);
      final next = state.controller.document.queryChild(offsetOf(state, 'Never fake them')).node! as Line;
      expect(next.style.attributes[Attribute.list.key], Attribute.ul);
    });

    testWidgets('numbering a paragraph starts a list of its own, and the later list still counts from 1', (tester) async {
      final state = await open(tester);
      pickWords(state, 'Numerals follow the company');
      await tester.ensureVisible(find.bySemanticsLabel('Numbered list'));
      await tester.tap(find.bySemanticsLabel('Numbered list'));
      await settle(tester);
      await save(tester);
      final xml = _documentXml(saved!);
      String? numOf(String words) => RegExp('<w:p>(?:(?!</w:p>).)*?<w:numId w:val="(\\d+)"/>(?:(?!</w:p>).)*?$words', dotAll: true)
          .firstMatch(xml)
          ?.group(1);
      final mine = numOf('Numerals follow');
      final later = numOf('Fix the trim size');
      expect(mine, isNotNull);
      expect(later, isNotNull);
      expect(mine, isNot(later));
      expect(RegExp('<w:numId w:val="$mine"/>').allMatches(xml).length, 1);
    });
  });
  group('round three', () {
    testWidgets('backspace under a table, or typing on it, never loses the table', (tester) async {
      final state = await open(tester);
      final start = offsetOf(state, 'Rules inside a table');
      state.controller.updateSelection(TextSelection.collapsed(offset: start), ChangeSource.local);
      state.controller.replaceText(start - 1, 1, '', TextSelection.collapsed(offset: start - 1));
      await settle(tester);
      final table = state.controller.document.toPlainText().lastIndexOf('￼', start);
      state.controller.replaceText(table, 0, 'x', TextSelection.collapsed(offset: table + 1));
      state.controller.replaceText(table + 1, 0, 'y', TextSelection.collapsed(offset: table + 2));
      await settle(tester);
      state.controller.replaceText(offsetOf(state, 'Most of what follows'), 0, 'Edited. ', null);
      await settle(tester);
      await save(tester);
      expect(RegExp('<w:tbl>').allMatches(_documentXml(saved!)).length, 1);
    });

    testWidgets('bold that comes from a heading shows on the bar, and tapping it makes the words plain', (tester) async {
      final state = await open(tester);
      pickWords(state, 'measure');
      final at = offsetOf(state, 'The measure and the leading') + 4;
      state.controller.updateSelection(TextSelection(baseOffset: at, extentOffset: at + 7), ChangeSource.local);
      await settle(tester);
      Semantics bold() => tester.widget<Semantics>(find.bySemanticsLabel('Bold'));
      final button = find.ancestor(of: find.bySemanticsLabel('Bold'), matching: find.byType(Container)).first;
      expect((tester.widget<Container>(button).decoration! as BoxDecoration).color, isNotNull);
      expect(bold().properties.label, 'Bold');
      await tester.tap(find.bySemanticsLabel('Bold'));
      await settle(tester);
      expect(drawnStyle(tester, 'measure')?.fontWeight, FontWeight.w400);
      await save(tester);
      expect(_documentXml(saved!), contains('<w:b w:val="0"/>'));
    });

    testWidgets('the text sheet keeps the words being set in sight above it, with the page undimmed', (tester) async {
      final state = await open(tester);
      pickWords(state, 'lowercase alphabet');
      await tester.tap(find.bySemanticsLabel('Text format'));
      await settle(tester);
      final sheetTop = tester.getTopLeft(find.text('Normal text')).dy - 60;
      final render = state.renderEditor!;
      final caret = render.localToGlobal(render.getLocalRectForCaret(TextPosition(offset: offsetOf(state, 'lowercase alphabet'))).bottomLeft);
      expect(caret.dy, lessThan(sheetTop));
    });

    testWidgets('find marks are painted only over the page', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Find and replace'));
      await settle(tester);
      final painter = find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_FindPainter');
      expect(find.ancestor(of: painter, matching: find.byType(ClipRect)), findsWidgets);
    });

    testWidgets('a long press on the page, keyboard down, selects with handles and the copy menu', (tester) async {
      final state = await open(tester);
      final render = state.renderEditor!;
      final at = offsetOf(state, 'restraint') + 2;
      final point = render.localToGlobal(render.getLocalRectForCaret(TextPosition(offset: at)).center);
      await tester.longPressAt(point);
      await settle(tester);
      expect(state.controller.selection.isCollapsed, isFalse);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('Back closes find and replace before it leaves the editor', (tester) async {
      original = (await tester.runAsync(() => documentBytes(kHouseStyle)))!;
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Builder(
            builder: (context) => GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => DocEditor(title: 'House style', bytes: original, onBack: () {}, onSave: (b, n) async => null),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('More options'));
      await settle(tester);
      await tester.tap(find.text('Find and replace'));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('doc-find')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('doc-find')), findsNothing);
      expect(find.byType(DocEditor), findsOneWidget);
    });
  });
}
