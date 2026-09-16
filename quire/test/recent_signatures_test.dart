import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/signature_painter.dart';
import 'package:quire/screens/sign/sign_pad.dart';
import 'package:quire/screens/sign/sign_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/recent_signatures.dart';

import 'sign_test.dart' show scriptStrokes;
import 'support/golden.dart';

/// A drawn signature, nudged by [shift] so each one is a different mark.
SavedSignature _drawn([double shift = 0]) {
  final mark = SignatureMark.of(scriptStrokes());
  return SavedSignature(
    outlines: <List<ui.Offset>>[
      for (final outline in mark.outlines)
        <ui.Offset>[for (final p in outline) p + ui.Offset(shift, 0)],
    ],
    bounds: mark.bounds,
  );
}

Widget _pad({
  required List<SavedSignature> recent,
  ValueChanged<SignatureMark>? onCommit,
  ValueChanged<SavedSignature>? onForget,
  SignPadController? pad,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: SignScreen(
    pad: pad,
    recent: recent,
    onCommit: onCommit,
    onForget: onForget,
  ),
);

void main() {
  group('the signatures kept to be used again', () {
    test('the one just used goes to the front, once', () {
      final a = _drawn();
      final b = _drawn(0.01);
      var kept = rememberSignature(<SavedSignature>[], a);
      kept = rememberSignature(kept, b);
      kept = rememberSignature(kept, _drawn());
      expect(kept.length, 2);
      expect(kept.first.sameAs(a), isTrue);
      expect(kept.last.sameAs(b), isTrue);
    });

    test('no more than ten are kept, and the oldest is the one let go', () {
      var kept = <SavedSignature>[];
      for (var i = 0; i < 12; i++) {
        kept = rememberSignature(kept, _drawn(i * 0.01));
      }
      expect(kept.length, kRecentSignatureLimit);
      expect(kept.first.sameAs(_drawn(0.11)), isTrue);
      expect(kept.any((s) => s.sameAs(_drawn(0))), isFalse);
      expect(kept.any((s) => s.sameAs(_drawn(0.01))), isFalse);
    });

    test('a drawn signature and a picture survive being written down', () {
      final drawn = _drawn();
      final picture = SavedSignature(
        outlines: const <List<ui.Offset>>[],
        bounds: const ui.Rect.fromLTWH(0, 0, 40, 20),
        encoded: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final back = SavedSignature.fromJson(drawn.toJson())!;
      expect(back.sameAs(drawn), isTrue);
      expect(back.bounds, drawn.bounds);
      final picBack = SavedSignature.fromJson(picture.toJson())!;
      expect(picBack.isPicture, isTrue);
      expect(picBack.sameAs(picture), isTrue);
      expect(SavedSignature.fromJson(<String, Object?>{'bounds': 3}), isNull);
    });

    test('the desk keeps them and forgets the one it is told to', () {
      final library = LibraryStore();
      addTearDown(library.dispose);
      library.useSignature(_drawn());
      library.useSignature(_drawn(0.01));
      expect(library.recentSignatures.length, 2);
      library.forgetSignature(_drawn());
      expect(library.recentSignatures.length, 1);
      expect(library.recentSignatures.single.sameAs(_drawn(0.01)), isTrue);
    });
  });

  group('the pad with signatures used before', () {
    testWidgets('shows no strip when there are none', (tester) async {
      await pumpScreen(tester, _pad(recent: const <SavedSignature>[]));
      expect(find.text('RECENT SIGNATURES'), findsNothing);
    });

    testWidgets('a tap puts one on the pad and the pill places it', (
      tester,
    ) async {
      final kept = <SavedSignature>[_drawn(), _drawn(0.01)];
      SignatureMark? placed;
      await pumpScreen(
        tester,
        _pad(recent: kept, onCommit: (mark) => placed = mark),
      );
      expect(find.text('RECENT SIGNATURES'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Use recent signature 2'));
      await settle(tester);
      expect(
        find.text('This signature will be set into the page.'),
        findsOneWidget,
      );
      await capture(tester, 'sign__recent');

      await tester.tap(find.text('Place on page'));
      await tester.pump();
      expect(placed, isNotNull);
      expect(savedOf(placed!).sameAs(kept[1]), isTrue);
    });

    testWidgets('a long press forgets one', (tester) async {
      SavedSignature? forgotten;
      final kept = <SavedSignature>[_drawn()];
      await pumpScreen(
        tester,
        _pad(recent: kept, onForget: (s) => forgotten = s),
      );
      await tester.longPress(find.bySemanticsLabel('Use recent signature 1'));
      await settle(tester);
      expect(forgotten, same(kept.single));
    });
  });
}
