import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/reader/document_states.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/render_plan.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/typography.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('the designed states', () {
    testWidgets('a file that will not parse lands on the torn sheet', (
      tester,
    ) async {
      final store = DocumentStore(entryFor(kHouseStyle))
        ..loadFrom(Uint8List(64));
      expect(store.state, ParseState.failed);
      expect(store.plan, RenderPlan.damaged);
      await _pumpReader(tester, store);
      expect(find.byType(DamagedSheet), findsOneWidget);
      expect(find.byType(SheetSurface), findsNothing);
    });

    testWidgets(
      'a locked file lands on the lock sheet, never on a blank page',
      (tester) async {
        final store = await storeFor(kPressLease);
        await _pumpReader(tester, store, plan: RenderPlan.locked);
        expect(find.byType(LockedSheet), findsOneWidget);
        expect(find.text('This file is locked.'), findsOneWidget);
      },
    );

    test('the reason is stated in the document own terms', () {
      expect(damageReasonFor(null), 'The file ends before its page table.');
      expect(
        damageReasonFor(const FormatException('not a docx')),
        'The file is a package, but not the one its name promises.',
      );
      expect(
        damageReasonFor(StateError('truncated')),
        'The file ends before its table of contents.',
      );
    });

    testWidgets('plain text is only offered when the bytes decode', (
      tester,
    ) async {
      expect(decodesAsText(await documentBytes(kBinderyNotes)), isTrue);
      expect(decodesAsText(await documentBytes(kHouseStyle)), isFalse);
      expect(decodesAsText(Uint8List(0)), isFalse);
    });
  });

  group('their goldens', () {
    testWidgets('reader__damaged', (tester) async {
      final store = DocumentStore(entryFor(kSubscribers))
        ..loadFrom(Uint8List.fromList(<int>[0x50, 0x4b, 0x03, 0x04, 0x00]));
      await _pumpReader(
        tester,
        store,
        plan: RenderPlan.damaged,
        onOpenAsText: () {},
      );
      await capture(tester, 'reader__damaged');
    });

    testWidgets('reader__locked', (tester) async {
      final store = await storeFor(kPressLease);
      await _pumpReader(tester, store, plan: RenderPlan.locked);
      await capture(tester, 'reader__locked');
    });
  });
}

Future<void> _pumpReader(
  WidgetTester tester,
  DocumentStore store, {
  RenderPlan? plan,
  VoidCallback? onOpenAsText,
}) async {
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
        plan: plan,
        onOpenAsText: onOpenAsText,
        bodyBuilder: (context) => _StubBody(store: store),
      ),
    ),
  );
}

/// A body that draws nothing, because none of these states ever reaches one.
class _StubBody extends ReaderBody {
  const _StubBody({required this.store});

  final DocumentStore store;

  @override
  Widget buildFront(BuildContext context) => Center(
    child: Text(
      'the page',
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
  List<double> get foreEdgeMarks => const <double>[];
}
