import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/writer.dart';
import 'package:quire/screens/edit/markup_screen.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';

import 'support/evidence.dart';
import 'support/golden.dart';
import 'support/pdf_bytes.dart';

/// [count] pages 300 wide and 400 tall, each with a line of words at the
/// top, and [annots] on the last page, its objects from number 5 + 2 × pages.
Uint8List _pages({int count = 1, String annots = '', List<List<int>> extra = const []}) {
  final kids = [for (var i = 0; i < count; i++) '${4 + i} 0 R'].join(' ');
  final contents = 4 + count;
  return buildPdf([
    obj('<< /Type /Catalog /Pages 2 0 R >>'),
    obj('<< /Type /Pages /Kids [$kids] /Count $count >>'),
    obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
    for (var i = 0; i < count; i++)
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 3 0 R >> >> '
          '/Contents $contents 0 R ${i == count - 1 && annots.isNotEmpty ? '/Annots [$annots]' : ''} >>'),
    streamObj('', ascii.encode('BT /F1 12 Tf 40 360 Td (The quick brown fox) Tj ET')),
    ...extra,
  ]);
}

Future<ui.Image> _red(WidgetTester tester, int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = (await tester.runAsync(() => picture.toImage(width, height)))!;
  picture.dispose();
  return image;
}

final PdfImage _redData = PdfImage(width: 2, height: 1, rgb: Uint8List.fromList([255, 0, 0, 255, 0, 0]));

void main() {
  late PdfPages pages;
  MarkupChanges? saved;

  Future<MarkupScreenState> open(WidgetTester tester, Uint8List bytes) async {
    pages = PdfPages(PdfFile.open(bytes));
    saved = null;
    await pumpScreen(
      tester,
      evidenceFrame(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MarkupScreen(
          title: 'Marks',
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
    final state = tester.state<MarkupScreenState>(find.byType(MarkupScreen));
    await tester.runAsync(() async {
      await state.font;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    return state;
  }

  Offset at(WidgetTester tester, MarkupScreenState state, Offset point) =>
      tester.getTopLeft(find.byKey(const ValueKey<String>('markup-page'))) + point * state.fit;

  Future<void> drag(WidgetTester tester, Offset from, Offset by, {int steps = 8}) async {
    final gesture = await tester.startGesture(from);
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(from + by * (i / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
  }

  Future<void> pick(WidgetTester tester, String tool) async {
    await tester.tap(find.bySemanticsLabel(tool));
    await settle(tester);
  }

  Future<Color> pixel(WidgetTester tester, Offset global) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(kEvidenceKey));
    final origin = boundary.localToGlobal(Offset.zero);
    final read = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      image.dispose();
      return (bytes!, width);
    });
    final (data, width) = read!;
    final p = global - origin;
    final i = (p.dy.round() * width + p.dx.round()) * 4;
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }

  bool isRed(Color c) => c.r > 0.9 && c.g < 0.2 && c.b < 0.2;

  testWidgets('a pasted picture is drawn where it lands', (tester) async {
    final state = await open(tester, _pages());
    state.placePicture(const Offset(40, 150), await _red(tester, 20, 10), _redData);
    await settle(tester);
    await tester.tap(find.text('Copy'));
    await settle(tester);
    await tester.tap(find.text('Paste'));
    await settle(tester);
    await tester.tapAt(at(tester, state, const Offset(250, 390)));
    await settle(tester);
    expect(state.marks, hasLength(2));
    final pasted = state.marks.last.edit.bounds;
    expect(pasted, const Rect.fromLTWH(52, 162, 140, 70));
    expect(isRed(await pixel(tester, at(tester, state, pasted.bottomRight - const Offset(4, 4)))), isTrue);
  });

  testWidgets('a copy of a picture the file holds is drawn where it is pasted', (tester) async {
    final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
      ImageEdit(0, rect: const Rect.fromLTWH(60, 100, 80, 40), image: _redData),
    ]);
    final state = await open(tester, bytes);
    await tester.tapAt(at(tester, state, const Offset(100, 120)));
    await settle(tester);
    await tester.tap(find.text('Copy'));
    await settle(tester);
    await tester.tap(find.text('Paste'));
    await settle(tester);
    await tester.tapAt(at(tester, state, const Offset(250, 390)));
    await settle(tester);
    final pasted = state.marks.last.edit.bounds;
    expect(pasted, const Rect.fromLTWH(72, 112, 80, 40));
    expect(isRed(await pixel(tester, at(tester, state, pasted.bottomRight - const Offset(4, 4)))), isTrue);
  });

  testWidgets('undo keeps the marks of a page opened after the step it undoes', (tester) async {
    final state = await open(
      tester,
      _pages(count: 2, annots: '7 0 R', extra: [
        obj('<< /Type /Annot /Subtype /Square /Rect [40 40 140 90] /C [0 0 1] /AP << /N 8 0 R >> >>'),
        streamObj('/Type /XObject /Subtype /Form /BBox [40 40 140 90]', ascii.encode('0 0 1 RG 40 40 100 50 re S')),
      ]),
    );
    await pick(tester, 'Ink');
    await drag(tester, at(tester, state, const Offset(60, 200)), const Offset(60, 20));
    expect(state.marks, hasLength(1));
    await tester.tap(find.bySemanticsLabel('The page after'));
    await settle(tester);
    expect(state.marks, hasLength(2));
    await tester.tap(find.bySemanticsLabel('Undo'));
    await settle(tester);
    expect(state.marks.single.found, isNotNull);
    await tester.tap(find.bySemanticsLabel('Redo'));
    await settle(tester);
    expect(state.marks, hasLength(2));
  });

  testWidgets('a short stroke and a single tap both leave ink', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Ink');
    await drag(tester, at(tester, state, const Offset(100, 200)), const Offset(3, 0), steps: 2);
    await tester.tapAt(at(tester, state, const Offset(150, 250)));
    await settle(tester);
    final ink = state.marks.single.edit as InkEdit;
    expect(ink.strokes, hasLength(2));
    expect(ink.strokes.first.length, greaterThan(1));
    expect(ink.strokes.last, hasLength(1));
  });

  testWidgets('a pause while drawing does not end or cancel the stroke', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Ink');
    final start = at(tester, state, const Offset(60, 200));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 900));
    await gesture.moveTo(start + const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await settle(tester);
    final stroke = (state.marks.single.edit as InkEdit).strokes.single;
    expect(stroke.last.dx - stroke.first.dx, closeTo(40 / state.fit, 0.5));
  });

  testWidgets('two fingers zoom the page and draw nothing', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Ink');
    final middle = at(tester, state, const Offset(150, 200));
    final one = await tester.startGesture(middle - const Offset(20, 0), pointer: 1);
    final two = await tester.startGesture(middle + const Offset(20, 0), pointer: 2);
    for (var i = 1; i <= 6; i++) {
      await one.moveTo(middle - Offset(20.0 + i * 12, 0));
      await two.moveTo(middle + Offset(20.0 + i * 12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await one.up();
    await two.up();
    await settle(tester);
    expect(state.marks, isEmpty);
    expect(state.zoom, greaterThan(2));
  });

  testWidgets('ink is picked up by its lines, not by the box around them', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Ink');
    // A ring drawn round the middle of the page.
    final corner = at(tester, state, const Offset(100, 150));
    final gesture = await tester.startGesture(corner);
    for (final p in const [Offset(100, 150), Offset(200, 150), Offset(200, 250), Offset(100, 250), Offset(100, 150)]) {
      await gesture.moveTo(at(tester, state, p));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
    await pick(tester, 'Select');
    await tester.tapAt(at(tester, state, const Offset(150, 200)));
    await settle(tester);
    expect(state.selection, isNull);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(at(tester, state, const Offset(200, 200)));
    await settle(tester);
    expect(state.selection, isNotNull);
  });

  testWidgets('leaving with marks not saved asks first', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Ink');
    await drag(tester, at(tester, state, const Offset(60, 200)), const Offset(60, 20));
    await tester.tap(find.bySemanticsLabel('Back to the document'));
    await settle(tester);
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.text('Discard changes'), findsOneWidget);
  });

  test('a thin mark stretches along its thin side and keeps it thin along the other', () {
    const line = Rect.fromLTWH(0, 0, 100, 2);
    expect(stretchedBy(line, 5, const Offset(0, 20)).height, 22);
    final narrower = stretchedBy(line, 3, const Offset(-95, 0));
    expect(narrower.width, kMarkMinSize);
    expect(narrower.height, 2);
  });

  testWidgets('a mark near the top of the page has its bar above it, off the page', (tester) async {
    final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
      const TextBoxEdit(0, rect: Rect.fromLTWH(40, 50, 160, 16), text: 'Near the top', size: 12),
    ]);
    final state = await open(tester, bytes);
    await tester.tapAt(at(tester, state, const Offset(100, 58)));
    await settle(tester);
    final bar = tester.getRect(find.byKey(const ValueKey<String>('markup-actions')));
    expect(bar.bottom, lessThanOrEqualTo(at(tester, state, const Offset(100, 50)).dy));
    expect(bar.top, lessThan(at(tester, state, Offset.zero).dy));
  });

  testWidgets('new marks come in the colour chosen for the tool', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Ink');
    await tester.tap(find.bySemanticsLabel('Colour for new marks'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Red'));
    await settle(tester);
    await tester.tapAt(const Offset(200, 120));
    await settle(tester);
    await drag(tester, at(tester, state, const Offset(60, 200)), const Offset(60, 20));
    expect((state.marks.single.edit as InkEdit).color, 0xFFD23B3B);
  });

  testWidgets('a tap off the page lets go of the mark', (tester) async {
    final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
      const TextBoxEdit(0, rect: Rect.fromLTWH(40, 100, 160, 16), text: 'A note', size: 12),
    ]);
    final state = await open(tester, bytes);
    await tester.tapAt(at(tester, state, const Offset(100, 108)));
    await settle(tester);
    expect(state.selection, isNotNull);
    await tester.tapAt(at(tester, state, const Offset(150, 400)) + const Offset(0, 12));
    await settle(tester);
    expect(state.selection, isNull);
  });

  testWidgets('zoomed in, a swipe that starts on a mark not picked up scrolls the page and leaves the mark', (tester) async {
    final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
      const TextBoxEdit(0, rect: Rect.fromLTWH(40, 100, 160, 40), text: 'A note', size: 12),
    ]);
    final state = await open(tester, bytes);
    await tester.tapAt(at(tester, state, const Offset(150, 160)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at(tester, state, const Offset(150, 160)));
    await settle(tester);
    expect(state.zoom, greaterThan(1));
    final before = state.origin;
    await drag(tester, at(tester, state, const Offset(120, 120)), const Offset(60, 150));
    expect(state.marks.single.shift, Offset.zero);
    expect(state.origin, isNot(before));
    expect(state.changes.isEmpty, isTrue);
  });

  testWidgets('after a pinch, the finger left on the page carries on moving it', (tester) async {
    final state = await open(tester, _pages());
    final middle = at(tester, state, const Offset(150, 200));
    final one = await tester.startGesture(middle - const Offset(20, 0), pointer: 1);
    final two = await tester.startGesture(middle + const Offset(20, 0), pointer: 2);
    for (var i = 1; i <= 6; i++) {
      await one.moveTo(middle - Offset(20.0 + i * 15, 0));
      await two.moveTo(middle + Offset(20.0 + i * 15, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await two.up();
    await tester.pump();
    final before = state.origin;
    for (var i = 1; i <= 6; i++) {
      await one.moveTo(middle - const Offset(110, 0) + Offset(0, i * 20.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await one.up();
    await settle(tester);
    expect(state.origin.dy, greaterThan(before.dy + 50));
    expect(state.marks, isEmpty);
  });

  testWidgets('a swipe across the whole page turns it, and the zoom stays when turning', (tester) async {
    final state = await open(tester, _pages(count: 2));
    await drag(tester, at(tester, state, const Offset(250, 250)), const Offset(-200, 0));
    expect(state.page, 1);
    await drag(tester, at(tester, state, const Offset(50, 250)), const Offset(200, 0));
    expect(state.page, 0);
    await tester.tapAt(at(tester, state, const Offset(150, 300)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at(tester, state, const Offset(150, 300)));
    await settle(tester);
    final zoom = state.zoom;
    expect(zoom, greaterThan(1));
    await tester.tap(find.bySemanticsLabel('The page after'));
    await settle(tester);
    expect(state.page, 1);
    expect(state.zoom, zoom);
  });

  testWidgets('words typed in the sheet are kept however it is closed', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Words');
    await tester.tapAt(at(tester, state, const Offset(40, 200)));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'Ask about the deposit');
    await tester.pump();
    await tester.tapAt(const Offset(200, 120));
    await settle(tester);
    expect((state.marks.single.edit as TextBoxEdit).text, 'Ask about the deposit');
    await tester.tapAt(at(tester, state, const Offset(60, 206)));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at(tester, state, const Offset(60, 206)));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'Second words, better ones');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect((state.marks.single.edit as TextBoxEdit).text, 'Second words, better ones');
  });

  group('after round three', () {
    testWidgets('words put down while zoomed in leave the page where it was once the keyboard goes', (tester) async {
      final state = await open(tester, _pages());
      await tester.tapAt(at(tester, state, const Offset(250, 350)));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at(tester, state, const Offset(250, 350)));
      await settle(tester);
      expect(state.zoom, greaterThan(1));
      final before = state.origin;
      await pick(tester, 'Words');
      final spot = at(tester, state, const Offset(230, 330));
      await tester.tapAt(spot);
      await settle(tester);
      addTearDown(tester.view.resetViewInsets);
      for (var i = 1; i <= 6; i++) {
        tester.view.viewInsets = FakeViewPadding(bottom: 290 * 2 * i / 6);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.enterText(find.byType(EditableText).last, 'Signed');
      await tester.tap(find.text('Put them on the page'));
      await settle(tester);
      for (var i = 5; i >= 0; i--) {
        tester.view.viewInsets = FakeViewPadding(bottom: 290 * 2 * i / 6);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle(tester);
      expect(state.origin, before);
      final box = state.marks.single.edit.bounds;
      expect((at(tester, state, box.topLeft) - spot).distance, lessThan(8));
    });

    testWidgets('a small tick is dragged from near its middle, not stretched', (tester) async {
      final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
        const InkEdit(0, strokes: [
          [Offset(150, 200), Offset(154, 206), Offset(162, 194)],
        ], width: 2),
      ]);
      final state = await open(tester, bytes);
      final tick = state.marks.single.edit.bounds;
      await tester.tapAt(at(tester, state, tick.center));
      await settle(tester);
      var shift = Offset.zero;
      for (final off in const <Offset>[Offset(2, 1), Offset(-3, 2), Offset(3, -2)]) {
        final from = at(tester, state, tick.center + shift) + off;
        await drag(tester, from, const Offset(40, 30));
        shift += const Offset(40, 30) / state.fit;
        final now = state.marks.single.edit.bounds;
        expect(now.size.width, closeTo(tick.width, 0.01));
        expect(now.size.height, closeTo(tick.height, 0.01));
        expect((now.center - (tick.center + shift)).distance, lessThan(0.5));
      }
    });

    testWidgets('the action bar comes back after a pinch or a pan', (tester) async {
      final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
        const TextBoxEdit(0, rect: Rect.fromLTWH(40, 100, 160, 40), text: 'A note', size: 12),
      ]);
      final state = await open(tester, bytes);
      await tester.tapAt(at(tester, state, const Offset(100, 120)));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('markup-actions')), findsOneWidget);
      final middle = at(tester, state, const Offset(150, 300));
      final one = await tester.startGesture(middle - const Offset(20, 0), pointer: 1);
      final two = await tester.startGesture(middle + const Offset(20, 0), pointer: 2);
      for (var i = 1; i <= 6; i++) {
        await one.moveTo(middle - Offset(20.0 + i * 10, 0));
        await two.moveTo(middle + Offset(20.0 + i * 10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await one.up();
      await two.up();
      await settle(tester);
      expect(state.zoom, greaterThan(1));
      expect(find.byKey(const ValueKey<String>('markup-actions')), findsOneWidget);
      await drag(tester, at(tester, state, const Offset(250, 350)), const Offset(-40, -60));
      expect(find.byKey(const ValueKey<String>('markup-actions')), findsOneWidget);
    });

    testWidgets('a box near the foot of the page grows upward, not off it', (tester) async {
      final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
        const TextBoxEdit(0, rect: Rect.fromLTWH(40, 350, 200, 30), text: 'Signed at the foot of the page', size: 12),
      ]);
      final state = await open(tester, bytes);
      await tester.tapAt(at(tester, state, const Offset(100, 365)));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('More actions'));
      await settle(tester);
      await tester.tap(find.text('Colour and size'));
      await settle(tester);
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.bySemanticsLabel('Larger'));
        await tester.pump();
      }
      await settle(tester);
      final box = state.marks.single.edit.bounds;
      expect(box.bottom, lessThanOrEqualTo(400.01));
      expect((state.marks.single.edit as TextBoxEdit).size, greaterThan(20));
    });
  });

  List<int> formObj(String bbox, String content, {String resources = ''}) => streamObj(
        '/Type /XObject /Subtype /Form /BBox [$bbox] /Resources << $resources >>',
        ascii.encode(content),
      );

  testWidgets('another program\'s line, note and underline are picked up; the underline stays where it is', (tester) async {
    final state = await open(tester, _pages(annots: '6 0 R 7 0 R 8 0 R', extra: [
      obj('<< /Type /Annot /Subtype /Line /Rect [55 195 205 255] /L [60 250 200 200] /AP << /N 9 0 R >> >>'),
      obj('<< /Type /Annot /Subtype /Text /Rect [250 290 270 310] /AP << /N 10 0 R >> >>'),
      obj('<< /Type /Annot /Subtype /Underline /Rect [40 330 140 344] /QuadPoints [40 344 140 344 40 330 140 330] /AP << /N 11 0 R >> >>'),
      formObj('55 195 205 255', '0 0 1 RG 2 w 60 250 m 200 200 l S'),
      formObj('250 290 270 310', '1 1 0 rg 250 290 20 20 re f'),
      formObj('40 330 140 344', '0 0 1 RG 1 w 40 331 m 140 331 l S'),
    ]));
    // The line runs from (60,150) to (200,200) on the page as read.
    await tester.tapAt(at(tester, state, const Offset(130, 175)));
    await settle(tester);
    expect(state.selection?.found?.subtype, 'Line');
    await tester.tapAt(at(tester, state, const Offset(250, 380)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(at(tester, state, const Offset(260, 100)));
    await settle(tester);
    expect(state.selection?.found?.subtype, 'Text');
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await settle(tester);
    expect(find.byType(WordsSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(WordsSheet))).pop();
    await settle(tester);
    await tester.tapAt(at(tester, state, const Offset(250, 380)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(at(tester, state, const Offset(90, 63)));
    await settle(tester);
    expect(state.selection?.found?.subtype, 'Underline');
    expect(find.text('Cut'), findsNothing);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(state.changes.updates.single, isA<MarkRemoved>());
  });

  testWidgets('an unfilled rectangle is picked up by its border, leaving the highlight inside it in reach', (tester) async {
    final state = await open(tester, _pages(annots: '6 0 R 7 0 R', extra: [
      obj('<< /Type /Annot /Subtype /Highlight /Rect [40 350 140 364] /QuadPoints [40 364 140 364 40 350 140 350] /C [1 1 0] /AP << /N 8 0 R >> >>'),
      obj('<< /Type /Annot /Subtype /Square /Rect [30 310 250 378] /C [1 0 0] /AP << /N 9 0 R >> >>'),
      formObj('40 350 140 364', '1 1 0 rg 40 350 100 14 re f'),
      formObj('30 310 250 378', '1 0 0 RG 2 w 31 311 218 66 re S'),
    ]));
    await tester.tapAt(at(tester, state, const Offset(90, 43)));
    await settle(tester);
    expect(state.selection?.found?.subtype, 'Highlight');
    await tester.tapAt(at(tester, state, const Offset(250, 380)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(at(tester, state, const Offset(249, 60)));
    await settle(tester);
    expect(state.selection?.found?.subtype, 'Square');
  });

  testWidgets('a highlight multiplied onto the page leaves what is under it dark', (tester) async {
    final state = await open(tester, _pages(annots: '6 0 R', extra: [
      obj('<< /Type /Annot /Subtype /Highlight /Rect [40 200 240 260] /QuadPoints [40 260 240 260 40 200 240 200] /C [1 1 0] /AP << /N 7 0 R >> >>'),
      formObj('40 200 240 260', '/GS0 gs 1 1 0 rg 40 200 200 60 re f', resources: '/ExtGState << /GS0 << /BM /Multiply /CA 1 /ca 1 >> >>'),
    ]));
    // The line of words at the top is under nothing; a solid black square is
    // drawn here by the page itself.
    expect(state.marks, hasLength(1));
    final under = await pixel(tester, at(tester, state, const Offset(140, 170)));
    expect(under.r, greaterThan(0.9));
    expect(under.b, lessThan(0.3));
  });

  testWidgets('ink can be made see-through, for the tool and for a drawing already down', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Ink');
    await tester.tap(find.bySemanticsLabel('Colour for new marks'));
    await settle(tester);
    expect(find.text('Opacity'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.bySemanticsLabel('More see-through'));
      await tester.pump();
    }
    await tester.tapAt(const Offset(200, 120));
    await settle(tester);
    await drag(tester, at(tester, state, const Offset(60, 200)), const Offset(60, 20));
    expect((state.marks.single.edit as InkEdit).opacity, closeTo(0.5, 0.001));
  });

  testWidgets('a larger size for another program\'s callout leaves its arrow where it points', (tester) async {
    final bytes = buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Annots [4 0 R] >>'),
      obj('<< /Type /Annot /Subtype /FreeText /IT /FreeTextCallout /Rect [20 200 280 300] '
          '/CL [30 210 80 270 120 270] /RD [100 0 0 50] /LE /OpenArrow '
          '/DA (/Helv 12 Tf 0 0 1 rg) /Contents (See this figure) /AP << /N 5 0 R >> >>'),
      formObj('20 200 280 300', '0 0 0 RG 1 w 30 210 m 80 270 l 120 270 l S 120 250 160 50 re S '
          'BT /Helv 12 Tf 0 0 1 rg 124 284 Td (See this figure) Tj ET',
          resources: '/Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >>'),
    ]);
    final state = await open(tester, bytes);
    await tester.tapAt(at(tester, state, const Offset(200, 125)));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More actions'));
    await settle(tester);
    await tester.tap(find.text('Colour and size'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Larger'));
    await settle(tester);
    await tester.tapAt(const Offset(200, 120));
    await settle(tester);
    final out = PdfFile.open(PdfAnnotator.apply(pages.file, updates: state.changes.updates, font: state.changes.font));
    final dict = out.dict((out.resolve(out.pages[0]['Annots'])! as List).single)!;
    expect([for (final v in out.resolve(dict['CL'])! as List) (out.resolve(v)! as num).toDouble()], [30, 210, 80, 270, 120, 270]);
    expect((state.marks.single.edit as TextBoxEdit).size, 13);
  });

  testWidgets('words no font here can set are pictured into the save', (tester) async {
    final state = await open(tester, _pages());
    await pick(tester, 'Words');
    await tester.tapAt(at(tester, state, const Offset(40, 200)));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).last, '你好，世界');
    await tester.tap(find.text('Put them on the page'));
    await settle(tester);
    await tester.tap(find.text('SAVE'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(tester);
    final words = saved!.added.single as TextBoxEdit;
    expect(words.drawn, isNotNull);
    expect(saved!.font, isNotNull);
    final out = PdfFile.open(PdfAnnotator.apply(pages.file, added: saved!.added, font: saved!.font));
    expect(out.dict((out.resolve(out.pages[0]['Annots'])! as List).single), isNotNull);
  });

  group('moving a mark once it is down', () {
    Uint8List twoLines() => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [4 0 R] /Count 1 >>'),
      obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 3 0 R >> >> /Contents 5 0 R >>'),
      streamObj('', ascii.encode('BT /F1 12 Tf 40 360 Td (The quick brown fox) Tj ET BT /F1 12 Tf 40 300 Td (jumps over the lazy dog) Tj ET')),
    ]);

    testWidgets('a mark is dragged straight away, with no tap to pick it up first', (tester) async {
      final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
        const TextBoxEdit(0, rect: Rect.fromLTWH(40, 150, 160, 40), text: 'A note', size: 12),
      ]);
      final state = await open(tester, bytes);
      expect(state.selection, isNull);
      await drag(tester, at(tester, state, const Offset(120, 170)), const Offset(48, 36));
      final moved = state.marks.single;
      expect(moved.shift.dx, closeTo(48 / state.fit, 0.5));
      expect(moved.shift.dy, closeTo(36 / state.fit, 0.5));
      expect(state.selection?.id, moved.id);
      expect(state.changes.updates, isNotEmpty);
    });

    testWidgets('with the pen out, holding a mark picks it up and the finger carries it', (tester) async {
      final state = await open(tester, _pages());
      await pick(tester, 'Ink');
      await drag(tester, at(tester, state, const Offset(60, 200)), const Offset(90, 0));
      final drawn = state.marks.single;
      final before = (drawn.edit as InkEdit).strokes.length;
      await tester.pump(kInkJoin);
      final start = at(tester, state, const Offset(100, 200));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 700));
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(start + Offset(0, 8.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);
      expect(state.marks, hasLength(1));
      final ink = state.marks.single;
      expect((ink.edit as InkEdit).strokes, hasLength(before));
      expect(ink.edit.bounds.top, closeTo(drawn.edit.bounds.top + 64 / state.fit, 1));
      expect(state.tool, MarkupTool.select);
      expect(state.selection?.id, ink.id);
    });

    testWidgets('with the pen out, a tap on a box of words picks it up and draws nothing', (tester) async {
      final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
        const TextBoxEdit(0, rect: Rect.fromLTWH(40, 150, 160, 40), text: 'A note', size: 12),
      ]);
      final state = await open(tester, bytes);
      await pick(tester, 'Ink');
      await tester.tapAt(at(tester, state, const Offset(120, 170)));
      await settle(tester);
      expect(state.marks, hasLength(1));
      expect(state.selection?.edit, isA<TextBoxEdit>());
      expect(state.tool, MarkupTool.select);
    });

    testWidgets('a new highlight dragged onto other words lands on them', (tester) async {
      final state = await open(tester, twoLines());
      await pick(tester, 'Highlight');
      await drag(tester, at(tester, state, const Offset(45, 36)), const Offset(90, 0));
      final lit = (state.marks.single.edit as HighlightEdit).rects.single;
      await pick(tester, 'Select');
      await drag(tester, at(tester, state, lit.center), Offset(0, 60 * state.fit));
      final now = (state.marks.single.edit as HighlightEdit).rects.single;
      // The second line of words sits 60 lower, and the highlight is on it,
      // as tall as the words and no taller.
      expect(now.center.dy, closeTo(lit.center.dy + 60, 3));
      expect(now.height, closeTo(lit.height, 1));
      expect(state.changes.added.single, isA<HighlightEdit>());
    });
  });
  group('after the integration critic', () {
    testWidgets('Back with a mark picked up lets go of it first, and only then asks to keep changes', (tester) async {
      final bytes = PdfAnnotator.annotated(PdfFile.open(_pages()), [
        const TextBoxEdit(0, rect: Rect.fromLTWH(40, 100, 160, 16), text: 'A note', size: 12),
      ]);
      final state = await open(tester, bytes);
      await tester.tapAt(at(tester, state, const Offset(100, 108)));
      await settle(tester);
      await drag(tester, at(tester, state, const Offset(100, 108)), const Offset(0, 40));
      expect(state.selection, isNotNull);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(MarkupScreen), findsOneWidget);
      expect(state.selection, isNull);
      expect(find.text('Keep editing'), findsNothing);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Keep editing'), findsOneWidget);
    });
  });
}
