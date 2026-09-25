import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/arrival/arrival_painter.dart';
import 'package:quire/painting/spinner_painter.dart' show kSpinnerPeriod;
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/desk/document_card.dart' show chromaFor;
import 'package:quire/screens/desk/document_row.dart';
import 'package:quire/screens/opening/opening_screen.dart';
import 'package:quire/services/incoming_documents.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/quire_spinner.dart';
import 'package:quire/widgets/type_mark.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// The reader, marked so a test can say whether it is up without building the
/// real one, the way the app's own test does.
const _readerKey = Key('reader');

Widget _app() => App(
  routes: <String, WidgetBuilder>{
    kReaderRoute: (context) =>
        const ColoredBox(key: _readerKey, color: Color(0xFF000000)),
  },
);

void main() {
  const incoming = MethodChannel(kIncomingChannel);

  /// Where the app keeps the documents it is handed. The real one asks the
  /// phone, and a test has no phone, so it is told a folder of its own.
  const storage = MethodChannel('plugins.flutter.io/path_provider');

  late Directory temp;
  late Directory home;

  /// Answers what the app was started on with [path], the way the platform
  /// would.
  void platformStartsWith(String? path) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(incoming, (call) async {
          if (call.method == kIncomingInitial) return path;
          return null;
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

  /// A real file called [name], holding a real bundled document, in the folder
  /// another app would have left it in.
  Future<String> handedOver(String name) async {
    final file = File('${temp.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(await documentBytes(name));
    return file.path;
  }

  /// Hands the real event loop back for a moment and then pumps a frame.
  ///
  /// The app's own start reads the phone, and a real read does not land inside
  /// a widget test's fake clock unless the clock is given up: without this the
  /// app would sit on its first frame for the whole of a test. The moment is a
  /// few real milliseconds and not none, because a read waiting on a thread
  /// needs time and not just a turn, and a suite running several files at once
  /// leaves it less of the machine than a file running alone.
  ///
  /// None of this moves the clock the app is animating against, which is why a
  /// keyframe taken after any number of these still means what it says.
  Future<void> turn(WidgetTester tester, [Duration by = Duration.zero]) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
    await tester.pump(by);
  }

  /// Turns until [found] is on screen, without moving the clock, so whatever
  /// is up afterwards has been up for no time at all and a keyframe measured
  /// from here means what it says.
  Future<void> turnUntil(
    WidgetTester tester,
    Finder found, {
    int turns = 1000,
  }) async {
    for (var i = 0; i < turns; i++) {
      if (found.evaluate().isNotEmpty) return;
      await turn(tester);
    }
    fail(
      'nothing matched $found after $turns turns, with '
      '${find.byType(OpeningScreen).evaluate().length} opening screen and '
      '${find.byType(DeskScreen).evaluate().length} desk on the tree',
    );
  }

  /// Lets one of the app's fades run out.
  ///
  /// A ticker counts from its first frame and not from the moment it was
  /// started, so the fade is given a frame to start on and then the whole of
  /// its own length. Pumped once, the screen leaving would still be on the
  /// tree and every count taken here would be doubled.
  Future<void> fade(WidgetTester tester) async {
    await pumpMs(tester, kDeskWakingFade.inMilliseconds);
    await pumpMs(tester, kDeskWakingFade.inMilliseconds);
    await tester.pump();
  }

  /// Runs the whole of the app's start: the desk read and laid out, and the
  /// platform asked what quire was opened on and answered.
  Future<void> startUp(WidgetTester tester) async {
    for (var i = 0; i < 300; i++) {
      if (find.byType(DocumentRow).evaluate().isNotEmpty) break;
      await turn(tester, const Duration(milliseconds: 16));
    }
    expect(find.byType(DocumentRow), findsWidgets);
    // The platform is asked after the desk has been read, so the start is not
    // over the moment the desk is on screen.
    for (var i = 0; i < 10; i++) {
      await turn(tester);
    }
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('quire_opening');
    home = Directory.systemTemp.createTempSync('quire_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return home.path;
          }
          return null;
        });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(incoming, null);
    messenger.setMockMethodCallHandler(storage, null);
    for (final folder in <Directory>[temp, home]) {
      try {
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      } on FileSystemException {
        // A read the app started and the test never waited for can still hold
        // a file open. A folder left in the system temp is not worth failing a
        // test over.
      }
    }
  });

  group('a cold start on a document', () {
    testWidgets('names the document, and shows nothing else', (tester) async {
      platformStartsWith(await handedOver(kPressLease));
      await pumpScreen(tester, _app());
      await turnUntil(tester, find.byType(OpeningScreen));
      // Past the fade, so what is left is what quire means to be showing
      // rather than what it is halfway through leaving.
      await fade(tester);

      expect(find.byType(OpeningScreen), findsOneWidget);
      expect(find.text('Press Lease'), findsOneWidget);
      final mark = tester.widget<TypeMark>(find.byType(TypeMark));
      expect(mark.letters, DocFormat.pdf.mark);
      expect(mark.chroma, chromaFor(DocFormat.pdf));
      // The app's own loading mark, the one the desk wakes behind.
      expect(find.byType(QuireSpinner), findsOneWidget);

      // Neither of the two screens it stands between.
      expect(find.byType(DeskScreen), findsNothing);
      expect(find.byKey(_readerKey), findsNothing);

      await pumpMs(tester, kOpeningLimit.inMilliseconds);
      await settle(tester);
    });

    testWidgets('names a deck by the letters a deck wears', (tester) async {
      platformStartsWith(await handedOver(kPressDayBriefing));
      await pumpScreen(tester, _app());
      await turnUntil(tester, find.byType(OpeningScreen));
      await fade(tester);

      expect(find.text('Press Day Briefing'), findsOneWidget);
      expect(
        tester.widget<TypeMark>(find.byType(TypeMark)).letters,
        DocFormat.pptx.mark,
      );

      await pumpMs(tester, kOpeningLimit.inMilliseconds);
      await settle(tester);
    });

    testWidgets('gives way to the reader once the document has been read', (
      tester,
    ) async {
      // The shortest of the bundled documents, because what is being watched
      // here is the handover and not how long a long file takes to read.
      platformStartsWith(await handedOver(kBinderyNotes));
      await pumpScreen(tester, _app());
      await turnUntil(tester, find.byType(OpeningScreen));
      expect(find.byType(OpeningScreen), findsOneWidget);

      await turnUntil(tester, find.byKey(_readerKey));
      await settle(tester);

      expect(find.byKey(_readerKey), findsOneWidget);
      // The screen goes with it. One left under the reader would be there
      // again the moment somebody dragged back.
      expect(find.byType(OpeningScreen), findsNothing);
      expect(find.byType(DeskScreen), findsOneWidget);
    });

    testWidgets('stops waiting on a document that is not coming', (
      tester,
    ) async {
      platformStartsWith(await handedOver(kPressLease));
      await pumpScreen(tester, _app());
      await turnUntil(tester, find.byType(OpeningScreen));
      await fade(tester);
      expect(find.byType(OpeningScreen), findsOneWidget);

      // The clock moves and the document does not: nothing is read, because
      // nothing here hands the real event loop back.
      await pumpMs(tester, kOpeningLimit.inMilliseconds);
      await fade(tester);

      // A screen that never goes is worse than a desk nobody asked for.
      expect(find.byType(OpeningScreen), findsNothing);
      expect(find.byType(DeskScreen), findsOneWidget);
      await settle(tester);
    });

    testWidgets('opening__document', (tester) async {
      platformStartsWith(await handedOver(kPressLease));
      await pumpScreen(tester, _app());
      await turnUntil(tester, find.byType(OpeningScreen));
      await fade(tester);
      // The arrival opens onto the screen that names the document; the golden
      // is of that screen, not of the mark still standing over it. The wait is
      // made up to whole turns of the spinner, so the loop is where it was.
      final over = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is ArrivalPainter,
      );
      var waited = 0;
      while (over.evaluate().isNotEmpty && waited < 5000) {
        await pumpMs(tester, 16);
        waited += 16;
      }
      final period = kSpinnerPeriod.inMilliseconds;
      await pumpMs(tester, (period - waited % period) % period);
      await capture(tester, 'opening__document');

      await pumpMs(tester, kOpeningLimit.inMilliseconds);
      await settle(tester);
    });
  });

  group('every other way in', () {
    testWidgets('the launcher opens the desk and nothing else', (tester) async {
      platformStartsWith(null);
      await pumpScreen(tester, _app());
      for (var i = 0; i < 120; i++) {
        expect(find.byType(OpeningScreen), findsNothing);
        await turn(tester, const Duration(milliseconds: 16));
      }
      expect(find.byType(DeskScreen), findsOneWidget);
      expect(find.byType(DocumentRow), findsWidgets);
      await settle(tester);
    });

    testWidgets('a document arriving while quire is up is not a splash', (
      tester,
    ) async {
      platformStartsWith(null);
      await pumpScreen(tester, _app());
      await startUp(tester);
      expect(find.byType(DeskScreen), findsOneWidget);

      await platformOpens(await handedOver(kBinderyNotes));
      await tester.pump();
      // It arrived on top of a desk somebody was already looking at.
      expect(find.byType(OpeningScreen), findsNothing);

      await turnUntil(tester, find.byKey(_readerKey));
      await settle(tester);
      expect(find.byType(OpeningScreen), findsNothing);
      expect(find.byKey(_readerKey), findsOneWidget);
    });
  });
}
