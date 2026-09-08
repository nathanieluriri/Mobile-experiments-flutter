import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/services/page_cache.dart';
import 'package:quire/services/render_plan.dart';

import 'support/fixtures.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
      .drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  return recorder.endRecording().toImage(2, 2);
}

void main() {
  group('the fallback ladder', () {
    test('text and paths are the default rung', () {
      expect(planFor(richPage(), encrypted: false, threw: false),
          RenderPlan.rich);
    });

    test('a decodable full page image with no text is an honest scan', () {
      for (final encoding in <String>['jpeg', 'raw-rgb', 'raw-gray']) {
        expect(
          planFor(scanPage(encoding: encoding),
              encrypted: false, threw: false),
          RenderPlan.scan,
          reason: encoding,
        );
      }
    });

    test('an undecodable full page image gets the designed scan card', () {
      for (final encoding in <String>['ccitt', 'jbig2', 'jpx', 'unsupported']) {
        expect(
          planFor(scanPage(encoding: encoding),
              encrypted: false, threw: false),
          RenderPlan.scanUnreadable,
          reason: encoding,
        );
      }
    });

    test('text plus an image this reader cannot decode is text only', () {
      expect(
        planFor(textWithUndecodableImagePage(),
            encrypted: false, threw: false),
        RenderPlan.textOnly,
      );
    });

    test('an invisible OCR layer over a scan stops it being a scan', () {
      // Render mode 3 text is never painted but it is in the display list, so
      // a page that looks like a scan and holds searchable text is rich, and
      // the reader gets the picture plus a text layer they can search.
      final list = scanPage();
      list.texts.add(textRun('the invisible layer', seq: 0));
      expect(planFor(list, encrypted: false, threw: false), RenderPlan.rich);
    });

    test('coverage must be over the threshold, not merely at it', () {
      final atThreshold =
          PageDisplayList(widthPts: 100, heightPts: 100, rotation: 0);
      atThreshold.images.add(imageCmd(
        rect: const <double>[0, 0, 40, 100],
        encoding: 'jpeg',
        bytes: Uint8List.fromList(const <int>[1]),
      ));
      expect(atThreshold.imageCoverage, closeTo(0.4, 1e-9));
      expect(planFor(atThreshold, encrypted: false, threw: false),
          RenderPlan.rich);

      final over =
          PageDisplayList(widthPts: 100, heightPts: 100, rotation: 0);
      over.images.add(imageCmd(
        rect: const <double>[0, 0, 41, 100],
        encoding: 'jpeg',
        bytes: Uint8List.fromList(const <int>[1]),
      ));
      expect(planFor(over, encrypted: false, threw: false), RenderPlan.scan);
    });

    test('a small undecodable image on a page with no text is not a scan', () {
      final list = PageDisplayList(widthPts: 612, heightPts: 792, rotation: 0);
      list.paths.add(rulePath());
      list.images.add(imageCmd(
        rect: const <double>[10, 10, 40, 40],
        encoding: 'jpx',
        bytes: null,
      ));
      expect(planFor(list, encrypted: false, threw: false), RenderPlan.rich,
          reason: 'no text to show, but nothing claiming to be a page either');
    });

    test('an encryption dictionary is a lock, not damage', () {
      expect(planFor(richPage(), encrypted: true, threw: false),
          RenderPlan.locked);
      expect(planFor(null, encrypted: true, threw: true), RenderPlan.locked,
          reason: 'a locked file usually fails to interpret as well, and '
              'locked is the true answer');
    });

    test('a parser that threw, or no list at all, is damage', () {
      expect(planFor(null, encrypted: false, threw: true), RenderPlan.damaged);
      expect(planFor(null, encrypted: false, threw: false),
          RenderPlan.damaged);
      expect(planFor(richPage(), encrypted: false, threw: true),
          RenderPlan.damaged);
    });

    test('an empty page is drawn as an empty page', () {
      // A PDF is allowed to hold a genuinely blank leaf. It gets the sheet, its
      // rule and its shadow, which is not the same thing as a blank white
      // screen presented as a document.
      expect(planFor(blankPage(), encrypted: false, threw: false),
          RenderPlan.rich);
    });

    test('planFor is pure: the same list gives the same answer every time', () {
      final list = textWithUndecodableImagePage();
      final answers = <RenderPlan>[
        for (var i = 0; i < 5; i++)
          planFor(list, encrypted: false, threw: false),
      ];
      expect(answers.toSet().length, 1);
    });
  });

  group('a truncated file is damage', () {
    test('cutting press-lease.pdf short destroys the trailer the engine needs',
        () async {
      final whole = await documentBytes(kPressLease);
      final text = String.fromCharCodes(whole);
      expect(text, contains('%PDF'));
      expect(text, contains('trailer'));
      expect(text.trimRight(), endsWith('%%EOF'));

      final truncated = Uint8List.sublistView(whole, 0, whole.length ~/ 2);
      final cut = String.fromCharCodes(truncated);
      expect(cut, contains('%PDF'), reason: 'it still looks like a PDF');
      expect(cut, isNot(contains('%%EOF')));
      expect(cut, isNot(contains('trailer')));

      // There is no display list to be had, so the rung is decided without
      // one and the reader sees the torn sheet.
      expect(planFor(null, encrypted: false, threw: true), RenderPlan.damaged);
    });
  });

  group('the page cache', () {
    test('a page comes back out the way it went in', () {
      final cache = PageCache();
      final page = richPage();
      expect(cache.list(0), isNull);
      cache.put(0, page);
      expect(identical(cache.list(0), page), isTrue);
      expect(cache.holds(0), isTrue);
      expect(cache.length, 1);
    });

    test('the twelfth page fits and the thirteenth evicts the oldest', () {
      final cache = PageCache();
      for (var page = 0; page < 12; page++) {
        cache.put(page, richPage());
      }
      expect(cache.length, 12);
      expect(cache.holds(0), isTrue);

      cache.put(12, richPage());
      expect(cache.length, 12);
      expect(cache.holds(0), isFalse, reason: 'page 0 was the least used');
      expect(cache.holds(12), isTrue);
    });

    test('reading a page keeps it alive through the next eviction', () {
      final cache = PageCache();
      for (var page = 0; page < 12; page++) {
        cache.put(page, richPage());
      }
      cache.list(0);
      cache.put(12, richPage());

      expect(cache.holds(0), isTrue, reason: 'it was just read');
      expect(cache.holds(1), isFalse);
      expect(cache.pages.last, 12);
    });

    test('a smaller cache honours its own capacity', () {
      final cache = PageCache(capacity: 2);
      cache.put(0, richPage());
      cache.put(1, richPage());
      cache.put(2, richPage());
      expect(cache.pages, <int>[1, 2]);
    });

    test('images are held per page and disposed when the page is evicted',
        () async {
      final cache = PageCache(capacity: 1);
      final first = await _tinyImage();
      final second = await _tinyImage();

      cache.put(0, richPage());
      cache.putImages(0, <String, ui.Image>{'Im0': first});
      expect(cache.imagesFor(0)['Im0'], same(first));
      expect(cache.imagesFor(1), isEmpty);

      cache.put(1, richPage());
      cache.putImages(1, <String, ui.Image>{'Im0': second});

      expect(cache.holds(0), isFalse);
      expect(first.debugDisposed, isTrue,
          reason: 'an evicted page must not leave its pixels behind');
      expect(second.debugDisposed, isFalse);

      cache.clear();
      expect(second.debugDisposed, isTrue);
      expect(cache.length, 0);
    });

    test('replacing a page image disposes the one it replaced', () async {
      final cache = PageCache();
      final first = await _tinyImage();
      final second = await _tinyImage();

      cache.putImages(0, <String, ui.Image>{'Im0': first});
      cache.putImages(0, <String, ui.Image>{'Im0': second});

      expect(first.debugDisposed, isTrue);
      expect(second.debugDisposed, isFalse);
      cache.clear();
    });
  });
}
