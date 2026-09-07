import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gooey_fab/screens/chats/chats_screen.dart';
import 'package:gooey_fab/widgets/gooey_fab/fab_action_button.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/golden.dart';

/// [video, voice] in tree order.
List<FabActionButton> _actions(WidgetTester tester) =>
    tester.widgetList<FabActionButton>(find.byType(FabActionButton)).toList();

double _videoDrive(WidgetTester tester) => _actions(tester)[0].drive.value;

double _voiceDrive(WidgetTester tester) => _actions(tester)[1].drive.value;

Widget _app({VoidCallback? onVideoCall, VoidCallback? onVoiceCall}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(fontFamily: kFontFamily, platform: TargetPlatform.iOS),
  home: ChatsScreen(onVideoCall: onVideoCall, onVoiceCall: onVoiceCall),
);

void main() {
  testWidgets('tapping the plus opens, tapping it again closes', (tester) async {
    await pumpScreen(tester, _app());

    expect(_voiceDrive(tester), 0);
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_voiceDrive(tester), closeTo(1, 0.01));
    expect(_videoDrive(tester), closeTo(1, 0.01));

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_voiceDrive(tester), closeTo(0, 0.01));
    expect(_videoDrive(tester), closeTo(0, 0.01));
  });

  testWidgets('voice leads the video circle by the stagger when opening', (tester) async {
    await pumpScreen(tester, _app());
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();

    await pumpMs(tester, 59);
    expect(_videoDrive(tester), 0, reason: 'video waits out the stagger');
    expect(_voiceDrive(tester), greaterThan(0.15), reason: 'voice is already moving');

    await pumpMs(tester, 60);
    expect(_videoDrive(tester), greaterThan(0), reason: 'video starts after the stagger');
    expect(_voiceDrive(tester), greaterThan(_videoDrive(tester)));
  });

  testWidgets('video leads the voice circle by the stagger when closing', (tester) async {
    await pumpScreen(tester, _app());
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await pumpMs(tester, 59);
    expect(_voiceDrive(tester), closeTo(1, 0.001), reason: 'voice waits out the stagger');
    expect(_videoDrive(tester), lessThan(0.95), reason: 'video is already retracting');
  });

  testWidgets('picking an action closes the fab and reports the choice', (tester) async {
    var voiceCalls = 0;
    await pumpScreen(tester, _app(onVoiceCall: () => voiceCalls++));

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byIcon(LucideIcons.phone));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(voiceCalls, 1);
    expect(_voiceDrive(tester), closeTo(0, 0.01));
    expect(_videoDrive(tester), closeTo(0, 0.01));
  });

  testWidgets('tapping outside closes the fab', (tester) async {
    await pumpScreen(tester, _app());

    await tester.tapAt(const Offset(60, 400));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_voiceDrive(tester), 0, reason: 'the backdrop is inert while closed');

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tapAt(const Offset(60, 400));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_voiceDrive(tester), closeTo(0, 0.01));
  });

  testWidgets('closing part way through an open picks up from where it is', (tester) async {
    await pumpScreen(tester, _app());

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await pumpMs(tester, 100);
    final voiceAtInterrupt = _voiceDrive(tester);
    expect(voiceAtInterrupt, greaterThan(0.15));
    expect(voiceAtInterrupt, lessThan(0.9));

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    expect(
      _voiceDrive(tester),
      closeTo(voiceAtInterrupt, 0.001),
      reason: 'no jump at the moment of reversal',
    );

    await tester.pump(const Duration(seconds: 2));
    expect(_voiceDrive(tester), closeTo(0, 0.01));
    expect(_videoDrive(tester), closeTo(0, 0.01));
  });

  testWidgets('the open spring overshoots past its target', (tester) async {
    await pumpScreen(tester, _app());
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();

    var peak = 0.0;
    for (var t = 0; t < 700; t += 10) {
      await pumpMs(tester, 10);
      peak = peak > _videoDrive(tester) ? peak : _videoDrive(tester);
    }
    expect(peak, greaterThan(1.05), reason: 'the looser video spring overshoots further');
    expect(peak, lessThan(1.2));
  });
}
