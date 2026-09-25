import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/edit/doc_editor.dart';

import '../support/evidence.dart';
import '../support/fixtures.dart';
import '../support/golden.dart';

/// Screens of the Word editor at each step, and the file it writes, for a
/// review to look at. Written only when QUIRE_EVIDENCE names a folder.
void main() {
  testWidgets('word editor, step by step', (tester) async {
    final original = (await tester.runAsync(() => documentBytes(kHouseStyle)))!;
    writeEvidence('C', 'before.docx', original);
    Uint8List? saved;
    await pumpScreen(
      tester,
      evidenceFrame(MaterialApp(
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
      )),
    );
    await settle(tester);
    final state = tester.state<DocEditorState>(find.byType(DocEditor));
    void pick(String words) {
      final at = state.controller.document.toPlainText().indexOf(words);
      state.controller.updateSelection(TextSelection(baseOffset: at, extentOffset: at + words.length), ChangeSource.local);
    }

    await screenshot(tester, 'C', '01_opened');
    pick('restraint');
    await tester.tap(find.bySemanticsLabel('Bold'));
    await settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
    addTearDown(tester.view.resetViewInsets);
    await settle(tester);
    await screenshot(tester, 'C', '02_bold_with_keyboard_up');
    tester.view.resetViewInsets();
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Text colour'));
    await settle(tester);
    await screenshot(tester, 'C', '03_text_colour_palette');
    await tester.tap(find.bySemanticsLabel('Dark red'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Text format'));
    await settle(tester);
    await screenshot(tester, 'C', '04_text_format_sheet');
    await tester.tapAt(const Offset(200, 100));
    await settle(tester);
    pick('Numerals follow the company');
    await tester.ensureVisible(find.bySemanticsLabel('Numbered list'));
    await tester.tap(find.bySemanticsLabel('Numbered list'));
    await settle(tester);
    await tester.ensureVisible(find.bySemanticsLabel('Alignment'));
    await tester.tap(find.bySemanticsLabel('Alignment'));
    await settle(tester);
    await screenshot(tester, 'C', '05_alignment_choices');
    await tester.tap(find.text('Align centre'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More options'));
    await settle(tester);
    await screenshot(tester, 'C', '06_more_menu');
    await tester.tap(find.text('Find and replace'));
    await settle(tester);
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey<String>('doc-find-field')), matching: find.byType(EditableText)),
      'measure',
    );
    await tester.tap(find.bySemanticsLabel('Next match'));
    await settle(tester);
    await screenshot(tester, 'C', '07_find');
    await tester.tap(find.bySemanticsLabel('Close find'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More options'));
    await settle(tester);
    await tester.tap(find.text('Document outline'));
    await settle(tester);
    await screenshot(tester, 'C', '08_outline');
    await tester.tap(find.text('Numbers in tables'));
    await settle(tester);
    await screenshot(tester, 'C', '09_table_kept');
    await tester.tap(find.text('SAVE'));
    await settle(tester);
    writeEvidence('C', 'after.docx', saved!);
  });
}
