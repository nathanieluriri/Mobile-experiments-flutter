import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/arrival_lines.dart';
import 'package:quire/data/library.dart';
import 'package:quire/services/arrival_notices.dart';
import 'package:quire/services/device_storage.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/incoming_documents.dart';

import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the lines', () {
    test('there are at least 29, none empty, none repeated', () {
      expect(kArrivalLines.length, greaterThanOrEqualTo(29));
      expect(kArrivalLines.every((line) => line.trim().isNotEmpty), isTrue);
      expect(kArrivalLines.toSet(), hasLength(kArrivalLines.length));
    });

    test('none is cut off in the collapsed notice', () {
      for (final line in kArrivalLines) {
        expect(line.length, lessThanOrEqualTo(kArrivalLineLimit), reason: line);
      }
      for (final format in DocFormat.values) {
        for (final count in [1, 6, 56, 999, 1000, 1200, 250000]) {
          final line = countedArrivalLine(format, count)!;
          expect(line.length, lessThanOrEqualTo(kArrivalLineLimit), reason: line);
        }
      }
    });

    test('a known count says something true about this one', () {
      expect(countedArrivalLine(DocFormat.pdf, 6), 'Six pages, unread.');
      expect(countedArrivalLine(DocFormat.pdf, 1), 'One page, unread.');
      expect(countedArrivalLine(DocFormat.pptx, 6), 'Six slides, unread.');
      expect(countedArrivalLine(DocFormat.xlsx, 56), 'Fifty six rows, unread.');
      expect(
        countedArrivalLine(DocFormat.docx, 1010),
        'About a thousand words. Read it here?',
      );
      expect(
        countedArrivalLine(DocFormat.md, 3400),
        'About three thousand words. Read it here?',
      );
      expect(countedArrivalLine(DocFormat.pdf, 0), isNull);
    });

    test('numbers are spelt the way they are said', () {
      expect(spelledCount(0), 'Zero');
      expect(spelledCount(13), 'Thirteen');
      expect(spelledCount(40), 'Forty');
      expect(spelledCount(56), 'Fifty six');
      expect(spelledCount(300), 'Three hundred');
      expect(spelledCount(305), 'Three hundred and five');
      expect(spelledCount(1000), '1000');
    });
  });

  group('the dealer', () {
    test('never repeats a line before every other has been dealt', () {
      final dealer = LineDealer(kArrivalLines, seed: 42);
      for (var pass = 0; pass < 20; pass++) {
        final dealt = <String>{
          for (var i = 0; i < kArrivalLines.length; i++) dealer.next(),
        };
        expect(dealt, hasLength(kArrivalLines.length), reason: 'pass $pass');
      }
    });

    test('never says the same thing twice in a row, across a reshuffle', () {
      for (var seed = 0; seed < 200; seed++) {
        final dealer = LineDealer(kArrivalLines, seed: seed);
        var last = '';
        for (var i = 0; i < kArrivalLines.length * 4; i++) {
          final line = dealer.next();
          expect(line, isNot(last), reason: 'seed $seed at $i');
          last = line;
        }
      }
    });

    test('picks up where it left off from nothing but a number', () {
      final first = LineDealer(kArrivalLines, seed: 7);
      for (var i = 0; i < 45; i++) {
        first.next();
      }
      final again = LineDealer(kArrivalLines, seed: 7, dealt: first.dealt);
      expect(again.ahead(60), first.ahead(60));
    });

    test('looking ahead deals nothing', () {
      final dealer = LineDealer(kArrivalLines, seed: 3);
      final ahead = dealer.ahead(5);
      expect(dealer.dealt, 0);
      expect(<String>[for (var i = 0; i < 5; i++) dealer.next()], ahead);
    });

    test('two installs tell them in a different order', () {
      final one = LineDealer(kArrivalLines, seed: 1).ahead(kArrivalLines.length);
      final two = LineDealer(kArrivalLines, seed: 2).ahead(kArrivalLines.length);
      expect(one, isNot(two));
    });
  });

  group('the phone', () {
    late List<MethodCall> calls;
    var used = 0;

    setUp(() {
      calls = <MethodCall>[];
      used = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kArrivalNoticesChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'configure' => used,
          'askLeave' => true,
          _ => null,
        };
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kDeviceStorageChannel, (call) async {
        return switch (call.method) {
          'adopt' => {'tree': 'content://tree/dl', 'name': 'Download'},
          'list' => <Object?>[],
          _ => null,
        };
      });
    });

    tearDown(() {
      for (final channel in [kArrivalNoticesChannel, kDeviceStorageChannel]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });

    test('is handed the folders and the lines ahead, and says what it used',
        () async {
      final dealer = LineDealer(kArrivalLines, seed: 9);
      final expected = dealer.ahead(kArrivalLinesAhead);
      used = 3;
      await const ArrivalNotices().watch(['content://tree/dl'], dealer);
      final args = (calls.single.arguments as Map).cast<String, Object?>();
      expect(args['trees'], ['content://tree/dl']);
      expect(args['lines'], expected);
      expect((args['pdfLines']! as List)[5], 'Six pages, unread.');
      expect(dealer.dealt, 3);
    });

    test('is asked for leave to post once, when the first folder comes',
        () async {
      final store = LibraryStore(entries: const [], catalogue: SavedDesk());
      await store.boot(parse: false);
      expect(calls.where((c) => c.method == 'askLeave'), isEmpty);
      await store.adoptFolder();
      await store.adoptFolder();
      expect(calls.where((c) => c.method == 'askLeave'), hasLength(1));
      final configured = calls.lastWhere((c) => c.method == 'configure');
      expect(
        (configured.arguments as Map)['trees'],
        ['content://tree/dl'],
      );
    });
  });

  group('a notice tapped', () {
    test('hands over a document on the phone to be read in place', () async {
      const channel = MethodChannel('test/incoming');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return '${kDeviceOpenPrefix}content://t/lease.pdf\nlease.pdf';
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final incoming = IncomingDocuments(channel: channel);
      await incoming.boot();
      final waiting = incoming.take()!;
      expect(waiting.onDevice, isTrue);
      expect(waiting.path, 'content://t/lease.pdf');
      expect(waiting.name, 'lease.pdf');
      expect(waiting.format, DocFormat.pdf);
    });

    test('refuses one it cannot read', () async {
      const channel = MethodChannel('test/incoming2');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return '${kDeviceOpenPrefix}content://t/a.mp4\na.mp4';
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final incoming = IncomingDocuments(channel: channel);
      await incoming.boot();
      expect(incoming.take(), isNull);
      expect(incoming.refused, IncomingRefusal.unreadable);
    });
  });
}
