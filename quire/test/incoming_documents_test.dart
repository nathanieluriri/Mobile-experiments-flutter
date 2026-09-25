import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/services/incoming_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kIncomingChannel);
  late Directory temp;
  late List<MethodCall> asked;

  /// Answers [kIncomingInitial] with [path], the way the platform would.
  void platformStartsWith(String? path) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          asked.add(call);
          if (call.method == kIncomingInitial) return path;
          return null;
        });
  }

  /// The platform going quiet, which is what a desktop or a plain launcher
  /// start looks like.
  void platformIsSilent() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          asked.add(call);
          throw MissingPluginException('no handler');
        });
  }

  /// The platform handing over a document while the app is already running.
  Future<void> platformOpens(String path) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          kIncomingChannel,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(kIncomingOpened, path),
          ),
          (_) {},
        );
  }

  String write(String name) {
    final file = File('${temp.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    return file.path;
  }

  setUp(() {
    asked = <MethodCall>[];
    temp = Directory.systemTemp.createTempSync('quire_incoming');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('what the app was started on', () {
    test('a document waiting at a cold start is taken up', () async {
      final path = write('press-lease.pdf');
      platformStartsWith(path);

      final incoming = IncomingDocuments();
      await incoming.boot();

      expect(asked.single.method, kIncomingInitial);
      expect(incoming.booted, isTrue);
      expect(incoming.waiting, isNotNull);
      expect(incoming.waiting!.path, path);
      expect(incoming.waiting!.format, DocFormat.pdf);
      expect(incoming.waiting!.name, 'press-lease.pdf');
      expect(incoming.refused, isNull);
    });

    test('nothing waiting is not a failure', () async {
      platformStartsWith(null);
      final incoming = IncomingDocuments();
      await incoming.boot();
      expect(incoming.booted, isTrue);
      expect(incoming.waiting, isNull);
      expect(incoming.refused, isNull);
    });

    test('a platform with no such channel is nothing waiting', () async {
      platformIsSilent();
      final incoming = IncomingDocuments();
      await incoming.boot();
      expect(incoming.booted, isTrue);
      expect(incoming.waiting, isNull);
      expect(incoming.refused, isNull);
    });
  });

  group('a document arriving while the app is up', () {
    test('is taken up and announced', () async {
      platformStartsWith(null);
      final incoming = IncomingDocuments();
      await incoming.boot();

      var beats = 0;
      incoming.addListener(() => beats++);

      final path = write('house-style.docx');
      await platformOpens(path);

      expect(beats, 1);
      expect(incoming.waiting!.path, path);
      expect(incoming.waiting!.format, DocFormat.docx);
    });

    test('the second one replaces the first, rather than queueing', () async {
      platformStartsWith(null);
      final incoming = IncomingDocuments();
      await incoming.boot();

      await platformOpens(write('one.pdf'));
      await platformOpens(write('two.csv'));
      expect(incoming.waiting!.name, 'two.csv');
    });
  });

  group('what is turned away', () {
    test('a path with nothing at it', () async {
      final gone = '${temp.path}${Platform.pathSeparator}vanished.pdf';
      platformStartsWith(gone);

      final incoming = IncomingDocuments();
      await incoming.boot();

      expect(incoming.waiting, isNull);
      expect(incoming.refused, IncomingRefusal.missing);
      expect(incoming.refused!.line, contains('no longer there'));
    });

    test('a file that was there and then was not', () async {
      platformStartsWith(null);
      final incoming = IncomingDocuments();
      await incoming.boot();

      final path = write('gone.pdf');
      File(path).deleteSync();
      await platformOpens(path);

      expect(incoming.waiting, isNull);
      expect(incoming.refused, IncomingRefusal.missing);
    });

    test('a kind of file quire does not read', () async {
      final path = write('holiday.mp4');
      platformStartsWith(path);

      final incoming = IncomingDocuments();
      await incoming.boot();

      expect(incoming.waiting, isNull);
      expect(incoming.refused, IncomingRefusal.unreadable);
      expect(incoming.refused!.line, contains('does not read'));
    });

    test('a file with no extension at all', () async {
      final path = write('scan');
      platformStartsWith(path);
      final incoming = IncomingDocuments();
      await incoming.boot();
      expect(incoming.refused, IncomingRefusal.unreadable);
    });

    test('an unreadable one does not throw away the one already waiting',
        () async {
      final good = write('field-guide.pdf');
      platformStartsWith(good);
      final incoming = IncomingDocuments();
      await incoming.boot();
      expect(incoming.waiting, isNotNull);

      // It does clear it, and says why. A reader who tapped a video and then
      // saw the last PDF open would think quire had opened the video.
      await platformOpens(write('holiday.mov'));
      expect(incoming.waiting, isNull);
      expect(incoming.refused, IncomingRefusal.unreadable);
    });
  });

  group('handing it over', () {
    test('taking it clears it, so it opens once', () async {
      final path = write('press-lease.pdf');
      platformStartsWith(path);
      final incoming = IncomingDocuments();
      await incoming.boot();

      final taken = incoming.take();
      expect(taken!.path, path);
      expect(incoming.waiting, isNull);
      expect(incoming.take(), isNull);
    });

    test('a refusal can be said and then forgotten', () async {
      platformStartsWith('${temp.path}${Platform.pathSeparator}no.pdf');
      final incoming = IncomingDocuments();
      await incoming.boot();
      expect(incoming.refused, isNotNull);
      incoming.clearRefusal();
      expect(incoming.refused, isNull);
    });
  });

  group('the formats it will take', () {
    test('every one the desk reads', () {
      expect(formatOfPath('/a/b.pdf'), DocFormat.pdf);
      expect(formatOfPath('/a/b.docx'), DocFormat.docx);
      expect(formatOfPath('/a/b.xlsx'), DocFormat.xlsx);
      expect(formatOfPath('/a/b.pptx'), DocFormat.pptx);
      expect(formatOfPath('/a/b.csv'), DocFormat.csv);
      expect(formatOfPath('/a/b.md'), DocFormat.md);
      expect(formatOfPath('/a/b.markdown'), DocFormat.md);
    });

    test('and nothing else, the old Office binaries included', () {
      expect(formatOfPath('/a/b.doc'), isNull);
      expect(formatOfPath('/a/b.xls'), isNull);
      expect(formatOfPath('/a/b.ppt'), isNull);
      expect(formatOfPath('/a/b.txt'), isNull);
      expect(formatOfPath('/a/b.mp4'), isNull);
      expect(formatOfPath('/a/b'), isNull);
      expect(formatOfPath('/a/b.'), isNull);
      expect(formatOfPath(''), isNull);
    });

    test('however it is spelled', () {
      expect(formatOfPath(r'C:\Users\x\Report.PDF'), DocFormat.pdf);
      expect(formatOfPath('/a/b.CsV'), DocFormat.csv);
    });
  });
}
