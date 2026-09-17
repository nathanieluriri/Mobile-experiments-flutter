import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
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
