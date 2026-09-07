import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/notes.dart';
import 'package:sticky_note_peel/widgets/sticky_note.dart';

import 'support/golden.dart';

void main() {
  testWidgets('notes list at rest', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();
    await capture(tester, 'notes__default');
  });

  testWidgets('notes list scrolled past the title collapse', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    await capture(tester, 'notes__scrolled');
  });

  testWidgets('every fixture note is on screen', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();
    expect(find.byType(StickyNote), findsNWidgets(kNotes.length));
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Suitcase/travel backpack'), findsOneWidget);
    expect(find.text('+5 checked items'), findsOneWidget);
    expect(find.text('May 3 2020, 00:00'), findsOneWidget);
  });

  testWidgets('the title swaps from the list into the header on scroll',
      (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();
    expect(largeTitleOpacity(tester), 1);
    expect(smallTitleOpacity(tester), 0);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(largeTitleOpacity(tester), 0);
    expect(smallTitleOpacity(tester), 1);
  });
}

/// Opacity of the 27 px title that scrolls with the list.
double largeTitleOpacity(WidgetTester tester) => _titleOpacity(tester, 27);

/// Opacity of the 16 px title pinned in the header.
double smallTitleOpacity(WidgetTester tester) => _titleOpacity(tester, 16);

double _titleOpacity(WidgetTester tester, double fontSize) {
  final title = find.byWidgetPredicate(
    (widget) => widget is Text && widget.style?.fontSize == fontSize,
  );
  final opacities = tester.widgetList<Opacity>(
    find.ancestor(of: title, matching: find.byType(Opacity)),
  );
  return opacities.fold<double>(1, (total, o) => total * o.opacity);
}
