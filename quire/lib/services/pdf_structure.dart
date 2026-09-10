import 'dart:math' as math;

import '../model/document.dart';
import '../pdf/display_list.dart';
import '../pdf/document.dart';
import '../pdf/interpreter.dart';

/// Reads the shape of a page file back out of where its words sit.
///
/// A PDF states positions, not meaning. It does not say that a line is a
/// heading, that two lines are one paragraph, or that a page is set in two
/// columns; it says that these glyphs are at these points in this size. Every
/// converter that treats a page file as a run of lines produces something that
/// opens and that nobody can use.
///
/// So this reads the geometry the way a person does. Type that is markedly
/// bigger than the rest is a heading. A line that fills its column and does
/// not end a sentence runs into the next one. A strip down the page that no
/// word ever crosses is a gutter, and what is either side of it is a column.
/// The same words at the same height on most pages are a running head, and a
/// running head repeated forty times is not part of the text.
///
/// It is inference, and it is stated as inference: what comes out is better
/// than a list of lines and it is not the original.

/// How much bigger than the body a line must be set to read as a heading.
const kHeadingRatio = 1.18;

/// The ratios at which a heading becomes a level one and a level two.
const kHeading1Ratio = 1.75;
const kHeading2Ratio = 1.34;

/// How near the column's right edge a line must reach to count as full, which
/// is what says the sentence carried on rather than ended.
const kFullLineShare = 0.88;

/// How wide a strip with no word in it has to be to count as a gutter, as a
/// share of the text's own width.
const kGutterShare = 0.045;

/// How much of a page a column has to hold before the split is believed.
const kColumnShare = 0.18;

/// How many pages a line has to appear on, at the same height, before it is
/// taken for a running head rather than for text.
const kRunningHeadShare = 0.6;

/// How long a run may be and still be furniture. A sentence that repeats on
/// every page is a refrain the reader wrote, and it stays.
const kFurnitureLength = 80;

/// The page file as a document, with headings, paragraphs and lists inferred
/// from how the type is set.
QuireDocument pdfAsDocument(PdfFile file, String title) {
  final raw = <List<LaidOutRun>>[];
  for (var page = 0; page < file.pageCount; page++) {
    try {
      final list = ContentInterpreter(file).run(file.pages[page]);
      raw.add(mergeRuns(list.texts));
    } on Object {
      raw.add(const <LaidOutRun>[]);
    }
  }

  // The furniture is found among the runs, before anything is gathered into
  // lines. A running foot with the folio at the other end of it is one line on
  // a page of one column and two on a page of two, and the same foot counted
  // two different ways is a foot that never reaches the threshold.
  final furniture = _runningHeads(raw);
  final pages = <List<_Line>>[
    for (final page in raw)
      _pageLines(<LaidOutRun>[
        for (final run in page)
          if (!furniture.contains(_shapeOf(run))) run,
      ]),
  ];
  final body = _bodySize(pages);
  final sections = <DocSection>[];
  for (var i = 0; i < pages.length; i++) {
    final blocks = _blocksOf(pages[i], body);
    if (blocks.isEmpty) continue;
    sections.add(DocSection('', blocks, kind: 'page'));
  }
  return QuireDocument(
    title: title,
    sections: sections.isEmpty
        ? <DocSection>[const DocSection('', <DocBlock>[])]
        : sections,
    sourceFormat: 'pdf',
  );
}

// -- lines -------------------------------------------------------------------

/// Runs gathered onto the baselines they were set on.
///
/// The interpreter already merges runs that share a baseline and a style, so
/// what this joins is the pieces of one line that changed face partway along,
/// which is exactly where the bold in a sentence lives.
List<_Line> _linesOf(List<LaidOutRun> runs) {
  if (runs.isEmpty) return const <_Line>[];
  final sorted = List<LaidOutRun>.of(runs)
    ..sort((a, b) {
      final down = a.y.compareTo(b.y);
      return down != 0 ? down : a.x.compareTo(b.x);
    });
  final out = <_Line>[];
  var current = <LaidOutRun>[sorted.first];
  for (var i = 1; i < sorted.length; i++) {
    final run = sorted[i];
    final last = current.last;
    // A superscript sits on its own baseline a hair off the line's, so the
    // tolerance is a share of the type size rather than a fixed number, and
    // it is a share of the smaller of the two: a drop cap set four times the
    // body would otherwise reach far enough to gather in the lines above and
    // below it, and three lines of type would come out as one sentence with
    // no spaces where they met.
    if ((run.y - last.y).abs() <= math.min(last.size, run.size) * 0.5) {
      current.add(run);
    } else {
      out.add(_Line.of(current));
      current = <LaidOutRun>[run];
    }
  }
  out.add(_Line.of(current));
  return out;
}

// -- columns -----------------------------------------------------------------

/// One page's lines, in reading order, columns worked out first.
///
/// The split has to happen before the runs are gathered onto baselines,
/// because in a two column page the two columns share their baselines: the
/// first line of the left column and the first line of the right are at the
/// same height, and anything that groups by height alone reads them as one
/// sentence with a subject from one story and a verb from another.
List<_Line> _pageLines(List<LaidOutRun> runs) {
  final gutter = _gutterIn(runs);
  if (gutter == null) return _linesOf(runs);

  final across = <LaidOutRun>[];
  final left = <LaidOutRun>[];
  final right = <LaidOutRun>[];
  for (final run in runs) {
    if (run.x < gutter && run.x + run.width > gutter) {
      across.add(run);
    } else if (run.x + run.width <= gutter) {
      left.add(run);
    } else {
      right.add(run);
    }
  }

  // A line that runs the width of the page divides the page: what is above it
  // belongs to what came before, what is below it belongs to what follows. So
  // the page is read band by band, and inside a band down one column and then
  // the other. Reading every full width line first and then both columns
  // whole would put the running foot before the article and the standfirst
  // before the title it stands under.
  final bands = _linesOf(across);
  final first = _column(left);
  final second = _column(right);
  final out = <_Line>[];
  var from = -double.infinity;
  for (var i = 0; i <= bands.length; i++) {
    final to = i < bands.length ? bands[i].y : double.infinity;
    for (final line in first) {
      if (line.y > from && line.y < to) out.add(line);
    }
    for (final line in second) {
      if (line.y > from && line.y < to) out.add(line);
    }
    if (i < bands.length) out.add(bands[i]);
    from = to;
  }
  return out;
}

/// One column's lines, each told where its own column ends.
///
/// A line is judged full or short against the column it sits in. Measured
/// against the whole page, no line of a two column page ever reaches the far
/// side, and every one of them looks like the end of a paragraph.
List<_Line> _column(List<LaidOutRun> runs) {
  final lines = _linesOf(runs);
  var edge = -double.infinity;
  for (final line in lines) {
    edge = math.max(edge, line.right);
  }
  return <_Line>[for (final line in lines) line.inColumn(edge)];
}

/// The x of the strip no word crosses, or null when the page is one column.
double? _gutterIn(List<LaidOutRun> runs) {
  if (runs.length < 12) return null;
  var left = double.infinity;
  var right = -double.infinity;
  for (final run in runs) {
    left = math.min(left, run.x);
    right = math.max(right, run.x + run.width);
  }
  final span = right - left;
  if (span <= 0) return null;

  // The page across in fine strips, each marked where a word covers it.
  //
  // A line that runs the width of the page is left out of the marking. It is
  // the head or the standfirst sitting over both columns, and counting it
  // would fill in the very gap it stands over, which is how a two column page
  // with a title convinces a reader it has one column.
  const cells = 240;
  final covered = List<bool>.filled(cells, false);
  for (final run in runs) {
    if (run.width > span * 0.55) continue;
    final from = ((run.x - left) / span * cells).floor().clamp(0, cells - 1);
    final to = ((run.x + run.width - left) / span * cells).ceil().clamp(
      0,
      cells,
    );
    for (var i = from; i < to; i++) {
      covered[i] = true;
    }
  }

  var bestStart = -1;
  var bestRun = 0;
  var runStart = -1;
  for (var i = 0; i < cells; i++) {
    if (!covered[i]) {
      if (runStart < 0) runStart = i;
      continue;
    }
    if (runStart > 0 && i - runStart > bestRun) {
      bestRun = i - runStart;
      bestStart = runStart;
    }
    runStart = -1;
  }
  if (bestStart < 0 || bestRun / cells < kGutterShare) return null;

  final gutter = left + (bestStart + bestRun / 2) / cells * span;
  // A gap with almost nothing on one side of it is a margin or an indent, not
  // a gutter between two columns.
  var before = 0;
  var after = 0;
  for (final run in runs) {
    if (run.x + run.width <= gutter) {
      before += run.text.length;
    } else if (run.x >= gutter) {
      after += run.text.length;
    }
  }
  final total = before + after;
  if (total == 0) return null;
  final share = math.min(before, after) / total;
  return share < kColumnShare ? null : gutter;
}

// -- running heads -----------------------------------------------------------

/// The lines that are furniture rather than text.
///
/// A line counts when the same words appear at about the same height on most
/// of the pages. The numbers are taken out of the shape first, so a folio
/// reading `2` and one reading `37` are recognised as the same line.
Set<String> _runningHeads(List<List<LaidOutRun>> pages) {
  if (pages.length < 3) return const <String>{};
  final seen = <String, int>{};
  for (final page in pages) {
    for (final shape in <String>{
      for (final run in page)
        if (run.text.trim().length <= kFurnitureLength) _shapeOf(run),
    }) {
      seen[shape] = (seen[shape] ?? 0) + 1;
    }
  }
  final needed = (pages.length * kRunningHeadShare).ceil();
  return <String>{
    for (final entry in seen.entries)
      if (entry.value >= needed) entry.key,
  };
}

/// A line as the thing that would repeat: its words without their numbers, and
/// roughly where down the page it sat.
String _shapeOf(LaidOutRun line) {
  final words = line.text
      .replaceAll(RegExp(r'\d+'), '#')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  return '${(line.y / 24).round()}|$words';
}

// -- blocks ------------------------------------------------------------------

/// The size most of the document's letters are set in.
///
/// Weighted by how many characters are set in each size, so a page of body
/// text with one big title reports the body, which is the number every other
/// judgement here is made against.
double _bodySize(List<List<_Line>> pages) {
  final weight = <double, int>{};
  for (final page in pages) {
    for (final line in page) {
      for (final piece in line.pieces) {
        final size = (piece.size * 2).round() / 2;
        weight[size] = (weight[size] ?? 0) + piece.text.length;
      }
    }
  }
  if (weight.isEmpty) return 10;
  var best = 10.0;
  var most = -1;
  for (final entry in weight.entries) {
    if (entry.value > most) {
      most = entry.value;
      best = entry.key;
    }
  }
  return best;
}

List<DocBlock> _blocksOf(List<_Line> lines, double body) {
  if (lines.isEmpty) return const <DocBlock>[];
  var widest = -double.infinity;
  for (final line in lines) {
    widest = math.max(widest, line.right);
  }

  final out = <DocBlock>[];
  List<DocSpan>? open;
  _Line? previous;

  // A drop cap is one letter set three lines tall at the head of a paragraph.
  // Its baseline is the third of those lines, so read by height alone it
  // lands in the middle of a sentence it is meant to begin.
  var dropped = '';

  void close() {
    var held = open;
    if (held != null && held.isNotEmpty) {
      // The letter goes back to the front of the paragraph it opened, which is
      // the one that starts lower case where the cap was lifted out of it.
      if (dropped.isNotEmpty && _opensLower(held)) {
        held = <DocSpan>[DocSpan(dropped), ...held];
        dropped = '';
      }
      out.add(ParagraphBlock(held));
    }
    open = null;
  }

  for (final raw in lines) {
    final cap = _dropCapIn(raw, body);
    final line = cap == null ? raw : cap.$2;
    if (cap != null) dropped = cap.$1;
    if (line.text.trim().isEmpty) continue;
    final level = _headingLevel(line, body);
    if (level != null) {
      close();
      out.add(HeadingBlock(level, line.spans));
      previous = line;
      continue;
    }
    final bullet = _bulletOf(line.text);
    if (bullet != null) {
      close();
      out.add(
        ListItemBlock(
          <DocSpan>[DocSpan(line.text.substring(bullet.$2).trim())],
          level: 0,
          ordered: bullet.$1,
        ),
      );
      previous = line;
      continue;
    }

    // A line that reached the far side of its column and did not finish a
    // sentence is the same paragraph carrying on.
    final spans = line.spans;
    final before = previous;
    final joins =
        open != null &&
        before != null &&
        before.right >= (before.columnRight ?? widest) * kFullLineShare &&
        !_ends(before.text) &&
        (line.y - before.y).abs() < body * 2.4;
    if (joins) {
      open!.add(const DocSpan(' '));
      open!.addAll(spans);
    } else {
      close();
      open = <DocSpan>[...spans];
    }
    previous = line;
  }
  close();
  return out;
}

/// The drop cap inside [line], and the line with it taken out.
///
/// A drop cap is one letter set two or three lines tall at the head of a
/// paragraph. Its baseline is the last of those lines, so a reader that
/// gathers runs by height finds it sitting in the middle of the sentence it
/// was meant to begin, which is where `travelled P on the wire` comes from.
(String, _Line)? _dropCapIn(_Line line, double body) {
  if (line.pieces.length < 2) {
    if (line.pieces.length == 1 &&
        line.pieces.first.text.trim().length == 1 &&
        line.pieces.first.size >= body * 1.8) {
      return (line.pieces.first.text.trim(), _Line(const <LaidOutRun>[], 0, 0,
          line.y));
    }
    return null;
  }
  for (final piece in line.pieces) {
    if (piece.text.trim().length != 1) continue;
    if (piece.size < body * 1.8) continue;
    final rest = <LaidOutRun>[
      for (final other in line.pieces)
        if (!identical(other, piece)) other,
    ];
    if (rest.isEmpty) {
      return (piece.text.trim(), _Line(const <LaidOutRun>[], 0, 0, line.y));
    }
    return (piece.text.trim(), _Line.of(rest));
  }
  return null;
}

/// True when the paragraph begins with a lower case letter, which is what a
/// paragraph looks like once its opening capital has been lifted off it.
bool _opensLower(List<DocSpan> spans) {
  for (final span in spans) {
    final text = span.text.trimLeft();
    if (text.isEmpty) continue;
    final first = text[0];
    return first.toLowerCase() == first && first.toUpperCase() != first;
  }
  return false;
}

/// The heading level of [line], or null when it is not one.
int? _headingLevel(_Line line, double body) {
  final size = line.size;
  final ratio = size / body;
  // Bold, short and a touch larger is a subheading even where the size alone
  // would not carry it.
  //  A standing head is often set at the body size in bold small capitals,
  // which is a heading to every eye and the same number of points to a
  // machine reading sizes alone.
  final shout =
      line.bold &&
      line.text.length <= 60 &&
      line.text == line.text.toUpperCase() &&
      RegExp('[A-Z]').hasMatch(line.text);
  final emphatic = line.bold && ratio >= 1.04 && line.text.length <= 80;
  if (ratio < kHeadingRatio && !emphatic && !shout) return null;
  if (shout && ratio < kHeading2Ratio) return 3;
  if (line.text.length > 160) return null;
  if (ratio >= kHeading1Ratio) return 1;
  if (ratio >= kHeading2Ratio) return 2;
  return 3;
}

/// Whether [text] opens a list item, whether it is numbered, and how many
/// characters the marker took.
(bool, int)? _bulletOf(String text) {
  final trimmed = text.trimLeft();
  final lost = text.length - trimmed.length;
  for (final mark in const <String>['•', '‣', '◦', '-', '*']) {
    if (trimmed.startsWith('$mark ')) return (false, lost + mark.length);
  }
  final numbered = RegExp(r'^(\d{1,3})[.)]\s').firstMatch(trimmed);
  if (numbered != null) return (true, lost + numbered.end);
  return null;
}

/// True when [text] finished what it was saying.
///
/// A colon and a semicolon are not endings. A sentence that reaches the far
/// side of the column on a colon is a sentence about to say what follows it,
/// and breaking there is breaking mid thought.
bool _ends(String text) {
  final trimmed = text.trimRight();
  if (trimmed.isEmpty) return true;
  return RegExp(r'[.!?•”")\]]$').hasMatch(trimmed);
}

// -- the line ----------------------------------------------------------------

class _Line {
  _Line(this.pieces, this.left, this.right, this.y, [this.columnRight]);

  /// The same line, told where the column it sits in ends.
  _Line inColumn(double edge) => _Line(pieces, left, right, y, edge);

  factory _Line.of(List<LaidOutRun> runs) {
    final sorted = List<LaidOutRun>.of(runs)..sort((a, b) => a.x.compareTo(b.x));
    var left = double.infinity;
    var right = -double.infinity;
    for (final run in sorted) {
      left = math.min(left, run.x);
      right = math.max(right, run.x + run.width);
    }
    return _Line(sorted, left, right, sorted.first.y);
  }

  final List<LaidOutRun> pieces;
  final double left;
  final double right;
  final double y;

  /// Where this line's own column ends, or null on a page of one column.
  final double? columnRight;

  /// The whole line, with a space wherever two pieces did not touch.
  String get text {
    final out = StringBuffer();
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      if (i > 0) {
        final gap = piece.x - (pieces[i - 1].x + pieces[i - 1].width);
        final wants = gap > piece.size * 0.18;
        final joined = out.toString();
        if (wants && !joined.endsWith(' ') && !piece.text.startsWith(' ')) {
          out.write(' ');
        }
      }
      out.write(piece.text);
    }
    return out.toString();
  }

  /// The line as spans, so the bold inside a sentence survives the trip.
  List<DocSpan> get spans => <DocSpan>[
    for (var i = 0; i < pieces.length; i++)
      DocSpan(
        i == 0 ? pieces[i].text : _spaced(i),
        bold: pieces[i].bold,
        italic: pieces[i].italic,
        mono: pieces[i].mono,
      ),
  ];

  String _spaced(int i) {
    final piece = pieces[i];
    final gap = piece.x - (pieces[i - 1].x + pieces[i - 1].width);
    final wants =
        gap > piece.size * 0.18 &&
        !pieces[i - 1].text.endsWith(' ') &&
        !piece.text.startsWith(' ');
    return wants ? ' ${piece.text}' : piece.text;
  }

  /// The size the line is mostly set in.
  double get size {
    var best = 0.0;
    var most = -1;
    final weight = <double, int>{};
    for (final piece in pieces) {
      final at = (piece.size * 2).round() / 2;
      final now = (weight[at] ?? 0) + piece.text.length;
      weight[at] = now;
      if (now > most) {
        most = now;
        best = at;
      }
    }
    return best;
  }

  /// True when most of the line is bold.
  bool get bold {
    var heavy = 0;
    var light = 0;
    for (final piece in pieces) {
      if (piece.bold) {
        heavy += piece.text.length;
      } else {
        light += piece.text.length;
      }
    }
    return heavy > light;
  }
}
