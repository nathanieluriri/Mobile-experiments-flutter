import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the fonts under assets/fonts before any test runs, so goldens render
/// real glyphs instead of the test harness placeholder font.
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
  for (final loader in loaders.values) {
    await loader.load();
  }
  await testMain();
}
