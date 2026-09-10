import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/reader/fore_edge.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/typography.dart';

import 'support/golden.dart';

void main() {
  group('the fore edge region', () {
    testWidgets('a drag inside the strip scrubs and never scrolls', (
      tester,
    ) async {
      final store = await _pumpReader(tester);
      final gesture = await dragAndHold(
        tester,
        foreEdgeAt(0.1),
        foreEdgeAt(0.1) + const Offset(0, 40),
      );
      expect(store.position, greaterThan(0));
      expect(_scrollOffset(), 0);
      await gesture.up();
      await settle(tester);
    });

    testWidgets(
      'the strip stops 72 points above the sheet, so the corner wins',
      (tester) async {
        final store = await _pumpReader(tester);
        final gesture = await dragAndHold(
          tester,
          const Offset(370, 790),
          const Offset(370, 700),
        );
        expect(store.position, 0);
        await gesture.up();
        await settle(tester);
      },
    );

    testWidgets('one page per 2.6 points of travel, in both directions', (
      tester,
    ) async {
      expect(scrubTarget(0, 26, 12), 10);
      expect(scrubTarget(10, -26, 12), 0);
      expect(scrubTarget(0, -100, 12), 0);
      expect(scrubTarget(0, 1000, 12), 11);
      expect(scrubTarget(3, 0, 12), 3);
    });
  });

  group('the strip', () {
    testWidgets('foreedge__scrubbing', (tester) async {
      final store = await _pumpReader(tester);
      store
        ..toggleDogEar(1)
        ..toggleDogEar(4)
        ..position = 5;
      final gesture = await dragAndHold(
        tester,
        foreEdgeAt(0.62),
        foreEdgeAt(0.62) - const Offset(0, 8),
      );
      await pumpMs(tester, 140);
      await capture(tester, 'foreedge__scrubbing');
      await gesture.up();
      await settle(tester);
    });

    testWidgets('rail__scrubbing', (tester) async {
      final store = await _pumpReader(tester, matches: _manyMatches());
      store
        ..toggleDogEar(4)
        ..position = 3;
      final gesture = await dragAndHold(
        tester,
        foreEdgeAt(0.45),
        foreEdgeAt(0.45) - const Offset(0, 6),
      );
      await pumpMs(tester, 140);
      await capture(tester, 'rail__scrubbing');
      await gesture.up();
      await settle(tester);
    });
  });
}

/// 240 matches spread through the document in three clusters, which is what a
/// real term does: it is not evenly distributed, and the whole point of the
/// rail is that the clustering is visible.
List<double> _manyMatches() {
  final marks = <double>[];
  for (var i = 0; i < 240; i++) {
    final cluster = i % 3;
    final within = (i ~/ 3) / 80;
    marks.add((cluster * 0.3 + within * 0.24).clamp(0, 1));
  }
  return marks;
}

final ScrollController _controller = ScrollController();

double _scrollOffset() => _controller.hasClients ? _controller.offset : 0;

Future<DocumentStore> _pumpReader(
  WidgetTester tester, {
  List<double> matches = const <double>[],
}) async {
  final store = DocumentStore(_entry)..pdfPageCount = 6;
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
        matches: matches,
        bodyBuilder: (context) => _StubBody(store: store),
      ),
    ),
  );
  return store;
}

const _entry = LibraryEntry(
  path: 'assets/documents/field-guide-to-paper.pdf',
  title: 'Field Guide To Paper',
  format: DocFormat.pdf,
  bytes: 313458,
);

/// A body of plain numbered lines that takes its counts from the store, so a
/// scrub moves the same number the chip prints.
class _StubBody extends ReaderBody {
  const _StubBody({required this.store});

  final DocumentStore store;

  @override
  Widget buildFront(BuildContext context) => ListView.builder(
    controller: _controller,
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
