import 'package:coverdeck/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

void main() {
  testWidgets('bundled font renders at every weight', (tester) async {
    await pumpScreen(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: kFontFamily),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final weight in const [
                  FontWeight.w400,
                  FontWeight.w500,
                  FontWeight.w600,
                  FontWeight.w700,
                ])
                  Text(
                    'Weight ${weight.value} Ag 0123',
                    style: TextStyle(fontSize: 28, fontWeight: weight),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await capture(tester, 'typography__weights');
  });

  test('every style states its own family, weight and decoration', () {
    // Nothing above these labels supplies a text style, so a style that leaves
    // a field out inherits the framework's fallback rather than the app's.
    const scale = <String, TextStyle>{
      'eyebrow': AppText.eyebrow,
      'nowPlayingTitle': AppText.nowPlayingTitle,
      'nowPlayingArtist': AppText.nowPlayingArtist,
      'time': AppText.time,
      'heading': AppText.heading,
      'tileTitle': AppText.tileTitle,
      'tileArtist': AppText.tileArtist,
      'rowTitle': AppText.rowTitle,
      'rowSubtitle': AppText.rowSubtitle,
      'dockLabel': AppText.dockLabel,
    };
    scale.forEach((name, style) {
      expect(style.fontFamily, appFontFamily, reason: name);
      expect(style.fontWeight, isNotNull, reason: name);
      expect(style.fontSize, isNotNull, reason: name);
      expect(style.decoration, TextDecoration.none, reason: name);
    });
  });
}
