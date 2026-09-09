import 'package:flutter/widgets.dart';

import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// How visible a shelf with nothing on it is.
///
/// It stays on the row rather than disappearing, because a row that changes
/// length as documents are read is a row you have to re-read every time.
const kEmptyShelfOpacity = 0.45;

/// The line box a chip label sets in.
const kChipLabelBox = 14.0;

/// Where that box sits, so the underline lands [kChipUnderlineGap] below it
/// and its own 2 points reach the chip's bottom edge exactly.
const kChipLabelTop =
    kChipHeight - kChipUnderlineHeight - kChipUnderlineGap - kChipLabelBox;

/// The label each shelf answers to, written uppercase in the source so a
/// golden reads what the source says.
String shelfLabel(Shelf shelf) => switch (shelf) {
      Shelf.all => 'ALL',
      Shelf.reading => 'READING',
      Shelf.signed => 'SIGNED',
    };

/// The three shelves, with one 2pt line under whichever you are standing on.
///
/// The underline travels rather than cutting, because the shelves are one row
/// and the line is your place in it.
class ShelfChips extends StatefulWidget {
  const ShelfChips({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final Shelf selected;

  /// How many cards each shelf would show, ignoring the query.
  final Map<Shelf, int> counts;

  final ValueChanged<Shelf> onSelect;

  @override
  State<ShelfChips> createState() => _ShelfChipsState();
}

class _ShelfChipsState extends State<ShelfChips>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: kChipUnderline,
    value: 1,
  );
  late Shelf _from = widget.selected;

  @override
  void didUpdateWidget(ShelfChips old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _from = old.selected;
      _travel.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  /// Where each label's box starts and how wide it is, measured once a build.
  ///
  /// The chip is that box plus [kChipPaddingX] either side, and the underline
  /// is exactly the box, so the line is the width of the word and never of the
  /// padding around it.
  List<({double left, double width})> _labels() {
    final out = <({double left, double width})>[];
    var x = 0.0;
    for (final shelf in Shelf.values) {
      final painter = TextPainter(
        text: TextSpan(text: shelfLabel(shelf), style: AppText.chipLabel),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();
      out.add((left: x + kChipPaddingX, width: width));
      x += width + kChipPaddingX * 2 + kChipGap;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels();
    return SizedBox(
      height: kChipHeight,
      child: AnimatedBuilder(
        animation: _travel,
        builder: (context, _) {
          final t = easeInOutQuad.transform(_travel.value);
          final from = labels[_from.index];
          final to = labels[widget.selected.index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final shelf in Shelf.values)
                Positioned(
                  left: labels[shelf.index].left - kChipPaddingX,
                  top: 0,
                  width: labels[shelf.index].width + kChipPaddingX * 2,
                  height: kChipHeight,
                  child: _Chip(
                    shelf: shelf,
                    selected: shelf == widget.selected,
                    empty: (widget.counts[shelf] ?? 0) == 0,
                    onSelect: widget.onSelect,
                  ),
                ),
              Positioned(
                left: from.left + (to.left - from.left) * t,
                top: kChipHeight - kChipUnderlineHeight,
                width: from.width + (to.width - from.width) * t,
                height: kChipUnderlineHeight,
                child: const ColoredBox(color: AppColors.thread),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.shelf,
    required this.selected,
    required this.empty,
    required this.onSelect,
  });

  final Shelf shelf;
  final bool selected;
  final bool empty;
  final ValueChanged<Shelf> onSelect;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: empty ? kEmptyShelfOpacity : 1,
      child: PaperPress(
        onTap: empty ? null : () => onSelect(shelf),
        enabled: !empty,
        semanticLabel: shelfLabel(shelf),
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: kChipLabelTop),
            child: Text(
              shelfLabel(shelf),
              style: AppText.chipLabel.copyWith(
                color: selected ? AppColors.ink : AppColors.inkFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
