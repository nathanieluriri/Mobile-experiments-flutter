import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/painting/thumbnail_painter.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/screens/desk/thumbnail.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';

void main() {
  test('a page file records its own first page at its own size', () async {
    final store = await storeFor(kFieldGuide);
    final page = thumbnailOf(store);
    final file = PdfFile.open(await documentBytes(kFieldGuide));
    final media = file.mediaBox(file.pages.first);

    // The page is recorded in the file's own points, so one recording serves
    // any card width and nothing is ever laid out twice.
    expect(page.source.width, closeTo((media[2] - media[0]).abs(), 0.01));
    expect(page.source.height, closeTo((media[3] - media[1]).abs(), 0.01));
  });

  test('every other format records the first screen of its own body', () async {
    for (final fileName in <String>[
      kHouseStyle,
      kPressRunCosts,
      kSubscribers,
      kBinderyNotes,
    ]) {
      final page = thumbnailOf(await storeFor(fileName));
      expect(page.source.width, kSheetWidth, reason: fileName);
      expect(page.source.height, closeTo(kThumbnailPageHeight, 0.01),
          reason: fileName);
    }
  });

  test('a document is interpreted once and then kept', () async {
    final store = await storeFor(kFieldGuide);
    final first = thumbnailOf(store);
    expect(identical(thumbnailOf(store), first), isTrue);
    expect(identical(thumbnailOf(store).picture, first.picture), isTrue);
  });

  test('a file nothing can read records an empty page, not a placeholder', () {
    final store = DocumentStore(
      const LibraryEntry(
        assetPath: 'assets/documents/torn.pdf',
        title: 'Torn',
        format: DocFormat.pdf,
        bytes: 0,
      ),
    );
    final page = thumbnailOf(store);
    expect(page.source.width, kSheetWidth);
  });

  testWidgets('a card with nothing behind it draws paper and no more',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(width: 180, child: Thumbnail(store: null)),
        ),
      ),
    );
    final page = tester.getRect(find.byType(Thumbnail));
    expect(page.width / page.height, closeTo(kThumbnailAspect, 0.01));
  });
}
