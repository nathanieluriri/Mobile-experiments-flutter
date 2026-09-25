import 'dart:ui' as ui;

import '../pdf/display_list.dart';

/// How many interpreted pages are kept at once.
///
/// Twelve is roughly four screens of a phone sized reader in either scroll
/// direction, which is enough that a fast scrub never re interprets a page the
/// reader can still see, and small enough that a long document cannot grow
/// without bound.
const int kPageCacheCapacity = 12;

/// An LRU of interpreted pages, with the images each page decoded to.
///
/// Decoding lives here rather than in a painter because a `ui.Image` decode is
/// asynchronous and `paint` is not: a painter that decoded on demand would
/// either block the frame or paint a hole. Everything in this cache is already
/// ready to draw.
class PageCache {
  PageCache({this.capacity = kPageCacheCapacity});

  /// The most pages held at once. Beyond it the least recently used page and
  /// its images are dropped.
  final int capacity;

  final Map<int, PageDisplayList> _lists = {};
  final Map<int, Map<String, ui.Image>> _images = {};
  final List<int> _order = [];

  /// The interpreted page at [page], or null when it is not held.
  ///
  /// Reading a page counts as using it, which is what keeps the pages either
  /// side of the reader's thumb alive during a scrub.
  PageDisplayList? list(int page) {
    final held = _lists[page];
    if (held != null) _touch(page);
    return held;
  }

  /// True when [page] is held, without counting as a use.
  bool holds(int page) => _lists.containsKey(page);

  /// Stores an interpreted page, evicting the least recently used one when the
  /// cache is over capacity.
  void put(int page, PageDisplayList list) {
    _lists[page] = list;
    _touch(page);
    _evict();
  }

  /// The decoded images for [page], keyed by the name the content stream used.
  Map<String, ui.Image> imagesFor(int page) =>
      _images[page] ?? const <String, ui.Image>{};

  /// Stores the images decoded for [page]. Any image already held under the
  /// same key is disposed, so a re decode cannot leak.
  void putImages(int page, Map<String, ui.Image> images) {
    final existing = _images[page];
    if (existing != null) {
      for (final entry in existing.entries) {
        if (images[entry.key] != entry.value) entry.value.dispose();
      }
    }
    _images[page] = Map<String, ui.Image>.from(images);
    _touch(page);
    _evict();
  }

  /// Pages held, least recently used first.
  List<int> get pages => List<int>.unmodifiable(_order);

  /// How many pages are held.
  int get length => _lists.length;

  /// Drops everything and disposes every decoded image.
  void clear() {
    for (final page in _images.values) {
      for (final image in page.values) {
        image.dispose();
      }
    }
    _lists.clear();
    _images.clear();
    _order.clear();
  }

  void _touch(int page) {
    _order.remove(page);
    _order.add(page);
  }

  void _evict() {
    while (_order.length > capacity) {
      final oldest = _order.removeAt(0);
      _lists.remove(oldest);
      final images = _images.remove(oldest);
      if (images == null) continue;
      for (final image in images.values) {
        image.dispose();
      }
    }
  }
}
