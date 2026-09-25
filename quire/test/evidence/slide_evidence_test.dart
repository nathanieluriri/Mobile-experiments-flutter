import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource;
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/edit/slides/slide_editor.dart';

import '../support/evidence.dart';
import '../support/fixtures.dart';
import '../support/golden.dart';

/// Screens of the slide editor at each step, and the file it writes, for a
/// review to look at. Written only when QUIRE_EVIDENCE names a folder.
void main() {
  testWidgets('slide editor, step by step', (tester) async {
    final original = (await tester.runAsync(() => documentBytes(kPressDayBriefing)))!;
    writeEvidence('D', 'before.pptx', original);
    Uint8List? saved;
    await pumpScreen(
      tester,
      evidenceFrame(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SlideEditor(
          title: 'Press day briefing',
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
    final state = tester.state<SlideEditorState>(find.byType(SlideEditor));
    final deck = state.deck!;
    Offset at(Offset slide) => tester.getTopLeft(find.byKey(const ValueKey<String>('slide-canvas'))) + state.onCanvas(slide);
    Offset middle(SlideBox b) => Offset(b.left + b.width / 2, b.top + b.height / 2);

    await screenshot(tester, 'D', '01_deck_view');
    final card = find.byKey(ValueKey<String>('card-${deck.slides[1]}'));
    await tester.tapAt(tester.getTopLeft(card) + const Offset(60, 20));
    await settle(tester);
    await screenshot(tester, 'D', '02_deck_view_edit_slide_pill');
    final first = find.byKey(ValueKey<String>('card-${deck.slides[0]}'));
    final hold = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 700));
    await hold.up();
    await settle(tester);
    await tester.tapAt(tester.getTopLeft(card) + const Offset(60, 20));
    await settle(tester);
    await screenshot(tester, 'D', '03_deck_view_two_picked_count_bar');
    await tester.tap(find.bySemanticsLabel('Clear the selection'));
    await settle(tester);

    await tester.tapAt(tester.getTopLeft(card) + const Offset(60, 20));
    await settle(tester);
    await tester.tapAt(tester.getTopLeft(card) + const Offset(60, 20));
    await settle(tester);
    final four = find.byKey(ValueKey<String>('card-${deck.slides[3]}'));
    await tester.scrollUntilVisible(four, 200, scrollable: find.descendant(of: find.byKey(const ValueKey<String>('deck-list')), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(four);
    await settle(tester);
    await tester.tapAt(tester.getTopLeft(four) + const Offset(60, 20));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey<String>('card-pill')), matching: find.text('Edit slide')));
    await settle(tester);
    await screenshot(tester, 'D', '04_slide_view_insert_bar_and_strip');

    final slide = deck.slides[3];
    final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
    await tester.tapAt(at(middle(picture.box)));
    await settle(tester);
    await screenshot(tester, 'D', '05_picture_picked_handles_and_pill');
    final top = at(Offset(middle(picture.box).dx, picture.box.top)) - const Offset(0, kTurnReach);
    await tester.timedDragFrom(top, const Offset(60, 10), const Duration(milliseconds: 300));
    await settle(tester);
    await screenshot(tester, 'D', '06_picture_turned');
    await tester.tap(find.bySemanticsLabel('Format options'));
    await settle(tester);
    await screenshot(tester, 'D', '07_format_sheet');
    await tester.tap(find.text('50%'));
    await settle(tester);
    await tester.tap(find.text('On'));
    await settle(tester);
    await screenshot(tester, 'D', '07b_format_applied_slide_in_sight');
    await tester.tapAt(const Offset(200, 120));
    await settle(tester);

    final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
    final into = at(Offset(caption.box.left + 30, caption.box.top + 10));
    await tester.tapAt(into);
    await settle(tester);
    await tester.tapAt(into);
    await settle(tester);
    final typing = state.typing!;
    typing.updateSelection(const TextSelection(baseOffset: 0, extentOffset: 6), ChangeSource.local);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Bold'));
    await settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
    addTearDown(tester.view.resetViewInsets);
    await settle(tester);
    await screenshot(tester, 'D', '08_typing_on_slide_with_text_bar_over_keyboard');
    tester.view.resetViewInsets();
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Done'));
    await settle(tester);
    await tester.tapAt(at(const Offset(20, 520)));
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Shape'));
    await settle(tester);
    await screenshot(tester, 'D', '09_shape_sheet');
    await tester.tap(find.byKey(const ValueKey<String>('shape-star5')));
    await settle(tester);
    await screenshot(tester, 'D', '10_star_added');
    await tester.tapAt(at(const Offset(20, 520)));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey<String>('strip-add')));
    await settle(tester);
    await screenshot(tester, 'D', '11_new_slide_layouts');
    final layout = deck.layouts.firstWhere((l) => l.type == 'obj');
    await tester.tap(find.byKey(ValueKey<String>('layout-${layout.path}')));
    await settle(tester);
    await screenshot(tester, 'D', '12_new_slide_empty_placeholders');

    await tester.tap(find.bySemanticsLabel('Slide format'));
    await settle(tester);
    await screenshot(tester, 'D', '13a_slide_format_sheet');
    await tester.tap(find.text('Theme'));
    await settle(tester);
    await screenshot(tester, 'D', '13_theme_sheet');
    await tester.ensureVisible(find.byKey(const ValueKey<String>('builtin-Ocean')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('builtin-Ocean')));
    await settle(tester);
    await screenshot(tester, 'D', '14_ocean_theme');

    await tester.tap(find.text('SAVE'));
    await settle(tester);
    if (saved != null) writeEvidence('D', 'after.pptx', saved!);
  });
}
