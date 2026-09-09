import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../helpers/fold_geometry.dart';
import '../../model/document.dart';
import '../../painting/fold_painter.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/card_marquee/card_marquee.dart';
import '../../widgets/card_marquee/marquee_constants.dart';
import '../../widgets/press_fade.dart';
import 'reader_chrome.dart';

/// How wide a text card in the riffle is: a page thumbnail is a picture of a
/// page, while a section is a line of type, and a line of type needs a
/// measure rather than a page shape.
const kRiffleCardWidth = 300.0;
const kRiffleCardHeight = 96.0;

/// The dot beside a dog eared item's folio.
const kRiffleDogEarDot = 3.0;

/// How far in the fold on a dog eared thumbnail sits.
const kRiffleThumbFold = 10.0;

/// One thing a reader can land on: a page, a section, or a sheet of a
/// workbook.
class RiffleItem {
  const RiffleItem({
    required this.folio,
    this.title,
    this.subtitle,
    this.dogEared = false,
    this.thumbnail,
  });

  /// What is printed under a page thumbnail, or beside a card.
  final String folio;

  /// A section heading or a sheet name. Null for a page.
  final String? title;

  /// The first line under that heading.
  final String? subtitle;

  final bool dogEared;

  /// A real picture of the page, when the format has one. Pages with no
  /// thumbnail draw an empty leaf, which is still the shape of the page.
  final Widget? thumbnail;
}

/// What the riffle holds for a document, by format.
///
/// A CSV comes back empty on purpose: a delimited file has no pages, no
/// headings and no sheets, so there is nothing to riffle and tapping its fore
/// edge does nothing rather than opening an empty drawer.
List<RiffleItem> riffleItemsFor(DocumentStore store) {
  if (store.isPdf) {
    return <RiffleItem>[
      for (var i = 0; i < store.pdfPageCount; i++)
        RiffleItem(folio: '${i + 1}', dogEared: store.dogEared.contains(i)),
    ];
  }
  final document = store.document;
  if (document == null) return const <RiffleItem>[];
  if (store.isGrid) {
    if (document.sourceFormat == 'csv') return const <RiffleItem>[];
    return <RiffleItem>[
      for (var i = 0; i < document.sections.length; i++)
        RiffleItem(
          folio: '${i + 1}',
          title: document.sections[i].title,
          subtitle: _rowCount(document.sections[i]),
        ),
    ];
  }
  final items = <RiffleItem>[];
  for (var s = 0; s < document.sections.length; s++) {
    final blocks = document.sections[s].blocks;
    for (var b = 0; b < blocks.length; b++) {
      final block = blocks[b];
      if (block is! HeadingBlock) continue;
      items.add(
        RiffleItem(
          folio: '${items.length + 1}',
          title: block.text,
          subtitle: _firstLineAfter(blocks, b),
        ),
      );
    }
  }
  return items;
}

String _rowCount(DocSection section) {
  for (final block in section.blocks) {
    if (block is TableBlock) return '${block.rows.length} rows';
  }
  return '';
}

String _firstLineAfter(List<DocBlock> blocks, int from) {
  for (var i = from + 1; i < blocks.length; i++) {
    final block = blocks[i];
    if (block is HeadingBlock) return '';
    if (block is ParagraphBlock && block.text.trim().isNotEmpty) {
      return block.text;
    }
    if (block is ListItemBlock && block.text.trim().isNotEmpty) {
      return block.text;
    }
  }
  return '';
}

/// The riffle: the document's own pages fanned on an arc you spin with a
/// thumb, over a scrim, over the reader.
///
/// It is the marquee from the family made finite, because a document has a
/// real first and last page, and the arc's foreshortening is what your eye
/// does looking down the edge of a fanned page block.
class RiffleSheet extends StatefulWidget {
  const RiffleSheet({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.kindLabel,
    this.progress = 1,
    this.onSelect,
    this.onClose,
  });

  final List<RiffleItem> items;

  /// The item the reader came in on, which is the one the arc opens at and the
  /// one a dismissal returns to.
  final int initialIndex;

  /// The standing head: `6 PAGES`, `9 SECTIONS`, `3 SHEETS`.
  final String kindLabel;

  /// 0 with the layer gone, 1 with it fully in.
  final double progress;

  final void Function(int index)? onSelect;
  final VoidCallback? onClose;

  @override
  State<RiffleSheet> createState() => _RiffleSheetState();
}

class _RiffleSheetState extends State<RiffleSheet> {
  static const double _viewport = kSheetHeight;

  late final ScrollController _controller = ScrollController(
    initialScrollOffset: finiteOrigin(widget.initialIndex, _viewport),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Which item is in the middle of the arc, from the scroll offset alone.
  ///
  /// The marquee does not report it, and asking each slot to decide for itself
  /// would mean every slot rebuilding every frame to find out it is not the
  /// one.
  int get _centre {
    final offset = _controller.hasClients
        ? _controller.offset
        : _controller.initialScrollOffset;
    final raw =
        (offset - finiteLeadingPadding(_viewport) + _viewport / 2) /
            kMarqueeItemHeight +
        0.5;
    return raw.round().clamp(0, widget.items.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.progress.clamp(0, 1),
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.ground.withValues(alpha: kRiffleScrimOpacity),
            ),
          ),
          Positioned(
            left: kScreenPadding,
            top: kRiffleHeaderTop,
            child: Text(
              widget.kindLabel,
              style: AppText.micro.copyWith(color: AppColors.inkFaint),
            ),
          ),
          Positioned(
            left: kScreenWidth - kScreenPadding - kHeaderButtonSize,
            top: kRiffleHeaderTop - (kHeaderButtonSize - 11) / 2,
            child: PaperPress(
              onTap: widget.onClose,
              semanticLabel: 'Close the riffle',
              child: Container(
                width: kHeaderButtonSize,
                height: kHeaderButtonSize,
                decoration: BoxDecoration(
                  // The same control fill and hairline the reader's own head
                  // band wears, because it is the same button in the same
                  // place doing the opposite job.
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(kHeaderButtonRadius),
                  border: AppEdges.all(context),
                ),
                child: const Center(
                  child: Icon(
                    LucideIcons.x,
                    size: kChromeIcon,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: kSheetTop,
            width: kScreenWidth,
            height: _viewport,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final centre = _centre;
                return CardMarquee(
                  controller: _controller,
                  finite: true,
                  itemCount: widget.items.length,
                  viewportHeight: _viewport,
                  ground: AppColors.ground,
                  onItemTap: widget.onSelect,
                  itemBuilder: (context, index) => _RiffleSlot(
                    item: widget.items[index],
                    centred: index == centre,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the riffle's standing head sits.
const kRiffleHeaderTop = 74.0;

/// One slot of the arc: a page thumbnail with its folio under it, or a card
/// carrying a section heading.
class _RiffleSlot extends StatelessWidget {
  const _RiffleSlot({required this.item, required this.centred});

  final RiffleItem item;

  /// True for the one item the arc has landed on, which lifts and takes the
  /// folio in the accent.
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final folio = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.dogEared)
          Container(
            width: kRiffleDogEarDot,
            height: kRiffleDogEarDot,
            margin: const EdgeInsets.only(right: kSpace4),
            decoration: const BoxDecoration(
              color: AppColors.accentBright,
              shape: BoxShape.circle,
            ),
          ),
        Text(
          item.folio,
          style: AppText.folioSmall.copyWith(
            color: centred ? AppColors.accentBright : AppColors.inkFaint,
          ),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        item.title == null
            ? _Thumbnail(item: item, centred: centred)
            : _Card(item: item, centred: centred),
        const SizedBox(height: kSpace4),
        folio,
      ],
    );
  }
}

/// A picture of a page, at 84 / 372 of its size on the sheet.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item, required this.centred});

  final RiffleItem item;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kRiffleThumbWidth,
      height: kRiffleThumbHeight,
      // Every slot carries the same hairline, centred or not. The stack
      // overlaps leaf on leaf, and without an edge on each one a run of
      // thumbnails would read as a single tall sheet.
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: kPeelableCorner,
        border: AppEdges.all(context),
      ),
      child: ClipRRect(
        borderRadius: kPeelableCorner,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?item.thumbnail,
            if (item.dogEared)
              CustomPaint(
                painter: FoldPainter.atRest(
                  restInset: kRiffleThumbFold,
                  corner: Corner.bottomRight,
                  background: AppColors.leafBack,
                  flapColor: AppColors.leafFlap,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A section of a document that has no pages: its heading, and the first line
/// under it.
class _Card extends StatelessWidget {
  const _Card({required this.item, required this.centred});

  final RiffleItem item;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kRiffleCardWidth,
      height: kRiffleCardHeight,
      padding: const EdgeInsets.all(kSpace14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kLeafRadius),
        border: AppEdges.all(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.title.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: kSpace4),
          Expanded(
            child: Text(
              item.subtitle ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodyTight.copyWith(color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
