import 'package:bookmark_dissolve/painting/dissolve_painter.dart';
import 'package:bookmark_dissolve/widgets/bookmark_card.dart';
import 'package:bookmark_dissolve/widgets/close_button.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const kMymind = 'mymind \u2014 Second Brain';
const kPlay = 'Play \u2014 Design on iOS';
const kArc = 'Arc \u2014 Browse Better';
const kNotion = 'Notion \u2014 Your Workspace';

/// The card with this title.
Finder cardNamed(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(BookmarkCard));

/// Taps the close button on the card titled [title]. Pumps no frames, so the
/// caller decides where the first frame of the run lands.
Future<void> tapClose(WidgetTester tester, String title) => tester.tap(
  find.descendant(of: cardNamed(title), matching: find.byType(CardCloseButton)),
);

/// Taps the close button on [title] and runs the whole dissolve out, leaving
/// the board settled without that card.
Future<void> removeCard(WidgetTester tester, String title) async {
  await tapClose(tester, title);
  await tester.pumpAndSettle();
}

/// Starts a dissolve and stops on the frame where its progress is still zero,
/// so later keyframes line up with the milliseconds in their names.
Future<void> startDissolve(WidgetTester tester, String title) async {
  await tapClose(tester, title);
  await tester.pump();
  await tester.pump();
}

/// Whether any card is currently coming apart or going back together.
bool isRunning(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((paint) => paint.painter is DissolvePainter);

/// Advances [ms] one frame at a time, so a run that begins part way through
/// still starts when it should. One long pump would collapse the stagger
/// between the cards.
Future<void> runMs(WidgetTester tester, int ms, {int step = 16}) async {
  for (var left = ms; left > 0; left -= step) {
    await tester.pump(Duration(milliseconds: left < step ? left : step));
  }
}

/// Runs frames until [ready] holds.
Future<void> runUntil(
  WidgetTester tester,
  bool Function() ready, {
  int limit = 500,
}) async {
  for (var frame = 0; frame < limit && !ready(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Empties the board and stops on the first frame of the first card coming
/// back, so later keyframes line up with the milliseconds in their names.
Future<void> startRestore(WidgetTester tester) async {
  await removeCard(tester, kMymind);
  await removeCard(tester, kPlay);
  await tapClose(tester, kArc);
  await tester.pump();
  await runUntil(tester, () => !isRunning(tester));
  await runUntil(tester, () => isRunning(tester));
  await tester.pump();
}
