import 'package:coverdeck/app.dart';
import 'package:coverdeck/screens/library/library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

void main() {
  testWidgets('library list', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Library'));
    await tester.pump();
    await capture(tester, 'library__default');
  });

  testWidgets('every playlist has a row with its track count', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Library'));
    await tester.pump();
    for (final playlist in playlists) {
      expect(find.text(playlist.name), findsOneWidget, reason: playlist.name);
      expect(
        find.text('${playlist.count} songs'),
        findsOneWidget,
        reason: playlist.name,
      );
    }
  });
}
