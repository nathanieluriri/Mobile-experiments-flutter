import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_note_peel/helpers/fold_geometry.dart';
import 'package:sticky_note_peel/theme/colors.dart';
import 'package:sticky_note_peel/theme/metrics.dart';

const _width = 362.0;
const _height = 200.0;
const _corner = Offset(_width, 0);

void main() {
  test('the flap is the clipped region reflected across the fold line', () {
    const point = Offset(250, 120);
    final fold = computeFoldGeometry(_width, _height, point.dx, point.dy);

    expect(fold.clipped.length, fold.flap.length);
    for (var i = 0; i < fold.clipped.length; i++) {
      // Reflecting across the bisector swaps which of the two the point is
      // near, and leaves both distances otherwise untouched.
      expect(
        (fold.flap[i] - point).distance,
        closeTo((fold.clipped[i] - _corner).distance, 0.001),
      );
      expect(
        (fold.flap[i] - _corner).distance,
        closeTo((fold.clipped[i] - point).distance, 0.001),
      );
    }
  });

  test('the top-right corner folds exactly onto the drag point', () {
    const point = Offset(200, 90);
    final fold = computeFoldGeometry(_width, _height, point.dx, point.dy);
    final cornerIndex = fold.clipped.indexWhere(
      (p) => (p - _corner).distance < 0.001,
    );
    expect(cornerIndex, isNonNegative);
    expect((fold.flap[cornerIndex] - point).distance, closeTo(0, 0.001));
  });

  test('the fold line itself does not move when the paper folds', () {
    const point = Offset(260, 140);
    final fold = computeFoldGeometry(_width, _height, point.dx, point.dy);
    var shared = 0;
    for (var i = 0; i < fold.clipped.length; i++) {
      if ((fold.clipped[i] - fold.flap[i]).distance < 0.001) {
        shared++;
        expect(
          (fold.clipped[i] - _corner).distance,
          closeTo((fold.clipped[i] - point).distance, 0.001),
        );
      }
    }
    expect(shared, 2, reason: 'the fold line crosses two edges of the note');
  });

  test('at rest the corner shows a triangle the size of the rest inset', () {
    final fold = computeFoldGeometry(
      _width,
      _height,
      _width - kFoldRestInset,
      kFoldRestInset,
    );
    expect(fold.clipped, hasLength(3));
    expect(fold.clipped, contains(_corner));
    expect(fold.clipped, contains(const Offset(_width - kFoldRestInset, 0)));
    expect(fold.clipped, contains(const Offset(_width, kFoldRestInset)));
    expect(fold.flap, contains(const Offset(_width - kFoldRestInset, 0)));
    expect(fold.flap, contains(const Offset(_width, kFoldRestInset)));
    expect(
      fold.flap.any(
        (p) =>
            (p - const Offset(_width - kFoldRestInset, kFoldRestInset))
                .distance <
            0.001,
      ),
      isTrue,
    );
  });

  test('a drag point beyond the corner is held inside the edge margin', () {
    final fold = computeFoldGeometry(_width, _height, _width + 50, -50);
    for (final point in fold.flap) {
      expect(point.dx, lessThanOrEqualTo(_width + 0.001));
      expect(point.dy, greaterThanOrEqualTo(-0.001));
    }
  });

  test('the flap colour is the note colour darkened by 20 percent', () {
    const noteColor = Color(0xFFFFD54A);
    final flap = shade(noteColor, kNoteFlapShade);
    expect(flap, const Color(0xFFCCAA3B));
    expect((flap.r * 255).round(), (noteColor.r * 255 * 0.8).round());
    expect((flap.g * 255).round(), (noteColor.g * 255 * 0.8).round());
    expect((flap.b * 255).round(), (noteColor.b * 255 * 0.8).round());
  });

  test('the dock row sits one gap below the note, evenly spaced', () {
    expect(dockRowCenterY(200), 200 + kDockGap + kDockButtonSize / 2);
    final centers = [
      for (var i = 0; i < 3; i++) dockButtonCenterX(i, _width, 3),
    ];
    expect(centers[1], _width / 2);
    expect(centers[1] - centers[0], kDockButtonSpacing);
    expect(centers[2] - centers[1], kDockButtonSpacing);
    // The hover circles overlap, so a point between two buttons is inside
    // both. The later button wins, the way the drag test resolves it.
    expect(kDockHoverRadius, greaterThan(kDockButtonSpacing / 2));
    final between = (centers[0] + centers[1]) / 2;
    expect((between - centers[0]).abs(), lessThan(kDockHoverRadius));
    expect((between - centers[1]).abs(), lessThan(kDockHoverRadius));
  });
}
