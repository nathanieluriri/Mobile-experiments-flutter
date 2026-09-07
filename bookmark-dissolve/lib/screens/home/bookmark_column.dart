import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../constants/board.dart';
import '../../data/bookmark_cards.dart';
import 'dissolvable_bookmark_card.dart';

/// Vertical spacing between two cards in a column.
const kColumnGap = 16.0;

/// One column of the board. Cards stack from the top; when one is taken out the
/// cards below it spring up into the space.
class BookmarkColumn extends StatelessWidget {
  const BookmarkColumn({
    super.key,
    required this.cards,
    required this.restoring,
    required this.snapshots,
    required this.onRemove,
    required this.onSnapshot,
    required this.onRestored,
  });

  final List<BookmarkCardDefinition> cards;
  final bool restoring;
  final Map<String, ui.Image> snapshots;
  final void Function(String cardId) onRemove;
  final void Function(String cardId, ui.Image image) onSnapshot;
  final void Function(String cardId) onRestored;

  @override
  Widget build(BuildContext context) {
    final slots = <Widget>[];
    var top = 0.0;
    for (final card in cards) {
      slots.add(
        _Slot(
          key: ValueKey(restoring ? '${card.id}-restored' : card.id),
          top: top,
          height: card.height,
          child: DissolvableBookmarkCard(
            card: card,
            snapshot: restoring ? snapshots[card.id] : null,
            onRemove: onRemove,
            onSnapshot: onSnapshot,
            onRestored: onRestored,
          ),
        ),
      );
      top += card.height + kColumnGap;
    }
    return Stack(children: slots);
  }
}

/// Holds one card at its place in the column and springs it to a new place when
/// the cards above it change.
class _Slot extends StatefulWidget {
  const _Slot({super.key, required this.top, required this.height, required this.child});

  final double top;
  final double height;
  final Widget child;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> with SingleTickerProviderStateMixin {
  late final AnimationController _top = AnimationController.unbounded(
    vsync: this,
    value: widget.top,
  );

  @override
  void didUpdateWidget(_Slot old) {
    super.didUpdateWidget(old);
    if (widget.top != old.top) {
      _top.animateWith(SpringSimulation(kCardSpring, _top.value, widget.top, _top.velocity));
    }
  }

  @override
  void dispose() {
    _top.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _top,
      builder: (context, child) =>
          Positioned(top: _top.value, left: 0, right: 0, height: widget.height, child: child!),
      child: widget.child,
    );
  }
}
