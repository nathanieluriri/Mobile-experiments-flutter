import 'dart:ui' show Rect;

import 'display_list.dart';

/// One occurrence of a query inside a PDF, with the box it occupies on its
/// page so the highlighter can be swept across it without re-reading the page.
class PdfHit {
  const PdfHit({
    required this.page,
    required this.runIndex,
    required this.start,
    required this.end,
    required this.rect,
    required this.snippet,
    required this.snippetStart,
  });

  /// Zero based page index.
  final int page;

  /// Index into that page's merged runs, and the character range inside the
  /// run's text.
  final int runIndex;
  final int start, end;

  /// The match's box in top-left page space, in PDF points.
  final Rect rect;

  /// A short window of the line around the match, for the results list.
  final String snippet;

  /// Where the match begins inside [snippet], so the list can mark it.
  final int snippetStart;

  @override
  String toString() => 'PdfHit(p$page r$runIndex $start..$end)';
}

/// A whole document index over merged runs, page by page.
///
/// Searching the raw display list finds nothing useful: a producer emits a word
/// in as many fragments as it likes, so "lease" can be four commands. The index
/// is therefore built over merged runs, which are the lines a person reads, and
/// it keeps the geometry of each line so a hit can be pointed at rather than
/// only counted.
///
/// Pages are indexed lazily. Opening a long document must not pay for text the
/// reader may never scroll to, and the reader only ever needs a page's hits
/// once that page is near the viewport.
class PdfSearch {
  PdfSearch(this._pageCount);

  /// Builds an index whose pages are already interpreted.
  factory PdfSearch.fromDisplayLists(List<PageDisplayList> lists) {
    final s = PdfSearch(lists.length);
    for (var i = 0; i < lists.length; i++) {
      s.setPage(i, mergeRuns(lists[i].texts));
    }
    return s;
  }

  final int _pageCount;
  final Map<int, List<LaidOutRun>> _runs = {};

  /// Pages, which is the unit the fore edge and the folio chip count in.
  int get unitCount => _pageCount;

  /// The pages that have been handed in so far.
  Iterable<int> get indexedPages => _runs.keys;

  /// True when [page] has been supplied and can be searched.
  bool hasPage(int page) => _runs.containsKey(page);

  /// Supplies the merged runs of one page. Calling it twice replaces the page,
  /// which is what happens when a cache evicts and re-interprets it.
  void setPage(int page, List<LaidOutRun> runs) {
    _runs[page] = runs;
  }

  /// Supplies one page straight from its display list.
  void addDisplayList(int page, PageDisplayList list) {
    setPage(page, mergeRuns(list.texts));
  }

  /// The merged runs of [page], or an empty list when it has not been indexed.
  List<LaidOutRun> runsOf(int page) => _runs[page] ?? const [];

  /// The reading order text of [page], one line per merged run.
  String textOf(int page) => runsOf(page).map((r) => r.text).join('\n');

  /// Every hit for [query] across every indexed page, in page then reading
  /// order. An empty or whitespace only query matches nothing, because the
  /// find field is live and an empty field must not flood the page.
  List<PdfHit> search(String query) {
    final out = <PdfHit>[];
    final pages = _runs.keys.toList()..sort();
    for (final p in pages) {
      out.addAll(searchPage(p, query));
    }
    return out;
  }

  /// Every hit for [query] on one page. Matching is case insensitive.
  List<PdfHit> searchPage(int page, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final runs = runsOf(page);
    final out = <PdfHit>[];
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      final hay = run.text.toLowerCase();
      var from = 0;
      while (true) {
        final at = hay.indexOf(needle, from);
        if (at < 0) break;
        final end = at + needle.length;
        final window = _snippet(run.text, at, end);
        out.add(PdfHit(
          page: page,
          runIndex: i,
          start: at,
          end: end,
          rect: run.sliceBounds(at, end),
          snippet: window.$1,
          snippetStart: window.$2,
        ));
        from = end;
      }
    }
    return out;
  }

  /// How many hits [query] has across every indexed page.
  int countOf(String query) => search(query).length;

  /// Where [hit] sits from 0 at the head of the document to 1 at its foot.
  ///
  /// The fraction inside the page is taken from the run's baseline against the
  /// page it was laid out on, so a match near the foot of page one does not
  /// share a fore edge tick with a match at its head.
  double positionOf(PdfHit hit, {double pageHeightPts = 792}) {
    if (_pageCount <= 0) return 0;
    final runs = runsOf(hit.page);
    var within = 0.0;
    if (hit.runIndex < runs.length && pageHeightPts > 0) {
      within = (runs[hit.runIndex].y / pageHeightPts).clamp(0.0, 1.0);
    }
    return ((hit.page + within) / _pageCount).clamp(0.0, 1.0);
  }

  static const int _snippetPad = 28;

  static (String, int) _snippet(String text, int start, int end) {
    final from = (start - _snippetPad) < 0 ? 0 : start - _snippetPad;
    final to = (end + _snippetPad) > text.length ? text.length : end + _snippetPad;
    final head = from > 0 ? '...' : '';
    final tail = to < text.length ? '...' : '';
    return ('$head${text.substring(from, to)}$tail', start - from + head.length);
  }
}
