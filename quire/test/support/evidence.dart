import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden.dart';

/// Where evidence for a review is written, from `QUIRE_EVIDENCE`, or null
/// when a run is not collecting any, which is every ordinary run.
final String? evidenceRoot = Platform.environment['QUIRE_EVIDENCE'];

const Key kEvidenceKey = ValueKey<String>('evidence');

/// [app] wrapped so a screen of it can be written out as a picture.
Widget evidenceFrame(Widget app) => RepaintBoundary(key: kEvidenceKey, child: app);

/// Writes the screen as it stands to `<root>/<part>/<name>.png`.
Future<void> screenshot(WidgetTester tester, String part, String name) async {
  final root = evidenceRoot;
  if (root == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(kEvidenceKey));
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: kDpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  writeEvidence(part, '$name.png', bytes!);
}

/// Writes [bytes] to `<root>/<part>/<name>`, for a file an editor saved.
void writeEvidence(String part, String name, Uint8List bytes) {
  final root = evidenceRoot;
  if (root == null) return;
  final dir = Directory('$root/$part')..createSync(recursive: true);
  File('${dir.path}/$name').writeAsBytesSync(bytes);
}
