import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_note_peel/theme/metrics.dart';
import 'package:sticky_note_peel/widgets/sticky_note.dart';

/// How wide a note is on the phone this app is judged on.
const kNoteWidth = 402.0 - kScreenHorizontalPadding * 2;

/// Where the fold point sits before a drag, in note coordinates.
const kFoldRestPoint = Offset(kNoteWidth - kFoldRestInset, kFoldRestInset);

/// The middle of the corner handle of note [index], where a peel starts.
Offset handleCenter(WidgetTester tester, int index) {
  final note = tester.getRect(find.byType(StickyNote).at(index));
  return Offset(
    note.right - kFoldHandleSize / 2,
    note.top + kFoldHandleSize / 2,
  );
}

/// Presses and holds the corner of note [index] until the peel gesture takes
/// over, then lets the lift and the dock finish arriving.
Future<TestGesture> liftNote(WidgetTester tester, int index) async {
  final gesture = await tester.startGesture(handleCenter(tester, index));
  await tester.pump(kPeelLongPress + const Duration(milliseconds: 10));
  await tester.pump(const Duration(milliseconds: 400));
  return gesture;
}

/// The centre of dock button [index] under note [noteIndex], in that note's own
/// coordinates.
Offset dockButtonCenter(WidgetTester tester, int index, {int noteIndex = 0}) {
  final note = tester.getRect(find.byType(StickyNote).at(noteIndex));
  return Offset(
    dockButtonCenterX(index, note.width, 3),
    dockRowCenterY(note.height),
  );
}

/// Drives one peel: the fold point eases out from its rest inset toward
/// [target] over [duration], the way a finger flicks a corner away and holds.
///
/// The pointer moves by the same amount as the fold point, because the fold
/// follows the drag translation.
class PeelDrag {
  PeelDrag(
    this.tester,
    this.gesture,
    this.target, {
    this.duration = const Duration(milliseconds: 600),
    this.frame = const Duration(milliseconds: 25),
  });

  final WidgetTester tester;
  final TestGesture gesture;

  /// Where the fold point ends up, in note coordinates.
  final Offset target;

  final Duration duration;
  final Duration frame;

  Duration _elapsed = Duration.zero;
  Offset _moved = Offset.zero;

  /// Advances the drag to [ms] after it started, one frame at a time.
  Future<void> advanceTo(int ms) async {
    final end = Duration(milliseconds: ms);
    while (_elapsed < end) {
      final next = Duration(
        microseconds: math.min(
          _elapsed.inMicroseconds + frame.inMicroseconds,
          end.inMicroseconds,
        ),
      );
      _elapsed = next;
      final progress = (_elapsed.inMicroseconds / duration.inMicroseconds)
          .clamp(0.0, 1.0);
      final eased = 1 - math.pow(1 - progress, 3).toDouble();
      final wanted = (target - kFoldRestPoint) * eased;
      await gesture.moveBy(wanted - _moved);
      _moved = wanted;
      await tester.pump(frame);
    }
  }
}
