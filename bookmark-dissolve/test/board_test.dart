import 'package:bookmark_dissolve/app.dart';
import 'package:bookmark_dissolve/screens/home/bookmark_column.dart';
import 'package:bookmark_dissolve/screens/home/home_screen.dart';
import 'package:bookmark_dissolve/widgets/bookmark_card.dart';
import 'package:bookmark_dissolve/theme/index.dart';
import 'package:bookmark_dissolve/widgets/close_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board.dart';
import 'support/golden.dart';

/// Column width and content top, from the board's padding and gaps.
const kColumnWidth = (440 - kBoardPadding * 2 - kBoardGap) / 2;
const kContentTop = 62 + kBoardGap;

/// Where the card titled [title] sits on screen.
Rect cardRect(WidgetTester tester, String title) =>
    tester.getRect(cardNamed(title));

void main() {
  testWidgets('board at rest', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    await capture(tester, 'board__default');
  });

  testWidgets('board opens with three cards on the board grid', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<BookmarkCard>(find.byType(BookmarkCard))
          .map((card) => card.title),
      [kMymind, kArc, kPlay],
    );

    expect(
      cardRect(tester, kMymind),
      rectMoreOrLessEquals(
        epsilon: 0.01,
        const Rect.fromLTWH(kBoardPadding, kContentTop, kColumnWidth, 208),
      ),
    );
    expect(
      cardRect(tester, kArc),
      rectMoreOrLessEquals(
        epsilon: 0.01,
        const Rect.fromLTWH(
          kBoardPadding,
          kContentTop + 208 + kColumnGap,
          kColumnWidth,
          202,
        ),
      ),
    );
    expect(
      cardRect(tester, kPlay),
      rectMoreOrLessEquals(
        epsilon: 0.01,
        const Rect.fromLTWH(
          kBoardPadding + kColumnWidth + kBoardGap,
          kContentTop,
          kColumnWidth,
          204,
        ),
      ),
    );
  });

  testWidgets('the title bar sits on the spacing scale', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();

    final card = cardRect(tester, kMymind);
    final title = tester.getRect(find.text(kMymind));
    // Icon 22 wide after pl-2.5 of padding, then a gap-2.
    expect(
      title.left,
      moreOrLessEquals(card.left + kStep * 2.5 + 22 + kStep * 2, epsilon: 0.01),
    );
    expect(
      title.center.dy,
      moreOrLessEquals(card.top + kCardHeaderHeight / 2, epsilon: 0.01),
    );

    final close = tester.getRect(
      find.descendant(
        of: cardNamed(kMymind),
        matching: find.byType(CardCloseButton),
      ),
    );
    expect(
      close.right,
      moreOrLessEquals(card.right - kStep * 3, epsilon: 0.01),
    );
    expect(close.width, 15);
  });

  testWidgets('the board holds two cards once one is deleted', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    await removeCard(tester, kArc);

    expect(cardNamed(kArc), findsNothing);
    expect(
      cardRect(tester, kMymind),
      rectMoreOrLessEquals(
        epsilon: 0.01,
        const Rect.fromLTWH(kBoardPadding, kContentTop, kColumnWidth, 208),
      ),
    );
    await capture(tester, 'board__after_delete');
  });

  testWidgets('the saved card sizes against the mymind content box', (
    tester,
  ) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();

    // The panel is 52 percent tall and 68 percent wide inside a body carrying
    // 2.5 steps of top padding, and a percentage resolves against what the
    // padding leaves.
    const body = 208 - kCardHeaderHeight;
    const inner = body - kStep * 2.5;
    final panel = tester.getRect(
      find
          .ancestor(
            of: find.text('SHOP · Soap'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(panel.height, moreOrLessEquals(inner * 0.52, epsilon: 0.01));
    expect(panel.width, moreOrLessEquals(kColumnWidth * 0.68, epsilon: 0.01));

    // bottom: -1 hangs it past the body, which the card then clips.
    final card = cardRect(tester, kMymind);
    expect(panel.bottom, moreOrLessEquals(card.bottom + kStep, epsilon: 0.01));
    expect(
      panel.right,
      moreOrLessEquals(card.right - kStep * 2.5, epsilon: 0.01),
    );
  });
}
