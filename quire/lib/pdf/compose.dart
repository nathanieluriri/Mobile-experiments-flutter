import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/document.dart';
import 'truetype.dart';

/// The page, in points, and the margins type is set inside.
const kComposeWidth = 595.28;
const kComposeHeight = 841.89;
const kComposeMargin = 56.0;

/// The sizes and the air around each kind of block.
const kComposeBody = 10.5;
const kComposeLeading = 1.45;
const kComposeParaGap = 8.0;
const kComposeListIndent = 16.0;
const kComposeRuleGap = 10.0;
const kComposeTableGap = 6.0;
const kComposeCellPad = 4.0;

/// The folio, set small at the foot of every page.
const kComposeFolio = 8.5;
const kComposeFolioDrop = 26.0;

/// A heading's size and the air above and below it, by level.
const kComposeHeadings = <int, (double, double, double)>{
  1: (19, 20, 9),
  2: (15.5, 16, 7),
  3: (13, 13, 6),
};

/// Sets a document as a fresh PDF.
///
/// This is a typesetter, not a copier. Nothing of the original's design comes
/// across, because for every format but PDF the original never stated one: a
/// Word file names styles, a spreadsheet names cells, and Markdown names
/// nothing at all. What comes out is the document read cleanly in one
/// typeface, which is the honest thing to make out of what is actually known.
///
/// The typeface is embedded, cut down to the glyphs the document uses, so the
/// file opens the same everywhere and stays a reasonable size doing it.
class PdfComposer {
  PdfComposer({
    required this.regular,
    required this.bold,
    this.width = kComposeWidth,
    this.height = kComposeHeight,
    this.margin = kComposeMargin,
  });

  /// Reads the two faces the composer sets in.
  factory PdfComposer.of(Uint8List regular, Uint8List bold) => PdfComposer(
    regular: TrueTypeFont.parse(regular),
    bold: TrueTypeFont.parse(bold),
  );

  final TrueTypeFont regular;
  final TrueTypeFont bold;
  final double width;
  final double height;
  final double margin;

  double get _column => width - margin * 2;

  /// What the composer could not carry, in the same words the convert sheet
  /// uses for everything else it drops.
  final List<String> warnings = <String>[];

  /// Every glyph each face was actually asked for, which is what the subset
  /// keeps and everything else it throws away.
  final Set<int> _regularGlyphs = <int>{};
  final Set<int> _boldGlyphs = <int>{};

  /// The unicode behind each glyph, so the text can be pulled back out of the
  /// page it was set on.
  ///
  /// Without this a converted page reads perfectly and searches as nothing:
  /// the page states glyph numbers, and only this says what letters they
  /// were. A reader that cannot find a word in a file it made itself is a
  /// reader that has produced a picture of a document.
  final Map<int, int> _regularText = <int, int>{};
  final Map<int, int> _boldText = <int, int>{};

  /// Sets [document] and returns the file.
  Uint8List compose(QuireDocument document) {
    final lines = <_Line>[];
    for (final section in document.sections) {
      if (document.sections.length > 1 && section.title.isNotEmpty) {
        _heading(lines, section.title, 1);
      }
      _blocks(section.blocks, lines, 0);
    }
    return _write(_paginate(lines), document.title);
  }

  // -- laying the words out --------------------------------------------------

  void _blocks(List<DocBlock> blocks, List<_Line> out, int indent) {
    for (final block in blocks) {
      switch (block) {
        case SlideBlock():
          // A slide composes as its title and then everything on it, in the
          // order the deck drew it. Its layout cannot survive being poured
          // into a column, and its words can.
          final named = block.title;
          if (named != null && named.isNotEmpty) _heading(out, named, 1);
          for (final shape in block.shapes) {
            if (shape.role == SlideRole.title) continue;
            _blocks(shape.blocks, out, indent);
          }
          _blocks(block.notes, out, (indent + kComposeListIndent).round());
        case HeadingBlock():
          _heading(out, block.text, block.level);
        case ParagraphBlock():
          if (block.text.trim().isEmpty) break;
          _wrap(
            out,
            block.spans,
            kComposeBody,
            indent + block.indent * kComposeListIndent,
            gapAfter: kComposeParaGap,
            quote: block.quote,
          );
        case ListItemBlock():
          final at = indent + (block.level + 1) * kComposeListIndent;
          _wrap(
            out,
            block.spans,
            kComposeBody,
            at,
            bullet: block.ordered ? null : '•',
            gapAfter: 3,
          );
        case CodeBlock():
          for (final line in block.text.split('\n')) {
            _wrap(
              out,
              <DocSpan>[DocSpan(line)],
              kComposeBody - 1,
              indent + kComposeListIndent,
              gapAfter: 0,
              wrapping: false,
            );
          }
          out.add(_Line.gap(kComposeParaGap));
        case DividerBlock():
          out.add(_Line.rule(indent.toDouble()));
        case ImageBlock():
          warnings.add(
            'A picture cannot be set from what was read of it, so the '
            'pictures were left out.',
          );
        case TableBlock():
          _table(block, out, indent);
      }
    }
  }

  void _heading(List<_Line> out, String text, int level) {
    final (size, before, after) =
        kComposeHeadings[level.clamp(1, 3)] ?? kComposeHeadings[3]!;
    if (out.isNotEmpty) out.add(_Line.gap(before));
    _wrap(
      out,
      <DocSpan>[DocSpan(text, bold: true)],
      size,
      0,
      gapAfter: after,
      keepWithNext: true,
    );
  }

  /// Breaks [spans] into lines that fit the column, and adds them to [out].
  void _wrap(
    List<_Line> out,
    List<DocSpan> spans,
    double size,
    double indent, {
    double gapAfter = 0,
    String? bullet,
    bool quote = false,
    bool wrapping = true,
    bool keepWithNext = false,
  }) {
    final room = _column - indent;
    // The bullet is set like any other letter and has to be counted like one:
    // a glyph nobody asked for is a glyph the subset throws away, and a bullet
    // thrown away is a list that lost its marks.
    if (bullet != null) _note(regular, bullet);
    var pieces = <_Piece>[];
    var used = 0.0;
    var first = true;

    void flush({bool last = false}) {
      if (pieces.isEmpty && !last) return;
      out.add(
        _Line(
          pieces: pieces,
          size: size,
          indent: indent,
          bullet: first ? bullet : null,
          quote: quote,
          gapAfter: last ? gapAfter : 0,
          keepWithNext: keepWithNext && last,
        ),
      );
      pieces = <_Piece>[];
      used = 0;
      first = false;
    }

    for (final span in spans) {
      final font = span.bold ? bold : regular;
      // A word and the space in front of it travel together, so a line never
      // starts with the space that ended the one above it.
      for (final word in _words(span.text)) {
        final advance = font.measure(word, size);
        if (wrapping && used > 0 && used + advance > room) {
          flush();
          final trimmed = word.trimLeft();
          if (trimmed.isEmpty) continue;
          _note(font, trimmed);
          pieces.add(_Piece(trimmed, span.bold, font.measure(trimmed, size)));
          used = font.measure(trimmed, size);
          continue;
        }
        _note(font, word);
        pieces.add(_Piece(word, span.bold, advance));
        used += advance;
      }
    }
    flush(last: true);
  }

  /// Words, each carrying the space that came before it.
  static List<String> _words(String text) {
    final out = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (char == ' ' || char == '\t') {
        if (buffer.isNotEmpty) {
          out.add(buffer.toString());
          buffer.clear();
        }
        buffer.write(' ');
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) out.add(buffer.toString());
    return out;
  }

  void _table(TableBlock table, List<_Line> out, int indent) {
    if (table.rows.isEmpty) return;
    var columns = 0;
    for (final row in table.rows) {
      final live = row.cells.where((c) => !c.merged).length;
      if (live > columns) columns = live;
    }
    if (columns == 0) return;
    if (columns > 8) {
      warnings.add(
        'A table $columns columns wide will not fit a page this size, so it '
        'was set narrow and some cells run into each other.',
      );
    }
    final cellWidth = _column / columns;
    out.add(_Line.gap(kComposeTableGap));
    for (final row in table.rows) {
      final cells = <String>[
        for (final cell in row.cells)
          if (!cell.merged) cell.text.replaceAll('\n', ' '),
      ];
      final pieces = <_Piece>[];
      final font = row.header ? bold : regular;
      for (var i = 0; i < columns; i++) {
        final text = i < cells.length ? cells[i] : '';
        final clipped = _clip(font, text, kComposeBody - 1, cellWidth);
        _note(font, clipped);
        pieces.add(
          _Piece(
            clipped,
            row.header,
            font.measure(clipped, kComposeBody - 1),
            at: i * cellWidth + kComposeCellPad,
          ),
        );
      }
      out.add(
        _Line(
          pieces: pieces,
          size: kComposeBody - 1,
          indent: indent.toDouble(),
          gapAfter: 2,
          ruleUnder: row.header,
        ),
      );
    }
    out.add(_Line.gap(kComposeTableGap));
  }

  /// [text] cut to [room], with an ellipsis where it was cut.
  String _clip(TrueTypeFont font, String text, double size, double room) {
    final space = room - kComposeCellPad * 2;
    if (font.measure(text, size) <= space) return text;
    var cut = text;
    while (cut.isNotEmpty && font.measure('$cut…', size) > space) {
      cut = cut.substring(0, cut.length - 1);
    }
    return '$cut…';
  }

  /// Records every glyph a face has been asked for.
  void _note(TrueTypeFont font, String text) {
    final glyphs = font == bold ? _boldGlyphs : _regularGlyphs;
    final map = font == bold ? _boldText : _regularText;
    for (final rune in text.runes) {
      final gid = font.glyphFor(rune);
      glyphs.add(gid);
      map.putIfAbsent(gid, () => rune);
    }
  }

  // -- filling pages ---------------------------------------------------------

  List<List<_Placed>> _paginate(List<_Line> lines) {
    final pages = <List<_Placed>>[];
    var page = <_Placed>[];
    final top = height - margin;
    final floor = margin + kComposeFolioDrop;
    var y = top;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isGap) {
        // A gap at the top of a page is a page starting with nothing.
        if (y < top) y -= line.gapAfter;
        continue;
      }
      final tall = line.size * kComposeLeading;
      // A heading alone at the foot of a page is a heading on the wrong page.
      final needs = line.keepWithNext ? tall * 2.4 : tall;
      if (y - needs < floor && page.isNotEmpty) {
        pages.add(page);
        page = <_Placed>[];
        y = top;
      }
      y -= tall;
      page.add(_Placed(line, y));
      y -= line.gapAfter;
    }
    if (page.isNotEmpty) pages.add(page);
    if (pages.isEmpty) pages.add(<_Placed>[]);
    return pages;
  }

  // -- writing the file ------------------------------------------------------

  Uint8List _write(List<List<_Placed>> pages, String title) {
    final objects = <int, List<int>>{};
    var next = 1;
    int take() => next++;

    final catalogue = take();
    final tree = take();
    final regularFont = take();
    final boldFont = take();
    final pageIds = <int>[for (var i = 0; i < pages.length; i++) take()];
    final contentIds = <int>[for (var i = 0; i < pages.length; i++) take()];

    for (var i = 0; i < pages.length; i++) {
      final stream = _content(pages[i], i + 1, pages.length);
      final packed = Uint8List.fromList(
        const ZLibEncoder().encodeBytes(stream),
      );
      objects[contentIds[i]] = <int>[
        ...latin1.encode(
          '<< /Length ${packed.length} /Filter /FlateDecode >>\nstream\n',
        ),
        ...packed,
        ...latin1.encode('\nendstream'),
      ];
      objects[pageIds[i]] = latin1.encode(
        '<< /Type /Page /Parent $tree 0 R '
        '/MediaBox [0 0 ${_n(width)} ${_n(height)}] '
        '/Resources << /Font << /F1 $regularFont 0 R /F2 $boldFont 0 R >> >> '
        '/Contents ${contentIds[i]} 0 R >>',
      );
    }

    objects[catalogue] = latin1.encode(
      '<< /Type /Catalog /Pages $tree 0 R >>',
    );
    objects[tree] = latin1.encode(
      '<< /Type /Pages /Count ${pages.length} /Kids ['
      '${pageIds.map((id) => '$id 0 R').join(' ')}] >>',
    );

    _font(objects, take, regularFont, regular, _regularGlyphs, _regularText,
        'Inter', false);
    _font(objects, take, boldFont, bold, _boldGlyphs, _boldText, 'Inter-Bold',
        true);

    return _serialise(objects, catalogue, title, next);
  }

  /// The one page's drawing commands.
  List<int> _content(List<_Placed> page, int folio, int folios) {
    final out = StringBuffer();
    out.writeln('BT');
    var face = '';
    var size = 0.0;
    for (final placed in page) {
      final line = placed.line;
      if (line.isRule) continue;
      var x = margin + line.indent;
      if (line.quote) x += kComposeListIndent;
      final bullet = line.bullet;
      if (bullet != null) {
        _piece(out, bullet, false, line.size, x - kComposeListIndent, placed.y,
            face, size);
        face = 'F1';
        size = line.size;
      }
      for (final piece in line.pieces) {
        final at = piece.at;
        final wantFace = piece.bold ? 'F2' : 'F1';
        _piece(out, piece.text, piece.bold, line.size,
            at == null ? x : margin + line.indent + at, placed.y, face, size);
        face = wantFace;
        size = line.size;
        if (at == null) x += piece.advance;
      }
    }
    // The folio, centred, in the same face as the body.
    final label = '$folio of $folios';
    final at = (width - regular.measure(label, kComposeFolio)) / 2;
    _note(regular, label);
    _piece(out, label, false, kComposeFolio, at, margin, face, size);
    out.writeln('ET');

    // Rules are drawn outside the text object, because a rule is not type.
    out.writeln('0.72 G 0.6 w');
    for (final placed in page) {
      final line = placed.line;
      if (!line.isRule && !line.ruleUnder) continue;
      final y = line.isRule
          ? placed.y + line.size * 0.4
          : placed.y - line.size * 0.28;
      out.writeln(
        '${_n(margin + line.indent)} ${_n(y)} m '
        '${_n(width - margin)} ${_n(y)} l S',
      );
    }
    return latin1.encode(out.toString());
  }

  void _piece(
    StringBuffer out,
    String text,
    bool bold,
    double size,
    double x,
    double y,
    String face,
    double lastSize,
  ) {
    if (text.isEmpty) return;
    final wanted = bold ? 'F2' : 'F1';
    if (wanted != face || size != lastSize) {
      out.writeln('/$wanted ${_n(size)} Tf');
    }
    out.writeln('1 0 0 1 ${_n(x)} ${_n(y)} Tm');
    final font = bold ? this.bold : regular;
    final hex = StringBuffer();
    for (final rune in text.runes) {
      hex.write(font.glyphFor(rune).toRadixString(16).padLeft(4, '0'));
    }
    out.writeln('<$hex> Tj');
  }

  /// The four objects one embedded face needs.
  void _font(
    Map<int, List<int>> objects,
    int Function() take,
    int id,
    TrueTypeFont font,
    Set<int> glyphs,
    Map<int, int> text,
    String name,
    bool bold,
  ) {
    final descendant = take();
    final descriptor = take();
    final file = take();
    final toUnicode = take();

    objects[id] = latin1.encode(
      '<< /Type /Font /Subtype /Type0 /BaseFont /$name '
      '/Encoding /Identity-H /DescendantFonts [$descendant 0 R] '
      '/ToUnicode $toUnicode 0 R >>',
    );
    objects[descendant] = latin1.encode(
      '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /$name '
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) '
      '/Supplement 0 >> /FontDescriptor $descriptor 0 R '
      '/DW 0 /W [${_widths(font, glyphs)}] /CIDToGIDMap /Identity >>',
    );
    final scale = 1000 / font.unitsPerEm;
    objects[descriptor] = latin1.encode(
      '<< /Type /FontDescriptor /FontName /$name /Flags 32 '
      '/FontBBox [${_n(font.bbox[0] * scale)} ${_n(font.bbox[1] * scale)} '
      '${_n(font.bbox[2] * scale)} ${_n(font.bbox[3] * scale)}] '
      '/ItalicAngle 0 /Ascent ${_n(font.ascender * scale)} '
      '/Descent ${_n(font.descender * scale)} /CapHeight '
      '${_n(font.ascender * scale * 0.72)} /StemV ${bold ? 140 : 80} '
      '/FontFile2 $file 0 R >>',
    );

    final subset = font.subset(glyphs);
    final packed = Uint8List.fromList(
      const ZLibEncoder().encodeBytes(subset),
    );
    objects[file] = <int>[
      ...latin1.encode(
        '<< /Length ${packed.length} /Filter /FlateDecode '
        '/Length1 ${subset.length} >>\nstream\n',
      ),
      ...packed,
      ...latin1.encode('\nendstream'),
    ];

    final cmap = _toUnicode(text);
    objects[toUnicode] = <int>[
      ...latin1.encode('<< /Length ${cmap.length} >>\nstream\n'),
      ...latin1.encode(cmap),
      ...latin1.encode('\nendstream'),
    ];
  }

  /// The widths array, one entry per glyph the document actually used.
  static String _widths(TrueTypeFont font, Set<int> glyphs) {
    final sorted = glyphs.toList()..sort();
    final out = StringBuffer();
    for (final gid in sorted) {
      out.write('$gid [${_n(font.widthOf(gid))}] ');
    }
    return out.toString().trimRight();
  }

  /// The map from glyph back to letter, which is what lets the words be found
  /// and copied out again.
  static String _toUnicode(Map<int, int> text) {
    final entries = text.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final out = StringBuffer()
      ..writeln('/CIDInit /ProcSet findresource begin')
      ..writeln('12 dict begin begincmap')
      ..writeln('/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) '
          '/Supplement 0 >> def')
      ..writeln('/CMapName /Adobe-Identity-UCS def')
      ..writeln('/CMapType 2 def')
      ..writeln('1 begincodespacerange')
      ..writeln('<0000> <FFFF>')
      ..writeln('endcodespacerange');
    // A bfchar run may hold at most a hundred entries.
    for (var at = 0; at < entries.length; at += 100) {
      final run = entries.sublist(
        at,
        at + 100 > entries.length ? entries.length : at + 100,
      );
      out.writeln('${run.length} beginbfchar');
      for (final entry in run) {
        out.writeln(
          '<${entry.key.toRadixString(16).padLeft(4, '0')}> '
          '<${_utf16(entry.value)}>',
        );
      }
      out.writeln('endbfchar');
    }
    out
      ..writeln('endcmap CMapName currentdict /CMap defineresource pop')
      ..writeln('end end');
    return out.toString();
  }

  /// A rune as the big endian UTF-16 a bfchar states it in.
  static String _utf16(int rune) {
    if (rune <= 0xFFFF) return rune.toRadixString(16).padLeft(4, '0');
    final v = rune - 0x10000;
    final high = 0xD800 + (v >> 10);
    final low = 0xDC00 + (v & 0x3FF);
    return high.toRadixString(16).padLeft(4, '0') +
        low.toRadixString(16).padLeft(4, '0');
  }

  /// The objects, an xref table and a trailer, in that order.
  Uint8List _serialise(
    Map<int, List<int>> objects,
    int catalogue,
    String title,
    int count,
  ) {
    final out = BytesBuilder();
    // The binary comment is what tells a transfer this is not a text file.
    out.add(latin1.encode('%PDF-1.7\n%\xE2\xE3\xCF\xD3\n'));
    final offsets = <int, int>{};
    final ids = objects.keys.toList()..sort();
    for (final id in ids) {
      offsets[id] = out.length;
      out
        ..add(latin1.encode('$id 0 obj\n'))
        ..add(objects[id]!)
        ..add(latin1.encode('\nendobj\n'));
    }

    final info = count;
    offsets[info] = out.length;
    out.add(
      latin1.encode(
        '$info 0 obj\n<< /Title (${_string(title)}) '
        '/Producer (quire) >>\nendobj\n',
      ),
    );

    final startxref = out.length;
    final total = count + 1;
    final xref = StringBuffer()
      ..writeln('xref')
      ..writeln('0 $total')
      ..write('0000000000 65535 f \n');
    for (var id = 1; id < total; id++) {
      final at = offsets[id];
      xref.write(
        at == null
            ? '0000000000 65535 f \n'
            : '${at.toString().padLeft(10, '0')} 00000 n \n',
      );
    }
    out
      ..add(latin1.encode(xref.toString()))
      ..add(
        latin1.encode(
          'trailer\n<< /Size $total /Root $catalogue 0 R /Info $info 0 R >>\n'
          'startxref\n$startxref\n%%EOF\n',
        ),
      );
    return out.toBytes();
  }

  /// A literal string with the three characters that would end it escaped.
  static String _string(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .replaceAll(RegExp(r'[^\x20-\x7e]'), '');

  /// A number as a page file states one: no exponent, no trailing zeros.
  static String _n(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

/// One piece of a line: a run of text in one face.
class _Piece {
  const _Piece(this.text, this.bold, this.advance, {this.at});

  final String text;
  final bool bold;
  final double advance;

  /// Where the piece starts, measured from the line's own left edge, for a
  /// table cell that sits in a column rather than after the piece before it.
  final double? at;
}

/// One line of the document, before it knows which page it is on.
class _Line {
  const _Line({
    required this.pieces,
    required this.size,
    required this.indent,
    this.bullet,
    this.quote = false,
    this.gapAfter = 0,
    this.keepWithNext = false,
    this.ruleUnder = false,
  }) : isRule = false;

  /// Air, which a page break swallows.
  const _Line.gap(double height)
    : pieces = const <_Piece>[],
      size = 0,
      indent = 0,
      bullet = null,
      quote = false,
      gapAfter = height,
      keepWithNext = false,
      ruleUnder = false,
      isRule = false;

  const _Line.rule(this.indent)
    : pieces = const <_Piece>[],
      size = kComposeRuleGap,
      bullet = null,
      quote = false,
      gapAfter = kComposeRuleGap,
      keepWithNext = false,
      ruleUnder = false,
      isRule = true;

  final List<_Piece> pieces;
  final double size;
  final double indent;
  final String? bullet;
  final bool quote;
  final double gapAfter;

  /// True for a heading, which must not be the last thing on a page.
  final bool keepWithNext;

  /// True for a table's header row.
  final bool ruleUnder;

  final bool isRule;

  bool get isGap => pieces.isEmpty && !isRule;
}

/// A line with a page and a baseline behind it.
class _Placed {
  const _Placed(this.line, this.y);
  final _Line line;
  final double y;
}
