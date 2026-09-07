import 'package:bookmark_dissolve/app.dart';
import 'package:bookmark_dissolve/screens/home/bookmark_column.dart';
import 'package:bookmark_dissolve/screens/home/home_screen.dart';
import 'package:bookmark_dissolve/widgets/bookmark_card.dart';
import 'package:bookmark_dissolve/widgets/close_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

const kMymind = 'mymind \u2014 Second Brain';
const kPlay = 'Play \u2014 Design on iOS';
const kArc = 'Arc \u2014 Browse Better';
const kNotion = 'Notion \u2014 Your Workspace';

/// Column width and content top, from the source's padding and gaps.
const kColumnWidth = (440 - kBoardPadding * 2 - kBoardGap) / 2;
const kContentTop = 62 + kBoardGap;

/// Where the card titled [title] sits on screen.
Rect cardRect(WidgetTester tester, String title) => tester.getRect(
  find.ancestor(of: find.text(title), matching: find.byType(BookmarkCard)),
);

void main() {
  testWidgets('board at rest', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    await capture(tester, 'board__default');
  });

  testWidgets('board opens with three cards on the source grid', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();

    expect(
      tester.widgetList<BookmarkCard>(find.byType(BookmarkCard)).map((card) => card.title),
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

  testWidgets('the title bar is 40 tall with the close button on the right', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();

    final card = cardRect(tester, kMymind);
    final title = tester.getRect(find.text(kMymind));
    // Icon 22 wide after 10 of padding, then a gap of 8.
    expect(title.left, moreOrLessEquals(card.left + 10 + 22 + 8, epsilon: 0.01));
    expect(title.center.dy, moreOrLessEquals(card.top + kCardHeaderHeight / 2, epsilon: 0.01));

    final close = tester.getRect(
      find.descendant(
        of: find.ancestor(of: find.text(kMymind), matching: find.byType(BookmarkCard)),
        matching: find.byType(CardCloseButton),
      ),
    );
    expect(close.right, moreOrLessEquals(card.right - 12, epsilon: 0.01));
    expect(close.width, 15);
  });
}
