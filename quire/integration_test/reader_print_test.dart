import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quire/app.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';

/// The whole app on the phone: a PDF opened from the desk is drawn by the
/// phone's renderer, not set again in the app's type.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a PDF opened from the desk is drawn in its own print', (
    tester,
  ) async {
    await tester.pumpWidget(const App());
    Future<void> wait(bool Function() done, {int seconds = 60}) async {
      for (var i = 0; i < seconds * 4 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    final lease = find.textContaining('Press Lease');
    await wait(() => lease.evaluate().isNotEmpty);
    expect(lease, findsWidgets);
    await tester.tap(lease.first);
    bool painted() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((paint) => paint.painter is RasterPagePainter);
    await wait(painted);
    expect(painted(), isTrue);
    // Held on screen long enough to be looked at from outside.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  });
}
