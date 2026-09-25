/// Laying a slide out in the deck's own points.
///
/// Every measurement in this file is in the stage's points rather than the
/// app's, which is why none of them sit on the spacing scale in
/// `theme/metrics.dart` and none of them should be moved onto it. A slide's
/// geometry belongs to whoever made the deck: a bullet gutter of 22 is 22 of
/// the file's points, and it becomes whatever the one scale factor makes of it
/// on a thumbnail, on the bench and on the stage. A number taken from the
/// app's scale here would be the app writing on somebody's slide, and it would
/// come out a different size in each of the three places.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../theme/colors.dart';

/// Laying a slide out in the deck's own points.
///
/// Every measurement in this file is in the stage's points rather than the
/// app's, which is why none of them sit on the spacing scale in
/// `theme/metrics.dart` and none of them should be moved onto it. A slide's
/// geometry belongs to whoever made the deck: a bullet gutter of 22 is 22 of
/// the file's points, and it becomes whatever the one scale factor makes of it
/// on a thumbnail, on the bench and on the stage. A number taken from the
/// app's scale here would be the app writing on somebody's slide, and it would
/// be a different size on each of the three.

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
    Widget body = single
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
    if (single && shape.opacity < 1) {
      body = Opacity(opacity: shape.opacity, child: body);
    }

    final Widget content = shape.blocks.isEmpty
        ? const SizedBox.expand()
        : single
        ? body
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
          );

    final plain = shape.geometry == 'rect' && shape.dash == null && !shape.shadow;
    if (plain) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: fill == null ? null : Color(fill),
          image: picture == null
              ? null
              : DecorationImage(
                  image: MemoryImage(picture),
                  fit: BoxFit.cover,
                  opacity: shape.opacity,
                ),
          border: line == null
              ? null
              : Border.all(
                  color: Color(line),
                  width: math.max(0.5, shape.lineWidth * scale),
                ),
        ),
        child: content,
      );
    }

    final outline = slideOutlineOf(shape.geometry);
    Widget inside = content;
    if (picture != null || (single && !outline.open)) {
      inside = ClipPath(
        clipper: _OutlineClip(outline, shape.flipH, shape.flipV),
        child: picture == null
            ? content
            : DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: MemoryImage(picture),
                    fit: BoxFit.cover,
                    opacity: shape.opacity,
                  ),
                ),
                child: content,
              ),
      );
    }
    return CustomPaint(
      painter: _OutlinePainter(
        outline: outline,
        fill: fill == null ? null : Color(fill),
        line: line == null ? null : Color(line),
        width: math.max(0.5, shape.lineWidth * scale),
        dash: shape.dash,
        shadow: shape.shadow,
        scale: scale,
        flipH: shape.flipH,
        flipV: shape.flipV,
      ),
      child: inside,
    );
  }
}

/// A preset outline: how to draw it in a box, and whether it is a line
/// rather than something that can be filled.
class SlideOutline {
  const SlideOutline(this.build, {this.open = false});
  final Path Function(Size size) build;
  final bool open;

  Path pathIn(Size size, {bool flipH = false, bool flipV = false}) {
    final path = build(size);
    if (!flipH && !flipV) return path;
    final matrix = Matrix4.identity()
      ..translateByDouble(flipH ? size.width : 0, flipV ? size.height : 0, 0, 1)
      ..scaleByDouble(flipH ? -1 : 1, flipV ? -1 : 1, 1, 1);
    return path.transform(matrix.storage);
  }
}

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

final Map<String, SlideOutline> _outlines = <String, SlideOutline>{};

/// The outline PowerPoint's preset [name] draws, or a rectangle for one this
/// reader does not know.
SlideOutline slideOutlineOf(String name) =>
    _outlines.putIfAbsent(name, () => _outlineFor(name));

SlideOutline _outlineFor(String name) {
  switch (name) {
    case 'line':
    case 'straightConnector1':
      return SlideOutline(
        (s) => Path()
          ..moveTo(0, 0)
          ..lineTo(s.width, s.height),
        open: true,
      );
    case 'bentConnector2':
      return SlideOutline(
        (s) => Path()
          ..moveTo(0, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width, s.height),
        open: true,
      );
    case 'bentConnector3':
    case 'bentConnector4':
      return SlideOutline(
        (s) => Path()
          ..moveTo(0, 0)
          ..lineTo(s.width / 2, 0)
          ..lineTo(s.width / 2, s.height)
          ..lineTo(s.width, s.height),
        open: true,
      );
    case 'curvedConnector2':
    case 'curvedConnector3':
    case 'curvedConnector4':
      return SlideOutline(
        (s) => Path()
          ..moveTo(0, 0)
          ..cubicTo(s.width / 2, 0, s.width / 2, s.height, s.width, s.height),
        open: true,
      );
    case 'ellipse':
    case 'flowChartConnector':
      return SlideOutline((s) => Path()..addOval(Offset.zero & s));
    case 'roundRect':
    case 'round2SameRect':
    case 'flowChartAlternateProcess':
      return SlideOutline(
        (s) => Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Offset.zero & s,
              Radius.circular(math.min(s.width, s.height) * 0.1667),
            ),
          ),
      );
    case 'flowChartTerminator':
      return SlideOutline(
        (s) => Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Offset.zero & s,
              Radius.circular(math.min(s.width, s.height) / 2),
            ),
          ),
      );
    case 'triangle':
    case 'flowChartExtract':
      return SlideOutline(
        (s) => _polygon(<Offset>[
          Offset(s.width / 2, 0),
          Offset(s.width, s.height),
          Offset(0, s.height),
        ]),
      );
    case 'rtTriangle':
      return SlideOutline(
        (s) => _polygon(<Offset>[
          Offset.zero,
          Offset(s.width, s.height),
          Offset(0, s.height),
        ]),
      );
    case 'diamond':
    case 'flowChartDecision':
      return SlideOutline(
        (s) => _polygon(<Offset>[
          Offset(s.width / 2, 0),
          Offset(s.width, s.height / 2),
          Offset(s.width / 2, s.height),
          Offset(0, s.height / 2),
        ]),
      );
    case 'parallelogram':
    case 'flowChartInputOutput':
      return SlideOutline((s) {
        final a = math.min(s.width, s.height) * 0.25;
        return _polygon(<Offset>[
          Offset(a, 0),
          Offset(s.width, 0),
          Offset(s.width - a, s.height),
          Offset(0, s.height),
        ]);
      });
    case 'trapezoid':
      return SlideOutline((s) {
        final a = math.min(s.width, s.height) * 0.25;
        return _polygon(<Offset>[
          Offset(a, 0),
          Offset(s.width - a, 0),
          Offset(s.width, s.height),
          Offset(0, s.height),
        ]);
      });
    case 'pentagon':
      return SlideOutline(
        (s) => _polygon(<Offset>[
          Offset(s.width / 2, 0),
          Offset(s.width, s.height * 0.382),
          Offset(s.width * 0.809, s.height),
          Offset(s.width * 0.191, s.height),
          Offset(0, s.height * 0.382),
        ]),
      );
    case 'hexagon':
      return SlideOutline((s) {
        final a = math.min(s.width, s.height) * 0.25;
        return _polygon(<Offset>[
          Offset(a, 0),
          Offset(s.width - a, 0),
          Offset(s.width, s.height / 2),
          Offset(s.width - a, s.height),
          Offset(a, s.height),
          Offset(0, s.height / 2),
        ]);
      });
    case 'octagon':
      return SlideOutline((s) {
        final a = math.min(s.width, s.height) * 0.29289;
        return _polygon(<Offset>[
          Offset(a, 0),
          Offset(s.width - a, 0),
          Offset(s.width, a),
          Offset(s.width, s.height - a),
          Offset(s.width - a, s.height),
          Offset(a, s.height),
          Offset(0, s.height - a),
          Offset(0, a),
        ]);
      });
    case 'star4':
    case 'star5':
    case 'star6':
    case 'star8':
      final points = int.parse(name.substring(4));
      final inner = switch (points) {
        4 => 0.25,
        5 => 0.382,
        6 => 0.5,
        _ => 0.7,
      };
      return SlideOutline((s) {
        final out = <Offset>[];
        for (var i = 0; i < points * 2; i++) {
          final r = i.isEven ? 1.0 : inner;
          final a = -math.pi / 2 + i * math.pi / points;
          out.add(
            Offset(
              s.width / 2 + math.cos(a) * s.width / 2 * r,
              s.height / 2 + math.sin(a) * s.height / 2 * r,
            ),
          );
        }
        return _polygon(out);
      });
    case 'rightArrow':
    case 'leftArrow':
    case 'upArrow':
    case 'downArrow':
      return SlideOutline((s) {
        final across = name == 'upArrow' || name == 'downArrow';
        final length = across ? s.height : s.width;
        final thick = across ? s.width : s.height;
        final head = math.min(length, math.min(s.width, s.height) * 0.5);
        final shaft = thick * 0.25;
        final raw = <Offset>[
          Offset(0, shaft),
          Offset(length - head, shaft),
          Offset(length - head, 0),
          Offset(length, thick / 2),
          Offset(length - head, thick),
          Offset(length - head, thick - shaft),
          Offset(0, thick - shaft),
        ];
        Offset place(Offset p) => switch (name) {
          'leftArrow' => Offset(length - p.dx, p.dy),
          'downArrow' => Offset(p.dy, p.dx),
          'upArrow' => Offset(p.dy, length - p.dx),
          _ => p,
        };
        return _polygon(raw.map(place).toList());
      });
    case 'chevron':
    case 'homePlate':
      return SlideOutline((s) {
        final a = math.min(s.width / 2, math.min(s.width, s.height) * 0.5);
        return _polygon(<Offset>[
          Offset.zero,
          Offset(s.width - a, 0),
          Offset(s.width, s.height / 2),
          Offset(s.width - a, s.height),
          Offset(0, s.height),
          if (name == 'chevron') Offset(a, s.height / 2),
        ]);
      });
    case 'plus':
    case 'mathPlus':
      return SlideOutline((s) {
        final a = math.min(s.width, s.height) * 0.25;
        return _polygon(<Offset>[
          Offset(a, 0),
          Offset(s.width - a, 0),
          Offset(s.width - a, a),
          Offset(s.width, a),
          Offset(s.width, s.height - a),
          Offset(s.width - a, s.height - a),
          Offset(s.width - a, s.height),
          Offset(a, s.height),
          Offset(a, s.height - a),
          Offset(0, s.height - a),
          Offset(0, a),
          Offset(a, a),
        ]);
      });
    case 'heart':
      return SlideOutline((s) {
        final w = s.width, h = s.height;
        return Path()
          ..moveTo(w / 2, h * 0.25)
          ..cubicTo(w * 0.15, -h * 0.15, -w * 0.25, h * 0.45, w / 2, h)
          ..moveTo(w / 2, h * 0.25)
          ..cubicTo(w * 0.85, -h * 0.15, w * 1.25, h * 0.45, w / 2, h);
      });
  }
  return SlideOutline((s) => Path()..addRect(Offset.zero & s));
}

/// The lengths of PowerPoint's preset dashes, in widths of the line.
List<double> slideDashOf(String name) => switch (name) {
  'sysDot' => const <double>[1, 1],
  'sysDash' => const <double>[3, 1],
  'dash' => const <double>[4, 3],
  'dashDot' => const <double>[4, 3, 1, 3],
  'lgDash' => const <double>[8, 3],
  'lgDashDot' => const <double>[8, 3, 1, 3],
  'lgDashDotDot' => const <double>[8, 3, 1, 3, 1, 3],
  'sysDashDot' => const <double>[3, 1, 1, 1],
  'sysDashDotDot' => const <double>[3, 1, 1, 1, 1, 1],
  'dot' => const <double>[1, 3],
  _ => const <double>[],
};

/// [path] cut into the dashes [pattern] states, in widths of [width].
Path dashedPath(Path path, List<double> pattern, double width) {
  if (pattern.isEmpty) return path;
  final out = Path();
  for (final metric in path.computeMetrics()) {
    var at = 0.0;
    var i = 0;
    while (at < metric.length) {
      final length = math.max(0.5, pattern[i % pattern.length] * width);
      if (i.isEven) out.addPath(metric.extractPath(at, at + length), Offset.zero);
      at += length;
      i++;
    }
  }
  return out;
}

class _OutlineClip extends CustomClipper<Path> {
  _OutlineClip(this.outline, this.flipH, this.flipV);
  final SlideOutline outline;
  final bool flipH;
  final bool flipV;

  @override
  Path getClip(Size size) => outline.pathIn(size, flipH: flipH, flipV: flipV);

  @override
  bool shouldReclip(_OutlineClip old) =>
      old.outline != outline || old.flipH != flipH || old.flipV != flipV;
}

/// A shape's outline filled, stroked and, where the deck asks for a drop
/// shadow, laid over a darker copy of itself set off down and to the right.
/// The copy is not blurred: nothing in this app blurs, and the offset alone
/// is what tells a reader the shape stands off the slide.
class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.outline,
    required this.fill,
    required this.line,
    required this.width,
    required this.dash,
    required this.shadow,
    required this.scale,
    required this.flipH,
    required this.flipV,
  });

  final SlideOutline outline;
  final Color? fill;
  final Color? line;
  final double width;
  final String? dash;
  final bool shadow;
  final double scale;
  final bool flipH;
  final bool flipV;

  @override
  void paint(Canvas canvas, Size size) {
    final path = outline.pathIn(size, flipH: flipH, flipV: flipV);
    final stroke = line == null
        ? null
        : (dash == null ? path : dashedPath(path, slideDashOf(dash!), width));
    if (shadow) {
      final offset = Offset(3 * scale, 3 * scale);
      final ink = Paint()..color = const Color(0x40000000);
      if (fill != null && !outline.open) {
        canvas.drawPath(path.shift(offset), ink);
      } else if (stroke != null) {
        canvas.drawPath(
          stroke.shift(offset),
          ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = width,
        );
      }
    }
    if (fill != null && !outline.open) {
      canvas.drawPath(path, Paint()..color = fill!);
    }
    if (stroke != null) {
      canvas.drawPath(
        stroke,
        Paint()
          ..color = line!
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.outline != outline ||
      old.fill != fill ||
      old.line != line ||
      old.width != width ||
      old.dash != dash ||
      old.shadow != shadow ||
      old.scale != scale ||
      old.flipH != flipH ||
      old.flipV != flipV;
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
