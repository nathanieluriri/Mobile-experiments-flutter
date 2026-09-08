import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Font families bundled with this app. Inter sets the interface, Quicksand
/// sets the few places the app speaks in its own voice.
const kFontFamily = 'Inter';
const kDisplayFamily = 'Quicksand';

/// Device pixel ratio used for every golden.
const kDpr = 2.0;

/// The phone this app is judged on: logical size and safe-area insets.
class Phone {
  const Phone(this.name, this.logical, {required this.top, required this.bottom});

  final String name;
  final Size logical;
  final double top;
  final double bottom;
}

const kPhone = Phone('iPhone 17 Pro', Size(402, 874), top: 62, bottom: 34);

/// Pumps [app] at the phone's size with its safe-area insets, then decodes
/// every picture in the tree.
Future<void> pumpScreen(WidgetTester tester, Widget app, {Phone phone = kPhone}) async {
  tester.view.physicalSize = phone.logical * kDpr;
  tester.view.devicePixelRatio = kDpr;
  final padding = FakeViewPadding(top: phone.top * kDpr, bottom: phone.bottom * kDpr);
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await precacheImages(tester);
}

/// Decodes every [Image] widget currently in the tree so goldens never show
/// blank pictures. Call again after navigating to a screen with new pictures.
Future<void> precacheImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();
}

/// Advances the clock by [ms] without settling, for animation keyframes.
Future<void> pumpMs(WidgetTester tester, int ms) {
  return tester.pump(Duration(milliseconds: ms));
}

/// Writes or compares `test/goldens/<name>.png` for the whole screen.
Future<void> capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp).first,
    matchesGoldenFile('goldens/$name.png'),
  );
}

/// Writes or compares `test/goldens/<name>.png` for one widget, for goldens
/// that judge a component rather than a screen.
Future<void> captureOf(WidgetTester tester, Finder finder, String name) async {
  await expectLater(finder, matchesGoldenFile('goldens/$name.png'));
}

/// Presses at [start] and drags to [end] over [steps] moves, returning the
/// gesture still held down so a keyframe can be captured mid drag. The caller
/// is responsible for calling `up` or `cancel`.
///
/// The moves are split into steps because a single large move reads as a fling
/// to anything measuring velocity, which is not what a slow deliberate drag
/// should look like.
Future<TestGesture> dragAndHold(
  WidgetTester tester,
  Offset start,
  Offset end, {
  int steps = 12,
  Duration between = const Duration(milliseconds: 16),
}) async {
  final gesture = await tester.startGesture(start);
  final step = (end - start) / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(step);
    await tester.pump(between);
  }
  return gesture;
}

/// Holds a long press at [start] for [holdMs], then drags to [end], returning
/// the gesture still held down. For interactions that arm on a long press
/// before they track a finger.
Future<TestGesture> longPressAndDrag(
  WidgetTester tester,
  Offset start,
  Offset end, {
  int holdMs = 200,
  int steps = 12,
}) async {
  final gesture = await tester.startGesture(start);
  await tester.pump(Duration(milliseconds: holdMs));
  final step = (end - start) / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

/// The centre of the widget [finder] resolves to, in global coordinates.
Offset centreOf(WidgetTester tester, Finder finder) => tester.getCenter(finder);

/// Settles the tree with a bound, so a stuck animation fails the test instead
/// of hanging the run.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 16),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}
