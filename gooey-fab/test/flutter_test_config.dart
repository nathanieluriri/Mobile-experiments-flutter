import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the fonts under assets/fonts, plus the icon font the app draws its
/// glyphs from, before any test runs. Without this the harness renders text as
/// boxes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loaders = <String, FontLoader>{};

  void add(String family, File file) {
    loaders
        .putIfAbsent(family, () => FontLoader(family))
        .addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }

  final dir = Directory('assets/fonts');
  if (dir.existsSync()) {
    for (final file in dir.listSync().whereType<File>()) {
      if (file.path.toLowerCase().endsWith('.ttf')) {
        add(file.uri.pathSegments.last.split('-').first, file);
      }
    }
  }

  final lucide = _packageFile('lucide_icons_flutter', 'assets/lucide.ttf');
  if (lucide != null) {
    add('packages/lucide_icons_flutter/Lucide', lucide);
  }

  for (final loader in loaders.values) {
    await loader.load();
  }
  await testMain();
}

/// Resolves a file shipped inside a package, through the resolved package
/// config rather than the asset bundle, which tests do not build.
File? _packageFile(String package, String relativePath) {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    return null;
  }
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['packages'] as List<dynamic>;
  for (final entry in packages.cast<Map<String, dynamic>>()) {
    if (entry['name'] != package) {
      continue;
    }
    var root = Uri.parse(entry['rootUri'] as String);
    if (!root.hasScheme) {
      root = config.parent.uri.resolveUri(root);
    }
    if (!root.path.endsWith('/')) {
      root = root.replace(path: '${root.path}/');
    }
    final file = File.fromUri(root.resolve(relativePath));
    return file.existsSync() ? file : null;
  }
  return null;
}
