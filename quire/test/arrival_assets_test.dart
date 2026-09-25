import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/arrival/quire_mark.dart';
import 'package:quire/arrival/quire_mark_data.dart';
import 'package:quire/theme/colors.dart';

const _res = 'android/app/src/main/res';
const _ios = 'ios/Runner';

String _read(String path) => File(path).readAsStringSync();

String _pathData(String drawable) => RegExp(
  r'android:pathData="([^"]+)"',
).firstMatch(_read('$_res/drawable/$drawable'))!.group(1)!;

Color _fill(String drawable) => Color(
  int.parse(
    RegExp(
      r'android:fillColor="#([0-9A-Fa-f]{8})"',
    ).firstMatch(_read('$_res/drawable/$drawable'))!.group(1)!,
    radix: 16,
  ),
);

/// The mark or the name alone on nothing, as the launch screen shows it.
class _Launch extends CustomPainter {
  const _Launch({required this.name});

  final bool name;

  @override
  void paint(Canvas canvas, Size size) {
    if (name) {
      canvas
        ..scale(
          size.width / kNameViewport.width,
          size.height / kNameViewport.height,
        )
        ..drawPath(QuireMark.name, Paint()..color = AppColors.ink);
    } else {
      canvas
        ..scale(size.width / kMarkViewport)
        ..drawPath(QuireMark.whole, Paint()..color = AppColors.accentBright);
    }
  }

  @override
  bool shouldRepaint(_Launch old) => old.name != name;
}

void main() {
  group('the splash drawn natively and the first frame agree', () {
    test('on the mark and the name, stroke for stroke', () {
      expect(kMarkPathData, _pathData('quire_splash_icon.xml'));
      expect(kNamePathData, _pathData('quire_wordmark.xml'));
      expect(_fill('quire_splash_icon.xml'), AppColors.accentBright);
      expect(_fill('quire_wordmark.xml'), AppColors.ink);
      final wordmark = _read('$_res/drawable/quire_wordmark.xml');
      expect(wordmark, contains('android:translateY="$kNameShift"'));
      expect(
        wordmark,
        contains('android:viewportWidth="${kNameViewport.width}"'),
      );
      expect(
        wordmark,
        contains('android:viewportHeight="${kNameViewport.height}"'),
      );
    });

    test('on the ground behind them', () {
      for (final night in ['values', 'values-night']) {
        final ground = RegExp(
          r'<color name="launch_ground">#([0-9A-Fa-f]{8})</color>',
        ).firstMatch(_read('$_res/$night/launch_ground.xml'))!.group(1)!;
        expect(Color(int.parse(ground, radix: 16)), AppColors.ground);
      }
    });

    test('on where older Android puts them', () {
      for (final dir in ['drawable', 'drawable-v21']) {
        final layers = _read('$_res/$dir/launch_background.xml');
        expect(layers, contains('android:width="${kMarkBox.toInt()}dp"'));
        expect(layers, contains('android:height="${kMarkBox.toInt()}dp"'));
        expect(layers, contains('android:width="${kNameBox.width.toInt()}dp"'));
        expect(
          layers,
          contains('android:height="${kNameBox.height.toInt()}dp"'),
        );
        expect(layers, contains('android:bottom="${kNameBottom.toInt()}dp"'));
      }
    });

    test('on a window that is never white or black behind the app', () {
      for (final night in ['values', 'values-night']) {
        final styles = _read('$_res/$night/styles.xml');
        final normal = RegExp(
          r'<style name="NormalTheme".*?</style>',
          dotAll: true,
        ).firstMatch(styles)!.group(0)!;
        expect(
          normal,
          contains(
            '<item name="android:windowBackground">@color/launch_ground</item>',
          ),
        );
        for (final theme in [
          normal,
          RegExp(
            r'<style name="LaunchTheme".*?</style>',
            dotAll: true,
          ).firstMatch(styles)!.group(0)!,
        ]) {
          expect(theme, contains('android:windowDrawsSystemBarBackgrounds'));
          expect(
            theme,
            contains(
              '<item name="android:statusBarColor">@android:color/transparent</item>',
            ),
          );
          expect(
            theme,
            contains(
              '<item name="android:navigationBarColor">@android:color/transparent</item>',
            ),
          );
        }
      }
    });

    test('on where the iOS launch screen puts them', () {
      final board = _read('$_ios/Base.lproj/LaunchScreen.storyboard');
      const view = 'Ze5-6b-2t3';
      String idOf(String image) => RegExp(
        'image="$image"[^>]*id="([^"]+)"',
      ).firstMatch(board)!.group(1)!;
      final mark = idOf('LaunchMark');
      final name = idOf('LaunchName');
      bool has(String constraint) => board.contains(constraint);

      expect(
        has('firstItem="$mark" firstAttribute="centerX" secondItem="$view" secondAttribute="centerX"'),
        isTrue,
      );
      expect(
        has('firstItem="$mark" firstAttribute="centerY" secondItem="$view" secondAttribute="centerY"'),
        isTrue,
      );
      expect(
        has('firstItem="$name" firstAttribute="centerX" secondItem="$view" secondAttribute="centerX"'),
        isTrue,
      );
      // Off the foot of the screen itself, as Android measures it, and not
      // off the safe area.
      expect(
        has(
          'firstItem="$view" firstAttribute="bottom" secondItem="$name" '
          'secondAttribute="bottom" constant="${kNameBottom.toInt()}"',
        ),
        isTrue,
      );
      expect(has('firstAttribute="width" constant="${kMarkBox.toInt()}"'), isTrue);
      expect(has('firstAttribute="height" constant="${kMarkBox.toInt()}"'), isTrue);
      expect(
        has('firstAttribute="width" constant="${kNameBox.width.toInt()}"'),
        isTrue,
      );
      expect(
        has('firstAttribute="height" constant="${kNameBox.height.toInt()}"'),
        isTrue,
      );

      final colour = RegExp(
        r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" blue="([\d.]+)" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
      ).firstMatch(board)!;
      expect(double.parse(colour.group(1)!), closeTo(AppColors.ground.r, 1e-6));
      expect(double.parse(colour.group(2)!), closeTo(AppColors.ground.g, 1e-6));
      expect(double.parse(colour.group(3)!), closeTo(AppColors.ground.b, 1e-6));

      final plist = _read('$_ios/Info.plist');
      expect(
        plist,
        matches(
          RegExp(
            r'<key>UIStatusBarStyle</key>\s*<string>UIStatusBarStyleLightContent</string>',
          ),
        ),
      );
    });

    // The launch images are the Android vectors, drawn by the same paths the
    // first frame draws. `flutter test --update-goldens` writes them.
    for (final scale in [1, 2, 3]) {
      final suffix = scale == 1 ? '' : '@${scale}x';
      for (final name in [false, true]) {
        final image = name ? 'LaunchName' : 'LaunchMark';
        testWidgets('$image$suffix is the vector at ${scale}x', (tester) async {
          tester.view
            ..devicePixelRatio = 1
            ..physicalSize = const Size(1000, 1000);
          addTearDown(tester.view.reset);
          final key = GlobalKey();
          // A golden is taken at one pixel per point, so each scale is drawn
          // at its own size in pixels.
          final size = (name ? kNameBox : const Size.square(kMarkBox)) * scale.toDouble();
          await tester.pumpWidget(
            Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox.fromSize(
                  size: size,
                  child: CustomPaint(painter: _Launch(name: name)),
                ),
              ),
            ),
          );
          await expectLater(
            find.byKey(key),
            matchesGoldenFile(
              '../$_ios/Assets.xcassets/$image.imageset/$image$suffix.png',
            ),
          );
        });
      }
    }
  });
}
