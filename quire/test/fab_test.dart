import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/constants/gooey_fab.dart';
import 'package:quire/painting/goo_circles_painter.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/gooey_fab/fab_action_pill.dart';
import 'package:quire/widgets/gooey_fab/gooey_fab.dart';

import 'desk_test.dart' show deskApp, deskStore;
import 'support/golden.dart';

void main() {
  group('the numbers the effect is made of', () {
    test('the springs are the ones the motion was tuned on', () {
      expect(kFabOpenSpring.stiffness, 130);
      expect(kFabOpenSpring.damping, 14);
      expect(kFabCloseSpring.stiffness, 190);
      expect(kFabCloseSpring.damping, 17);
      expect(kFabLooseOpenSpring.stiffness, 130);
      expect(kFabLooseOpenSpring.damping, 13);
      expect(kFabActionStagger, const Duration(milliseconds: 60));
      expect(kFabOpenRotationDegrees, 135);
    });

    test('the alpha row multiplies by 32 and subtracts 14 of 255', () {
      expect(kGooAlphaThresholdMatrix.length, 20);
      expect(kGooAlphaThresholdMatrix.sublist(15), <double>[0, 0, 0, 32, -3570]);
      expect(kGooBlurSigma, 9);
    });

    test('three actions rise to the three offsets, bottom to top', () {
      expect(
        kFabActions.map((action) => action.offsetY),
        <double>[-82, -152, -222],
      );
      expect(
        kFabActions.map((action) => action.label),
        <String>['Open a file', 'Sign a PDF', 'Recent'],
      );
    });

    test('a pill only becomes real over the last part of its trip', () {
      expect(
        interpolateClamped(0, kActionOpacityInput, kActionOpacityOutput),
        0,
      );
      expect(
        interpolateClamped(0.65, kActionOpacityInput, kActionOpacityOutput),
        0,
      );
      expect(
        interpolateClamped(1, kActionOpacityInput, kActionOpacityOutput),
        1,
      );
      expect(interpolateClamped(0, kActionScaleInput, kActionScaleOutput), 0.4);
      expect(interpolateClamped(2, kActionScaleInput, kActionScaleOutput), 1);
    });
  });

  group('the action button', () {
    testWidgets('opens on a tap and closes on the scrim', (tester) async {
      final chosen = <int>[];
      await pumpScreen(tester, _Harness(onSelected: chosen.add));
      expect(_scrimAlpha(tester), 0);

      await tester.tapAt(_buttonCentre);
      await settle(tester);
      expect(_scrimAlpha(tester), closeTo(AppColors.scrim.a, 0.001));

      // The top left corner is scrim and nothing else.
      await tester.tapAt(const Offset(20, 120));
      await settle(tester);
      expect(_scrimAlpha(tester), 0);
      expect(chosen, isEmpty);
    });

    testWidgets('an action that has not opened takes no taps', (tester) async {
      await pumpScreen(tester, const _Harness());
      expect(_pillsAreLive(tester), isFalse);

      await tester.tapAt(_buttonCentre);
      await settle(tester);
      expect(_pillsAreLive(tester), isTrue);
    });

    testWidgets('choosing an action reports it and closes', (tester) async {
      final chosen = <int>[];
      await pumpScreen(tester, _Harness(onSelected: chosen.add));
      await tester.tapAt(_buttonCentre);
      await settle(tester);

      await tester.tap(find.text('Sign a PDF'));
      await settle(tester);
      expect(chosen, <int>[1]);
      expect(_scrimAlpha(tester), 0);
    });

    testWidgets('the scrim dims and never blurs', (tester) async {
      await pumpScreen(tester, const _Harness());
      await _openAndStart(tester);
      var rose = false;
      for (var i = 0; i < 8; i++) {
        expect(find.byType(BackdropFilter), findsNothing);
        await pumpMs(tester, 40);
        rose |= _scrimAlpha(tester) > 0;
      }
      expect(rose, isTrue);
      await settle(tester);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('every pill keeps its round end on the button centre line', (
      tester,
    ) async {
      await pumpScreen(tester, const _Harness());
      await _openAndStart(tester);
      for (final ms in <int>[80, 90, 130, 300]) {
        await pumpMs(tester, ms);
        for (var i = 0; i < kFabActions.length; i++) {
          final pill = tester.getRect(_pillBody(i));
          // The right end is a half circle of the pill's own height, so its
          // centre is half a height in from the right edge at any scale.
          expect(
            pill.right - pill.height / 2,
            closeTo(_buttonCentre.dx, 0.01),
            reason: 'pill $i at $ms ms',
          );
          expect(pill.left, lessThan(_buttonCentre.dx));
        }
      }
      await settle(tester);
    });

    testWidgets('mid flight the goo is one body, not two circles', (
      tester,
    ) async {
      await pumpScreen(tester, const _Harness());
      await _openAndStart(tester);
      await pumpMs(tester, 170);

      final circles = _circles(tester);
      final gap =
          (kFabCenterY - circles.actionCentresY.first) -
          kGooActionDiameter / 2 -
          circles.buttonDiameter / 2;
      // On its way out, clear of the button, and still close enough that one
      // blur reaches across the gap. A gap wider than the blur is two circles,
      // not a neck.
      expect(circles.actionCentresY.first, lessThan(kFabCenterY));
      expect(gap, greaterThan(0));
      expect(gap, lessThan(kGooBlurSigma * 2));
      await settle(tester);
    });

    testWidgets('open, the goo has let every pill go', (tester) async {
      await pumpScreen(tester, const _Harness());
      await tester.tapAt(_buttonCentre);
      await settle(tester);

      final circles = _circles(tester);
      for (var i = 0; i < kFabActions.length; i++) {
        expect(
          circles.actionCentresY[i],
          closeTo(kFabCenterY + kFabActions[i].offsetY, 0.5),
        );
      }
      expect(circles.buttonDiameter, closeTo(kGooButtonOpenDiameter, 0.5));
    });

    testWidgets('keyframes', (tester) async {
      // The real desk, not the harness: what the scrim dims and what the goo
      // is seen against is the library, and a keyframe over a stand in would
      // be a picture of a screen this app does not have.
      await pumpScreen(tester, deskApp(await deskStore()));
      await settle(tester);
      await capture(tester, 'fab__t0000');
      await _openAndStart(tester);
      await pumpMs(tester, 170);
      await capture(tester, 'fab__t0170');
      await pumpMs(tester, 430);
      await capture(tester, 'fab__t0600');
      await settle(tester);
    });
  });
}

/// Taps the button and pumps the frame the springs start on, so a keyframe
/// pumped after this is that many milliseconds into the motion rather than one
/// frame short of it.
Future<void> _openAndStart(WidgetTester tester) async {
  await tester.tapAt(_buttonCentre);
  await tester.pump();
}

/// The button's centre on screen. The canvas is pinned to the bottom right, so
/// this is the one place the two coordinate systems have to agree, and a test
/// that taps here proves they do.
const Offset _buttonCentre = Offset(
  kScreenWidth - (kFabCanvasWidth - kFabCenterX),
  kScreenHeight - kFabCanvasBottomOffset - (kFabCanvasHeight - kFabCenterY),
);

/// The filled body of the pill at [index], which is what the eye reads as the
/// pill and what the goo circle sits under.
Finder _pillBody(int index) => find.descendant(
  of: find.byType(FabActionPill).at(index),
  matching: find.byType(DecoratedBox),
);

/// The scrim's current alpha, read off the widget that paints it.
double _scrimAlpha(WidgetTester tester) {
  final box = tester.widget<ColoredBox>(
    find
        .descendant(
          of: find.byType(GooeyFab),
          matching: find.byType(ColoredBox),
        )
        .first,
  );
  return box.color.a;
}

/// Whether the pills are taking taps.
bool _pillsAreLive(WidgetTester tester) {
  final gates = tester
      .widgetList<IgnorePointer>(
        find.descendant(
          of: find.byType(FabActionPill).first,
          matching: find.byType(IgnorePointer),
        ),
      )
      .toList();
  expect(gates, hasLength(1));
  return !gates.single.ignoring;
}

GooCirclesPainter _circles(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is GooCirclesPainter,
    ),
  );
  return paint.painter! as GooCirclesPainter;
}

/// The button on the app's own ground, with a hook on what it chose.
///
/// The desk builds the button itself and answers its actions in place, so a
/// test that has to see what was chosen mounts it alone. What the button looks
/// like over the library is a golden, and those are taken on the real desk.
class _Harness extends StatelessWidget {
  const _Harness({this.onSelected});

  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: AppColors.ground,
        child: Stack(
          children: [GooeyFab(onSelected: onSelected)],
        ),
      ),
    );
  }
}
