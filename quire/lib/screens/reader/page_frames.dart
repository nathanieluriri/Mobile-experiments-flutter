import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Where a page of the document has actually been drawn on screen.
///
/// A page is not at the top of the sheet. The sheet is the whole screen now,
/// the strip holds its pages clear of the band, and the reader has scrolled
/// them somewhere else again since. Anything that puts a mark on the paper has
/// to be told where the paper is, and the body running the strip is the only
/// thing that knows.
@immutable
class PageFrame {
  const PageFrame({required this.index, required this.rect});

  /// Which page this is, zero based.
  final int index;

  /// The page's rectangle in the coordinates of the sheet it is drawn on.
  final Rect rect;

  @override
  bool operator ==(Object other) =>
      other is PageFrame && other.index == index && other.rect == rect;

  @override
  int get hashCode => Object.hash(index, rect);
}

/// The channel a body reports [PageFrame] on, and a placement reads it from.
///
/// One page at a time, because one page at a time is what can be signed.
class PageFrames extends ValueNotifier<PageFrame?> {
  PageFrames() : super(null);
}
