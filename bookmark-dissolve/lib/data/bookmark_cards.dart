import 'package:flutter/widgets.dart';

import '../constants/board.dart';
import '../widgets/previews/index.dart';

/// One bookmark on the board: what it is called, how tall its card is, and the
/// two widgets that draw it.
class BookmarkCardDefinition {
  const BookmarkCardDefinition({
    required this.id,
    required this.title,
    required this.height,
    required this.icon,
    required this.body,
  });

  final String id;
  final String title;
  final double height;
  final Widget icon;
  final Widget body;
}

const bookmarkCards = <BookmarkCardDefinition>[
  BookmarkCardDefinition(
    id: 'mymind',
    title: 'mymind \u2014 Second Brain',
    height: 208,
    icon: MymindIcon(),
    body: MymindBody(),
  ),
  BookmarkCardDefinition(
    id: 'play',
    title: 'Play \u2014 Design on iOS',
    height: 204,
    icon: PlayIcon(),
    body: PlayBody(),
  ),
  BookmarkCardDefinition(
    id: 'arc',
    title: 'Arc \u2014 Browse Better',
    height: 202,
    icon: ArcIcon(),
    body: ArcBody(),
  ),
  BookmarkCardDefinition(
    id: 'notion',
    title: 'Notion \u2014 Your Workspace',
    height: 192,
    icon: NotionIcon(),
    body: NotionBody(),
  ),
];

int _indexOf(String cardId) => bookmarkCards.indexWhere((card) => card.id == cardId);

/// Which column a card belongs to, by its place in the list.
int bookmarkColumn(String cardId) => _indexOf(cardId) % kBoardColumnCount;

/// How long after a restore starts this card comes back.
Duration restoreDelay(String cardId) => kRestoreStagger * _indexOf(cardId);
