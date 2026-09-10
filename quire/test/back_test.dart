import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/reader/reader_route.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/typography.dart';

import 'support/golden.dart';

void main() {
  group('the back edge region', () {
    testWidgets('a drag from the edge zone slides the reader off', (
      tester,
    ) async {
      await _pumpReader(tester);
      final gesture = await dragAndHold(
        tester,
        const Offset(10, 400),
        const Offset(150, 400),
      );
      expect(_slide(tester), greaterThan(0));
      await gesture.up();
      await settle(tester);
    });

    testWidgets('a drag that starts outside the edge zone never slides', (
      tester,
    ) async {
      await _pumpReader(tester);
      final gesture = await dragAndHold(
        tester,
        const Offset(200, 400),
        const Offset(340, 400),
      );
      expect(_slide(tester), 0);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('past the commit distance the reader leaves', (tester) async {
      await _pumpReader(tester);
      final gesture = await dragAndHold(
        tester,
        const Offset(10, 400),
        const Offset(150, 400),
      );
      await gesture.up();
      await settle(tester);
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.byType(DeskScreen), findsOneWidget);
    });

    testWidgets('short of it the reader springs back', (tester) async {
      await _pumpReader(tester);
      final gesture = await dragAndHold(
        tester,
        const Offset(10, 400),
        const Offset(70, 400),
      );
      await gesture.up();
      await settle(tester);
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(_slide(tester), 0);
    });
  });

  testWidgets('back__t0300', (tester) async {
    // The desk under the reader carries a search field, and a blinking caret
    // would make this golden disagree with itself.
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
    await _pumpReader(tester);
    final gesture = await tester.startGesture(const Offset(10, 400));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(14, 0));
      await pumpMs(tester, 30);
    }
    await capture(tester, 'back__t0300');
    await gesture.up();
    await settle(tester);
  });
}

/// How far the reader has been slid off, read from the transform the shell
/// actually applied rather than from its private state.
double _slide(WidgetTester tester) {
  final finder = find.byType(ReaderScreen);
  if (finder.evaluate().isEmpty) return 0;
  final sheet = find.byType(SheetSurface);
  if (sheet.evaluate().isEmpty) return 0;
  return tester.getTopLeft(sheet).dx - 12;
}

/// The reader over the real desk.
///
/// A back drag reveals whatever is behind the reader, so what is behind it has
/// to be the desk itself: a stand in would prove the slide moves a widget, not
/// that it uncovers the shelf a reader left.
Future<void> _pumpReader(WidgetTester tester) async {
  final store = DocumentStore(_entry)..pdfPageCount = 6;
  final library = LibraryStore();
  await library.hydrate();
  addTearDown(library.dispose);
  await pumpScreen(
    tester,
    App(
      routes: <String, WidgetBuilder>{
        kDeskRoute: (context) => DeskScreen(store: library),
      },
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  unawaited(
    navigator.push(
      ReaderRoute<void>(
        builder: (context) => ReaderScreen(
          store: store,
          bodyBuilder: (context) => _StubBody(store: store),
        ),
      ),
    ),
  );
  await settle(tester);
}

const _entry = LibraryEntry(
  path: 'assets/documents/field-guide-to-paper.pdf',
  title: 'Field Guide To Paper',
  format: DocFormat.pdf,
  bytes: 313458,
);

/// A body of plain numbered lines, standing in for a real format.
class _StubBody extends ReaderBody {
  const _StubBody({required this.store});

  final DocumentStore store;

  @override
  Widget buildFront(BuildContext context) => ListView.builder(
    itemCount: 60,
    itemExtent: 24,
    itemBuilder: (context, index) => Text(
      'Line ${index + 1}',
      style: AppText.pageBody.copyWith(color: AppColors.ink),
    ),
  );

  @override
  Widget buildBack(BuildContext context) => const SizedBox.expand();

  @override
  int get unitCount => store.unitCount;

  @override
  String get positionLabel => store.positionLabel;

  @override
  List<double> get foreEdgeMarks => <double>[
    for (var i = 0; i < store.unitCount; i++)
      i / (store.unitCount - 1).clamp(1, double.infinity),
  ];
}
