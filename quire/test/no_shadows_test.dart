import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/screens/desk/desk_top_bar.dart';
import 'package:quire/screens/desk/sort_row.dart';
import 'package:quire/screens/reader/reader_host.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// Nothing in this app casts a shadow. Surfaces are told apart by their own
/// value against the ground and by a hairline where value is not enough.
///
/// The rule is worth a test of its own because a shadow is the single easiest
/// thing to add back: one `boxShadow:` on one decoration reads as harmless in
/// isolation and puts the whole app back into the idiom it was taken out of.
void main() {
  group('no surface on screen carries a shadow', () {
    testWidgets('the desk', (tester) async {
      await pumpScreen(tester, const App());
      await settle(tester);
      expectNoShadows(tester);
    });

    testWidgets('the desk with the drawer over it and the sort menu open', (
      tester,
    ) async {
      await pumpScreen(tester, const App());
      await settle(tester);

      await tester.tap(find.byType(HamburgerGlyph));
      await settle(tester);
      expectNoShadows(tester);

      await tester.tapAt(const Offset(380, 400));
      await settle(tester);
      await tester.tap(
        find.descendant(of: find.byType(SortRow), matching: find.byType(Text))
            .first,
      );
      await settle(tester);
      expectNoShadows(tester);
    });

    for (final fileName in <String>[
      kFieldGuide,
      kBinderyNotes,
      kPressRunCosts,
    ]) {
      testWidgets('the reader showing $fileName', (tester) async {
        final store = await storeFor(fileName);
        await pumpScreen(
          tester,
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ReaderHost(store: store),
          ),
        );
        await settle(tester);
        expectNoShadows(tester);
      });
    }
  });

  test('no file under lib asks for one', () {
    // The ink bleed under a wet signature is the one blur the app keeps: that
    // is the mark spreading into the paper, not something floating above it.
    const allowedBlur = 'signature_painter.dart';
    const banned = <String>[
      'BoxShadow',
      'boxShadow:',
      'shadows:',
      'elevation:',
      'Shadow(',
      'MaskFilter.blur',
      // Not a shadow, but the same failure: chrome you can read the page
      // through separates by blur instead of by value, and it costs a debug
      // versus release difference no golden can pin down.
      'BackdropFilter',
    ];
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final name = file.uri.pathSegments.last;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trimLeft();
        if (code.startsWith('//')) {
          continue;
        }
        for (final term in banned) {
          if (!code.contains(term)) {
            continue;
          }
          if (term == 'MaskFilter.blur' && name == allowedBlur) {
            continue;
          }
          offenders.add('$name:${i + 1} $term');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}

/// Fails if any decoration currently mounted carries a shadow, in any of the
/// four ways Flutter offers one.
void expectNoShadows(WidgetTester tester) {
  final offenders = <String>[];
  for (final widget in tester.allWidgets) {
    switch (widget) {
      case Container(:final decoration, :final foregroundDecoration):
        _check(decoration, widget, offenders);
        _check(foregroundDecoration, widget, offenders);
      case DecoratedBox(:final decoration):
        _check(decoration, widget, offenders);
      case PhysicalModel(:final elevation) when elevation > 0:
        offenders.add('PhysicalModel elevation $elevation');
      case PhysicalShape(:final elevation) when elevation > 0:
        offenders.add('PhysicalShape elevation $elevation');
      case Material(:final elevation) when elevation > 0:
        offenders.add('Material elevation $elevation');
      case Text(:final style?) when style.shadows?.isNotEmpty ?? false:
        offenders.add('Text "${widget.data}" carries a text shadow');
      default:
        break;
    }
  }
  expect(offenders, isEmpty);
}

void _check(Decoration? decoration, Widget owner, List<String> offenders) {
  switch (decoration) {
    case BoxDecoration(:final boxShadow?) when boxShadow.isNotEmpty:
      offenders.add('${owner.runtimeType} BoxDecoration $boxShadow');
    case ShapeDecoration(:final shadows?) when shadows.isNotEmpty:
      offenders.add('${owner.runtimeType} ShapeDecoration $shadows');
    default:
      break;
  }
}
