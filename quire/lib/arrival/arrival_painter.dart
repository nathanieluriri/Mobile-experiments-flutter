import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../theme/colors.dart';
import 'arrival_bounds.dart';
import 'arrival_geometry.dart';
import 'arrival_motion.dart';
import 'quire_mark.dart';

/// Paints the arrival over the app: the resting mark exactly as the vector
/// draws it, and from the first moving frame the goo from arrival.frag.
class ArrivalPainter extends CustomPainter {
  ArrivalPainter({
    required this.pose,
    required this.geometry,
    required this.shader,
    required this.pixelRatio,
    this.showMark = 1,
    this.showName = 1,
    this.markPixels,
    this.markPixelsRect,
    this.namePixels,
  });

  final ArrivalPose pose;
  final ArrivalGeometry geometry;

  /// Null until arrival.frag has loaded, which only the moving frames need.
  final ui.FragmentShader? shader;

  final double pixelRatio;

  /// Whether the shader is run only where the goo can be. Off only to prove
  /// the bound changes no pixel.
  static bool bounded = true;

  /// How much of the mark and of the name to show at rest, for a splash that
  /// came up without them.
  final double showMark;
  final double showName;

  /// The platform splash's own pixels for the mark and the name, drawn in
  /// place of the vector while they are still, where the platform gave them.
  final ui.Image? markPixels;
  final Rect? markPixelsRect;
  final ui.Image? namePixels;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final shader = this.shader;
    final resting = identical(pose, ArrivalPose.rest);
    if (resting || shader == null) {
      canvas.drawRect(full, Paint()..color = AppColors.ground);
      if (shader != null) {
        // A pixel of ground drawn through the shader, so a driver that
        // compiles on first use does it now rather than on the first frame
        // that moves.
        _uniforms(shader, ArrivalPose.rest);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..shader = shader);
      }
      _mark(canvas, showMark);
      _name(canvas, showName);
      return;
    }
    _uniforms(shader, pose);
    final bounds = bounded ? arrivalBounds(pose, geometry, pixelRatio) : null;
    if (bounds == null || bounds.expandToInclude(full) == bounds) {
      canvas.drawRect(full, Paint()..shader = shader);
    } else {
      // Outside the bound the shader would draw the ground and nothing else,
      // so most of an early frame is filled flat instead of shaded. Only
      // around the bound: inside it the holes are translucent, and ground
      // under them would show where the desk should.
      final shaded = bounds.intersect(full);
      final ground = Paint()
        ..color = AppColors.ground
        ..isAntiAlias = false;
      if (shaded.isEmpty) {
        canvas.drawRect(full, ground);
      } else {
        canvas
          ..drawRect(Rect.fromLTRB(0, 0, full.right, shaded.top), ground)
          ..drawRect(
            Rect.fromLTRB(0, shaded.bottom, full.right, full.bottom),
            ground,
          )
          ..drawRect(
            Rect.fromLTRB(0, shaded.top, shaded.left, shaded.bottom),
            ground,
          )
          ..drawRect(
            Rect.fromLTRB(shaded.right, shaded.top, full.right, shaded.bottom),
            ground,
          )
          ..drawRect(
            shaded,
            Paint()
              ..shader = shader
              ..isAntiAlias = false,
          );
      }
    }
    if (pose.exactMark > 0) {
      // The resting frame is opaque, so laying the whole of it over the goo
      // at this opacity is a true crossfade. The mark alone laid over the
      // goo's mark would add their edges together and embolden them.
      canvas
        ..saveLayer(full, Paint()..color = Color.fromRGBO(0, 0, 0, pose.exactMark))
        ..drawRect(full, Paint()..color = AppColors.ground);
      _mark(canvas, showMark);
      canvas.restore();
    }
    if (pose.nameOpacity > 0) _name(canvas, pose.nameOpacity * showName);
  }

  void _mark(Canvas canvas, double opacity) {
    if (opacity <= 0) return;
    final pixels = markPixels;
    final at = markPixelsRect;
    if (pixels != null && at != null) {
      _pixels(canvas, pixels, at, opacity);
      return;
    }
    canvas
      ..save()
      ..translate(geometry.markBox.left, geometry.markBox.top)
      ..scale(geometry.unit)
      ..drawPath(
        QuireMark.whole,
        Paint()..color = AppColors.accentBright.withValues(alpha: opacity),
      )
      ..restore();
  }

  void _name(Canvas canvas, double opacity) {
    if (opacity <= 0) return;
    final box = geometry.nameBox;
    final pixels = namePixels;
    if (pixels != null) {
      _pixels(canvas, pixels, box.shift(Offset(0, pose.nameDrop)), opacity);
      return;
    }
    canvas
      ..save()
      ..translate(box.left, box.top + pose.nameDrop)
      ..scale(
        box.width / kNameViewport.width,
        box.height / kNameViewport.height,
      )
      ..drawPath(
        QuireMark.name,
        Paint()..color = AppColors.ink.withValues(alpha: opacity),
      )
      ..restore();
  }

  /// [image] laid pixel for pixel into [at], which the platform measured in
  /// the same pixels, so nothing is resampled.
  void _pixels(Canvas canvas, ui.Image image, Rect at, double opacity) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      at,
      Paint()
        ..filterQuality = FilterQuality.none
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
  }

  void _uniforms(ui.FragmentShader shader, ArrivalPose pose) {
    var index = 0;
    void put(double value) => shader.setFloat(index++, value);
    void colour(Color colour) {
      put(colour.r);
      put(colour.g);
      put(colour.b);
      put(colour.a);
    }

    put(geometry.markBox.left);
    put(geometry.markBox.top);
    put(geometry.unit);
    put(1 / pixelRatio);
    put(pose.swell);
    put(pose.window);
    put(pose.gooOutline);
    put(pose.gooHole);
    put(QuireMark.middle.dx);
    put(QuireMark.middle.dy);
    put(pose.rim);
    put(pose.morph);
    for (final pane in pose.panes) {
      put(pane.shift.dx);
      put(pane.shift.dy);
      put(pane.outlineScale);
      put(pane.holeScale);
    }
    for (final pane in pose.panes) {
      put(pane.holeRound);
    }
    for (final pane in pose.panes) {
      put(pane.outlineRound);
    }
    put(pose.blob.center.dx);
    put(pose.blob.center.dy);
    put(pose.blob.width / 2);
    put(pose.blob.height / 2);
    put(pose.blobCorner);
    put(pose.settle);
    put(pose.stubRound);
    put(pose.flapMelt);
    put(pose.join);
    put(pose.reach);
    put(pose.opening);
    put(pose.zip);
    colour(AppColors.ground);
    colour(AppColors.accentBright);
  }

  @override
  bool shouldRepaint(ArrivalPainter old) =>
      !identical(old.pose, pose) ||
      old.geometry != geometry ||
      old.shader != shader ||
      old.pixelRatio != pixelRatio ||
      old.showMark != showMark ||
      old.showName != showName ||
      old.markPixels != markPixels ||
      old.markPixelsRect != markPixelsRect ||
      old.namePixels != namePixels;
}
