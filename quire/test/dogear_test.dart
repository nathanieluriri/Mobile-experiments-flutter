import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/reader/corner_peel.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/typography.dart';

import 'support/golden.dart';

void main() {
  test('ten catch steps land between the catch and the commit distances', () {
    final travel = (_catchStep * 10).distance;
    expect(travel, greaterThan(dogEarCatchDistance(const Size(kSheetWidth, kSheetHeight)) + 20));
    expect(travel, lessThan(flipCommitDistance(const Size(kSheetWidth, kSheetHeight)) - 20));
  });

  group('the dog ear catch', () {
    testWidgets('a peel held still catches, and stays caught', (tester) async {
      final store = await _pumpReader(tester);
      final gesture = await _peelAndStop(tester);
      expect(store.dogEared, isEmpty);
      await pumpMs(tester, 200);
      expect(store.dogEared, contains(0));
      await gesture.up();
      await settle(tester);
      expect(store.dogEared, contains(0));
    });

    testWidgets('a peel that keeps moving never catches', (tester) async {
      final store = await _pumpReader(tester);
      final gesture = await _peelAndStop(tester);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-2, -2));
        await pumpMs(tester, 24);
      }
      expect(store.dogEared, isEmpty);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('dogear keyframes', (tester) async {
      await _pumpReader(tester);
      final gesture = await _peelAndStop(tester);
      await capture(tester, 'dogear__t0000');
      await pumpMs(tester, 200);
      await capture(tester, 'dogear__t0200');
      await gesture.up();
      await pumpMs(tester, 400);
      await capture(tester, 'dogear__t0600');
      await settle(tester);
    });
  });
}

/// One of ten moves that carry the corner past the dog ear's catch distance
/// and short of the flip's commit distance, on the sheet as it is now.
const _catchStep = Offset(-25, -25);

/// Holds the corner until the peel arms, drags it past the catch distance, and
/// stops moving, which is the moment the dog ear timer starts.
///
/// The gesture is written out rather than taken from a helper because the
/// whole interaction is about when the finger stopped, and a helper that pumps
/// its own trailing frames would move that moment.
Future<TestGesture> _peelAndStop(WidgetTester tester) async {
  final gesture = await tester.startGesture(sheetCornerHandle());
  await pumpMs(tester, 160);
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(_catchStep);
    await pumpMs(tester, 16);
  }
  return gesture;
}

Future<DocumentStore> _pumpReader(WidgetTester tester) async {
  final store = DocumentStore(_entry)..pdfPageCount = 6;
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
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

/// A body of plain numbered lines, standing in for a real format so the fold
/// can be judged on its own.
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
  Widget buildBack(BuildContext context) => ColoredBox(
    color: AppColors.leafBack,
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Text(
        'The back of the sheet.',
        style: AppText.bodyTight.copyWith(color: AppColors.inkSoft),
      ),
    ),
  );

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
