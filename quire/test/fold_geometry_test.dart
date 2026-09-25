import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/helpers/fold_geometry.dart';
import 'package:quire/painting/fold_painter.dart';
import 'package:quire/theme/metrics.dart';

/// Twice the signed area of [points], which is what the shoelace sum gives.
/// Sign is dropped by the callers: a reflection reverses winding.
double _twiceArea(List<Offset> points) {
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum;
}

/// Signed distance of [p] from the fold line of [geometry]. Positive means the
/// same side as the corner, which is the side that gets torn away.
double _sideOf(FoldGeometry geometry, Offset p) {
  final d = p - geometry.foldMid;
  return d.dx * geometry.foldNormal.dx + d.dy * geometry.foldNormal.dy;
}

void main() {
  const width = 362.0;
  const height = 96.0;

  group('the fold line is the perpendicular bisector', () {
    test('reflecting the corner lands exactly on the drag point', () {
      final geometry = computeFoldGeometry(width, height, 250, 40);
      expect(geometry.corner, const Offset(width, 0));
      final landed = geometry.reflect(geometry.corner);
      expect(landed.dx, closeTo(250, 1e-9));
      expect(landed.dy, closeTo(40, 1e-9));
    });

    test('the reflection matrix agrees with reflect', () {
      final geometry = computeFoldGeometry(width, height, 190, 60);
      final matrix = geometry.reflection;
      for (final p in [
        const Offset(0, 0),
        const Offset(width, 0),
        const Offset(width, height),
        const Offset(12.5, 71.25),
      ]) {
        final storage = matrix.storage;
        final mapped = Offset(
          storage[0] * p.dx + storage[4] * p.dy + storage[12],
          storage[1] * p.dx + storage[5] * p.dy + storage[13],
        );
        expect(mapped.dx, closeTo(geometry.reflect(p).dx, 1e-9));
        expect(mapped.dy, closeTo(geometry.reflect(p).dy, 1e-9));
      }
    });

    test('the drag point is its own reflection of the corner both ways', () {
      final geometry = computeFoldGeometry(width, height, 300, 30);
      final back = geometry.reflect(geometry.point);
      expect(back.dx, closeTo(width, 1e-9));
      expect(back.dy, closeTo(0, 1e-9));
    });
  });

  group('the flap is the clipped polygon reflected, never a skew', () {
    test('every flap point is its clipped point reflected', () {
      final geometry = computeFoldGeometry(width, height, 210, 55);
      expect(geometry.clipped.length, geometry.flap.length);
      expect(geometry.clipped.length, greaterThanOrEqualTo(3));
      for (var i = 0; i < geometry.clipped.length; i++) {
        final reflected = geometry.reflect(geometry.clipped[i]);
        expect(geometry.flap[i].dx, closeTo(reflected.dx, 1e-9));
        expect(geometry.flap[i].dy, closeTo(reflected.dy, 1e-9));
      }
    });

    test('a reflection preserves area and reverses winding', () {
      final geometry = computeFoldGeometry(width, height, 240, 44);
      final clipped = _twiceArea(geometry.clipped);
      final flap = _twiceArea(geometry.flap);
      expect(flap.abs(), closeTo(clipped.abs(), 1e-6));
      expect(clipped.sign, isNot(flap.sign));
    });

    test('a reflection is not a skew: it is not an affine shear', () {
      // A skew would leave the corner-to-point distance along the fold line
      // unchanged while stretching across it. A true reflection keeps every
      // distance, so the two edges meeting at the corner keep their lengths.
      final geometry = computeFoldGeometry(width, height, 200, 50);
      final corner = geometry.corner;
      final neighbours = [const Offset(0, 0), const Offset(width, height)];
      for (final n in neighbours) {
        final before = (n - corner).distance;
        final after = (geometry.reflect(n) - geometry.reflect(corner)).distance;
        expect(after, closeTo(before, 1e-9));
      }
    });

    test('the clipped region sits on the corner side of the fold line', () {
      final geometry = computeFoldGeometry(width, height, 230, 48);
      for (final p in geometry.clipped) {
        expect(_sideOf(geometry, p), greaterThanOrEqualTo(-1e-9));
      }
      for (final p in geometry.flap) {
        expect(_sideOf(geometry, p), lessThanOrEqualTo(1e-9));
      }
    });

    test('points on the fold line belong to both polygons unmoved', () {
      final geometry = computeFoldGeometry(width, height, 260, 36);
      var shared = 0;
      for (var i = 0; i < geometry.clipped.length; i++) {
        if ((geometry.clipped[i] - geometry.flap[i]).distance < 1e-9) {
          shared++;
          expect(_sideOf(geometry, geometry.clipped[i]).abs(), lessThan(1e-9));
        }
      }
      expect(shared, 2, reason: 'the fold line crosses exactly two edges');
    });
  });

  group('the edge margin keeps the geometry from degenerating', () {
    test('a drag past the right edge is pulled back by the margin', () {
      final geometry = computeFoldGeometry(width, height, width + 40, 30);
      expect(geometry.point.dx, closeTo(width - kFoldEdgeMargin, 1e-9));
    });

    test('a drag above the top edge is pushed down by the margin', () {
      final geometry = computeFoldGeometry(width, height, 200, -30);
      expect(geometry.point.dy, closeTo(kFoldEdgeMargin, 1e-9));
    });

    test('a drag at the corner still gives three points, not zero', () {
      final geometry = computeFoldGeometry(width, height, width, 0);
      expect(geometry.clipped.length, greaterThanOrEqualTo(3));
      expect(_twiceArea(geometry.clipped).abs(), greaterThan(0));
    });
  });

  group('a Corner mirrors the input so one function serves four folds', () {
    /// Bottom right is the top right fold with y mirrored, so the polygons are
    /// the top right ones read back through the same mirror.
    test('bottom right mirrors the top right fold about the mid height', () {
      final top = computeFoldGeometry(width, height, 240, 44);
      final bottom = computeFoldGeometry(
        width,
        height,
        240,
        height - 44,
        corner: Corner.bottomRight,
      );
      expect(bottom.corner, const Offset(width, height));
      expect(bottom.point.dx, closeTo(240, 1e-9));
      expect(bottom.point.dy, closeTo(height - 44, 1e-9));
      expect(bottom.clipped.length, top.clipped.length);
      for (var i = 0; i < top.clipped.length; i++) {
        expect(bottom.clipped[i].dx, closeTo(top.clipped[i].dx, 1e-9));
        expect(
          bottom.clipped[i].dy,
          closeTo(height - top.clipped[i].dy, 1e-9),
        );
        expect(bottom.flap[i].dx, closeTo(top.flap[i].dx, 1e-9));
        expect(bottom.flap[i].dy, closeTo(height - top.flap[i].dy, 1e-9));
      }
    });

    test('top left mirrors about the mid width', () {
      final top = computeFoldGeometry(width, height, 240, 44);
      final left = computeFoldGeometry(
        width,
        height,
        width - 240,
        44,
        corner: Corner.topLeft,
      );
      expect(left.corner, const Offset(0, 0));
      for (var i = 0; i < top.clipped.length; i++) {
        expect(left.clipped[i].dx, closeTo(width - top.clipped[i].dx, 1e-9));
        expect(left.clipped[i].dy, closeTo(top.clipped[i].dy, 1e-9));
      }
    });

    test('bottom left mirrors both ways', () {
      final geometry = computeFoldGeometry(
        width,
        height,
        120,
        60,
        corner: Corner.bottomLeft,
      );
      expect(geometry.corner, const Offset(0, height));
      final landed = geometry.reflect(geometry.corner);
      expect(landed.dx, closeTo(120, 1e-9));
      expect(landed.dy, closeTo(60, 1e-9));
    });

    test('every corner still lands its own corner under the finger', () {
      const drags = <Corner, Offset>{
        Corner.topRight: Offset(300, 30),
        Corner.bottomRight: Offset(300, 66),
        Corner.topLeft: Offset(62, 30),
        Corner.bottomLeft: Offset(62, 66),
      };
      drags.forEach((corner, drag) {
        final geometry = computeFoldGeometry(
          width,
          height,
          drag.dx,
          drag.dy,
          corner: corner,
        );
        final landed = geometry.reflect(geometry.corner);
        expect(landed.dx, closeTo(drag.dx, 1e-9), reason: '$corner');
        expect(landed.dy, closeTo(drag.dy, 1e-9), reason: '$corner');
      });
    });

    test('the resting fold of a card is a small triangle at its corner', () {
      // What FoldPainter.atRest asks for on a 362 x 96 card: the corner pulled
      // in by 16 along both axes.
      final geometry = computeFoldGeometry(
        width,
        height,
        width - kCardFoldRestInset,
        height - kCardFoldRestInset,
        corner: Corner.bottomRight,
      );
      expect(geometry.clipped.length, 3);
      final area = _twiceArea(geometry.clipped).abs() / 2;
      // The bisector of a corner pulled in equally on both axes cuts a right
      // isosceles triangle whose legs are the inset itself.
      expect(
        area,
        closeTo(0.5 * kCardFoldRestInset * kCardFoldRestInset, 1e-6),
      );
    });
  });

  group('the painter draws what the geometry describes', _painterTests);
}

/// A flat slab, standing in for whatever a sheet holds on its front or its
/// back, so the painter's two optional layers can be exercised.
class _Slab extends CustomPainter {
  const _Slab(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Slab old) => old.color != color;
}

/// The painter is exercised as a widget rather than against a recording
/// canvas, because the thing that can break is the save layer and the clip
/// around the show through, not the polygon the geometry test already proves.
void _painterTests() {
  Future<void> pump(WidgetTester tester, CustomPainter painter) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 362,
            height: 96,
            child: CustomPaint(painter: painter),
          ),
        ),
      ),
    );
  }

  testWidgets('a resting fold paints at every corner', (tester) async {
    for (final corner in Corner.values) {
      await pump(
        tester,
        FoldPainter.atRest(
          restInset: kCardFoldRestInset,
          corner: corner,
          background: const Color(0xFFE5DED2),
          flapColor: const Color(0xFFEDE6D8),
        ),
      );
      expect(tester.takeException(), isNull, reason: '$corner');
    }
  });

  testWidgets('a dragged fold paints its back layer and its show through',
      (tester) async {
    await pump(
      tester,
      const FoldPainter(
        dragX: 210,
        dragY: 40,
        corner: Corner.bottomRight,
        background: Color(0xFFE5DED2),
        flapColor: Color(0xFFEDE6D8),
        backLayer: _Slab(Color(0xFFF4EFE4)),
        showThrough: _Slab(Color(0xFF1E1B17)),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fold dragged into its own corner does not degenerate',
      (tester) async {
    await pump(
      tester,
      const FoldPainter(
        dragX: 362,
        dragY: 0,
        background: Color(0xFFE5DED2),
        flapColor: Color(0xFFEDE6D8),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
