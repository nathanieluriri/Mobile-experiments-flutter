import 'package:audiobook_player/screens/player/sheet_transition.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

SheetTransition at(double progress) => SheetTransition(
  progress: progress,
  window: const Size(440, 956),
  insets: const EdgeInsets.only(top: 62, bottom: 34),
);

void main() {
  test('shut, the sheet is the mini player sitting above the tab bar', () {
    final t = at(0);
    expect(t.bottom, 90);
    expect(t.height, 76);
    expect(t.topRadius, 20);
    expect(t.blurSigma, 0);
    expect(t.scrimOpacity, 0);
    expect(t.artworkSize, 44);
    expect(t.artworkTop, 16);
    expect(t.artworkLeft, 20);
    expect(t.artworkRadius, 10);
    expect(t.handleTop, 8);
    expect(t.miniOpacity, 1);
    expect(t.expandedOpacity, 0);
  });

  test('open, the sheet is the whole screen with square corners', () {
    final t = at(1);
    expect(t.bottom, 0);
    expect(t.height, 956);
    expect(t.topRadius, 0);
    expect(t.artworkSize, 352);
    expect(t.artworkTop, 130);
    expect(t.artworkLeft, 44);
    expect(t.artworkRadius, 24);
    expect(t.handleTop, 72);
    expect(t.miniOpacity, 0);
    expect(t.expandedOpacity, 1);
    expect(t.expandedTranslateY, 0);
  });

  test('one progress value moves every part of the sheet at once', () {
    var previous = at(0);
    for (var i = 1; i <= 20; i++) {
      final t = at(i / 20);
      expect(t.height, greaterThan(previous.height));
      expect(t.blurSigma, greaterThanOrEqualTo(previous.blurSigma));
      expect(t.scrimOpacity, greaterThanOrEqualTo(previous.scrimOpacity));
      expect(t.artworkSize, greaterThan(previous.artworkSize));
      expect(t.artworkTop, greaterThan(previous.artworkTop));
      expect(t.artworkLeft, greaterThan(previous.artworkLeft));
      expect(t.artworkRadius, greaterThanOrEqualTo(previous.artworkRadius));
      expect(t.handleTop, greaterThan(previous.handleTop));
      expect(t.miniOpacity, lessThanOrEqualTo(previous.miniOpacity));
      expect(t.expandedOpacity, greaterThanOrEqualTo(previous.expandedOpacity));
      expect(t.bottom, lessThanOrEqualTo(previous.bottom));
      previous = t;
    }
  });

  test('the sheet clears the tab bar space before it is half open', () {
    expect(at(0.4).bottom, 0);
    expect(at(0.2).bottom, 45);
  });

  test('the corners round up to 28 then square off at the very end', () {
    expect(at(0.9).topRadius, 28);
    expect(at(0.95).topRadius, closeTo(14, 0.001));
    expect(at(1).topRadius, 0);
  });

  test('the mini row is gone well before the full player arrives', () {
    expect(at(0.12).miniOpacity, 0);
    expect(at(0.44).expandedOpacity, 0);
    expect(at(0.9).expandedOpacity, 1);
  });

  test('dragging the whole range opens the sheet', () {
    expect(at(0).dragRange, 790);
  });

  test('the full player slides its last 32 pixels as it fades in', () {
    expect(at(0.2).expandedTranslateY, 32);
    expect(at(0.45).expandedTranslateY, 32);
    expect(at(0.725).expandedTranslateY, closeTo(16, 0.001));
    expect(at(1).expandedTranslateY, 0);
  });

  test('the blur and the wash build the whole way up', () {
    expect(at(0.5).blurSigma, closeTo(5, 0.001));
    expect(at(1).blurSigma, 10);
    expect(at(0.5).tintOpacity, closeTo(0.21, 0.001));
    expect(at(1).tintOpacity, closeTo(0.42, 0.001));
    expect(at(0.5).scrimOpacity, closeTo(0.175, 0.001));
    expect(at(1).scrimOpacity, closeTo(0.35, 0.001));
  });

  test('only one of the two layers answers a tap at a time', () {
    expect(at(0).miniTakesTaps, isTrue);
    expect(at(0.049).miniTakesTaps, isTrue);
    expect(at(0.05).miniTakesTaps, isFalse);
    expect(at(0.95).expandedTakesTaps, isFalse);
    expect(at(0.951).expandedTakesTaps, isTrue);
  });
}
