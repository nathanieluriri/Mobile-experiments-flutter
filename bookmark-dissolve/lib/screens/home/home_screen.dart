import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../constants/board.dart';
import '../../data/bookmark_cards.dart';
import '../../theme/index.dart';
import 'bookmark_column.dart';

/// Horizontal padding around the board.
const kBoardPadding = 20.0;

/// Space between the two columns, and above the first row of cards.
const kBoardGap = 16.0;

/// The board. Two columns of bookmark cards; close one and it comes apart, and
/// once the board is empty every card blows back in.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<BookmarkCardDefinition> _cards = bookmarkCards.take(kInitialVisibleCards).toList();
  final Map<String, ui.Image> _snapshots = {};
  bool _restoring = false;
  Timer? _restoreTimer;

  @override
  void dispose() {
    _restoreTimer?.cancel();
    for (final image in _snapshots.values) {
      image.dispose();
    }
    _snapshots.clear();
    super.dispose();
  }

  void _removeCard(String cardId) {
    setState(() => _cards = _cards.where((card) => card.id != cardId).toList());
    if (_cards.isEmpty) {
      _restoreTimer?.cancel();
      _restoreTimer = Timer(kRestorePause, () {
        if (!mounted) {
          return;
        }
        setState(() {
          _restoring = true;
          _cards = bookmarkCards;
        });
      });
    }
  }

  void _saveSnapshot(String cardId, ui.Image image) {
    _snapshots.remove(cardId)?.dispose();
    _snapshots[cardId] = image;
  }

  void _releaseSnapshot(String cardId) {
    _snapshots.remove(cardId)?.dispose();
  }

  List<BookmarkCardDefinition> _column(int index) =>
      _cards.where((card) => bookmarkColumn(card.id) == index).toList();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvas,
      child: SafeArea(
        left: false,
        right: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(left: kBoardPadding, right: kBoardPadding, top: kBoardGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column = 0; column < kBoardColumnCount; column++) ...[
                if (column > 0) const SizedBox(width: kBoardGap),
                Expanded(
                  child: BookmarkColumn(
                    cards: _column(column),
                    restoring: _restoring,
                    snapshots: _snapshots,
                    onRemove: _removeCard,
                    onSnapshot: _saveSnapshot,
                    onRestored: _releaseSnapshot,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
