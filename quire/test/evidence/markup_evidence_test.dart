import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/writer.dart';
import 'package:quire/screens/edit/markup_screen.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';

import '../support/evidence.dart';
import '../support/fixtures.dart';
import '../support/golden.dart';
import '../support/pdf_bytes.dart';

/// Screens of the mark editor at each step, and the file it writes, for a
/// review to look at. Written only when QUIRE_EVIDENCE names a folder.
void main() {
  testWidgets('mark up, step by step', (tester) async {
    final original = (await tester.runAsync(() => documentBytes(kPressLease)))!;
    // The page as a reader left it last time: words, ink, a highlight and a
    // picture already on it.
    final marked = PdfAnnotator.annotated(PdfFile.open(original), [
      const TextBoxEdit(0, rect: Rect.fromLTWH(70, 90, 200, 34), text: 'Check the rent review date', size: 12),
      const InkEdit(0, strokes: [[Offset(80, 520), Offset(140, 540), Offset(200, 515), Offset(260, 535)]], width: 2.5),
      const HighlightEdit(0, rects: [Rect.fromLTWH(72, 150, 230, 14)]),
      ImageEdit(
        0,
        rect: const Rect.fromLTWH(380, 640, 90, 45),
        image: PdfImage(
          width: 4,
          height: 2,
          rgb: Uint8List.fromList([for (var i = 0; i < 8; i++) ...[30, 90, 200]]),
        ),
      ),
    ]);
    writeEvidence('A', 'before.pdf', marked);
    final pages = PdfPages(PdfFile.open(marked));
    MarkupChanges? saved;
    await pumpScreen(
      tester,
      evidenceFrame(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MarkupScreen(
          title: 'Press lease',
          pages: pages,
          openAt: 0,
          onBack: () {},
          onSave: (changes) async {
            saved = changes;
            return null;
          },
        ),
      )),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    final state = tester.state<MarkupScreenState>(find.byType(MarkupScreen));
    Offset at(Offset point) =>
        tester.getTopLeft(find.byKey(const ValueKey<String>('markup-page'))) + point * state.fit;
    Future<void> drag(Offset from, Offset by) async {
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(from + by * (i / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);
    }

    await screenshot(tester, 'A', '01_opened_with_saved_marks');
    await tester.tapAt(at(const Offset(170, 107)));
    await settle(tester);
    await screenshot(tester, 'A', '02_words_selected');
    await drag(at(const Offset(170, 107)), const Offset(20, 120));
    await screenshot(tester, 'A', '03_words_moved');
    final words = state.selection!.edit.bounds;
    await drag(at(words.bottomRight), const Offset(-40, 0));
    await screenshot(tester, 'A', '04_words_narrower_wraps');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await settle(tester);
    await screenshot(tester, 'A', '05_more_sheet');
    await tester.tap(find.text('Colour and size'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Red'));
    await tester.tap(find.bySemanticsLabel('Larger'));
    await settle(tester);
    await screenshot(tester, 'A', '06_colour_and_size_sheet');
    await tester.tapAt(const Offset(200, 80));
    await settle(tester);
    await tester.tapAt(at(const Offset(425, 662)));
    await settle(tester);
    await screenshot(tester, 'A', '07_picture_selected');
    await drag(at(const Offset(470, 685)), const Offset(40, 20));
    await screenshot(tester, 'A', '08_picture_stretched_from_corner');
    await tester.tap(find.bySemanticsLabel('Ink'));
    await settle(tester);
    await drag(at(const Offset(300, 420)), const Offset(90, 40));
    await screenshot(tester, 'A', '09_ink_drawn');
    await tester.tap(find.bySemanticsLabel('Select'));
    await settle(tester);
    await tester.tapAt(at(const Offset(170, 527)));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await screenshot(tester, 'A', '10_old_ink_deleted');
    await tester.tapAt(at(const Offset(425, 662)));
    await settle(tester);
    await tester.tap(find.text('Copy'));
    await settle(tester);
    await tester.tap(find.text('Paste'));
    await settle(tester);
    await screenshot(tester, 'A', '11_picture_pasted');
    final line = state.pageRuns.firstWhere((r) => r.width > 200 && r.y > 250);
    await tester.tap(find.bySemanticsLabel('Highlight'));
    await settle(tester);
    await drag(at(Offset(line.x + 30, line.y - 3)), Offset(line.width * 0.5 * state.fit, 2));
    await screenshot(tester, 'A', '12_highlight_snapped_to_words');
    await tester.tap(find.bySemanticsLabel('Colour for new marks'));
    await settle(tester);
    await screenshot(tester, 'A', '13_colour_for_new_marks');
    await tester.tap(find.bySemanticsLabel('Green'));
    await settle(tester);
    await tester.tapAt(const Offset(200, 80));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Words'));
    await settle(tester);
    await tester.tapAt(at(const Offset(70, 700)));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'Zażółć gęślą jaźń, Привет, 你好');
    await tester.tap(find.text('Put them on the page'));
    await settle(tester);
    await screenshot(tester, 'A', '14_words_in_other_scripts');
    final middle = at(const Offset(300, 420));
    final one = await tester.startGesture(middle - const Offset(30, 0), pointer: 7);
    final two = await tester.startGesture(middle + const Offset(30, 0), pointer: 8);
    for (var i = 1; i <= 8; i++) {
      await one.moveTo(middle - Offset(30.0 + i * 10, 0));
      await two.moveTo(middle + Offset(30.0 + i * 10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await one.up();
    await two.up();
    await settle(tester);
    await screenshot(tester, 'A', '15_pinched_to_zoom');
    await tester.tap(find.text('SAVE'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await settle(tester);
    final changes = saved!;
    final out = PdfAnnotator.apply(
      PdfFile.open(marked),
      added: changes.added,
      updates: changes.updates,
      font: changes.font,
    );
    writeEvidence('A', 'after.pdf', out);
  });

  testWidgets('another program\'s callout, recoloured', (tester) async {
    final page = buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Annots [4 0 R] >>'),
      obj('<< /Type /Annot /Subtype /FreeText /IT /FreeTextCallout /Rect [20 200 280 300] '
          '/CL [30 210 80 270 120 270] /RD [100 0 0 50] /LE /OpenArrow '
          '/DA (/Helv 12 Tf 0 0 1 rg) /Contents (See this figure) /AP << /N 5 0 R >> >>'),
      streamObj(
        '/Type /XObject /Subtype /Form /BBox [20 200 280 300] '
        '/Resources << /Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>',
        ascii.encode('0 0 0 RG 1 w 30 210 m 80 270 l 120 270 l S 120 250 160 50 re S '
            'BT /Helv 12 Tf 0 0 1 rg 124 284 Td (See this figure) Tj ET'),
      ),
    ]);
    writeEvidence('A', 'callout_before.pdf', page);
    MarkupChanges? saved;
    await pumpScreen(
      tester,
      evidenceFrame(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MarkupScreen(
          title: 'Callout',
          pages: PdfPages(PdfFile.open(page)),
          openAt: 0,
          onBack: () {},
          onSave: (changes) async {
            saved = changes;
            return null;
          },
        ),
      )),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    final state = tester.state<MarkupScreenState>(find.byType(MarkupScreen));
    Offset at(Offset point) =>
        tester.getTopLeft(find.byKey(const ValueKey<String>('markup-page'))) + point * state.fit;
    await screenshot(tester, 'A', 'callout_01_opened');
    await tester.tapAt(at(const Offset(200, 125)));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More actions'));
    await settle(tester);
    await tester.tap(find.text('Colour and size'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Red'));
    await settle(tester);
    await tester.tapAt(const Offset(200, 80));
    await settle(tester);
    await screenshot(tester, 'A', 'callout_02_recoloured');
    await tester.tap(find.text('SAVE'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    final out = PdfAnnotator.apply(PdfFile.open(page), updates: saved!.updates, font: saved!.font);
    writeEvidence('A', 'callout_after.pdf', out);
  });
}
