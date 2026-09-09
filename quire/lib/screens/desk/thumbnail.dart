import 'package:flutter/widgets.dart';

import '../../model/document.dart';
import '../../painting/thumbnail_painter.dart';
import '../../pdf/interpreter.dart';
import '../../services/document_store.dart';
import '../../theme/metrics.dart';

/// Every first page recorded so far, keyed to the document it came from.
///
/// An [Expando] rather than a cache with a policy, because there is exactly one
/// right lifetime for a thumbnail: as long as the document. It survives
/// switching between the list and the grid, scrolling a card off the screen
/// and back, and every rebuild in between, and it is collected the moment the
/// document it belongs to is.
final Expando<ThumbnailPicture> _held = Expando<ThumbnailPicture>();

/// [store]'s document as its own first page, recorded once and then kept.
///
/// The recording is the expensive half: a PDF's first content stream is
/// interpreted here and nowhere else, so six cards on screen cost six
/// interpretations in the life of the app rather than six a frame.
ThumbnailPicture thumbnailOf(DocumentStore store) =>
    _held[store] ??= _record(store);

ThumbnailPicture _record(DocumentStore store) {
  if (store.isPdf) return _firstPage(store);
  final document = store.document;
  if (document == null) return recordEmptyThumbnail();
  final grid = _gridOf(document);
  if (grid != null) return recordGridThumbnail(grid);
  final blocks = <DocBlock>[
    for (final section in document.sections) ...section.blocks,
  ];
  if (blocks.isEmpty) return recordEmptyThumbnail();
  return recordProseThumbnail(
    blocks,
    foldBreaks: document.sourceFormat == 'md',
  );
}

/// The first page of a page file, run through the same engine the reader runs.
///
/// A file that will not open, or that opens with no page tree, records an
/// empty page. That is not a placeholder for a page that exists: it is what is
/// known about a file nothing could read.
ThumbnailPicture _firstPage(DocumentStore store) {
  try {
    final file = store.pdf;
    if (file == null || file.pages.isEmpty) return recordEmptyThumbnail();
    return recordPdfThumbnail(ContentInterpreter(file).run(file.pages.first));
  } on Object {
    return recordEmptyThumbnail();
  }
}

/// The first grid in [document], which is what a spreadsheet and a CSV both
/// parse to, or null for a flowing document.
TableBlock? _gridOf(QuireDocument document) {
  for (final section in document.sections) {
    for (final block in section.blocks) {
      if (block is TableBlock && block.grid) return block;
    }
  }
  return null;
}

/// A card's white rect, carrying the document's real first page.
///
/// It is never a generic glyph and never a coloured placeholder, because the
/// whole reason a grid exists is that a document is recognised by the shape of
/// its first page before its name has been read. A page too tall for the rect
/// shows its top and is clipped, the way a page sticking out of a folder is.
class Thumbnail extends StatelessWidget {
  const Thumbnail({
    super.key,
    required this.store,
    this.radius = const BorderRadius.vertical(
      bottom: Radius.circular(kGridCardRadius),
    ),
  });

  /// What has been read of the document, or null before anything has read it.
  final DocumentStore? store;

  /// The corners the page is cut to. A card rounds only the two it owns.
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final held = store;
    return AspectRatio(
      aspectRatio: kThumbnailAspect,
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: ThumbnailPainter(held == null ? null : thumbnailOf(held)),
          size: Size.infinite,
        ),
      ),
    );
  }
}
