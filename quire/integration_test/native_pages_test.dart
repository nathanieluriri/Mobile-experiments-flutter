import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quire/services/native_pdf.dart';

/// A one page PDF [width] by [height] points, turned by [rotate], with a
/// black square in the corner of its own space at the origin.
Uint8List _cornerPage({int width = 200, int height = 300, int rotate = 0}) {
  final out = <int>[];
  void add(String s) => out.addAll(ascii.encode(s));
  const content = '0 0 0 rg 0 0 40 40 re f';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] '
        '/Rotate $rotate /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  add('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    add('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  add('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    add('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  add('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(out);
}

Future<(Uint8List, int, int)> _pixels(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return (data!.buffer.asUint8List(), image.width, image.height);
}

bool _dark((Uint8List, int, int) p, double fx, double fy) {
  final (bytes, w, h) = p;
  final x = (fx * (w - 1)).round(), y = (fy * (h - 1)).round();
  final i = (y * w + x) * 4;
  return bytes[i] < 60 && bytes[i + 1] < 60 && bytes[i + 2] < 60;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the phone draws a shipped document from its bytes', (_) async {
    final data = await rootBundle.load('assets/documents/press-lease.pdf');
    final native = await NativePdf.open(bytes: data.buffer.asUint8List());
    expect(native, isNotNull);
    expect(native!.pageCount, 2);
    final image = await native.render(0, 612, 792);
    expect(image, isNotNull);
    final (bytes, w, h) = await _pixels(image!);
    expect((w, h), (612, 792));
    var ink = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] < 128) ink++;
    }
    // Text in its own font: some ink, most of the page still paper.
    expect(ink, greaterThan(1000));
    expect(ink, lessThan(w * h ~/ 2));
    await native.close();
    expect(await native.render(0, 612, 792), isNull);
  });

  testWidgets('an upright page puts its origin at the bottom left', (_) async {
    final native = (await NativePdf.open(bytes: _cornerPage()))!;
    final p = await _pixels((await native.render(0, 200, 300))!);
    expect(_dark(p, 0.05, 0.95), isTrue);
    expect(_dark(p, 0.95, 0.05), isFalse);
    await native.close();
  });

  testWidgets('a page turned a quarter is drawn turned, the way quire lays '
      'it out', (_) async {
    // Turned 90 clockwise, a 200 by 300 page stands 300 wide and 200 tall,
    // and its origin corner moves to the top left.
    final native = (await NativePdf.open(bytes: _cornerPage(rotate: 90)))!;
    final p = await _pixels((await native.render(0, 300, 200))!);
    expect(_dark(p, 0.04, 0.06), isTrue);
    expect(_dark(p, 0.96, 0.94), isFalse);
    await native.close();
  });

  testWidgets('a file the phone cannot read is refused, not crashed on', (
    _,
  ) async {
    expect(await NativePdf.open(bytes: Uint8List.fromList([1, 2, 3])), isNull);
  });
}
