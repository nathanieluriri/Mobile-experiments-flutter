import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/arrival/arrival_handoff.dart';
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

/// The body of the Kotlin function [signature] in [source].
String _kotlin(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: signature);
  return source.substring(start, source.indexOf('\n    }\n', start));
}

String _constant(String source, String name) => RegExp(
  'const val $name = "([^"]+)"',
).firstMatch(source)!.group(1)!;

void main() {
  group('Android tells the first frame what its splash showed', () {
    final activity = _read(
      'android/app/src/main/kotlin/ng/com/uriri/quire/MainActivity.kt',
    );

    test('on the channel Dart listens on', () {
      expect(_constant(activity, 'ARRIVAL'), kArrivalChannel);
      expect(_constant(activity, 'HANDS_OVER'), kArrivalHandsOver);
      expect(_constant(activity, 'PLACE'), 'place');
      expect(_constant(activity, 'GONE'), 'gone');
    });

    test('before the first frame, that it owns a splash', () {
      final args = _kotlin(
        activity,
        'override fun getDartEntrypointArgs()',
      );
      expect(args, contains('super.getDartEntrypointArgs()'));
      expect(args, contains('if (splashUp) given + HANDS_OVER else given'));
      final created = _kotlin(activity, 'override fun onCreate(');
      expect(
        created,
        matches(
          RegExp(
            r'SDK_INT >= Build\.VERSION_CODES\.S\) \{\s*splashUp = true\s*'
            r'splashScreen\.setOnExitAnimationListener',
          ),
        ),
      );
    });

    test('that it was bare, when the system never hands it over', () {
      final shown = _kotlin(activity, 'override fun onFlutterUiDisplayed()');
      expect(shown, contains('if (!splashUp || handing) return'));
      expect(shown, contains('if (splashUp && !handing)'));
      expect(
        shown,
        matches(
          RegExp(
            r'invokeMethod\(\s*PLACE,\s*'
            r'mapOf\("showedMark" to false, "showedName" to false\),?\s*\)',
          ),
        ),
      );
      expect(shown, contains('invokeMethod(GONE, null)'));
      final handing = _kotlin(activity, 'private fun handOver(');
      expect(
        handing,
        matches(RegExp(r'if \(!splashUp\) \{[^}]*\.alpha\(0f\)')),
      );
      expect(handing, contains('handing = true'));
    });

    test('from under both bars, every time it comes back below Android 10', () {
      final resumed = _kotlin(activity, 'override fun onPostResume()');
      expect(
        resumed,
        contains(
          'if (!resumedOnce || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)',
        ),
      );
      final edges = _kotlin(activity, 'private fun reachTheEdges()');
      expect(
        edges,
        matches(
          RegExp(
            r'systemUiVisibility =\s*window\.decorView\.systemUiVisibility or',
          ),
        ),
      );
    });
  });

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
          // Android 10 and 11 lay a scrim under a transparent bar unless told
          // not to, and the app window is told not to.
          for (final bar in ['Status', 'Navigation']) {
            expect(
              theme,
              contains(
                '<item name="android:enforce${bar}BarContrast" '
                'tools:targetApi="q">false</item>',
              ),
            );
          }
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

    test('on the status bar iOS starts the app with', () {
      final board = _read('$_ios/Base.lproj/Main.storyboard');
      final root = RegExp(
        r'initialViewController="([^"]+)"',
      ).firstMatch(board)!.group(1)!;
      expect(
        board,
        contains(
          '<viewController id="$root" customClass="QuireViewController" '
          'customModule="Runner" customModuleProvider="target"',
        ),
      );
      final swift = _read('$_ios/AppDelegate.swift');
      expect(
        swift,
        matches(
          RegExp(
            r'class QuireViewController: FlutterViewController \{\s*'
            r'override var preferredStatusBarStyle: UIStatusBarStyle \{\s*'
            r'let asked = super\.preferredStatusBarStyle\s*'
            r'return asked == \.default \? \.lightContent : asked',
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
