/// Searching inside a parsed document.
///
/// Two strategies sit behind one interface because the two shapes of document
/// want opposite things. Prose is a few hundred long strings, so an index pays
/// for itself many times over. A grid is hundreds of thousands of short
/// strings, and an index over them measured slower than scanning the strings
/// directly while costing a large multiple of the document in memory, so the
/// grid strategy deliberately builds nothing.
library;

import 'document.dart';

/// One match, addressed precisely enough for the highlighter to find it again.
class DocHit {
  const DocHit(this.sectionIndex, this.blockPath, this.start, this.end,
      this.snippet, this.label);

  /// Which section of the document the match is in.
  final int sectionIndex;

  /// Block index, then cell row and column, then sub block, as deep as the
  /// match sits. A prose hit is one element long, a grid hit is four.
  final List<int> blockPath;

  /// Character offsets of the match inside the block's own text.
  final int start;
  final int end;

  /// A short window of surrounding text, for the find list.
  final String snippet;

  /// The section or sheet name the match was found under.
  final String label;

  @override
  String toString() =>
      'DocHit(s$sectionIndex ${blockPath.join(".")} $start..$end "$snippet")';
}

/// What every search strategy can answer.
abstract interface class DocSearch {
  /// Every match for [query], in document order. An empty query finds nothing.
  List<DocHit> search(String query);

  /// Pages, blocks or rows, whichever this document counts in. It is the scale
  /// the fore edge draws against.
  int get unitCount;

  /// Where [hit] falls down the whole document, 0 at the top and 1 at the end.
  double positionOf(DocHit hit);

  /// How many units the reader lays the whole document out in: top level
  /// blocks for prose, counted across every section, and rows for a grid.
  ///
  /// It is not always [unitCount]. The prose index also counts every table
  /// cell it walks into, and a reader that stepped by those would land on
  /// the wrong block.
  int get readerUnits;

  /// The unit, out of [readerUnits], that the reader lays [hit] out in.
  int unitOf(DocHit hit);
}

/// One searchable string and where it came from.
class DocIndexEntry {
  const DocIndexEntry(this.section, this.path, this.text, this.label);
  final int section;
  final List<int> path;
  final String text;
  final String label;
}

/// The prose strategy: walk the blocks once into a flat list, then scan it.
///
/// Building the list up front is worth it because a prose document is walked
/// on every keystroke and the walk is the expensive half, not the string
/// search.
class ProseSearch implements DocSearch {
  ProseSearch(QuireDocument doc) {
    for (var s = 0; s < doc.sections.length; s++) {
      _blocksBefore.add(_blocks);
      _blocks += doc.sections[s].blocks.length;
      _walk(doc.sections[s].blocks, s, const <int>[], doc.sections[s].title);
    }
    for (var i = 0; i < entries.length; i++) {
      _ordinal[_key(entries[i].section, entries[i].path)] = i;
    }
  }

  /// Every indexed block, in document order.
  final List<DocIndexEntry> entries = [];
  final Map<String, int> _ordinal = {};

  /// How many top level blocks come before each section, and in all.
  final List<int> _blocksBefore = [];
  int _blocks = 0;

  @override
  int get readerUnits => _blocks;

  @override
  int unitOf(DocHit hit) {
    if (_blocks <= 0) return 0;
    final before = hit.sectionIndex < _blocksBefore.length
        ? _blocksBefore[hit.sectionIndex]
        : 0;
    final block = hit.blockPath.isEmpty ? 0 : hit.blockPath.first;
    return (before + block).clamp(0, _blocks - 1);
  }

  static String _key(int section, List<int> path) => '$section/${path.join(".")}';

  void _walk(List<DocBlock> blocks, int section, List<int> path, String label) {
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final p = [...path, i];
      switch (b) {
        case ParagraphBlock():
          _add(section, p, b.text, label);
        case HeadingBlock():
          _add(section, p, b.text, label);
        case ListItemBlock():
          _add(section, p, b.text, label);
        case CodeBlock():
          _add(section, p, b.text, label);
        case ImageBlock():
          if (b.alt != null) _add(section, p, b.alt!, label);
        case TableBlock():
          for (var r = 0; r < b.rows.length; r++) {
            for (var c = 0; c < b.rows[r].cells.length; c++) {
              final cell = b.rows[r].cells[c];
              if (cell.merged) continue;
              _walk(cell.blocks, section, [...p, r, c], label);
            }
          }
        case SlideBlock():
          for (var i = 0; i < b.shapes.length; i++) {
            _walk(b.shapes[i].blocks, section, [...p, i], label);
          }
          // The notes go in after the slide, so a search finds what the
          // speaker was going to say as well as what the room could read, and
          // finds it after the slide it belongs to rather than before it.
          _walk(b.notes, section, [...p, b.shapes.length], label);
        case DividerBlock():
          break;
      }
    }
  }

  void _add(int section, List<int> path, String text, String label) {
    if (text.isEmpty) return;
    entries.add(DocIndexEntry(section, path, text, label));
  }

  @override
  List<DocHit> search(String query) {
    if (query.isEmpty) return const [];
    final needle = query.toLowerCase();
    final hits = <DocHit>[];
    for (final e in entries) {
      final hay = e.text.toLowerCase();
      var from = 0;
      while (true) {
        final at = hay.indexOf(needle, from);
        if (at < 0) break;
        hits.add(DocHit(e.section, e.path, at, at + needle.length,
            snippetAround(e.text, at, needle.length), e.label));
        from = at + needle.length;
      }
    }
    return hits;
  }

  @override
  int get unitCount => entries.length;

  @override
  double positionOf(DocHit hit) {
    if (entries.isEmpty) return 0;
    final at = _ordinal[_key(hit.sectionIndex, hit.blockPath)];
    if (at == null) return 0;
    return entries.length == 1 ? 0 : at / (entries.length - 1);
  }
}

/// The grid strategy: hold the tables and scan their cell text directly.
///
/// A per cell index of a real workbook measured slower than this scan and cost
/// a large multiple of the sheet in memory, so the cheapest correct thing is
/// also the fastest one.
class GridSearch implements DocSearch {
  GridSearch(this.document) {
    var rows = 0;
    for (var s = 0; s < document.sections.length; s++) {
      _rowsBefore.add(rows);
      for (final block in document.sections[s].blocks) {
        if (block is TableBlock) rows += block.rows.length;
      }
    }
    _totalRows = rows;
  }

  final QuireDocument document;
  final List<int> _rowsBefore = [];
  int _totalRows = 0;

  @override
  List<DocHit> search(String query) {
    if (query.isEmpty) return const [];
    final needle = query.toLowerCase();
    final hits = <DocHit>[];
    for (var s = 0; s < document.sections.length; s++) {
      final section = document.sections[s];
      for (var b = 0; b < section.blocks.length; b++) {
        final block = section.blocks[b];
        if (block is! TableBlock) continue;
        for (var r = 0; r < block.rows.length; r++) {
          final row = block.rows[r];
          for (var c = 0; c < row.cells.length; c++) {
            final cell = row.cells[c];
            if (cell.merged) continue;
            final text = cell.text;
            if (text.isEmpty) continue;
            final hay = text.toLowerCase();
            var from = 0;
            while (true) {
              final at = hay.indexOf(needle, from);
              if (at < 0) break;
              hits.add(DocHit(s, [b, r, c, 0], at, at + needle.length,
                  snippetAround(text, at, needle.length), section.title));
              from = at + needle.length;
            }
          }
        }
      }
    }
    return hits;
  }

  @override
  int get unitCount => _totalRows;

  @override
  int get readerUnits => _totalRows;

  @override
  int unitOf(DocHit hit) {
    final before =
        hit.sectionIndex < _rowsBefore.length ? _rowsBefore[hit.sectionIndex] : 0;
    final row = hit.blockPath.length > 1 ? hit.blockPath[1] : 0;
    return before + row;
  }

  @override
  double positionOf(DocHit hit) {
    if (_totalRows <= 1) return 0;
    final before =
        hit.sectionIndex < _rowsBefore.length ? _rowsBefore[hit.sectionIndex] : 0;
    final row = hit.blockPath.length > 1 ? hit.blockPath[1] : 0;
    return ((before + row) / (_totalRows - 1)).clamp(0.0, 1.0);
  }
}

/// The right strategy for a document, decided by its own [TableBlock.grid]
/// flag rather than by its file extension, so a Word table never accidentally
/// gets the grid treatment.
DocSearch searchFor(QuireDocument doc) {
  for (final section in doc.sections) {
    for (final block in section.blocks) {
      if (block is TableBlock && block.grid) return GridSearch(doc);
    }
  }
  return ProseSearch(doc);
}

/// A window of at most 24 characters either side of a match, for the find list.
String snippetAround(String text, int start, int length) {
  final from = (start - 24).clamp(0, text.length);
  final to = (start + length + 24).clamp(0, text.length);
  return text.substring(from, to);
}
