import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/desk/desk_top_bar.dart';
import 'package:quire/screens/desk/nav_drawer.dart';
import 'package:quire/screens/desk/shell_model.dart';
import 'package:quire/screens/desk/sort_row.dart';
import 'package:quire/screens/desk/tab_strip.dart';
import 'package:quire/theme/metrics.dart';

import 'desk_test.dart' show deskApp, deskStore;
import 'support/fixtures.dart';
import 'support/golden.dart';

/// How far the panel has actually come in, read off the transform that moves
/// it rather than off the number the shell handed the drawer.
///
/// That is the whole point of the measurement: the glyph is only a readout of
/// the drawer if the pixels agree, and a widget field the shell set twice
/// would agree with itself no matter what it drew.
double panelProgress(WidgetTester tester) {
  final transform = tester
      .widget<Transform>(
        find
            .descendant(of: find.byType(NavDrawer), matching: find.byType(Transform))
            .first,
      )
      .transform;
  final width = drawerWidth(kPhone.logical.width);
  return 1 + transform.getTranslation().x / width;
}

/// What the hamburger is drawing at this instant.
double glyphProgress(WidgetTester tester) =>
    tester.widget<HamburgerGlyph>(find.byType(HamburgerGlyph)).progress;

/// A destination's row inside the panel.
///
/// The label alone is not enough: the action button's third pill is also
/// called `Recent`, because it is a shortcut to this very row, and a finder
/// that could not tell them apart would be testing the wrong one.
Finder drawerRowNamed(String label) => find.descendant(
      of: find.byType(NavDrawer),
      matching: find.text(label),
    );

Future<void> openDrawer(WidgetTester tester) async {
  await tester.tap(find.byType(HamburgerGlyph));
  await tester.pump();
}

void main() {
  testWidgets('the drawer comes over the shell with Recent lit', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    expect(panelProgress(tester), 0);
    await openDrawer(tester);
    await settle(tester);

    expect(panelProgress(tester), 1);
    for (final destination in DrawerDestination.values) {
      expect(drawerRowNamed(destination.label), findsOneWidget);
    }
    await capture(tester, 'drawer__open');
  });

  testWidgets('the glyph is a readout of the panel, not a second animation', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    await openDrawer(tester);
    expect(glyphProgress(tester), 0);
    expect(panelProgress(tester), 0);
    await capture(tester, 'hamburger__t0000');

    await pumpMs(tester, 120);
    // Half the drawer is half the arrow. The spring decides how far that is;
    // the glyph only has to agree with it.
    expect(glyphProgress(tester), closeTo(0.577, 0.02));
    expect(panelProgress(tester), closeTo(glyphProgress(tester), 0.0001));
    await capture(tester, 'hamburger__t0120');

    await pumpMs(tester, 140);
    expect(glyphProgress(tester), closeTo(0.966, 0.02));
    expect(panelProgress(tester), closeTo(glyphProgress(tester), 0.0001));
    await capture(tester, 'hamburger__t0260');

    await settle(tester);
    expect(glyphProgress(tester), 1);
  });

  testWidgets('a finger on the panel takes the glyph back with it', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);
    await openDrawer(tester);
    await settle(tester);

    final width = drawerWidth(kPhone.logical.width);
    final gesture = await tester.startGesture(Offset(width / 2, 400));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(-width / 12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // The drag drives the same number the spring did, so the arrow unwinds
    // under the finger rather than waiting for it to let go.
    expect(panelProgress(tester), closeTo(2 / 3, 0.02));
    expect(glyphProgress(tester), closeTo(panelProgress(tester), 0.0001));

    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(-width / 12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
    expect(panelProgress(tester), 0);
  });

  testWidgets('the scrim shuts the drawer without choosing anything', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);
    await openDrawer(tester);
    await settle(tester);

    await tester.tapAt(const Offset(kScreenWidth - 20, 400));
    await settle(tester);
    expect(panelProgress(tester), 0);
    expect(find.byType(TabStrip), findsOneWidget);
  });

  testWidgets('every row that cannot be filled says what would be there', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    for (final destination in DrawerDestination.values) {
      await openDrawer(tester);
      await settle(tester);
      await tester.tap(drawerRowNamed(destination.label));
      await settle(tester);

      if (destination.library) {
        // The two rows that reach the documents keep the library's own chrome.
        expect(find.byType(TabStrip), findsOneWidget);
        expect(find.byType(SortRow), findsOneWidget);
        expect(documentTitled('Field Guide To Paper'), findsOneWidget);
        continue;
      }
      // A destination with nothing in it drops the tabs and the sort row,
      // because there is no list for them to be about, and says in full what
      // would have been here.
      expect(find.byType(TabStrip), findsNothing, reason: destination.label);
      expect(find.byType(SortRow), findsNothing, reason: destination.label);
      expect(destination.headline, isNotEmpty);
      expect(destination.body, isNotEmpty);
      expect(find.text(destination.headline), findsOneWidget);
      expect(find.text(destination.body), findsOneWidget);
    }
  });

  testWidgets('an empty destination is designed, not greyed out', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    await openDrawer(tester);
    await settle(tester);
    await tester.tap(drawerRowNamed(DrawerDestination.starred.label));
    await settle(tester);
    await capture(tester, 'desk__starred');
  });
}
