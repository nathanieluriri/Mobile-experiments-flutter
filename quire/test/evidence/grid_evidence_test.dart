import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/edit/grid_editor.dart';

import '../support/evidence.dart';
import '../support/fixtures.dart';
import '../support/golden.dart';

/// Screens of the CSV grid at each step, and the file it writes, for a review
/// to look at. Written only when QUIRE_EVIDENCE names a folder.
void main() {
  testWidgets('csv grid, step by step', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    final original = (await tester.runAsync(() => documentBytes(kSubscribers)))!;
    writeEvidence('B', 'before.csv', original);
    Uint8List? saved;
    await pumpScreen(
      tester,
      evidenceFrame(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: GridEditor(
          title: 'Subscribers',
          bytes: original,
          onBack: () {},
          onSave: (bytes, note) async {
            saved = bytes;
            return null;
          },
        ),
      )),
    );
    await settle(tester);
    Offset cell(int row, int column) {
      final body = tester.getTopLeft(find.byKey(const ValueKey<String>('grid-body')));
      final c0 = tester.getTopLeft(find.byKey(const ValueKey<String>('column-0')));
      final head = tester.getRect(find.byKey(ValueKey<String>('column-$column')));
      return Offset(body.dx + head.left - c0.dx + head.width / 2, body.dy + row * kGridRowHeight + kGridRowHeight / 2);
    }

    await screenshot(tester, 'B', '01_opened');
    await tester.tapAt(cell(2, 1));
    await settle(tester);
    await screenshot(tester, 'B', '02_cell_picked');
    await tester.tapAt(cell(2, 1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(cell(2, 1));
    await settle(tester);
    await tester.enterText(find.byType(EditableText).first, 'Changed in the grid');
    await settle(tester);
    await screenshot(tester, 'B', '03_editing_in_the_bar');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await screenshot(tester, 'B', '04_kept_and_moved_down');
    await tester.tap(find.bySemanticsLabel('Keep'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(cell(3, 1));
    await settle(tester);
    await screenshot(tester, 'B', '05_cell_actions');
    await tester.tap(find.byKey(const ValueKey<String>('row-4')));
    await settle(tester);
    await screenshot(tester, 'B', '06_row_actions');
    await tester.tap(find.text('Insert below'));
    await settle(tester);
    await screenshot(tester, 'B', '07_row_inserted');
    await tester.tap(find.byKey(const ValueKey<String>('column-1')));
    await settle(tester);
    await screenshot(tester, 'B', '08_column_actions');
    await tester.tap(find.bySemanticsLabel('Undo'));
    await settle(tester);
    // A long note, picked and opened: the bar keeps its height.
    await tester.timedDragFrom(cell(6, 1), const Offset(-360, 0), const Duration(milliseconds: 900));
    await settle(tester);
    final notes = find.byKey(const ValueKey<String>('column-5'));
    final notesX = math.min(tester.getRect(notes).left + 80, 380.0);
    final body = tester.getTopLeft(find.byKey(const ValueKey<String>('grid-body')));
    Offset low(int row) => Offset(notesX, body.dy + row * kGridRowHeight + kGridRowHeight / 2);
    await tester.tapAt(low(7));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(low(7));
    await settle(tester);
    await screenshot(tester, 'B', '09_long_value_open');
    // Typing low in the grid with the keyboard up.
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await settle(tester);
    await tester.tapAt(low(14));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(low(14));
    await settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 330 * 2);
    addTearDown(tester.view.resetViewInsets);
    await settle(tester);
    await tester.enterText(find.byType(EditableText).first, 'Typed, not yet kept');
    await settle(tester);
    await screenshot(tester, 'B', '10_keyboard_up_typing_counts');
    await tester.tap(find.bySemanticsLabel('Keep'));
    await settle(tester);
    tester.view.resetViewInsets();
    await settle(tester);
    await tester.timedDragFrom(cell(5, 2), const Offset(200, -250), const Duration(milliseconds: 500));
    await settle(tester);
    await screenshot(tester, 'B', '11_after_a_diagonal_drag');
    await tester.tap(find.text('SAVE'));
    await settle(tester);
    writeEvidence('B', 'after.csv', saved!);
  });
}
