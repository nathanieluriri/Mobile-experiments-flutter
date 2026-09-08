import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:quire/screens/desk/desk_search_field.dart';
import 'package:quire/theme/metrics.dart';

import 'desk_test.dart' show deskApp, deskStore;
import 'support/golden.dart';

/// Opens the field and lets it finish arriving.
Future<void> openSearch(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.search));
  await tester.pump();
  await pumpMs(tester, kSearchOpen.inMilliseconds);
  await settle(tester);
}

void main() {
  setUp(() {
    // The caret would otherwise blink on a repeating timer, which is both a
    // golden that disagrees with itself and a settle that never returns.
    EditableText.debugDeterministicCursor = true;
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
  });

  testWidgets('typing filters the desk and marks what matched', (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    await openSearch(tester);
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text(kSearchPlaceholder), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'es');
    await tester.pump();
    await settle(tester);

    expect(store.visible.length, 3);
    await capture(tester, 'desk__searching');
  });

  testWidgets('a query that matches nothing leaves the shelves standing',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    await openSearch(tester);
    await tester.enterText(find.byType(EditableText), 'vellum');
    await tester.pump();
    await settle(tester);

    expect(store.visible, isEmpty);
    expect(find.text('Nothing on the desk matches.'), findsOneWidget);
    expect(find.text('for "vellum"'), findsOneWidget);
    await capture(tester, 'desk__search_none');
  });
}
