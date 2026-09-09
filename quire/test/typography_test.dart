import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/theme/typography.dart' as type;

import 'support/golden.dart';

/// Every style, with the size, line height, weight and tracking the design
/// names for it. A style that drifts fails here rather than in a screen golden
/// where it would read as a layout change.
const _expected = <String, (double, double, FontWeight, double)>{
  'wordmark': (30, 34, FontWeight.w700, 1.4),
  'wordmarkSmall': (17, 22, FontWeight.w600, 0.6),
  'display': (26, 31, FontWeight.w700, -0.5),
  'title': (17, 22, FontWeight.w600, -0.2),
  'pageHeading1': (24, 30, FontWeight.w700, -0.4),
  'pageHeading2': (19, 25, FontWeight.w600, -0.2),
  'pageHeading3': (16, 21, FontWeight.w600, 0),
  'pageBody': (15.5, 24, FontWeight.w400, 0),
  'pageBodyBold': (15.5, 24, FontWeight.w600, 0),
  'pageBodyItalic': (15.5, 24, FontWeight.w500, 0.2),
  'bodyTight': (14, 19, FontWeight.w400, 0),
  'rowTitle': (16, 20, FontWeight.w400, 0),
  'search': (15, 20, FontWeight.w400, 0),
  'drawerRow': (16, 21, FontWeight.w400, 0),
  'drawerRowSelected': (16, 21, FontWeight.w500, 0),
  'sortLabel': (14, 19, FontWeight.w500, 0),
  'menuRow': (15, 20, FontWeight.w400, 0),
  'menuRowSelected': (15, 20, FontWeight.w500, 0),
  'avatar': (15, 20, FontWeight.w600, 0),
  'destinationTitle': (19, 25, FontWeight.w600, 0),
  'destinationBody': (14, 20, FontWeight.w400, 0),
  'actionPill': (15, 20, FontWeight.w500, -0.1),
  'docMeta': (13, 17, FontWeight.w400, 0),
  'label': (13, 16, FontWeight.w500, -0.1),
  'hint': (13, 17, FontWeight.w500, 0),
  'code': (13.5, 20, FontWeight.w500, 0.1),
  'cell': (13, 17, FontWeight.w400, 0),
  'cellHeader': (12, 15, FontWeight.w600, 0.4),
  'folio': (12, 15, FontWeight.w500, 1.2),
  'folioSmall': (10, 13, FontWeight.w500, 1.0),
  'chipLabel': (11, 14, FontWeight.w600, 0.6),
  'typeMark': (10, 12, FontWeight.w600, 0.2),
  'micro': (9, 11, FontWeight.w600, 0.8),
};

Map<String, TextStyle> get _styles => {
      'wordmark': type.AppText.wordmark,
      'wordmarkSmall': type.AppText.wordmarkSmall,
      'display': type.AppText.display,
      'title': type.AppText.title,
      'pageHeading1': type.AppText.pageHeading1,
      'pageHeading2': type.AppText.pageHeading2,
      'pageHeading3': type.AppText.pageHeading3,
      'pageBody': type.AppText.pageBody,
      'pageBodyBold': type.AppText.pageBodyBold,
      'pageBodyItalic': type.AppText.pageBodyItalic,
      'bodyTight': type.AppText.bodyTight,
      'rowTitle': type.AppText.rowTitle,
      'search': type.AppText.search,
      'drawerRow': type.AppText.drawerRow,
      'drawerRowSelected': type.AppText.drawerRowSelected,
      'sortLabel': type.AppText.sortLabel,
      'menuRow': type.AppText.menuRow,
      'menuRowSelected': type.AppText.menuRowSelected,
      'avatar': type.AppText.avatar,
      'destinationTitle': type.AppText.destinationTitle,
      'destinationBody': type.AppText.destinationBody,
      'actionPill': type.AppText.actionPill,
      'docMeta': type.AppText.docMeta,
      'label': type.AppText.label,
      'hint': type.AppText.hint,
      'code': type.AppText.code,
      'cell': type.AppText.cell,
      'cellHeader': type.AppText.cellHeader,
      'folio': type.AppText.folio,
      'folioSmall': type.AppText.folioSmall,
      'chipLabel': type.AppText.chipLabel,
      'typeMark': type.AppText.typeMark,
      'micro': type.AppText.micro,
    };

/// The styles that set numbers, which must carry tabular figures or a column
/// of them ripples and the digit roll cannot work.
const _tabular = {'code', 'cell', 'folio', 'folioSmall'};

void main() {
  testWidgets('bundled font renders at every weight', (tester) async {
    await pumpScreen(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: kFontFamily),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final weight in const [
                  FontWeight.w400,
                  FontWeight.w500,
                  FontWeight.w600,
                  FontWeight.w700,
                ])
                  Text(
                    'Weight ${weight.value} Ag 0123',
                    style: TextStyle(fontSize: 28, fontWeight: weight),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await capture(tester, 'typography__weights');
  });

  group('every style is exactly what the design names', () {
    _expected.forEach((name, values) {
      test(name, () {
        final (size, lineHeight, weight, tracking) = values;
        final style = _styles[name]!;
        expect(style.fontSize, size, reason: '$name size');
        expect(
          style.height! * style.fontSize!,
          closeTo(lineHeight, 1e-9),
          reason: '$name line height',
        );
        expect(style.fontWeight, weight, reason: '$name weight');
        expect(style.letterSpacing, tracking, reason: '$name tracking');
      });
    });
  });

  group('the rules every style obeys', () {
    test('no style inherits, and every one names Inter itself', () {
      for (final entry in _styles.entries) {
        expect(entry.value.inherit, isFalse, reason: entry.key);
        expect(entry.value.fontFamily, type.kFontFamily, reason: entry.key);
      }
    });

    test('leading is split evenly, so a line box centres its glyphs', () {
      for (final entry in _styles.entries) {
        expect(
          entry.value.leadingDistribution,
          TextLeadingDistribution.even,
          reason: entry.key,
        );
      }
    });

    test('colour is never baked in, it is applied at the call site', () {
      for (final entry in _styles.entries) {
        expect(entry.value.color, isNull, reason: entry.key);
      }
    });

    test('numbers are tabular wherever they are named, and nowhere else', () {
      for (final entry in _styles.entries) {
        final features = entry.value.fontFeatures ?? const <FontFeature>[];
        expect(
          features.contains(const FontFeature.tabularFigures()),
          _tabular.contains(entry.key),
          reason: entry.key,
        );
      }
    });

    test('there is no italic face and none is faked', () {
      for (final entry in _styles.entries) {
        expect(entry.value.fontStyle, isNot(FontStyle.italic),
            reason: entry.key);
      }
      // An italic run is weight 500 with a touch of tracking, in inkSoft at
      // the call site, and never a skew.
      expect(type.AppText.pageBodyItalic.fontWeight, FontWeight.w500);
      expect(type.AppText.pageBodyItalic.letterSpacing, 0.2);
      expect(type.AppText.pageBodyItalic.fontStyle, isNot(FontStyle.italic));
    });
  });
}
