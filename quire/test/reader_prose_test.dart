import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/bodies/page_states.dart';
import 'package:quire/screens/reader/bodies/prose_body.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/theme/typography.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('the reading column', () {
    testWidgets('is the measure the design names, in every format', (
      tester,
    ) async {
      await _pumpBlocks(tester, const <DocBlock>[
        ParagraphBlock(<DocSpan>[DocSpan('Set the measure by counting.')]),
      ]);
      expect(tester.getSize(find.byType(ProseColumn)).width, kProseMeasure);
    });

    test('space between two blocks is the larger of the two, never the sum', () {
      const heading = HeadingBlock(1, <DocSpan>[DocSpan('House Style')]);
      const body = ParagraphBlock(<DocSpan>[DocSpan('This is how we set type.')]);
      expect(proseSpaceAbove(heading), 28);
      expect(proseSpaceBelow(heading), 10);
      expect(proseSpaceBelow(body), 12);
      expect(proseGap(body, heading), 28);
      expect(proseGap(heading, body), 10);
    });

    test('a heading past the third level keeps the third level size', () {
      const h3 = HeadingBlock(3, <DocSpan>[DocSpan('Trimming allowance')]);
      const h6 = HeadingBlock(6, <DocSpan>[DocSpan('A note on humidity')]);
      expect(proseHeadingStyle(h3), AppText.pageHeading3);
      expect(proseHeadingStyle(h6), AppText.pageHeading3);
      expect(proseSpaceAbove(h6), 20);
      expect(proseSpaceBelow(h6), 6);
    });
  });

  group('a run inside a paragraph', () {
    test('a line break where the source wrapped is a space, not a break', () {
      expect(
        foldLineBreak('Our house stock is listed in the\npaper record.'),
        'Our house stock is listed in the paper record.',
      );
      expect(foldLineBreak('one   two'), 'one   two');
    });

    test('bold is 600, because 700 shouts in a reading column', () {
      expect(
        proseSpanStyle(const DocSpan('dead flat', bold: true)).fontWeight,
        FontWeight.w600,
      );
    });

    test('italic is weight 500 with tracking, and is never skewed', () {
      final style = proseSpanStyle(const DocSpan('colour', italic: true));
      expect(style.fontWeight, FontWeight.w500);
      expect(style.letterSpacing, 0.2);
      expect(style.fontStyle, isNot(FontStyle.italic));
    });

    test('a link is ink underlined in faint, and is never coloured', () {
      final style = proseSpanStyle(
        const DocSpan('the prepress checklist', href: 'https://example/x'),
      );
      expect(style.color, AppColors.ink);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.decoration, TextDecoration.underline);
      // A step under the text, not down at the rule colour: a rule that is
      // invisible on a dark sheet leaves a link telling itself apart from
      // body text by weight alone.
      expect(style.decorationColor, AppColors.inkFaint);
    });

    test('a document colour is never carried onto the page', () {
      final style = proseSpanStyle(
        const DocSpan('Quire Press', color: 0xFFCC0000),
      );
      expect(style.color, AppColors.inkSoft);
    });

    testWidgets('a mono run sits on its own slab', (tester) async {
      await _pumpBlocks(tester, const <DocBlock>[
        ParagraphBlock(<DocSpan>[
          DocSpan('Cold rooms, and '),
          DocSpan('PUR', mono: true),
          DocSpan(' adhesive.'),
        ]),
      ]);
      expect(find.byType(MonoSpan), findsOneWidget);
      expect(find.text('PUR'), findsOneWidget);
    });
  });

  group('every block the model can hold', () {
    testWidgets('a checklist draws a box per item, ticked or not', (
      tester,
    ) async {
      final doc = await parsedDocument(kBinderyNotes);
      final ticks = doc.sections.first.blocks
          .whereType<ListItemBlock>()
          .where((item) => item.checked != null)
          .toList();
      expect(ticks, hasLength(6));
      await _pumpBlocks(tester, ticks);
      expect(find.byType(CheckMark), findsNWidgets(6));
      final checked = tester
          .widgetList<CheckMark>(find.byType(CheckMark))
          .where((box) => box.checked)
          .length;
      expect(checked, 2);
    });

    testWidgets('a heading is set at its own level, in ink', (tester) async {
      await _pumpBlocks(tester, const <DocBlock>[
        HeadingBlock(1, <DocSpan>[DocSpan('House Style')]),
        HeadingBlock(2, <DocSpan>[DocSpan('The measure and the leading')]),
      ]);
      expect(find.text('House Style'), findsOneWidget);
      final first = tester.getRect(find.text('House Style'));
      final second = tester.getRect(find.text('The measure and the leading'));
      expect(first.height, greaterThan(second.height));
    });

    testWidgets('a fenced block names its language, when the file does', (
      tester,
    ) async {
      final doc = await parsedDocument(kBinderyNotes);
      final code = doc.sections.first.blocks.whereType<CodeBlock>().toList();
      expect(code, hasLength(2));
      await _pumpBlocks(tester, code);
      expect(find.text('yaml'), findsOneWidget);
      expect(find.byType(CodeSlab), findsNWidgets(2));
    });

    testWidgets('an ordered item hangs its own resolved marker', (
      tester,
    ) async {
      await _pumpBlocks(tester, const <DocBlock>[
        ListItemBlock(<DocSpan>[DocSpan('Tear a strip.')],
            level: 0, ordered: true, marker: '1.'),
        ListItemBlock(<DocSpan>[DocSpan('Three hundred pixels per inch.')],
            level: 1, ordered: true, marker: 'a)'),
      ]);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('a)'), findsOneWidget);
    });

    testWidgets('a table keeps its spans and fits the measure', (tester) async {
      final doc = await parsedDocument(kHouseStyle);
      final table = doc.sections.first.blocks.whereType<TableBlock>().single;
      expect(table.rows.last.cells.first.colSpan, 3);
      await _pumpBlocks(tester, <DocBlock>[table]);
      expect(find.byType(ProseTable), findsOneWidget);
      expect(
        tester.getSize(find.byType(ProseTable)).width,
        lessThanOrEqualTo(kProseMeasure),
      );
      expect(find.text('Kind of number'), findsOneWidget);
    });

    testWidgets('an image the file does not carry leaves its rect behind', (
      tester,
    ) async {
      await _pumpBlocks(tester, const <DocBlock>[
        ImageBlock('images/grain-fold-test.png', alt: 'Grain fold test'),
      ]);
      expect(find.byType(UnsupportedImageBox), findsOneWidget);
      expect(find.text(kImageLabel), findsOneWidget);
    });

    testWidgets('an image the file does carry is drawn from its own bytes', (
      tester,
    ) async {
      final doc = await parsedDocument(kHouseStyle);
      final image = doc.sections.first.blocks.whereType<ImageBlock>().single;
      await _pumpBlocks(
        tester,
        <DocBlock>[image],
        assets: doc.assets,
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(UnsupportedImageBox), findsNothing);
    });

    testWidgets('a rule is a typographic full point, not a divider', (
      tester,
    ) async {
      await _pumpBlocks(tester, const <DocBlock>[DividerBlock()]);
      final rule = tester.getSize(
        find.descendant(
          of: find.byType(ProseRule),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(rule.width, closeTo(kProseMeasure * kProseRuleFraction, 0.01));
      expect(rule.height, 1);
    });

    testWidgets('a quotation hangs on a bar, not on quotation marks', (
      tester,
    ) async {
      await _pumpBlocks(tester, const <DocBlock>[
        ParagraphBlock(<DocSpan>[DocSpan('Set the punctuation.')], quote: true),
      ]);
      expect(find.byType(QuoteBar), findsOneWidget);
    });
  });

  group('the body in the shell', () {
    testWidgets('a flowing document reports a percentage, not a block', (
      tester,
    ) async {
      final store = await storeFor(kBinderyNotes);
      final body = ProseBody(store: store, document: (await parsedDocument(kBinderyNotes)));
      expect(body.unitCount, store.unitCount);
      expect(body.positionLabel.endsWith('%'), isTrue);
      expect(body.foreEdgeMarks.length, greaterThan(4));
      expect(body.foreEdgeMarks.first, 0);
      expect(body.foreEdgeMarks.every((m) => m >= 0 && m <= 1), isTrue);
    });

    testWidgets('opening at a block puts that block at the top', (
      tester,
    ) async {
      await _pumpProse(tester, kBinderyNotes, anchorBlock: 44);
      final heading = tester.getRect(find.text('Before the Guillotine'));
      expect(heading.top, lessThan(kSheetTop + 80));
      expect(heading.top, greaterThan(kSheetTop));
    });

    testWidgets('scrolling moves the reader through the document', (
      tester,
    ) async {
      final store = await _pumpProse(tester, kHouseStyle);
      expect(store.position, 0);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pump();
      expect(store.position, greaterThan(0));
    });
  });

  group('its goldens', () {
    testWidgets('reader__docx', (tester) async {
      await _pumpProse(tester, kHouseStyle, anchorBlock: 26);
      await capture(tester, 'reader__docx');
    });

    testWidgets('reader__markdown', (tester) async {
      await _pumpProse(tester, kBinderyNotes, anchorBlock: 44);
      await capture(tester, 'reader__markdown');
    });

    testWidgets('reader__markdown_code', (tester) async {
      await _pumpProse(tester, kBinderyNotes, anchorBlock: 36);
      await capture(tester, 'reader__markdown_code');
    });
  });
}

/// Pumps [blocks] inside the sheet's own column, with nothing else on screen,
/// so a block's own rendering can be judged without the shell around it.
Future<void> _pumpBlocks(
  WidgetTester tester,
  List<DocBlock> blocks, {
  Map<String, Uint8List> assets = const <String, Uint8List>{},
}) async {
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: AppColors.surface,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: kSheetWidth,
            height: kSheetHeight,
            child: SingleChildScrollView(
              child: Center(
                child: ProseColumn(blocks: blocks, assets: assets),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The named document open in the reader, scrolled to [anchorBlock].
Future<DocumentStore> _pumpProse(
  WidgetTester tester,
  String fileName, {
  int anchorBlock = 0,
}) async {
  final store = await storeFor(fileName);
  final document = await parsedDocument(fileName);
  final source = fileName.endsWith('.md')
      ? String.fromCharCodes(await documentBytes(fileName))
      : null;
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
        bodyBuilder: (context) => ProseBody(
          store: store,
          document: document,
          source: source,
          anchorBlock: anchorBlock,
        ),
      ),
    ),
  );
  await tester.pump();
  await precacheImages(tester);
  await settle(tester);
  return store;
}
