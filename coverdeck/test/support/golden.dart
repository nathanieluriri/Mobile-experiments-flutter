import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Font family bundled with this app.
const kFontFamily = 'Inter';

/// Device pixel ratio used for every golden.
const kDpr = 2.0;

/// The phone this app is judged on: logical size and safe-area insets.
class Phone {
  const Phone(
    this.name,
    this.logical, {
    required this.top,
    required this.bottom,
  });

  final String name;
  final Size logical;
  final double top;
  final double bottom;
}

const kPhone = Phone('iPhone 17 Pro Max', Size(440, 956), top: 62, bottom: 34);

/// A short strip for goldens of one component rather than a whole screen.
const kStrip = Phone('strip', Size(440, 160), top: 0, bottom: 0);

/// Pumps [app] at the phone's size with its safe-area insets, then decodes
/// every picture in the tree.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget app, {
  Phone phone = kPhone,
}) async {
  tester.view.physicalSize = phone.logical * kDpr;
  tester.view.devicePixelRatio = kDpr;
  final padding = FakeViewPadding(
    top: phone.top * kDpr,
    bottom: phone.bottom * kDpr,
  );
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

/// Runs the clock far enough forward for any spring in flight to finish.
///
/// The first frame only starts the clock for a spring that has just been
/// handed off, so it takes two: one to start and one long one to finish.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}

/// Writes or compares `test/goldens/<name>.png` for whatever [finder] matches.
Future<void> captureAt(WidgetTester tester, Finder finder, String name) async {
  await expectLater(finder, matchesGoldenFile('goldens/$name.png'));
}

/// Writes or compares `test/goldens/<name>.png` for the whole screen.
Future<void> capture(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp).first,
    matchesGoldenFile('goldens/$name.png'),
  );
}
