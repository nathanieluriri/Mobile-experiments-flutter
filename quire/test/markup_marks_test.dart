import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/marks.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/pdf/writer.dart';
import 'package:quire/screens/edit/markup_screen.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';

import 'support/golden.dart';
import 'support/pdf_bytes.dart';

/// A page 300 wide and 400 tall with one line of words at the top, turned
/// by [rotate].
Uint8List _page({int rotate = 0, String annots = ''}) => buildPdf([
  obj('<< /Type /Catalog /Pages 2 0 R >>'),
  obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
  obj(
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Rotate $rotate '
    '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R $annots >>',
  ),
  streamObj(
    '',
    ascii.encode('BT /F1 12 Tf 40 360 Td (The quick brown fox) Tj ET'),
  ),
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
]);

PdfFile _open(Uint8List bytes) => PdfFile.open(bytes);

List<Object?> _annots(PdfFile file, [int page = 0]) =>
    (file.resolve(file.pages[page]['Annots']) as List?) ?? const <Object?>[];

Map<String, Object?> _annot(PdfFile file, int index, [int page = 0]) =>
    file.dict(_annots(file, page)[index])!;

List<double> _nums(PdfFile file, Object? raw) => [
  for (final v in file.resolve(raw)! as List)
    (file.resolve(v)! as num).toDouble(),
];

const _box = Rect.fromLTWH(40, 100, 120, 30);

final _all = <PageEdit>[
  const TextBoxEdit(0, rect: _box, text: 'A note', size: 14, color: 0xFFD23B3B),
  const InkEdit(
    0,
    strokes: [
      [Offset(50, 200), Offset(90, 230), Offset(130, 210)],
    ],
    width: 3,
  ),
  const HighlightEdit(0, rects: [Rect.fromLTWH(40, 30, 100, 14)]),
  const StrikeEdit(0, rects: [Rect.fromLTWH(40, 50, 100, 14)]),
  ImageEdit(
    0,
    rect: const Rect.fromLTWH(200, 300, 40, 20),
    image: PdfImage(
      width: 2,
      height: 1,
      rgb: Uint8List.fromList([255, 0, 0, 0, 0, 255]),
    ),
  ),
];

void expectRect(Rect actual, Rect expected, {double within = 0.05}) {
  expect(actual.left, closeTo(expected.left, within));
  expect(actual.top, closeTo(expected.top, within));
  expect(actual.right, closeTo(expected.right, within));
  expect(actual.bottom, closeTo(expected.bottom, within));
}

void main() {
  group('stretching a box by a handle', () {
    const box = Rect.fromLTWH(10, 10, 100, 50);

    test('each handle moves its own sides and no others', () {
      expect(
        stretchedBy(box, 4, const Offset(20, 10)),
        const Rect.fromLTRB(10, 10, 130, 70),
      );
      expect(
        stretchedBy(box, 0, const Offset(-5, -5)),
        const Rect.fromLTRB(5, 5, 110, 60),
      );
      expect(
        stretchedBy(box, 1, const Offset(30, 20)),
        const Rect.fromLTRB(10, 30, 110, 60),
      );
      expect(
        stretchedBy(box, 7, const Offset(40, 99)),
        const Rect.fromLTRB(50, 10, 110, 60),
      );
    });

    test('never smaller than the least a mark can be', () {
      final r = stretchedBy(box, 4, const Offset(-500, -500));
      expect(r.width, kMarkMinSize);
      expect(r.height, kMarkMinSize);
    });

    test('a picture keeps its proportions from a corner', () {
      final r = stretchedBy(box, 4, const Offset(100, 0), keepShape: true);
      expect(r.width / r.height, closeTo(2, 1e-9));
      expect(r.width, 200);
    });
  });

  group('a mark moved and stretched', () {
    test('ink keeps its shape inside the new box', () {
      const ink = InkEdit(
        0,
        strokes: [
          [Offset(0, 0), Offset(10, 20)],
        ],
      );
      final fitted = ink.fitted(const Rect.fromLTWH(100, 100, 20, 40));
      expect(fitted.strokes.single, [
        const Offset(100, 100),
        const Offset(120, 140),
      ]);
      final moved = ink.moved(const Offset(5, 5));
      expect(moved.strokes.single, [const Offset(5, 5), const Offset(15, 25)]);
    });

    test('a highlight moves every line it covers', () {
      const mark = HighlightEdit(
        0,
        rects: [Rect.fromLTWH(0, 0, 10, 5), Rect.fromLTWH(0, 10, 20, 5)],
      );
      final moved = mark.moved(const Offset(3, 4));
      expect(moved.rects, [
        const Rect.fromLTWH(3, 4, 10, 5),
        const Rect.fromLTWH(3, 14, 20, 5),
      ]);
    });
  });

  group('reading back the marks a file carries', () {
    for (final rotate in [0, 90, 180, 270]) {
      test(
        'every kind comes back where it was put, on a page turned $rotate',
        () {
          final out = PdfAnnotator.annotated(
            _open(_page(rotate: rotate)),
            _all,
          );
          final found = readMarks(_open(out), 0);
          expect(found.map((f) => f.subtype), [
            'FreeText',
            'Ink',
            'Highlight',
            'StrikeOut',
            'Stamp',
          ]);
          final words = found[0].edit as TextBoxEdit;
          expectRect(words.rect, _box);
          expect(words.text, 'A note');
          expect(words.size, 14);
          expect(words.color, 0xFFD23B3B);
          final ink = found[1].edit as InkEdit;
          expect(ink.width, 3);
          expect(ink.strokes.single.length, 3);
          expect(ink.strokes.single.first.dx, closeTo(50, 0.01));
          expect(ink.strokes.single.first.dy, closeTo(200, 0.01));
          expectRect(
            (found[2].edit as HighlightEdit).rects.single,
            const Rect.fromLTWH(40, 30, 100, 14),
          );
          expect(found[4].edit, isA<KeptEdit>());
          expectRect(
            found[4].edit.bounds,
            const Rect.fromLTWH(200, 300, 40, 20),
          );
        },
      );
    }

    test('a link or a hidden mark is not something to pick up', () {
      final bytes = buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        obj(
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Annots [4 0 R 5 0 R] >>',
        ),
        obj('<< /Type /Annot /Subtype /Link /Rect [0 0 10 10] >>'),
        obj(
          '<< /Type /Annot /Subtype /FreeText /F 2 /Rect [0 0 10 10] /Contents (x) >>',
        ),
      ]);
      expect(readMarks(_open(bytes), 0), isEmpty);
    });
  });

  group('changing the marks already in a file', () {
    Uint8List marked() => PdfAnnotator.annotated(_open(_page()), _all);

    test('a moved mark keeps its object, its look and its maker', () {
      final file = _open(marked());
      final before = _annot(file, 0);
      final ref = _annots(file)[0] as PdfRef;
      final out = PdfAnnotator.apply(
        file,
        updates: [const MarkMoved(MarkOrigin(0, 0), Offset(30, 40))],
      );
      final again = _open(out);
      expect((_annots(again)[0] as PdfRef).number, ref.number);
      final after = _annot(again, 0);
      expect((after['AP']! as Map)['N'], (before['AP']! as Map)['N']);
      expect(
        (after['NM']! as PdfString).bytes,
        (before['NM']! as PdfString).bytes,
      );
      final r0 = _nums(file, before['Rect']);
      final r1 = _nums(again, after['Rect']);
      // The reader's y runs down and user space's up.
      expect(r1[0] - r0[0], closeTo(30, 1e-6));
      expect(r1[1] - r0[1], closeTo(-40, 1e-6));
      expectRect(
        readMarks(again, 0).first.edit.bounds,
        _box.shift(const Offset(30, 40)),
      );
    });

    test('moved ink and highlights take their points with them', () {
      final file = _open(marked());
      final out = PdfAnnotator.apply(
        file,
        updates: [
          const MarkMoved(MarkOrigin(0, 1), Offset(10, 0)),
          const MarkMoved(MarkOrigin(0, 2), Offset(0, 10)),
        ],
      );
      final again = _open(out);
      final ink = readMarks(again, 0)[1].edit as InkEdit;
      expect(ink.strokes.single.first.dx, closeTo(60, 0.01));
      final lit = readMarks(again, 0)[2].edit as HighlightEdit;
      expectRect(lit.rects.single, const Rect.fromLTWH(40, 40, 100, 14));
    });

    test('changed words are written again, and the old rich text goes', () {
      final file = _open(marked());
      final ref = _annots(file)[0] as PdfRef;
      final nm = (_annot(file, 0)['NM']! as PdfString).bytes;
      final out = PdfAnnotator.apply(
        file,
        updates: [
          const MarkRewritten(
            MarkOrigin(0, 0),
            TextBoxEdit(
              0,
              rect: Rect.fromLTWH(40, 100, 200, 30),
              text: 'New words',
              size: 12,
            ),
          ),
        ],
      );
      final again = _open(out);
      expect((_annots(again)[0] as PdfRef).number, ref.number);
      final dict = _annot(again, 0);
      expect((dict['NM']! as PdfString).bytes, nm);
      expect(dict.containsKey('RC'), isFalse);
      final words = readMarks(again, 0).first.edit as TextBoxEdit;
      expect(words.text, 'New words');
      final list = ContentInterpreter(again).run(again.pages[0]);
      expect(list.texts.map((t) => t.text).join(' '), contains('New'));
    });

    test('a removed mark leaves the page with its note window', () {
      final bytes = buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        obj(
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Annots [4 0 R 5 0 R 6 0 R] >>',
        ),
        obj(
          '<< /Type /Annot /Subtype /Ink /Rect [0 0 50 50] /InkList [[1 1 40 40]] /Popup 5 0 R >>',
        ),
        obj(
          '<< /Type /Annot /Subtype /Popup /Rect [0 0 50 50] /Parent 4 0 R >>',
        ),
        obj('<< /Type /Annot /Subtype /Link /Rect [0 0 10 10] >>'),
      ]);
      final out = PdfAnnotator.apply(
        _open(bytes),
        updates: [const MarkRemoved(MarkOrigin(0, 0))],
      );
      final left = _annots(_open(out));
      expect(left, hasLength(1));
      expect(
        (_open(out).dict(left.single)!['Subtype']! as PdfName).value,
        'Link',
      );
    });

    test('a stretched stamp keeps the picture it had', () {
      final file = _open(marked());
      final ap = (_annot(file, 4)['AP']! as Map)['N'];
      final out = PdfAnnotator.apply(
        file,
        updates: [
          const MarkRefitted(MarkOrigin(0, 4), Rect.fromLTWH(150, 250, 80, 40)),
        ],
      );
      final again = _open(out);
      expect((_annot(again, 4)['AP']! as Map)['N'], ap);
      expectRect(
        readMarks(again, 0)[4].edit.bounds,
        const Rect.fromLTWH(150, 250, 80, 40),
      );
      final drawn = ContentInterpreter(
        again,
      ).run(again.pages[0], onlyAnnotation: 4);
      expect(drawn.images, hasLength(1));
    });

    test('a copied stamp is a new mark that shares the picture', () {
      final file = _open(marked());
      final ap = (_annot(file, 4)['AP']! as Map)['N'];
      final out = PdfAnnotator.apply(
        file,
        added: [
          const KeptEdit(
            0,
            rect: Rect.fromLTWH(10, 10, 40, 20),
            origin: MarkOrigin(0, 4),
          ),
        ],
      );
      final again = _open(out);
      expect(_annots(again), hasLength(6));
      // The copy draws the original's own appearance, placed where it lands.
      final copy = again.dict((_annot(again, 5)['AP']! as Map)['N'])!;
      expect(again.dict(copy['Resources'])!['XObject'], {'Kept': ap});
      expect(
        (_annot(again, 5)['NM']! as PdfString).bytes,
        isNot((_annot(again, 4)['NM']! as PdfString).bytes),
      );
    });

    test('a mark written inline in the page is moved inside the page', () {
      final bytes = buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        obj(
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] '
          '/Annots [<< /Type /Annot /Subtype /Square /Rect [10 10 60 60] /AP << /N 4 0 R >> >>] >>',
        ),
        streamObj(
          '/Type /XObject /Subtype /Form /BBox [0 0 50 50]',
          ascii.encode('0 0 50 50 re f'),
        ),
      ]);
      final out = PdfAnnotator.apply(
        _open(bytes),
        updates: [const MarkMoved(MarkOrigin(0, 0), Offset(5, 0))],
      );
      final again = _open(out);
      expect(_nums(again, _annot(again, 0)['Rect']), [15, 10, 65, 60]);
    });

    test('a mark that is gone from the file is said so, not guessed at', () {
      expect(
        () => PdfAnnotator.apply(
          _open(_page()),
          updates: [const MarkRemoved(MarkOrigin(0, 3))],
        ),
        throwsA(isA<PdfWriteError>()),
      );
    });
  });

  test('the page can be drawn without the marks lifted off it', () {
    final file = _open(PdfAnnotator.annotated(_open(_page()), _all));
    final interp = ContentInterpreter(file);
    final all = interp.run(file.pages[0]);
    final bare = ContentInterpreter(
      file,
    ).run(file.pages[0], skipAnnotations: {0, 1, 2, 3, 4});
    final words = ContentInterpreter(
      file,
    ).run(file.pages[0], onlyAnnotation: 0);
    expect(all.texts.map((t) => t.text).join(), contains('note'));
    expect(bare.texts.map((t) => t.text).join(), isNot(contains('note')));
    expect(bare.texts.map((t) => t.text).join(), contains('quick'));
    expect(words.texts.map((t) => t.text).join(), 'A note');
  });

  group('the mark up screen', () {
    late PdfPages pages;
    MarkupChanges? saved;

    Future<MarkupScreenState> open(WidgetTester tester, Uint8List bytes) async {
      pages = PdfPages(PdfFile.open(bytes));
      saved = null;
      await pumpScreen(
        tester,
        MaterialApp(
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
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      return tester.state<MarkupScreenState>(find.byType(MarkupScreen));
    }

    Offset at(WidgetTester tester, MarkupScreenState state, Offset point) =>
        tester.getTopLeft(find.byKey(const ValueKey<String>('markup-page'))) +
        point * state.fit;

    Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(from + by * (i / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);
    }

    Uint8List withWords() => PdfAnnotator.annotated(_open(_page()), [
      const TextBoxEdit(0, rect: _box, text: 'A note', size: 12),
    ]);

    testWidgets(
      'opens holding the marks the file already has, ready to pick up',
      (tester) async {
        final state = await open(tester, withWords());
        expect(state.tool, MarkupTool.select);
        expect(state.marks, hasLength(1));
        expect(state.marks.single.found, isNotNull);
        expect(state.selection, isNull);
      },
    );

    testWidgets('a tap picks a mark up, with its bar of actions', (
      tester,
    ) async {
      final state = await open(tester, withWords());
      await tester.tapAt(at(tester, state, _box.center));
      await settle(tester);
      expect(state.selection, isNotNull);
      expect(
        find.byKey(const ValueKey<String>('markup-actions')),
        findsOneWidget,
      );
      for (final label in ['Cut', 'Copy', 'Delete']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tapAt(at(tester, state, const Offset(250, 380)));
      await settle(tester);
      expect(state.selection, isNull);
    });

    testWidgets(
      'a mark from the file is picked up, dragged somewhere else and saved as moved',
      (tester) async {
        final state = await open(tester, withWords());
        await tester.tapAt(at(tester, state, _box.center));
        await settle(tester);
        await drag(
          tester,
          at(tester, state, _box.center),
          const Offset(60, 90),
        );
        final moved = state.marks.single;
        final shift = moved.shift;
        expect(shift.dx, closeTo(60 / state.fit, 1));
        expect(shift.dy, closeTo(90 / state.fit, 1));
        expect(moved.reshaped, isFalse);
        await tester.tap(find.text('SAVE'));
        await settle(tester);
        final update = saved!.updates.single as MarkMoved;
        expect(update.origin, const MarkOrigin(0, 0));
        final out = PdfAnnotator.apply(pages.file, updates: saved!.updates);
        expectRect(
          readMarks(_open(out), 0).single.edit.bounds,
          _box.shift(shift),
          within: 0.01,
        );
      },
    );

    testWidgets('a picked up small box moves from its middle rather than stretching', (tester) async {
      final state = await open(tester, PdfAnnotator.annotated(_open(_page()), [
        const TextBoxEdit(0, rect: Rect.fromLTWH(40, 100, 120, 16), text: 'Tiny', size: 10),
      ]));
      const middle = Offset(100, 108);
      await tester.tapAt(at(tester, state, middle));
      await settle(tester);
      expect(state.selection, isNotNull);
      await drag(tester, at(tester, state, middle), const Offset(0, 80));
      final mark = state.marks.single;
      expect(mark.reshaped, isFalse);
      expect(mark.edit.bounds.height, closeTo(16, 0.01));
      expect(mark.shift.dy, closeTo(80 / state.fit, 1));
    });

    testWidgets(
      'a corner handle makes a box of words wider and keeps it tall enough',
      (tester) async {
        final state = await open(tester, withWords());
        await tester.tapAt(at(tester, state, _box.center));
        await settle(tester);
        // The handle is drawn at the corner of the frame round the box,
        // which stands clear of a box this thin.
        await drag(
          tester,
          at(tester, state, selectionFrame(_box, state.fit).bottomRight),
          const Offset(60, 0),
        );
        final words = state.marks.single.edit as TextBoxEdit;
        expect(words.rect.width, closeTo(_box.width + 60 / state.fit, 1));
        expect(
          words.rect.height,
          greaterThanOrEqualTo(
            PdfAnnotator.wordsHeight('A note', 12, words.rect.width) - 0.01,
          ),
        );
        expect(state.changes.updates.single, isA<MarkRewritten>());
      },
    );

    testWidgets(
      'delete takes a mark off, undo puts it back and redo takes it off again',
      (tester) async {
        final state = await open(tester, withWords());
        await tester.tapAt(at(tester, state, _box.center));
        await settle(tester);
        await tester.tap(find.text('Delete'));
        await settle(tester);
        expect(state.marks, isEmpty);
        expect(state.changes.updates.single, isA<MarkRemoved>());
        await tester.tap(find.bySemanticsLabel('Undo'));
        await settle(tester);
        expect(state.marks, hasLength(1));
        expect(state.changes.isEmpty, isTrue);
        await tester.tap(find.bySemanticsLabel('Redo'));
        await settle(tester);
        expect(state.marks, isEmpty);
      },
    );

    testWidgets('copy and paste put down a second mark beside the first', (
      tester,
    ) async {
      final state = await open(tester, withWords());
      await tester.tapAt(at(tester, state, _box.center));
      await settle(tester);
      await tester.tap(find.text('Copy'));
      await settle(tester);
      await tester.tap(find.text('Paste'));
      await settle(tester);
      expect(state.marks, hasLength(2));
      expect(state.marks.last.found, isNull);
      expectRect(
        state.marks.last.edit.bounds,
        _box.shift(const Offset(kPasteStep, kPasteStep)),
      );
      // A copy of a mark the file drew keeps its look.
      expect(state.changes.added.single, isA<KeptEdit>());
    });

    testWidgets('a double tap on words opens them to be changed', (
      tester,
    ) async {
      final state = await open(tester, withWords());
      await tester.tapAt(at(tester, state, _box.center));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at(tester, state, _box.center));
      await settle(tester);
      expect(find.byType(WordsSheet), findsOneWidget);
      expect(find.text('A note'), findsWidgets);
      await tester.enterText(find.byType(EditableText).last, 'Changed words');
      await tester.tap(find.text('Keep these words'));
      await settle(tester);
      expect((state.marks.single.edit as TextBoxEdit).text, 'Changed words');
      expect(state.changes.updates.single, isA<MarkRewritten>());
    });

    testWidgets('a highlight is dragged across the words and stays on them', (
      tester,
    ) async {
      final state = await open(tester, _page());
      await tester.tap(find.bySemanticsLabel('Highlight'));
      await settle(tester);
      // The line of words sits at 360 up from the bottom of a 400 tall page.
      await drag(
        tester,
        at(tester, state, const Offset(45, 36)),
        const Offset(120, 0),
      );
      expect(state.marks.single.edit, isA<HighlightEdit>());
      final lit = state.marks.single.edit as HighlightEdit;
      await tester.tap(find.bySemanticsLabel('Select'));
      await settle(tester);
      await drag(
        tester,
        at(tester, state, lit.rects.single.center),
        const Offset(50, 50),
      );
      expect((state.marks.single.edit as HighlightEdit).rects, lit.rects);
    });

    testWidgets('strokes drawn one after another make one drawing', (
      tester,
    ) async {
      final state = await open(tester, _page());
      await tester.tap(find.bySemanticsLabel('Ink'));
      await settle(tester);
      await drag(
        tester,
        at(tester, state, const Offset(60, 200)),
        const Offset(80, 20),
      );
      await drag(
        tester,
        at(tester, state, const Offset(60, 240)),
        const Offset(80, 20),
      );
      expect(state.marks, hasLength(1));
      expect((state.marks.single.edit as InkEdit).strokes, hasLength(2));
    });
  });
}
