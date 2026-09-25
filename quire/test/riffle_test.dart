import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/riffle_sheet.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/typography.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('the riffle', () {
    testWidgets('a tap on the fore edge opens it', (tester) async {
      await _pumpReader(tester, kBinderyNotes);
      await tester.tapAt(foreEdgeAt(0.5));
      await settle(tester);
      expect(find.byType(RiffleSheet), findsOneWidget);
    });

    testWidgets('a tap on the sheet does not', (tester) async {
      await _pumpReader(tester, kBinderyNotes);
      await tester.tapAt(const Offset(200, 400));
      await settle(tester);
      expect(find.byType(RiffleSheet), findsNothing);
    });

    testWidgets('a CSV has no riffle at all', (tester) async {
      final store = await _pumpReader(tester, kSubscribers);
      expect(riffleItemsFor(store), isEmpty);
      await tester.tapAt(foreEdgeAt(0.5));
      await settle(tester);
      expect(find.byType(RiffleSheet), findsNothing);
    });

    testWidgets('a workbook riffles its sheets, prose its headings', (
      tester,
    ) async {
      final sheets = await storeFor(kPressRunCosts);
      expect(
        riffleItemsFor(sheets).map((item) => item.title),
        containsAll(<String>['Runs', 'Paper', 'Summary']),
      );
      final prose = await storeFor(kBinderyNotes);
      final headings = riffleItemsFor(prose);
      expect(headings, isNotEmpty);
      expect(headings.first.title, isNotEmpty);
    });

    testWidgets('closing it returns the reader to where it came in', (
      tester,
    ) async {
      final store = await _pumpReader(tester, kBinderyNotes);
      store.position = 2;
      await tester.tapAt(foreEdgeAt(0.5));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Close the riffle'));
      await settle(tester);
      expect(find.byType(RiffleSheet), findsNothing);
      expect(store.position, 2);
    });

    testWidgets('the arc never covers the control that closes it', (
      tester,
    ) async {
      await _pumpReader(tester, kBinderyNotes);
      await tester.tapAt(foreEdgeAt(0.5));
      await settle(tester);

      // The arc borrowed the reading sheet's own band once, and when the
      // sheet grew to fill the glass the arc came up over the standing head
      // and swallowed every touch meant for the close control. A riffle that
      // cannot be dismissed is a trapped reader, and a tap that lands on the
      // wrong thing only warns, so it has to be asserted outright.
      final close = tester.getRect(find.bySemanticsLabel('Close the riffle'));
      expect(close.bottom, lessThanOrEqualTo(kRiffleArcTop));

      final reached = tester
          .hitTestOnBinding(close.center)
          .path
          .any(
            (entry) => find
                .bySemanticsLabel('Close the riffle')
                .evaluate()
                .any((e) => e.renderObject == entry.target),
          );
      expect(
        reached,
        isTrue,
        reason: 'the close control must answer at its own centre',
      );
    });
  });

  group('the arc', () {
    testWidgets('riffle__t0000', (tester) async {
      await _pumpReader(tester, kBinderyNotes);
      await tester.tapAt(foreEdgeAt(0.5));
      await capture(tester, 'riffle__t0000');
      await settle(tester);
    });

    testWidgets('riffle__t0220', (tester) async {
      await _pumpReader(tester, kBinderyNotes);
      await tester.tapAt(foreEdgeAt(0.5));
      await pumpMs(tester, 220);
      await capture(tester, 'riffle__t0220');
      await settle(tester);
    });

    testWidgets('riffle__rest', (tester) async {
      final store = await _pumpReader(tester, kBinderyNotes);
      store.position = 3;
      await tester.tapAt(foreEdgeAt(0.5));
      await settle(tester);
      await capture(tester, 'riffle__rest');
    });

    testWidgets('riffle__commit', (tester) async {
      await _pumpReader(tester, kBinderyNotes);
      await tester.tapAt(foreEdgeAt(0.5));
      await settle(tester);
      await tester.tapAt(const Offset(kScreenCentreX, kSheetCentreY));
      await pumpMs(tester, 150);
      await capture(tester, 'riffle__commit');
      await settle(tester);
    });
  });
}

/// The middle of the marquee, where the item the arc has landed on sits.
const kScreenCentreX = 201.0;
const kSheetCentreY = 475.0;

Future<DocumentStore> _pumpReader(WidgetTester tester, String fileName) async {
  final store = await storeFor(fileName);
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

/// A body that prints the document's own first lines, so the sheet under the
/// riffle is a real page rather than a placeholder.
class _StubBody extends ReaderBody {
  const _StubBody({required this.store});

  final DocumentStore store;

  @override
  Widget buildFront(BuildContext context) {
    final document = store.document;
    final blocks = document?.sections.first.blocks ?? const <DocBlock>[];
    return ListView.builder(
      padding: const EdgeInsets.all(26),
      itemCount: blocks.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          _textOf(blocks[index]),
          style: AppText.pageBody.copyWith(color: AppColors.ink),
        ),
      ),
    );
  }

  String _textOf(DocBlock block) => switch (block) {
    ParagraphBlock(:final text) => text,
    HeadingBlock(:final text) => text,
    ListItemBlock(:final text) => text,
    CodeBlock(:final text) => text,
    DividerBlock() => '',
    SlideBlock(:final title) => title ?? '',
    ImageBlock(:final alt) => alt ?? '',
    TableBlock(:final rows) => '${rows.length} rows',
  };

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
