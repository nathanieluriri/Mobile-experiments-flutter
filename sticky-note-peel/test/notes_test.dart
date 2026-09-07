import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/notes.dart';
import 'package:sticky_note_peel/screens/notes/compose_note_button.dart';
import 'package:sticky_note_peel/theme/metrics.dart';
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

  testWidgets('the screen is laid out on the design grid', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final menu = tester.getRect(
      find
          .ancestor(
            of: find.byIcon(LucideIcons.menu),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(menu.size, const Size(kHeaderButtonSize, kHeaderButtonSize));
    expect(menu.left, kHeaderHorizontalPadding);
    expect(menu.top, kPhone.top + kHeaderVerticalPadding);

    final first = tester.getRect(find.byType(StickyNote).at(0));
    final second = tester.getRect(find.byType(StickyNote).at(1));
    expect(first.left, kScreenHorizontalPadding);
    expect(first.width, 402 - kScreenHorizontalPadding * 2);
    expect(first.top, closeTo(171.25, 0.5));
    expect(first.height, closeTo(201.25, 0.5));
    expect(second.height, closeTo(289.25, 0.5));
    expect(second.top - first.bottom, kNoteListGap);

    final compose = tester.getRect(
      find.descendant(
        of: find.byType(ComposeNoteButton),
        matching: find.byType(Container),
      ),
    );
    expect(compose.size, const Size(58, 58));
    expect(compose.bottom, 874 - kPhone.bottom - kComposeButtonBottomMargin);
  });

  testWidgets('goldens are rendered with real shadow blur', (tester) async {
    expect(debugDisableShadows, isFalse);
  });

  testWidgets('the title swaps from the list into the header on scroll', (
    tester,
  ) async {
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
