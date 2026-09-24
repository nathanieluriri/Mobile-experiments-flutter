import 'dart:ui';

import 'quire_mark_data.dart';
import 'svg_path.dart';

/// The side of the square the mark's path data is drawn in.
const kMarkViewport = 240.0;

/// What the native splash maps [kMarkViewport] onto, in logical pixels.
///
/// Android 12 and later draw a plain vector icon at one and a half times its
/// 192 icon view, and the launch screens on older Android and on iOS are laid
/// out to match, so this is the size on every phone.
const kMarkBox = 288.0;

/// The name's slot at the foot of the splash, and how far it sits above the
/// bottom of the screen. Android 12's branding view has exactly this size and
/// margin, and the other launch screens copy it.
const kNameBox = Size(200, 80);
const kNameBottom = 60.0;

/// The name's path data is drawn in this box and moved down by [kNameShift].
const kNameViewport = Size(335.04, 134.016);
const kNameShift = 48.16;

/// One of the mark's four panes: its outline, and the holes inside it.
class MarkPane {
  MarkPane({required this.outline, required this.holes})
    : square = _squareOf(outline);

  final Path outline;
  final List<Path> holes;

  /// The pane's square, without the dog ear the first pane carries above it.
  final Rect square;

  Offset get centre => square.center;

  static Rect _squareOf(Path outline) {
    final bounds = outline.getBounds();
    return Rect.fromLTRB(
      bounds.left,
      bounds.bottom - bounds.width,
      bounds.right,
      bounds.bottom,
    );
  }
}

/// The mark and the name as paths, in their own viewports.
abstract final class QuireMark {
  static final Path whole = parseSvgPath(kMarkPathData)
    ..fillType = PathFillType.evenOdd;

  /// The panes in reading order: the dog-eared one, then right, then the two
  /// below.
  static final List<MarkPane> panes = _panes();

  /// The ink's own bounds inside the viewport.
  static final Rect ink = whole.getBounds();

  /// The middle of the two by two the panes make, which is where they gather.
  static final Offset middle = Offset(
    (panes[0].centre.dx + panes[1].centre.dx) / 2,
    (panes[0].centre.dy + panes[2].centre.dy) / 2,
  );

  static final Path name = parseSvgPath(
    kNamePathData,
  ).shift(const Offset(0, kNameShift));

  static List<MarkPane> _panes() {
    final parts = subpathsOf(kMarkPathData).map(parseSvgPath).toList();
    return [
      MarkPane(outline: parts[0], holes: [parts[1], parts[2]]),
      MarkPane(outline: parts[3], holes: [parts[4]]),
      MarkPane(outline: parts[5], holes: [parts[6]]),
      MarkPane(outline: parts[7], holes: [parts[8]]),
    ];
  }
}
