import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/marked_text.dart';
import '../../widgets/press_fade.dart';
import '../../widgets/type_mark.dart';
import 'document_card.dart';

/// Where a row's title starts: the padding, the mark, and the gap after it.
const double kListTextLeft =
    kListRowPaddingX + kTypeMarkSize + kListMarkGap;

/// The meta line under a row's title, as in `PDF - 6 pages - 306 KB`.
///
/// The noun is set in lower case here and in upper case on a card, because a
/// row sets it beside a title in sentence case and a card sets it alone. Both
/// are literals rather than one string put through a transform, so a golden
/// reads exactly what the source says.
String rowMeta(LibraryEntry entry, DocumentStore? store) {
  final units = cardUnits(entry, store);
  return <String>[
    entry.mark,
    if (units != null) '${groupedNumber(units.count)} ${units.lower}',
    entry.sizeLabel,
    // Read where it lies rather than held by quire, which is worth a word
    // because it is gone from the desk if it is gone from the phone.
    if (entry.onDevice) 'on the phone',
  ].join(' - ');
}

/// One document in the list: its mark, its title, what it is made of, and how
/// far into it you are.
///
/// The rule under it starts under the title rather than under the mark, which
/// is what makes a column of marks read as a column and the rules read as a
/// list rather than as a table.
class DocumentRow extends StatelessWidget {
  const DocumentRow({
    super.key,
    required this.entry,
    required this.store,
    this.query = '',
    this.onOpen,
    this.onOverflow,
  });

  final LibraryEntry entry;

  /// What is known about the file, or null before anything has read it.
  final DocumentStore? store;

  /// The search, marked wherever it appears in the title.
  final String query;

  final VoidCallback? onOpen;

  /// The three dots. The menu behind them belongs to the shell, which is
  /// handed the dots' rect so it can hang the menu off them.
  final void Function(Rect target)? onOverflow;

  @override
  Widget build(BuildContext context) {
    final held = store;
    final opened = held != null && held.opened;
    return PaperPress(
      onTap: onOpen,
      semanticLabel: entry.title,
      // A row is drawn square, but its wash is not: it fills the row's own
      // padding and stops short of the hairline, so it reads as light on the
      // row rather than as a selection band across the list.
      washRadius: kListRowWashRadius,
      child: SizedBox(
        height: kListRowHeight,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kListRowPaddingX,
              ),
              child: Row(
                children: [
                  TypeMark(
                    letters: entry.mark,
                    chroma: chromaFor(entry.format),
                  ),
                  const SizedBox(width: kListMarkGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MarkedText(
                          entry.title,
                          style: AppText.rowTitle.copyWith(
                            color: AppColors.ink,
                          ),
                          markerColor: AppColors.foundWash,
                          query: query,
                          maxLines: 1,
                          ellipsis: '…',
                        ),
                        const SizedBox(height: kListTitleGap),
                        Text(
                          rowMeta(entry, held),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.docMeta.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OverflowTarget(
                    size: kOverflowTarget,
                    onTap: onOverflow,
                  ),
                ],
              ),
            ),
            // The bar hangs off the bottom of the row rather than sitting in
            // the column above it, so a document you have read and one you
            // have not put their titles on the same line. A column that grew a
            // third child would lift its own title by half the bar's height,
            // and a list whose titles moved up and down according to whether
            // they had been opened would read as badly set.
            if (opened)
              Positioned(
                left: kListTextLeft,
                bottom: kSpace8,
                child: _Progress(fraction: held.progress),
              ),
            // The rule stops at the row's own right padding. Running it to the
            // screen edge would leave the list ruled off centre: carefully
            // placed under the title at one end and bleeding past everything
            // at the other.
            Positioned(
              left: kListRuleInset,
              right: kListRowPaddingX,
              bottom: 0,
              height: hairline(context),
              child: const ColoredBox(color: AppColors.hairline),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far into a document you have read, under its meta line.
class _Progress extends StatelessWidget {
  const _Progress({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kListProgressWidth,
      height: kListProgressHeight,
      child: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: AppColors.surfaceHigh),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: kListProgressWidth * fraction.clamp(0, 1),
            child: const ColoredBox(color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

/// The three dots that open whatever a document can have done to it.
///
/// Vertical, in [AppColors.inkFaint], on a target big enough for a thumb: 40
/// in a row, 32 in a card header, and the dots themselves are the same size in
/// both, because the dots are the mark and the target is only the room round
/// it.
class OverflowTarget extends StatefulWidget {
  const OverflowTarget({super.key, required this.size, this.onTap});

  final double size;

  /// Handed the dots' own rectangle on screen, because a menu belongs under
  /// the thing that opened it. A card is tall enough that its bottom edge is
  /// most of a screen away from the dots printed at its head.
  final void Function(Rect target)? onTap;

  @override
  State<OverflowTarget> createState() => _OverflowTargetState();
}

class _OverflowTargetState extends State<OverflowTarget> {
  final GlobalKey _dots = GlobalKey();

  /// Where the dots are, in the coordinates the shell lays its menu out in.
  ///
  /// [Rect.zero] when the box has not been laid out, which the shell already
  /// treats as no anchor rather than as the top left corner.
  Rect get _rect {
    final box = _dots.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final tap = widget.onTap;
    final size = widget.size;
    return GestureDetector(
      key: _dots,
      behavior: HitTestBehavior.opaque,
      onTap: tap == null ? null : () => tap(_rect),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (var dot = 0; dot < 3; dot++) ...<Widget>[
              if (dot > 0) const SizedBox(height: kOverflowDotGap),
              const SizedBox(
                width: kOverflowDot,
                height: kOverflowDot,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.inkFaint,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
