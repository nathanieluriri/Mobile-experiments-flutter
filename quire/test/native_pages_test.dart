import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/pdf_page_painter.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/writer.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/services/native_pdf.dart';
import 'package:quire/theme/metrics.dart';

import 'support/evidence.dart';
import 'support/fixtures.dart';
import 'support/golden.dart';

/// A phone renderer that paints every page a flat grey and remembers what it
/// was asked.
class _FakeRenderer {
  final calls = <MethodCall>[];
  var pages = 2;
  var refuseOpen = false;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final args = (call.arguments as Map).cast<String, Object?>();
    switch (call.method) {
      case 'open':
        if (refuseOpen) throw PlatformException(code: 'unreadable');
        return <String, Object?>{'id': 7, 'pages': pages};
      case 'render':
        final width = args['width']! as int;
        final height = args['height']! as int;
        final pixels = Uint8List(width * height * 4);
        for (var i = 0; i < pixels.length; i += 4) {
          pixels
            ..[i] = 0x40
            ..[i + 1] = 0x40
            ..[i + 2] = 0x40
            ..[i + 3] = 0xFF;
        }
        return <String, Object?>{
          'width': width,
          'height': height,
          'pixels': pixels,
        };
      case 'close':
        return null;
    }
    return null;
  }

  int count(String method) => calls.where((c) => c.method == method).length;
}

_FakeRenderer _install(WidgetTester tester) {
  final fake = _FakeRenderer();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    kNativePdfChannel,
    fake.handle,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      kNativePdfChannel,
      null,
    ),
  );
  return fake;
}

bool _paintedByPhone(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((paint) => paint.painter is RasterPagePainter);

bool _setByQuire(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .any((paint) => paint.painter is PageListPainter);

void main() {
  test('with no renderer on the phone nothing is opened', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await NativePdf.open(bytes: Uint8List(8)), isNull);
  });

  testWidgets('a renderer that refuses the file leaves quire drawing it', (
    tester,
  ) async {
    final fake = _install(tester)..refuseOpen = true;
    expect(await NativePdf.open(path: '/nowhere.pdf'), isNull);
    expect(fake.count('open'), 1);
  });

  testWidgets('the pages on screen are drawn by the phone, and the text '
      'layer is still read', (tester) async {
    final fake = _install(tester);
    final store = await storeFor(kPressLease);
    final pages = PdfPages.open(await documentBytes(kPressLease));
    final native = await NativePdf.open(bytes: await documentBytes(kPressLease));
    pages.attachNative(native);
    await pumpScreen(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ReaderScreen(
          store: store,
          bodyBuilder: (context) => PdfBody(store: store, pages: pages),
        ),
      ),
    );
    // The render and the decode are real asynchronous work.
    for (var i = 0; i < 10 && !_paintedByPhone(tester); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(fake.count('render'), greaterThan(0));
    final asked = fake.calls.firstWhere((c) => c.method == 'render');
    final args = (asked.arguments as Map).cast<String, Object?>();
    // At the pixels the page is drawn at, on a whole step.
    expect(args['width']! as int, greaterThanOrEqualTo(kSheetWidth * kDpr));
    expect((args['width']! as int) % 128, 0);
    expect(_paintedByPhone(tester), isTrue);
    // The search and the back of the sheet read quire's own text.
    expect(pages.linesOf(0), isNotEmpty);

    pages.drawnByPhone = false;
    await tester.pump();
    expect(_paintedByPhone(tester), isFalse);
    expect(_setByQuire(tester), isTrue);
    pages.dispose();
  });

  testWidgets('a page is drawn again only when the size moves far enough', (
    tester,
  ) async {
    _install(tester);
    final pages = PdfPages.open(await documentBytes(kPressLease));
    pages.attachNative(
      await NativePdf.open(bytes: await documentBytes(kPressLease)),
    );
    expect(pages.wantsRaster(0, 1024), isTrue);
    await tester.runAsync(() => pages.rasterize(0, 1024));
    expect(pages.pageAt(0).raster, isNotNull);
    expect(pages.wantsRaster(0, 1152), isFalse);
    expect(pages.wantsRaster(0, 1408), isTrue);
    expect(pages.wantsRaster(0, 512), isTrue);
    pages.dispose();
  });

  testWidgets('a page the phone has no page for is drawn by quire', (
    tester,
  ) async {
    final fake = _install(tester)..pages = 1;
    final pages = PdfPages.open(await documentBytes(kPressLease));
    pages.attachNative(
      await NativePdf.open(bytes: await documentBytes(kPressLease)),
    );
    expect(pages.pageCount, greaterThan(1));
    expect(pages.wantsRaster(1, 1024), isFalse);
    expect(fake.count('render'), 0);
    pages.dispose();
  });

  testWidgets('marks saved into the file are drawn over a page the phone '
      'draws without them', (tester) async {
    _install(tester);
    final bytes = PdfAnnotator.annotated(PdfFile.open(await documentBytes(kPressLease)), [
      const InkEdit(0, strokes: <List<Offset>>[<Offset>[Offset(100, 100), Offset(300, 300)]], width: 10, color: 0xFFD23B3B),
      const TextBoxEdit(0, rect: Rect.fromLTWH(60, 400, 200, 20), text: 'Checked', size: 14),
    ]);
    final store = await storeFor(kPressLease);
    final pages = PdfPages.open(bytes);
    pages.attachNative(await NativePdf.open(bytes: bytes));
    await pumpScreen(
      tester,
      evidenceFrame(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ReaderScreen(
          store: store,
          bodyBuilder: (context) => PdfBody(store: store, pages: pages),
        ),
      )),
    );
    for (var i = 0; i < 10 && !_paintedByPhone(tester); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(_paintedByPhone(tester), isTrue);
    expect(pages.pageAt(0).marks?.texts.map((t) => t.text).join(), contains('Checked'));
    // The page fades in once it has something to show.
    await tester.pump(const Duration(seconds: 1));
    await screenshot(tester, 'N', 'marks_over_native');
    // On the line of ink, what shows is the ink, not the grey the phone drew.
    final page = find.byType(PdfPageView).first;
    final scale = tester.getSize(page).width / pages.sizeOf(0).width;
    final at = tester.getTopLeft(page) + const Offset(200, 200) * scale;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(kEvidenceKey));
    final origin = boundary.localToGlobal(Offset.zero);
    final read = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      image.dispose();
      return (data!, width);
    });
    final (data, width) = read!;
    final p = at - origin;
    final i = (p.dy.round() * width + p.dx.round()) * 4;
    expect(data.getUint8(i), greaterThan(0xA0));
    expect(data.getUint8(i + 1), lessThan(0x70));
    pages.dispose();
  });

  test('the choice of type is remembered with the document', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final store = await storeFor(kPressLease);
    expect(store.quireType, isFalse);
    store.quireType = true;
    final saved = store.toJson();
    final again = await storeFor(kPressLease);
    again.restore(saved);
    expect(again.quireType, isTrue);
  });
}
