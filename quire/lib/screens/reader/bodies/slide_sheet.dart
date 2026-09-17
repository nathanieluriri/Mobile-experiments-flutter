import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../theme/colors.dart';

/// The size a slide's text is laid out at before it is scaled.
///
/// A deck states everything in the stage's own points, so one number turns the
/// whole slide into whatever it is being drawn at: a thumbnail, a card in the
/// reader, or the whole screen. Nothing inside a slide is ever laid out
/// against the screen, which is what keeps a slide the same shape everywhere
/// it appears.
double slideScale(SlideBlock slide, double width) =>
    slide.width <= 0 ? 1 : width / slide.width;

/// How tall a slide stands when it is drawn [width] wide.
double slideHeightFor(SlideBlock slide, double width) =>
    slide.width <= 0 ? 0 : width * slide.height / slide.width;

/// The ink a slide's text falls back to when the file says nothing.
///
/// Slides are read as paper, so the fallback is the paper's own ink rather
/// than the app's. A deck that stated a colour has it resolved by the parser
/// long before this.
const Color kSlideInk = AppColors.pageInk;

/// The ground a slide has when the file names none.
const Color kSlidePaper = AppColors.page;

/// The smallest a line of slide text is allowed to be drawn.
///
/// Under about four points a line stops being text and becomes a grey smear,
/// and a deck of smears is worse than a deck of slightly large text: at least
/// large text can be read. It only ever bites on a thumbnail.
const double kSlideMinFontSize = 4.0;

/// The size a run is set at when the file never said, in the stage's points.
const double kSlideDefaultFontSize = 18.0;

/// How far a bullet's glyph hangs to the left of its text, in stage points.
const double kSlideMarkerGutter = 22.0;

/// The gap between two paragraphs in a text box, as a share of the line's own
/// size. PowerPoint's own default space before a paragraph is close to this
/// and stating it as a share is what keeps it right at every scale.
const double kSlideParagraphGap = 0.35;

/// One slide, drawn at whatever size it is given.
///
/// Every shape is placed at the box the file put it in, scaled by one number.
/// That is the whole trick: a deck that laid its text out against the screen
/// would reflow differently on a card and on the stage, and two slides that
/// disagreed about where a line breaks are two different slides.
class SlideSheet extends StatelessWidget {
  const SlideSheet({
    super.key,
    required this.slide,
    required this.assets,
    this.width,
    this.showBackground = true,
  });

  final SlideBlock slide;

  /// The deck's media, keyed by the path the file stored it under.
  final Map<String, Uint8List> assets;

  /// The width to draw at, or null to take whatever the parent gives.
  final double? width;

  /// False for a slide drawn over a ground of its own, which present mode
  /// does while it is lifting one off the deck.
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final given = width;
    if (given != null) return _at(given);
    return LayoutBuilder(
      builder: (context, constraints) => _at(
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : slide.width,
      ),
    );
  }

  Widget _at(double width) {
    final scale = slideScale(slide, width);
    final height = slideHeightFor(slide, width);
    final ground = slide.background == null
        ? kSlidePaper
        : Color(slide.background!);
    final picture = slide.backgroundAsset == null
        ? null
        : assets[slide.backgroundAsset!];

    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (showBackground) ColoredBox(color: ground),
            if (showBackground && picture != null)
              Image.memory(picture, fit: BoxFit.cover, gaplessPlayback: true),
            for (final shape in slide.shapes)
              _PlacedShape(shape: shape, scale: scale, assets: assets),
          ],
        ),
      ),
    );
  }
}

/// One shape, at the box the file gave it.
class _PlacedShape extends StatelessWidget {
  const _PlacedShape({
    required this.shape,
    required this.scale,
    required this.assets,
  });

  final SlideShape shape;
  final double scale;
  final Map<String, Uint8List> assets;

  @override
  Widget build(BuildContext context) {
    final box = shape.box;
    Widget content = _Contents(shape: shape, scale: scale, assets: assets);
    if (shape.rotation != 0) {
      content = Transform.rotate(
        angle: shape.rotation * math.pi / 180,
        child: content,
      );
    }
    return Positioned(
      left: box.left * scale,
      top: box.top * scale,
      width: math.max(0, box.width * scale),
      height: math.max(0, box.height * scale),
      child: IgnorePointer(child: content),
    );
  }
}

/// What is inside a shape: its fill, its outline, and its blocks stacked the
/// way the file anchors them.
class _Contents extends StatelessWidget {
  const _Contents({
    required this.shape,
    required this.scale,
    required this.assets,
  });

  final SlideShape shape;
  final double scale;
  final Map<String, Uint8List> assets;

  @override
  Widget build(BuildContext context) {
    final fill = shape.fill;
    final line = shape.line;
    final picture = shape.fillAsset == null ? null : assets[shape.fillAsset!];

    final blocks = <Widget>[
      for (var i = 0; i < shape.blocks.length; i++)
        _SlideBlockView(
          block: shape.blocks[i],
          previous: i == 0 ? null : shape.blocks[i - 1],
          scale: scale,
          assets: assets,
        ),
    ];

    // A picture fills its shape edge to edge and everything else lays its
    // blocks out inside it. A shape holding a single picture is the ordinary
    // case and a column with one child in it would only add a seam.
    final single = shape.blocks.length == 1 && shape.blocks.first is ImageBlock;
    final Widget body = single
        ? blocks.first
        : Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: switch (shape.verticalAlign) {
              DocVerticalAlign.center => MainAxisAlignment.center,
              DocVerticalAlign.bottom => MainAxisAlignment.end,
              _ => MainAxisAlignment.start,
            },
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: blocks,
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill == null ? null : Color(fill),
        image: picture == null
            ? null
            : DecorationImage(image: MemoryImage(picture), fit: BoxFit.cover),
        border: line == null
            ? null
            : Border.all(
                color: Color(line),
                width: math.max(0.5, shape.lineWidth * scale),
              ),
      ),
      child: shape.blocks.isEmpty
          ? const SizedBox.expand()
          // A shape whose words are taller than the box it was given keeps
          // its box: PowerPoint would have shrunk the text to fit, and this
          // reader would rather clip one line than move everything under it.
          : ClipRect(
              child: OverflowBox(
                alignment: switch (shape.verticalAlign) {
                  DocVerticalAlign.bottom => Alignment.bottomCenter,
                  DocVerticalAlign.center => Alignment.center,
                  _ => Alignment.topCenter,
                },
                maxHeight: double.infinity,
                child: body,
              ),
            ),
    );
  }
}

/// One block of a shape.
class _SlideBlockView extends StatelessWidget {
  const _SlideBlockView({
    required this.block,
    required this.previous,
    required this.scale,
    required this.assets,
  });

  final DocBlock block;
  final DocBlock? previous;
  final double scale;
  final Map<String, Uint8List> assets;

  @override
  Widget build(BuildContext context) {
    final body = switch (block) {
      HeadingBlock() => _text(
        (block as HeadingBlock).spans,
        align: DocAlign.start,
      ),
      ParagraphBlock() => _paragraph(block as ParagraphBlock),
      ListItemBlock() => _listItem(block as ListItemBlock),
      CodeBlock() => _text(
        <DocSpan>[DocSpan((block as CodeBlock).text, mono: true)],
        align: DocAlign.start,
      ),
      ImageBlock() => _image(block as ImageBlock),
      TableBlock() => _table(block as TableBlock),
      DividerBlock() => Padding(
        padding: EdgeInsets.symmetric(vertical: 4 * scale),
        child: Container(height: math.max(0.5, scale), color: kSlideInk),
      ),
      // A deck cannot nest a deck. The case exists because the block model is
      // sealed, which is what makes every renderer say what it does with a new
      // kind rather than quietly drawing nothing.
      SlideBlock() => const SizedBox.shrink(),
    };
    final gap = _gapAbove;
    if (gap <= 0) return body;
    return Padding(padding: EdgeInsets.only(top: gap), child: body);
  }

  /// The space above this block, taken from its own size so the gaps in a
  /// text box grow and shrink with the text rather than staying put.
  double get _gapAbove {
    if (previous == null) return 0;
    return _sizeOf(block) * kSlideParagraphGap * scale;
  }

  double _sizeOf(DocBlock block) {
    final spans = switch (block) {
      HeadingBlock() => block.spans,
      ParagraphBlock() => block.spans,
      ListItemBlock() => block.spans,
      _ => const <DocSpan>[],
    };
    for (final span in spans) {
      final size = span.fontSize;
      if (size != null) return size;
    }
    return kSlideDefaultFontSize;
  }

  Widget _paragraph(ParagraphBlock block) {
    if (block.spans.isEmpty) {
      return SizedBox(height: kSlideDefaultFontSize * scale);
    }
    return Padding(
      padding: EdgeInsets.only(left: block.indent * kSlideMarkerGutter * scale),
      child: _text(block.spans, align: block.align),
    );
  }

  /// A bullet hangs in its own gutter, the way it does on the slide, rather
  /// than being written into the text. A marker inside the string would be
  /// found by the search and read out by a screen reader as a word.
  Widget _listItem(ListItemBlock block) {
    final marker = block.marker;
    final gutter = kSlideMarkerGutter * scale;
    return Padding(
      padding: EdgeInsets.only(left: block.level * gutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: gutter,
            child: marker == null
                ? null
                : _text(
                    <DocSpan>[
                      DocSpan(
                        marker,
                        color: _inkOf(block.spans),
                        fontSize: _sizeOf(block),
                      ),
                    ],
                    align: DocAlign.start,
                  ),
          ),
          Expanded(child: _text(block.spans, align: DocAlign.start)),
        ],
      ),
    );
  }

  int? _inkOf(List<DocSpan> spans) {
    for (final span in spans) {
      if (span.color != null) return span.color;
    }
    return null;
  }

  Widget _text(List<DocSpan> spans, {required DocAlign align}) => Text.rich(
    TextSpan(
      children: <InlineSpan>[
        for (final span in spans) TextSpan(text: span.text, style: _style(span)),
      ],
    ),
    textAlign: switch (align) {
      DocAlign.center => TextAlign.center,
      DocAlign.end => TextAlign.right,
      DocAlign.justify => TextAlign.justify,
      DocAlign.start => TextAlign.left,
    },
  );

  TextStyle _style(DocSpan span) => TextStyle(
    // One family, because this app has one and a slide that brought its own
    // would be the only place in quire speaking in a second voice. What the
    // deck's own face was is lost here, and the size and the weight are not.
    fontFamily: 'Inter',
    fontSize: math.max(
      kSlideMinFontSize,
      (span.fontSize ?? kSlideDefaultFontSize) * scale,
    ),
    height: 1.22,
    fontWeight: span.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
    // Stated either way, never left to inherit. A slide is drawn outside any
    // Material, and the fallback style there carries a yellow double
    // underline that would land under every line of every deck.
    decoration: span.underline
        ? TextDecoration.underline
        : TextDecoration.none,
    decorationColor: span.color == null ? kSlideInk : Color(span.color!),
    color: span.color == null ? kSlideInk : Color(span.color!),
  );

  Widget _image(ImageBlock block) {
    final bytes = assets[block.assetKey];
    if (bytes == null) {
      // A picture the file pointed at and did not carry. The space it claimed
      // is kept, because a slide that closed the hole up would be telling the
      // reader the deck was always laid out this way.
      return const _MissingPicture();
    }
    return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
  }

  Widget _table(TableBlock table) {
    final hairline = math.max(0.5, scale);
    return Table(
      border: TableBorder.symmetric(
        inside: BorderSide(color: AppColors.pageInkSoft, width: hairline),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: <int, TableColumnWidth>{
        for (var i = 0; i < table.columns.length; i++)
          if (table.columns[i].width != null)
            i: FixedColumnWidth(table.columns[i].width! * scale),
      },
      children: <TableRow>[
        for (final row in table.rows)
          TableRow(
            children: <Widget>[
              for (final cell in row.cells)
                _TableCell(cell: cell, scale: scale, assets: assets),
            ],
          ),
      ],
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.cell,
    required this.scale,
    required this.assets,
  });

  final DocCell cell;
  final double scale;
  final Map<String, Uint8List> assets;

  @override
  Widget build(BuildContext context) {
    final fill = cell.background;
    return Container(
      color: fill == null ? null : Color(fill),
      padding: EdgeInsets.symmetric(
        horizontal: 6 * scale,
        vertical: 4 * scale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < cell.blocks.length; i++)
            _SlideBlockView(
              block: cell.blocks[i],
              previous: i == 0 ? null : cell.blocks[i - 1],
              scale: scale,
              assets: assets,
            ),
        ],
      ),
    );
  }
}

/// The space a picture the file did not carry was going to take.
class _MissingPicture extends StatelessWidget {
  const _MissingPicture();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.pageInkSoft.withValues(alpha: 0.10),
      border: Border.all(
        color: AppColors.pageInkSoft.withValues(alpha: 0.35),
        width: 0.5,
      ),
    ),
    child: const SizedBox.expand(),
  );
}
