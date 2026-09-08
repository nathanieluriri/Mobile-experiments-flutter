import 'dart:async';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every font a widget asks for that does not live under assets/fonts, keyed by
/// the family name the engine resolves. A font shipped by a package carries a
/// `packages/<name>/` prefix.
const _packageFonts = <String, String>{
  'packages/lucide_icons_flutter/Lucide':
      'packages/lucide_icons_flutter/assets/lucide.ttf',
};

/// The default test binding paints every shadow as a hard silhouette. This one
/// keeps the blur, so a golden shows the same soft shadow the app draws. Paper
/// in this app is read by its edges, and a hard edge is the wrong edge.
class _BlurredShadowsBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

/// Loads the fonts under assets/fonts and the icon font before any test runs,
/// so goldens render real glyphs instead of the test harness placeholder font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  _BlurredShadowsBinding();
  debugDisableShadows = false;
  final loaders = <String, FontLoader>{};
  final dir = Directory('assets/fonts');
  if (dir.existsSync()) {
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.toLowerCase().endsWith('.ttf')) {
        continue;
      }
      final family = file.uri.pathSegments.last.split('-').first;
      final bytes = file.readAsBytesSync();
      loaders
          .putIfAbsent(family, () => FontLoader(family))
          .addFont(Future.value(ByteData.sublistView(bytes)));
    }
  }
  for (final entry in _packageFonts.entries) {
    loaders
        .putIfAbsent(entry.key, () => FontLoader(entry.key))
        .addFont(rootBundle.load(entry.value));
  }
  for (final loader in loaders.values) {
    await loader.load();
  }
  await testMain();
}
