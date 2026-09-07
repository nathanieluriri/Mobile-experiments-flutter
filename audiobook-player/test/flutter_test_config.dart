import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The icon font, which lives inside the package that declares it.
const _iconFontFamily = 'packages/lucide_icons_flutter/Lucide';
const _iconFontAsset = 'packages/lucide_icons_flutter/assets/lucide.ttf';

/// Loads the fonts under assets/fonts and the bundled icon font before any test
/// runs, so goldens render real glyphs instead of the test harness placeholder
/// font.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  await (FontLoader(
    _iconFontFamily,
  )..addFont(rootBundle.load(_iconFontAsset))).load();
  for (final loader in loaders.values) {
    await loader.load();
  }
  await testMain();
}
