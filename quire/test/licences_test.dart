import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/desk/desk_colophon.dart';
import 'package:quire/services/licences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled font travels with its licence', () async {
    registerFontLicences();
    final entries = await LicenseRegistry.licenses.toList();
    for (final family in kFontLicences.keys) {
      final entry = entries.firstWhere((e) => e.packages.contains(family));
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(text, contains('The $family Project Authors'));
    }
  });

  testWidgets('the colophon links to the licences', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: DeskColophon(
            documents: 2,
            words: 10,
            minutes: 1,
            onLicences: () => opened++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('LICENCES'));
    expect(opened, 1);
  });

  testWidgets('a colophon with nowhere to open them offers no link',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DeskColophon(documents: 2, words: 10, minutes: 1),
      ),
    );
    expect(find.text('LICENCES'), findsNothing);
  });
}
