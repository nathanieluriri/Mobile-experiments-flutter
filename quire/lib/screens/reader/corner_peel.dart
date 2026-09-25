import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../helpers/fold_geometry.dart';
import '../../painting/fold_painter.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';

/// How thick the thread line along a caught dog ear's fold is drawn.
const kDogEarLineWidth = 1.5;

/// Where the corner that folds sits, in sheet coordinates.
Offset foldCornerOf(Corner corner, Size size) =>
    Offset(corner.mirrorsX ? 0 : size.width, corner.mirrorsY ? size.height : 0);

/// The corner diagonally across from the one that folds, which is where a
/// committed flip sweeps to.
Offset foldOppositeOf(Corner corner, Size size) =>
    Offset(corner.mirrorsX ? size.width : 0, corner.mirrorsY ? 0 : size.height);

/// Where an untouched fold sits, [inset] in from its corner along both edges.
Offset foldRestPoint(Corner corner, Size size, double inset) => Offset(
  corner.mirrorsX ? inset : size.width - inset,
  corner.mirrorsY ? size.height - inset : inset,
);

/// How far the corner has to travel before letting go turns the sheet over.
///
/// It is a fraction of the whole diagonal rather than of the sheet's height,
/// because the gesture is one corner reaching for the corner opposite it, and
/// the diagonal is the distance that actually separates them.
double flipCommitDistance(Size size) =>
    kFlipCommitFraction *
    math.sqrt(size.width * size.width + size.height * size.height);

/// How far the corner has to travel before stopping still catches a dog ear
/// instead of springing home.
double dogEarCatchDistance(Size size) =>
    kDogEarCatchFraction * flipCommitDistance(size);

/// The peeled corner of a sheet: the region torn away, the flap over it, and
/// the front's own content showing faintly through that flap.
///
/// At rest the torn region is a flat [AppColors.leafBack], because a corner
/// that has not moved is not showing you anything yet. The moment it does
/// move, the region fills with what the sheet holds on its back, which is the
/// one rule the whole app is built from.
class CornerPeel extends StatefulWidget {
  const CornerPeel({
    super.key,
    required this.child,
    required this.back,
    this.corner = Corner.bottomRight,
    this.point,
    this.restInset = kFoldRestInset,
    this.caught = false,
  });

  /// The face that is up.
  final Widget child;

  /// The face underneath, uncovered wherever the corner has torn away.
  final Widget back;

  final Corner corner;

  /// Where the corner has been pulled to, in sheet coordinates, or null when
  /// the fold is at rest.
  final Offset? point;

  final double restInset;

  /// True once a dog ear has caught, which draws the thread line along the
  /// fold and keeps it there after the finger has gone.
  final bool caught;

  @override
  State<CornerPeel> createState() => _CornerPeelState();
}

class _CornerPeelState extends State<CornerPeel> {
  /// Snapshotting is on only while a fold is in progress, so an untouched
  /// sheet paints its text straight to the canvas and never through an image.
  final SnapshotController _snapshot = SnapshotController();

  @override
  void initState() {
    super.initState();
    _snapshot.allowSnapshotting = widget.point != null;
  }

  @override
  void didUpdateWidget(CornerPeel old) {
    super.didUpdateWidget(old);
    _snapshot.allowSnapshotting = widget.point != null;
  }

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    if (point == null) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: FoldPainter.atRest(
                  restInset: widget.restInset,
                  corner: widget.corner,
                  background: AppColors.leafBack,
                  flapColor: AppColors.leafFlap,
                ),
                foregroundPainter: _FoldLinePainter(
                  corner: widget.corner,
                  point: null,
                  restInset: widget.restInset,
                  lit: widget.caught,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipPath(
              clipper: _TornClipper(corner: widget.corner, point: point),
              child: widget.back,
            ),
          ),
        ),
        SnapshotWidget(
          controller: _snapshot,
          painter: _PeelPainter(corner: widget.corner, point: point),
          child: widget.child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _FoldLinePainter(
                corner: widget.corner,
                point: point,
                restInset: widget.restInset,
                lit: widget.caught,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Clips the back of the sheet to the region the corner has torn away, so the
/// back is visible exactly where the front is not.
class _TornClipper extends CustomClipper<Path> {
  const _TornClipper({required this.corner, required this.point});

  final Corner corner;
  final Offset point;

  @override
  Path getClip(Size size) {
    final geometry = computeFoldGeometry(
      size.width,
      size.height,
      point.dx,
      point.dy,
      corner: corner,
    );
    if (geometry.clipped.length < 3) return Path();
    return Path()..addPolygon(geometry.clipped, true);
  }

  @override
  bool shouldReclip(_TornClipper old) =>
      old.corner != corner || old.point != point;
}

/// Paints the front of the sheet with its corner torn away, and paints it a
/// second time on the flap, mirrored about the fold line.
///
/// It works from one rasterisation of the front rather than from the widget
/// tree twice, which is what lets a body own a scroll controller and still
/// show through its own flap.
class _PeelPainter extends SnapshotPainter {
  _PeelPainter({required this.corner, required this.point});

  final Corner corner;
  final Offset point;

  FoldGeometry _geometry(Size size) => computeFoldGeometry(
    size.width,
    size.height,
    point.dx,
    point.dy,
    corner: corner,
  );

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    final geometry = _geometry(size);
    if (geometry.clipped.length < 3) {
      painter(context, offset);
      return;
    }
    final canvas = context.canvas;
    canvas.save();
    canvas.clipPath(_remaining(size, geometry).shift(offset));
    painter(context, offset);
    canvas.restore();
    _flap(canvas, offset, geometry, null);
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    final canvas = context.canvas;
    final src = Offset.zero & sourceSize;
    final dst = offset & size;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final geometry = _geometry(size);
    if (geometry.clipped.length < 3) {
      canvas.drawImageRect(image, src, dst, paint);
      return;
    }
    canvas.save();
    canvas.clipPath(_remaining(size, geometry).shift(offset));
    canvas.drawImageRect(image, src, dst, paint);
    canvas.restore();
    _flap(canvas, offset, geometry, (canvas) {
      canvas.drawImageRect(image, src, dst, paint);
    });
  }

  /// The sheet with the torn away region removed, which is what the front is
  /// clipped to.
  Path _remaining(Size size, FoldGeometry geometry) => Path.combine(
    PathOperation.difference,
    Path()..addRect(Offset.zero & size),
    Path()..addPolygon(geometry.clipped, true),
  );

  /// The flap, and the front showing faintly through it.
  void _flap(
    Canvas canvas,
    Offset offset,
    FoldGeometry geometry,
    void Function(Canvas canvas)? front,
  ) {
    if (geometry.flap.length < 3) return;
    final flap = (Path()..addPolygon(geometry.flap, true)).shift(offset);
    canvas.drawPath(flap, Paint()..color = AppColors.leafFlap);
    if (front == null) return;
    canvas.save();
    canvas.clipPath(flap);
    // A layer paint carries an opacity and nothing else: only the alpha is
    // read when the layer composites, which is why no palette colour is named
    // here.
    canvas.saveLayer(
      flap.getBounds(),
      Paint()
        ..color = const Color.fromARGB(
          255,
          0,
          0,
          0,
        ).withValues(alpha: kShowThroughOpacity),
    );
    canvas.translate(offset.dx, offset.dy);
    canvas.transform(geometry.reflection.storage);
    canvas.translate(-offset.dx, -offset.dy);
    front(canvas);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PeelPainter old) =>
      old.corner != corner || old.point != point;
}

/// The thread line along a caught dog ear's fold.
///
/// It is drawn over the flap rather than inside it, so it reads as a crease in
/// the paper, which is the whole claim a dog ear makes.
class _FoldLinePainter extends CustomPainter {
  const _FoldLinePainter({
    required this.corner,
    required this.point,
    required this.restInset,
    this.lit = true,
  });

  final Corner corner;
  final Offset? point;
  final double restInset;
  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    if (!lit) return;
    final at = point ?? foldRestPoint(corner, size, restInset);
    final geometry = computeFoldGeometry(
      size.width,
      size.height,
      at.dx,
      at.dy,
      corner: corner,
    );
    if (geometry.clipped.length < 3) return;
    // The fold line is the segment the torn region and the flap share: the
    // crossings came out of the polygon walk identical in both lists.
    final shared = <Offset>[
      for (var i = 0; i < geometry.clipped.length; i++)
        if (geometry.clipped[i] == geometry.flap[i]) geometry.clipped[i],
    ];
    if (shared.length < 2) return;
    canvas.drawLine(
      shared.first,
      shared.last,
      Paint()
        ..color = AppColors.accentBright
        ..strokeWidth = kDogEarLineWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FoldLinePainter old) =>
      old.corner != corner ||
      old.point != point ||
      old.restInset != restInset ||
      old.lit != lit;
}
