import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/screens/reader/reader_host.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// The desk, marked so a test can tell it from the app's bare ground.
const _deskKey = Key('desk');

Widget _app() => App(
  routes: <String, WidgetBuilder>{
    kDeskRoute: (context) => const ColoredBox(
      key: _deskKey,
      color: Colors.black,
      child: SizedBox.expand(),
    ),
  },
);

/// The route on top, and whether there is anything under it to go back to.
({String? top, bool deeper}) _stack(WidgetTester tester) {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  String? top;
  navigator.popUntil((route) {
    top = route.settings.name;
    // True on the first route looked at, so nothing is ever popped.
    return true;
  });
  return (top: top, deeper: navigator.canPop());
}

void main() {
  group('a document opened from another app', () {
    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher
          .clearDefaultRouteNameTestValue();
    });

    testWidgets('does not turn its own address into a stack of blank pages', (
      tester,
    ) async {
      // What a file manager hands the platform, and what the platform then
      // hands the app as the route to start on.
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/document/primary:Download/lease.pdf';
      await pumpScreen(tester, _app());
      await settle(tester);

      // Only the desk. Anything else is a blank page somebody has to press
      // back through to get anywhere.
      expect(_stack(tester), (top: kDeskRoute, deeper: false));
      expect(find.byKey(_deskKey), findsOneWidget);
    });

    testWidgets('an address arriving while the app is open is not a page', (
      tester,
    ) async {
      await pumpScreen(tester, _app());
      await settle(tester);

      await tester.binding.handlePushRoute('/document/1234');
      await settle(tester);

      expect(_stack(tester), (top: kDeskRoute, deeper: false));
      expect(find.byKey(_deskKey), findsOneWidget);
    });
  });

  group('the platform is told not to route documents at all', () {
    test('on Android', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('flutter_deeplinking_enabled'));
      expect(
        RegExp(
          r'flutter_deeplinking_enabled"\s*android:value="false"',
        ).hasMatch(manifest),
        isTrue,
      );
    });

    test('on iOS', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(
        RegExp(r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>')
            .hasMatch(plist),
        isTrue,
      );
    });
  });

  group('leaving a document another app opened', () {
    testWidgets('back goes where the reader was told, not down the stack', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      var left = 0;
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const ColoredBox(key: _deskKey, color: Colors.black),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (context) =>
                ReaderHost(store: store, onLeave: () => left++),
          ),
          initialRoute: '/reader',
        ),
      );
      await settle(tester);
      expect(find.byType(ReaderHost), findsOneWidget);

      // The phone's own back.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(left, 1);
      // Nothing was popped out from under the caller's way out.
      expect(find.byType(ReaderHost), findsOneWidget);

      // And the corner button agrees with it.
      await tester.tap(find.bySemanticsLabel('Back to the desk'));
      await settle(tester);
      expect(left, 2);
    });

    testWidgets('a reader with no way out of its own still pops as before', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Builder(
            builder: (context) => GestureDetector(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => ReaderHost(store: store),
                ),
              ),
              child: const ColoredBox(key: _deskKey, color: Colors.black),
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(_deskKey));
      await settle(tester);
      expect(find.byType(ReaderHost), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(ReaderHost), findsNothing);
      expect(find.byKey(_deskKey), findsOneWidget);
    });

    testWidgets('on Android the way back is to the app that opened it', (
      tester,
    ) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var inApp = 0;
      await leaveToCaller(
        platform: TargetPlatform.android,
        backInApp: () => inApp++,
      );
      expect(calls, contains('SystemNavigator.pop'));
      expect(inApp, 0);
    });

    testWidgets('on iOS, which will not send an app away, it goes back inside', (
      tester,
    ) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var inApp = 0;
      await leaveToCaller(platform: TargetPlatform.iOS, backInApp: () => inApp++);
      expect(calls, isNot(contains('SystemNavigator.pop')));
      expect(inApp, 1);
    });
  });
}
