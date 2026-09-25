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
import 'package:quire/screens/reader/bodies/page_states.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/bodies/sheet_grid.dart';
import 'package:quire/screens/reader/find/find_field.dart';
import 'package:quire/screens/reader/find/find_layer.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/reader_screen.dart';
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

/// Runs [count] frames at sixty a second, the way a glide is actually seen.
Future<void> _frames(WidgetTester tester, int count) async {
  for (var frame = 0; frame < count; frame++) {
    await pumpMs(tester, 16);
  }
}

/// How far down a flowing document's sheet is scrolled.
double _proseScroll(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .firstWhere((s) => s.position.axis == Axis.vertical)
    .position
    .pixels;

/// How far down a PDF's strip of pages is scrolled.
double _pdfScroll(WidgetTester tester) => tester
    .stateList<ScrollableState>(find.byType(Scrollable))
    .firstWhere((s) => s.position.axis == Axis.vertical)
    .position
    .pixels;

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
  SlideBlock() => <String>[
    for (final shape in block.shapes)
      for (final inner in shape.blocks) _wordsIn(inner),
  ].join(' '),
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

  group('going to a match in a flowing document', () {
    for (final (name, query) in <(String, String)>[
      (kHouseStyle, 'about'),
      (kBinderyNotes, 'grain'),
    ]) {
      testWidgets('every match in $name is brought on screen', (tester) async {
        final store = await storeFor(name);
        await pumpScreen(tester, _host(store));
        await settle(tester);
        final finder = await _search(tester, query);
        final blocks = <DocBlock>[
          for (final section in store.document!.sections) ...section.blocks,
        ];
        for (var step = 0; step < finder.matches.length; step++) {
          await tester.tap(find.bySemanticsLabel('Next match'));
          await _frames(tester, 70);
          if (blocks[finder.matches[finder.current].unit] is ImageBlock) {
            // A picture found by what it is described as has no letters to
            // mark, so what has to be on screen is the picture.
            final pictures = <Rect>[
              for (final element in <Element>[
                ...find.byType(Image).evaluate(),
                ...find.byType(UnsupportedImageBox).evaluate(),
              ])
                tester.getRect(find.byWidget(element.widget)),
            ];
            expect(
              pictures.any((rect) => _readable(tester, rect)),
              isTrue,
              reason: 'match ${finder.current + 1}, a picture, is on screen',
            );
            continue;
          }
          final screen = await Screen.of(tester);
          final live = _proseOccurrences(tester, query).where(
            (rect) =>
                _readable(tester, rect) && _washOf(screen, rect) > 100,
          );
          expect(
            live,
            isNotEmpty,
            reason: 'match ${finder.current + 1} of ${finder.matches.length} '
                'is on screen and marked as the one stood on',
          );
        }
        await _release(tester);
      });
    }

    testWidgets('a step glides there rather than jumping', (tester) async {
      final store = await storeFor(kHouseStyle);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      final finder = await _search(tester, 'about');
      // From the fifth match to the sixth is most of the document.
      for (var step = 0; step < 4; step++) {
        await tester.tap(find.bySemanticsLabel('Next match'));
        await _frames(tester, 70);
      }
      expect(finder.current, 4);
      final from = _proseScroll(tester);
      await tester.tap(find.bySemanticsLabel('Next match'));
      final path = <double>[from];
      for (var frame = 0; frame < 70; frame++) {
        await pumpMs(tester, 16);
        path.add(_proseScroll(tester));
      }
      final to = path.last;
      final distance = (to - from).abs();
      expect(distance, greaterThan(400), reason: 'a long way to go');
      final between = path
          .where((p) => (p - from).abs() > 2 && (p - to).abs() > 2)
          .length;
      expect(between, greaterThanOrEqualTo(12), reason: 'it is seen moving');
      for (var i = 1; i < path.length; i++) {
        expect(
          (path[i] - path[i - 1]).abs(),
          lessThan(distance * 0.2),
          reason: 'no one frame covers a fifth of the way (frame $i)',
        );
      }
      await _release(tester);
    });

    testWidgets('a second step mid glide carries on from where the page is', (
      tester,
    ) async {
      final store = await storeFor(kHouseStyle);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _search(tester, 'about');
      await tester.tap(find.bySemanticsLabel('Next match'));
      await _frames(tester, 70);

      await tester.tap(find.bySemanticsLabel('Next match'));
      await _frames(tester, 6);
      final midway = _proseScroll(tester);
      await tester.tap(find.bySemanticsLabel('Next match'));
      await pumpMs(tester, 16);
      final after = _proseScroll(tester);
      expect(
        (after - midway).abs(),
        lessThan(60),
        reason: 'the page carries on from where it was, it does not leap',
      );
      await _release(tester);
    });
  });

  group('going to a match in a PDF', () {
    testWidgets('every match is brought on screen, big enough to read', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      final finder = await _search(tester, 'grain');
      // Forward through the first dozen, then back round to the last, which is
      // the far end of the document.
      final steps = <String>[
        for (var i = 0; i < 12; i++) 'Next match',
        for (var i = 0; i < 13; i++) 'Previous match',
      ];
      for (final step in steps) {
        await tester.tap(find.bySemanticsLabel(step));
        await _frames(tester, 70);
        final match = finder.matches[finder.current];
        final rect = _pdfMatchRect(tester, match);
        final where = 'match ${finder.current + 1} of ${finder.matches.length}';
        expect(rect, isNotNull, reason: '$where has its page built');
        expect(
          _readable(tester, rect!),
          isTrue,
          reason: '$where is on screen under the bar, at $rect',
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(18),
          reason: '$where is set big enough to read',
        );
        final screen = await Screen.of(tester);
        expect(
          _washOf(screen, rect),
          greaterThan(100),
          reason: '$where is marked as the one stood on',
        );
      }
      await _release(tester);
    });

    testWidgets('a step glides and zooms there rather than jumping', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _search(tester, 'grain');
      await tester.tap(find.bySemanticsLabel('Next match'));
      await _frames(tester, 70);
      // Back round to the last match: the other end of the document.
      await tester.tap(find.bySemanticsLabel('Previous match'));
      await tester.tap(find.bySemanticsLabel('Previous match'));
      final down = <double>[_pdfScroll(tester)];
      final zoom = <double>[store.zoom];
      for (var frame = 0; frame < 70; frame++) {
        await pumpMs(tester, 16);
        down.add(_pdfScroll(tester));
        zoom.add(store.zoom);
      }
      final travel = (down.last - down.first).abs();
      expect(travel, greaterThan(1000), reason: 'a long way to go');
      final between = down
          .where((p) => (p - down.first).abs() > 2 && (p - down.last).abs() > 2)
          .length;
      expect(between, greaterThanOrEqualTo(12), reason: 'it is seen moving');
      for (var i = 1; i < down.length; i++) {
        expect(
          (down[i] - down[i - 1]).abs(),
          lessThan(travel * 0.2),
          reason: 'no one frame covers a fifth of the way (frame $i)',
        );
        expect(
          (zoom[i] / zoom[i - 1] - 1).abs(),
          lessThan(0.2),
          reason: 'no one frame changes the size by a fifth (frame $i)',
        );
      }
      await _release(tester);
    });

    testWidgets('a second step mid glide carries on from where the page is', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _search(tester, 'grain');
      await tester.tap(find.bySemanticsLabel('Next match'));
      await _frames(tester, 70);
      await tester.tap(find.bySemanticsLabel('Next match'));
      await _frames(tester, 6);
      final midway = (_pdfScroll(tester), store.zoom);
      await tester.tap(find.bySemanticsLabel('Next match'));
      await pumpMs(tester, 16);
      final after = (_pdfScroll(tester), store.zoom);
      expect(
        (after.$1 - midway.$1).abs(),
        lessThan(60),
        reason: 'the page carries on from where it was, it does not leap',
      );
      expect(
        (after.$2 / midway.$2 - 1).abs(),
        lessThan(0.1),
        reason: 'the size carries on from where it was',
      );
      await _release(tester);
    });
  });

  group('putting find away', () {
    testWidgets('Done glides a PDF back out to the size it was read at', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      expect(store.fit, FitMode.width);
      final finder = await _search(tester, 'grain');
      await tester.tap(find.bySemanticsLabel('Next match'));
      await _frames(tester, 70);
      expect(store.zoom, greaterThan(2), reason: 'find brought the page up');
      final stoodOn = finder.matches[finder.current];

      await tester.tap(find.text(kFindCancelLabel));
      final sizes = <double>[store.zoom];
      for (var frame = 0; frame < 70; frame++) {
        await pumpMs(tester, 16);
        sizes.add(store.fit == FitMode.width ? 1.0 : store.zoom);
      }
      expect(store.fit, FitMode.width, reason: 'back to fitting the width');
      final shrinking = sizes
          .where((z) => z < sizes.first - 0.05 && z > 1.05)
          .length;
      expect(shrinking, greaterThanOrEqualTo(8), reason: 'seen going back');
      final rect = _pdfMatchRect(tester, stoodOn);
      expect(rect, isNotNull);
      expect(
        rect!.top >= 0 && rect.bottom <= 874,
        isTrue,
        reason: 'the match it stood on is still on screen, at $rect',
      );
      await _release(tester);
    });

    testWidgets('Done keeps a size the reader chose while searching', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _search(tester, 'grain');
      await tester.tap(find.bySemanticsLabel('Next match'));
      await _frames(tester, 70);
      store.zoomTo(4.5);
      await _frames(tester, 4);

      await tester.tap(find.text(kFindCancelLabel));
      await _frames(tester, 70);
      expect(store.fit, FitMode.free);
      expect(store.zoom, 4.5, reason: 'a size somebody chose is theirs');
      await _release(tester);
    });
  });

  group('typing a query', () {
    testWidgets('starts from where the reader is and goes there once they stop', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      store.position = 3;
      await settle(tester);
      expect(store.position, 3, reason: 'reading page four');

      // Reading on took the band away, so find is opened the way the menu
      // opens it.
      tester.widget<ReaderScreen>(find.byType(ReaderScreen)).onFind?.call();
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'grain');
      await tester.pump();
      final finder = tester.widget<FindLayer>(find.byType(FindLayer)).controller;
      final first = finder.matches.indexWhere((m) => m.unit >= 3);
      expect(finder.current, first, reason: 'the first match from page four');

      // Still typing: nothing has moved yet.
      final before = _pdfScroll(tester);
      await _frames(tester, 10);
      expect(_pdfScroll(tester), before, reason: 'a keystroke does not move it');

      // Stopped: it goes there.
      await _frames(tester, 80);
      final rect = _pdfMatchRect(tester, finder.matches[finder.current]);
      expect(rect, isNotNull);
      expect(_readable(tester, rect!), isTrue, reason: 'on screen at $rect');
      expect(rect.height, greaterThanOrEqualTo(18), reason: 'big enough');
      await _release(tester);
    });

    testWidgets('the search key on the keyboard goes there at once', (
      tester,
    ) async {
      final store = await storeFor(kHouseStyle);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Find in document'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'punctuation');
      await tester.pump();
      final before = _proseScroll(tester);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _frames(tester, 6);
      expect(
        _proseScroll(tester),
        isNot(before),
        reason: 'it set off without waiting for the pause',
      );
      await _release(tester);
    });
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
