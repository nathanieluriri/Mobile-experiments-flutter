import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/desk/search_pill.dart';

import 'desk_test.dart' show deskApp, deskStore;
import 'support/golden.dart';

/// Puts the cursor in the pill, which is already on the bar.
Future<void> openSearch(WidgetTester tester) async {
  await tester.tap(find.byType(SearchPill));
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

  testWidgets('typing in the pill filters the desk', (tester) async {
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
