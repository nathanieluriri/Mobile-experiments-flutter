import 'package:coverdeck/app.dart';
import 'package:coverdeck/data/albums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

void main() {
  testWidgets('browse grid', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Browse'));
    await tester.pump();
    await capture(tester, 'browse__default');
  });

  testWidgets('every album has a tile', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Browse'));
    await tester.pump();
    for (final album in albums) {
      expect(find.text(album.title), findsWidgets, reason: album.title);
    }
  });
}
