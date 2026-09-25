/// Writes every frame of a cold start's arrival to `build/arrival_frames/`,
/// one PNG per 60th of a second, from the first frame to the live desk.
///
/// The arrival is judged by watching it, and a widget test can only hold one
/// moment still. Run it from the app directory, optionally at another phone
/// size:
///
///     flutter test tool/arrival_frames_test.dart
///     flutter test tool/arrival_frames_test.dart --dart-define=PHONE=402x874
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/arrival/arrival_painter.dart';

import '../test/support/golden.dart';

const _phone = String.fromEnvironment('PHONE', defaultValue: '402x874');
const _frame = Duration(microseconds: 16667);

void main() {
  testWidgets('arrival frames', (tester) async {
    final sides = _phone.split('x').map(double.parse).toList();
    final phone = Phone('phone', Size(sides[0], sides[1]), top: 62, bottom: 34);
    final out = Directory('build/arrival_frames/$_phone')
      ..createSync(recursive: true);
    for (final old in out.listSync()) {
      old.deleteSync();
    }
    final home = Directory.systemTemp.createTempSync('quire_arrival');
    addTearDown(() => home.deleteSync(recursive: true));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => home.path,
    );
    final boundary = GlobalKey();
    await pumpScreen(
      tester,
      RepaintBoundary(key: boundary, child: const App()),
      phone: phone,
    );

    final log = StringBuffer();
    var frame = 0;
    var afterGone = 0;
    for (var elapsed = Duration.zero;
        elapsed < const Duration(seconds: 6);
        elapsed += _frame) {
      final painters = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is ArrivalPainter,
      );
      final pose = painters.evaluate().isEmpty
          ? null
          : ((painters.evaluate().first.widget as CustomPaint).painter!
                    as ArrivalPainter)
                .pose;
      final bytes = await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: kDpr);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final name = 'f${frame.toString().padLeft(4, '0')}.png';
      File('${out.path}/$name').writeAsBytesSync(bytes!);
      log.writeln(
        '$name ${elapsed.inMicroseconds / 1000} '
        '${pose == null ? 'gone' : 'swell=${pose.swell.toStringAsFixed(3)} window=${pose.window.toStringAsFixed(2)}'}',
      );
      frame++;
      if (pose == null && ++afterGone > 12) break;
      await tester.pump(_frame);
    }
    File('${out.path}/frames.txt').writeAsStringSync(log.toString());
  });
}
