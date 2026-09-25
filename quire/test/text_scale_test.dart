import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/reader/bodies/prose_body.dart';
import 'package:quire/widgets/system_text_scale.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// Every error the framework reported while [body] ran, overflows included.
Future<List<FlutterErrorDetails>> _errorsDuring(
  Future<void> Function() body,
) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

void main() {
  for (final scale in [1.0, 1.3, 2.0, 3.0]) {
    testWidgets('the desk lays out whole with the system text at ${scale}x', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final errors = await _errorsDuring(() async {
        await pumpScreen(tester, const App());
        await settle(tester);
      });
      expect(
        errors.map((e) => e.exceptionAsString().split('\n').first).toList(),
        isEmpty,
      );
    });
  }

  testWidgets('the chrome is clamped and the phone setting is kept whole', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(tester, const App());
    await settle(tester);
    final desk = tester.element(find.byType(DeskScreen));
    expect(MediaQuery.textScalerOf(desk).scale(1), kMaxChromeTextScale);
    expect(SystemTextScale.of(desk).scale(1), 2);
  });

  testWidgets('prose multiplies the reader size by the phone setting', (
    tester,
  ) async {
    final store = await storeFor(kBinderyNotes);
    store.textScale = 1.5;
    final document = await parsedDocument(kBinderyNotes);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(402, 874)),
        child: SystemTextScale(
          scaler: const TextScaler.linear(2),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ProseBody(store: store, document: document),
          ),
        ),
      ),
    );
    final inside = tester.element(find.byType(SingleChildScrollView).first);
    expect(MediaQuery.textScalerOf(inside).scale(1), 3);
  });
}
