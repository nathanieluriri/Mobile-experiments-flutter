import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/model/search.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/pdf_search.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/bodies/sheet_grid.dart';
import 'package:quire/screens/reader/find/find_field.dart';
import 'package:quire/screens/reader/find/find_layer.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/digit_roll.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';
import 'support/pixels.dart';

Widget _host(DocumentStore store) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderHost(store: store),
);

/// Opens find from the band's own pill and types [query] into it.
Future<FindController> _search(WidgetTester tester, String query) async {
  await tester.tap(find.bySemanticsLabel('Find in document'));
  await settle(tester);
  await tester.enterText(find.byType(EditableText), query);
  // A frame for the sweep to start on, then long enough for it to finish.
  await tester.pump();
  await pumpMs(tester, 700);
  return tester.widget<FindLayer>(find.byType(FindLayer)).controller;
}

/// Lets go of the field, so the caret's blink timer is not still pending when
/// the tree comes down.
Future<void> _release(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(seconds: 1));
}

/// Where a PDF match's letters are painted on the screen, or null while its
/// page is not built.
///
/// A page sets each of its lines in the app's typeface and fits it to the
/// width the file gives the line, so the letters are wherever that setting
/// puts them. This sets the line the same way, independently of the reader,
/// and measures the match in it.
Rect? _pdfMatchRect(WidgetTester tester, FindMatch match) {
  for (final element in find.byType(PdfPageView).evaluate()) {
    final view = element.widget as PdfPageView;
    if (view.page.index != match.unit) continue;
    final runs = view.page.runs;
    if (match.path.isEmpty || match.path.first >= runs.length) return null;
    final run = runs[match.path.first];
    final setting = TextPainter(
      text: TextSpan(
        text: run.text,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: run.size,
          height: 1.0,
          fontWeight: run.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final fit = run.width > 0 && setting.width > 0
        ? run.width / setting.width
        : 1.0;
    final squeeze = fit > 0.55 && fit < 1.8 ? fit : 1.0;
    final letters = setting.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    setting.dispose();
    if (letters.isEmpty) return null;
    final left = letters.first.left;
    final right = letters.last.right;
    final page = tester.getRect(find.byWidget(view));
    final scale = page.width / view.page.size.width;
    return Rect.fromLTWH(
      page.left + (run.x + left * squeeze) * scale,
      page.top + (run.y - run.size * 0.8) * scale,
      (right - left) * squeeze * scale,
      run.size * scale,
    );
  }
  return null;
}

/// Every place [query] is set in the reading column, found in the text the
/// screen actually lays out rather than in the model, so a mark in the wrong
/// place cannot pass for one in the right place.
List<Rect> _proseOccurrences(WidgetTester tester, String query) {
  final out = <Rect>[];
  for (final paragraph in tester.allRenderObjects.whereType<RenderParagraph>()) {
    final text = paragraph.text.toPlainText().toLowerCase();
    var from = 0;
    while (true) {
      final at = text.indexOf(query, from);
      if (at < 0) break;
      from = at + query.length;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: at, extentOffset: at + query.length),
      );
      if (boxes.isEmpty) continue;
      final origin = paragraph.localToGlobal(Offset.zero);
      out.add(boxes.first.toRect().shift(origin));
    }
  }
  return out;
}

/// True when [rect] is wholly on the part of the screen a page is read on:
/// under the find bar and above the foot of the screen.
bool _readable(WidgetTester tester, Rect rect) {
  final safe = tester.view.padding.top / tester.view.devicePixelRatio;
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  return rect.top >= safe + kHeadBandHeight && rect.bottom <= height - 60;
}

/// How much highlighter is under [rect]: the most any sampled point leans
/// toward yellow, red minus blue out of 255. Paper, white or dark, and ink,
/// light or dark, sit near zero.
double _washOf(Screen screen, Rect rect) {
  var most = -255.0;
  for (final fx in const <double>[0.1, 0.3, 0.5, 0.7, 0.9]) {
    for (final fy in const <double>[0.25, 0.45, 0.65]) {
      final colour = screen.at(
        Offset(rect.left + rect.width * fx, rect.top + rect.height * fy),
      );
      final lean = (colour.r - colour.b) * 255;
      if (lean > most) most = lean;
    }
  }
  return most;
}

/// Everything a block says, its table cells included, for asking whether a
/// match really is where it claims to be.
String _wordsIn(DocBlock block) => switch (block) {
  ParagraphBlock() => block.text,
  HeadingBlock() => block.text,
  ListItemBlock() => block.text,
  CodeBlock() => block.text,
  ImageBlock() => block.alt ?? '',
  DividerBlock() => '',
  TableBlock() => <String>[
    for (final row in block.rows)
      for (final cell in row.cells)
        for (final inner in cell.blocks) _wordsIn(inner),
  ].join('\n'),
};

void main() {
  group('where a match is', () {
    test('a PDF match carries the box its word sits in on the page', () async {
      final file = PdfFile.open(await documentBytes(kFieldGuide));
      final search = PdfSearch.fromDisplayLists(<PageDisplayList>[
        for (var i = 0; i < file.pageCount; i++)
          ContentInterpreter(file).run(file.pages[i]),
      ]);
      final hits = search.search('grain');
      final matches = PdfFindSource(search).find('grain');
      expect(matches, hasLength(hits.length));
      for (var i = 0; i < hits.length; i++) {
        expect(matches[i].box, hits[i].rect, reason: 'match $i');
      }
    });

    for (final (name, query, blocks) in <(String, String, int)>[
      (kHouseStyle, 'about', 50),
      (kBinderyNotes, 'grain', 57),
      (kBinderyNotes, 'the', 57),
    ]) {
      test('a match in $name names the block "$query" is laid out in', () async {
        final doc = await parsedDocument(name);
        final laidOut = <DocBlock>[
          for (final section in doc.sections) ...section.blocks,
        ];
        expect(laidOut, hasLength(blocks));
        final source = DocFindSource(searchFor(doc));
        // The reader lays a flowing document out block by block, so that is
        // what a match has to be counted in for a step to land on it.
        expect(source.unitCount, blocks);
        final matches = source.find(query);
        expect(matches, isNotEmpty);
        for (final match in matches) {
          expect(
            _wordsIn(laidOut[match.unit]).toLowerCase(),
            contains(query),
            reason: 'match at ${match.path} named block ${match.unit}',
          );
        }
      });
    }
  });

  group('the find bar', () {
    testWidgets('the count and the arrows sit on the bar, never on the page', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      final finder = await _search(tester, 'grain');
      expect(finder.matches, hasLength(30));

      final count = tester.getRect(
        find.descendant(
          of: find.byType(FindLayer),
          matching: find.byType(DigitRoll),
        ),
      );
      final previous = tester.getRect(find.bySemanticsLabel('Previous match'));
      final next = tester.getRect(find.bySemanticsLabel('Next match'));
      final screen = await Screen.of(tester);

      // What is just either side of the count, and in the corners of each
      // arrow's own box, is whatever the count and the arrows are drawn on. A
      // white page there is a count nobody can read.
      final behind = <Offset>[
        Offset(count.left - 3, count.center.dy),
        Offset(count.right + 3, count.center.dy),
        for (final arrow in <Rect>[previous, next]) ...<Offset>[
          arrow.topLeft + const Offset(2, 2),
          arrow.topRight + const Offset(-2, 2),
          arrow.bottomLeft + const Offset(2, -2),
          arrow.bottomRight + const Offset(-2, -2),
        ],
      ];
      for (final point in behind) {
        expect(
          screen.at(point),
          looksLike(AppColors.surfaceHigh),
          reason: 'behind the count and the arrows at $point',
        );
      }
      await _release(tester);
    });

    testWidgets('the top of the screen stays covered after the band has gone', (
      tester,
    ) async {
      final store = await storeFor(kHouseStyle);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _search(tester, 'about');

      // Going down the document to a match takes the band away, and find must
      // not go with it: the words going past under the status bar would be
      // read through the search they are being searched by.
      for (var step = 0; step < 3; step++) {
        await tester.tap(find.bySemanticsLabel('Next match'));
        for (var frame = 0; frame < 60; frame++) {
          await pumpMs(tester, 16);
        }
      }
      expect(
        tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden,
        1,
        reason: 'the band has left the screen',
      );

      final screen = await Screen.of(tester);
      for (final point in const <Offset>[
        Offset(kScreenWidth / 2, kSafeTop / 2),
        Offset(kScreenWidth / 2, 4),
        Offset(8, kSafeTop + kHeadBandHeight / 2),
        Offset(kScreenWidth / 2, kSafeTop + kHeadBandHeight - 3),
      ]) {
        expect(
          screen.at(point),
          looksLike(AppColors.ground),
          reason: 'the head of the screen at $point',
        );
      }
      await _release(tester);
    });

    testWidgets('a workbook stays where it is when find opens', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      final before = tester.getRect(find.byType(SheetGrid)).top;

      await _search(tester, 'ream');

      // The count lives in the bar now, so nothing has to make room for it
      // under the band, and the column letters stay where the eye left them.
      expect(tester.getRect(find.byType(SheetGrid)).top, before);
      await _release(tester);
    });

    testWidgets('the arrows in the bar step through the matches', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      final finder = await _search(tester, 'grain');
      final bar = tester.getRect(find.byType(FindField));
      final next = tester.getRect(find.bySemanticsLabel('Next match'));
      expect(
        bar.contains(next.center),
        isTrue,
        reason: 'the arrow is on the bar',
      );

      await tester.tap(find.bySemanticsLabel('Next match'));
      await pumpMs(tester, 100);
      expect(finder.current, 1);
      await tester.tap(find.bySemanticsLabel('Previous match'));
      await tester.tap(find.bySemanticsLabel('Previous match'));
      await pumpMs(tester, 100);
      expect(finder.current, 29, reason: 'back from the first is the last');
      await _release(tester);
    });
  });

  group('the marks', () {
    testWidgets('the words found are marked on a PDF page', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      final finder = await _search(tester, 'grain');
      final screen = await Screen.of(tester);

      final seen = <int, double>{};
      final beside = <int, double>{};
      for (var i = 0; i < finder.matches.length; i++) {
        final match = finder.matches[i];
        final rect = _pdfMatchRect(tester, match);
        if (rect == null || !_readable(tester, rect)) continue;
        seen[i] = _washOf(screen, rect);
        // A letter's width either side of the word is not part of the word,
        // so the marker must not be there. A neighbour that is itself a match
        // is the one place it may be.
        final letter = rect.width / (match.end - match.start);
        final crowded = finder.matches.any(
          (other) =>
              !identical(other, match) &&
              other.unit == match.unit &&
              listEquals(other.path, match.path) &&
              (other.end >= match.start - 2 && other.start <= match.end + 2),
        );
        if (crowded) continue;
        beside[i] = <double>[
          _washOf(
            screen,
            Rect.fromLTWH(
              rect.left - letter * 1.6,
              rect.top,
              letter * 0.8,
              rect.height,
            ),
          ),
          _washOf(
            screen,
            Rect.fromLTWH(
              rect.right + letter * 0.8,
              rect.top,
              letter * 0.8,
              rect.height,
            ),
          ),
        ].reduce((a, b) => a > b ? a : b);
      }
      expect(seen, isNotEmpty, reason: 'some matches are on screen');
      for (final entry in seen.entries) {
        expect(entry.value, greaterThan(40), reason: 'match ${entry.key}');
      }
      for (final entry in beside.entries) {
        expect(
          entry.value,
          lessThan(40),
          reason: 'the marker runs off match ${entry.key} onto its neighbours',
        );
      }
      final others = seen.entries.where((e) => e.key != finder.current);
      for (final other in others) {
        expect(
          seen[finder.current],
          greaterThan(other.value + 20),
          reason: 'the match stood on is heavier than match ${other.key}',
        );
      }
      await _release(tester);
    });

    for (final (name, query) in <(String, String)>[
      (kHouseStyle, 'about'),
      (kBinderyNotes, 'grain'),
    ]) {
      testWidgets('the words found are marked in $name', (tester) async {
        final store = await storeFor(name);
        await pumpScreen(tester, _host(store));
        await settle(tester);
        final finder = await _search(tester, query);
        final screen = await Screen.of(tester);

        var checked = 0;
        for (final rect in _proseOccurrences(tester, query)) {
          if (!_readable(tester, rect)) continue;
          checked++;
          expect(
            _washOf(screen, rect),
            greaterThan(40),
            reason: '"$query" at $rect',
          );
        }
        expect(checked, greaterThan(0), reason: 'some matches are on screen');
        expect(finder.matches, isNotEmpty);
        await _release(tester);
      });
    }
  });

  group('its goldens', () {
    testWidgets('find__on_a_white_page', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _search(tester, 'grain');
      await capture(tester, 'find__on_a_white_page');
      await _release(tester);
    });
  });
}
