import 'package:coverdeck/app.dart';
import 'package:coverdeck/data/albums.dart';
import 'package:coverdeck/painting/glyphs.dart';
import 'package:coverdeck/screens/deck/deck_screen.dart';
import 'package:coverdeck/screens/deck/progress_bar.dart';
import 'package:coverdeck/widgets/glyph_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

Finder _glyph(Glyph glyph) =>
    find.byWidgetPredicate((widget) => widget is GlyphIcon && widget.glyph == glyph);

void main() {
  testWidgets('deck at rest on the first album', (tester) async {
    await pumpScreen(tester, const App());
    await capture(tester, 'deck__default');
  });

  testWidgets('deck playing', (tester) async {
    await pumpScreen(tester, const App());
    expect(_glyph(Glyph.playFill), findsOneWidget);
    await tester.tap(_glyph(Glyph.playFill));
    await tester.pump();
    await pumpMs(tester, 600);
    expect(_glyph(Glyph.pauseFill), findsOneWidget);
    await capture(tester, 'deck__playing');
  });

  test('the backdrop samples the wash colours end to end', () {
    expect(deckWash(0), albums[0].wash);
    expect(deckWash(11), albums[11].wash);
    expect(deckWash(-3), albums[0].wash, reason: 'clamped below');
    expect(deckWash(40), albums[11].wash, reason: 'clamped above');
    expect(
      deckWash(0.5),
      Color.lerp(albums[0].wash, albums[1].wash, 0.5),
      reason: 'halfway between two albums',
    );
  });

  test('times read as minutes and padded seconds', () {
    expect(formatDuration(214), '3:34');
    expect(formatDuration(187), '3:07');
    expect(formatDuration(60), '1:00');
  });

  testWidgets('skipping forward moves to the next album', (tester) async {
    await pumpScreen(tester, const App());
    expect(find.text('Midnight Static'), findsOneWidget);
    await tester.tap(_glyph(Glyph.forwardFill));
    await tester.pump();
    await pumpMs(tester, 1200);
    expect(find.text('Crowd Theory'), findsOneWidget);
    await tester.tap(_glyph(Glyph.backwardFill));
    await tester.pump();
    await pumpMs(tester, 1200);
    expect(find.text('Midnight Static'), findsOneWidget);
  });

  testWidgets('skipping back from the first album stays put', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(_glyph(Glyph.backwardFill));
    await tester.pump();
    await pumpMs(tester, 1200);
    expect(find.text('Midnight Static'), findsOneWidget);
  });
}
