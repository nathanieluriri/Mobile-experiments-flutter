import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';
import '../../theme/metrics.dart';
import 'document_card.dart';

/// The desk as a grid: two columns of cards, each showing its document's own
/// first page.
///
/// Like the list, it takes the documents already filtered and sorted, because
/// what is on screen is the shell's question and how it is drawn is this
/// body's.
///
/// The cards are laid out from the width they are given rather than from a
/// fixed card size, so the two columns and the gap between them always add up
/// to the body exactly, and a card is never a fraction of a point out.
class GridBody extends StatefulWidget {
  const GridBody({
    super.key,
    required this.library,
    required this.entries,
    this.query = '',
    this.onOpen,
    this.onOverflow,
    this.controller,
    this.padding = const EdgeInsets.all(kGridPadding),
    this.footer,
  });

  /// The desk itself, which is what has been read of each document.
  final LibraryStore library;

  /// The documents to draw, already filtered and sorted.
  final List<LibraryEntry> entries;

  /// The search, marked wherever it appears in a title.
  final String query;

  /// Opening a document, with the rect its card occupies on the screen.
  final void Function(LibraryEntry entry, Rect cardRect)? onOpen;

  /// A card's three dots. The menu behind them belongs to the shell.
  final void Function(LibraryEntry entry, Rect cardRect, Rect target)?
      onOverflow;

  final ScrollController? controller;

  /// Room round the cards, and for whatever the shell floats over them.
  final EdgeInsets padding;

  /// What goes under the last row of cards, once there is one.
  final Widget? footer;

  @override
  State<GridBody> createState() => _GridBodyState();
}

class _GridBodyState extends State<GridBody> {
  /// One key per document rather than one per position, so a card keeps its
  /// own boundary when the grid is sorted and a rect is always the rect of the
  /// card that was touched.
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  GlobalKey _keyFor(LibraryEntry entry) =>
      _keys.putIfAbsent(entry.path, GlobalKey.new);

  Rect _rectOf(LibraryEntry entry) {
    final box = _keys[entry.path]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inside = constraints.maxWidth - widget.padding.horizontal;
        final card =
            (inside - kGridGap * (kGridColumns - 1)) / kGridColumns;
        return SingleChildScrollView(
          controller: widget.controller,
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                spacing: kGridGap,
                runSpacing: kGridGap,
                children: <Widget>[
                  for (final entry in widget.entries)
                    SizedBox(
                      width: card > 0 ? card : 0,
                      child: DocumentCard(
                        key: _keyFor(entry),
                        entry: entry,
                        store: widget.library.peek(entry),
                        query: widget.query,
                        onOpen: widget.onOpen == null
                            ? null
                            : () => widget.onOpen!(entry, _rectOf(entry)),
                        onOverflow: widget.onOverflow == null
                            ? null
                            : (target) => widget.onOverflow!(
                                entry, _rectOf(entry), target),
                      ),
                    ),
                ],
              ),
              if (widget.footer case final footer?
                  when widget.entries.isNotEmpty)
                footer,
            ],
          ),
        );
      },
    );
  }
}
