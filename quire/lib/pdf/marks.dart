import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'document.dart';
import 'encodings.dart' show decodePdfText;
import 'objects.dart';
import 'writer.dart';

/// An annotation already on a page, as the mark editor holds it.
class FoundMark {
  const FoundMark(
    this.origin,
    this.subtype,
    this.edit, {
    this.hasLook = true,
    bool? movable,
    bool? resizable,
    this.outline,
    this.anchored = false,
    this.note,
  })  : movable = movable ?? (edit is! HighlightEdit && edit is! StrikeEdit),
        resizable = resizable ?? (edit is! HighlightEdit && edit is! StrikeEdit);

  final MarkOrigin origin;

  /// False for a mark whose file gives it no appearance, which quire draws
  /// from [edit] and writes again, appearance and all, when it is touched.
  final bool hasLook;

  /// The annotation's /Subtype.
  final String subtype;

  /// A kind quire writes itself, as the edit that would write it again, and
  /// anything else it can move, as a [KeptEdit] keeping its own look.
  final PageEdit edit;

  /// False for marks that belong to the words under them, highlights,
  /// underlines, strikes, which stay where they are.
  final bool movable;

  /// False for a mark that is an icon of fixed size, such as a note.
  final bool resizable;

  /// A sticky note's words, which open from its icon.
  final String? note;

  /// The lines a mark is drawn with, in the reader's points, for one that
  /// is picked up by its lines rather than anywhere in its box: an outline
  /// with nothing inside it, a line, a drawing.
  final List<List<Offset>>? outline;

  /// True for a box of words with a callout line pointing at something on
  /// the page, whose box does not grow by itself, so the line stays on
  /// what it points at.
  final bool anchored;
}

/// The marks on page [index] that the editor can pick up: words, ink,
/// highlights and strikes as themselves, and stamps and boxes kept as they
/// look. Links, form fields, note windows and anything hidden are left
/// alone, and so is a mark with no appearance to draw it by.
List<FoundMark> readMarks(PdfFile file, int index) {
  final pages = file.pages;
  if (index < 0 || index >= pages.length) return const <FoundMark>[];
  final page = pages[index];
  final annots = file.resolve(page['Annots']);
  if (annots is! List) return const <FoundMark>[];
  final place = PagePlace.of(file, page);
  final out = <FoundMark>[];
  final count = annots.length < 2000 ? annots.length : 2000;
  for (var i = 0; i < count; i++) {
    final annot = file.dict(annots[i]);
    if (annot == null) continue;
    final flags = _int(file, annot['F']);
    // Hidden, not shown on screen, read only, or locked against being
    // moved, sized or deleted.
    if (flags & 2 != 0 || flags & 32 != 0 || flags & 64 != 0 || flags & 128 != 0) continue;
    final subtype = file.resolve(annot['Subtype']);
    if (subtype is! PdfName) continue;
    final rect = _numbers(file, annot['Rect']);
    if (rect == null || rect.length != 4) continue;
    final bounds = place.readerRect(rect);
    final origin = MarkOrigin(index, i);
    final hasLook = file.dict(annot['AP']) != null;
    // Words locked against change can still be moved and taken off, as
    // they look.
    final wordsLocked = flags & 512 != 0;
    final kept = hasLook ? KeptEdit(index, rect: bounds, origin: origin) : null;
    final PageEdit? edit = switch (subtype.value) {
      'FreeText' when wordsLocked => kept,
      'FreeText' => _words(file, annot, index, bounds, place),
      'Ink' => _ink(file, annot, index, place),
      'Highlight' => _markup(
        file,
        annot,
        index,
        place,
        bounds,
        highlight: true,
      ),
      'StrikeOut' => _markup(
        file,
        annot,
        index,
        place,
        bounds,
        highlight: false,
      ),
      'Stamp' || 'Square' || 'Circle' || 'Line' || 'PolyLine' || 'Polygon' || 'Text' ||
      'Caret' || 'FileAttachment' || 'Sound' || 'Underline' || 'Squiggly' =>
        kept,
      _ => null,
    };
    if (edit == null) continue;
    final text = subtype.value == 'Underline' || subtype.value == 'Squiggly';
    final icon = subtype.value == 'Text' || subtype.value == 'FileAttachment' || subtype.value == 'Sound';
    out.add(FoundMark(
      origin,
      subtype.value,
      edit,
      hasLook: hasLook,
      movable: text ? false : null,
      resizable: text || icon ? false : null,
      outline: _outline(file, annot, subtype.value, place, bounds),
      anchored: subtype.value == 'FreeText' && _numbers(file, annot['CL']) != null,
      note: subtype.value == 'Text' ? _noteWords(file, annot) : null,
    ));
  }
  return out;
}

/// The lines [annot] is drawn along, for a mark that should be picked up
/// by them: an unfilled rectangle or ellipse, a line, a polyline or polygon,
/// and a drawing.
List<List<Offset>>? _outline(
  PdfFile file,
  Map<String, Object?> annot,
  String subtype,
  PagePlace place,
  Rect bounds,
) {
  List<Offset> points(List<double>? values) => <Offset>[
        if (values != null)
          for (var i = 0; i + 1 < values.length; i += 2) place.reader(values[i], values[i + 1]),
      ];
  final filled = (_numbers(file, annot['IC']) ?? const <double>[]).isNotEmpty;
  switch (subtype) {
    case 'Square' when !filled:
      final b = bounds;
      return <List<Offset>>[
        <Offset>[b.topLeft, b.topRight, b.bottomRight, b.bottomLeft, b.topLeft],
      ];
    case 'Circle' when !filled:
      final c = bounds.center;
      return <List<Offset>>[
        <Offset>[
          for (var i = 0; i <= 48; i++)
            c + Offset(math.cos(i * math.pi / 24) * bounds.width / 2, math.sin(i * math.pi / 24) * bounds.height / 2),
        ],
      ];
    case 'Line':
      final line = points(_numbers(file, annot['L']));
      return line.length < 2 ? null : <List<Offset>>[line];
    case 'PolyLine':
      final line = points(_numbers(file, annot['Vertices']));
      return line.length < 2 ? null : <List<Offset>>[line];
    case 'Polygon' when !filled:
      final line = points(_numbers(file, annot['Vertices']));
      return line.length < 2 ? null : <List<Offset>>[<Offset>[...line, line.first]];
  }
  return null;
}

String _noteWords(PdfFile file, Map<String, Object?> annot) {
  final contents = file.resolve(annot['Contents']);
  return contents is PdfString ? lineBreaks(pdfTextString(contents)) : '';
}

TextBoxEdit _words(
  PdfFile file,
  Map<String, Object?> annot,
  int page,
  Rect bounds,
  PagePlace place,
) {
  final contents = file.resolve(annot['Contents']);
  final text = contents is PdfString ? lineBreaks(pdfTextString(contents)) : '';
  final da = file.resolve(annot['DA']);
  final appearance = da is PdfString ? latin1.decode(da.bytes, allowInvalid: true) : '';
  final ds = file.resolve(annot['DS']);
  final style = ds is PdfString ? pdfTextString(ds) : '';
  final size = _number(RegExp(r'([0-9]*\.?[0-9]+)\s+Tf').firstMatch(appearance)?.group(1)) ??
      _number(RegExp(r'([0-9]*\.?[0-9]+)pt').firstMatch(style)?.group(1)) ??
      12;
  return TextBoxEdit(
    page,
    rect: bounds,
    text: text,
    size: (size <= 0 ? 12 : size) * place.unit,
    color: _daColour(appearance) ?? _dsColour(style) ?? 0xFF111111,
    inset: _wordsInset(file, annot, bounds, place),
    family: _family(file, annot, appearance),
  );
}

/// The standard typeface a box of words is set in, from the font its /DA
/// names, looked up in its appearance or the form's resources, or null for
/// a face of its own.
String? _family(PdfFile file, Map<String, Object?> annot, String da) {
  final name = RegExp(r'/([^\s/\[\]()<>{}%]+)\s+[0-9.]+\s+Tf').firstMatch(da)?.group(1);
  if (name == null) return null;
  String? base;
  final look = file.dict(file.dict(annot['AP'])?['N']);
  final form = file.dict(file.dict(file.trailer['Root'])?['AcroForm']);
  for (final resources in <Map<String, Object?>?>[file.dict(look?['Resources']), file.dict(form?['DR'])]) {
    final font = file.dict(file.dict(resources?['Font'])?[name]);
    final baseFont = file.resolve(font?['BaseFont']);
    if (baseFont is PdfName) {
      base = baseFont.value;
      break;
    }
  }
  // The names forms give the standard faces, which are told apart by case.
  const short = <String, String>{
    'Helv': 'Helvetica', 'HeBo': 'Helvetica-Bold', 'HeOb': 'Helvetica-Oblique', 'HeBO': 'Helvetica-BoldOblique',
    'TiRo': 'Times-Roman', 'TiBo': 'Times-Bold', 'TiIt': 'Times-Italic', 'TiBI': 'Times-BoldItalic',
    'Cour': 'Courier', 'CoBo': 'Courier-Bold', 'CoOb': 'Courier-Oblique', 'CoBO': 'Courier-BoldOblique',
  };
  final known = base == null ? short[name] : null;
  if (known != null) return known;
  final key = (base ?? name).toLowerCase().replaceAll(RegExp(r'^[a-z]{6}\+'), '').replaceAll(RegExp(r'[\s_,-]'), '');
  final bold = key.contains('bold');
  final slant = key.contains('italic') || key.contains('oblique');
  if (key.startsWith('courier')) {
    return bold && slant ? 'Courier-BoldOblique' : bold ? 'Courier-Bold' : slant ? 'Courier-Oblique' : 'Courier';
  }
  if (key.startsWith('times')) {
    return bold && slant ? 'Times-BoldItalic' : bold ? 'Times-Bold' : slant ? 'Times-Italic' : 'Times-Roman';
  }
  if (key.startsWith('helvetica') || key.startsWith('arial')) {
    return bold && slant ? 'Helvetica-BoldOblique' : bold ? 'Helvetica-Bold' : slant ? 'Helvetica-Oblique' : 'Helvetica';
  }
  return null;
}

double? _number(String? text) => text == null ? null : double.tryParse(text);

int? _dsColour(String style) {
  final hex = RegExp(r'color\s*:\s*#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b').firstMatch(style)?.group(1);
  if (hex == null) return null;
  final full = hex.length == 3 ? hex.split('').map((c) => '$c$c').join() : hex;
  return 0xFF000000 | int.parse(full, radix: 16);
}

/// Where the words of a box another program drew sit inside it: inside the
/// inner box its /RD names, and inside its border when it draws one.
BoxInsets _wordsInset(PdfFile file, Map<String, Object?> annot, Rect bounds, PagePlace place) {
  final rect = _numbers(file, annot['Rect'])!;
  var inner = bounds;
  var framed = false;
  final rd = _numbers(file, annot['RD']);
  if (rd != null && rd.length == 4) {
    framed = true;
    final l = math.min(rect[0], rect[2]), b = math.min(rect[1], rect[3]);
    final r = math.max(rect[0], rect[2]), t = math.max(rect[1], rect[3]);
    if (l + rd[0] < r - rd[2] && b + rd[3] < t - rd[1]) {
      inner = place.readerRect([l + rd[0], b + rd[3], r - rd[2], t - rd[1]]);
    }
  }
  final bs = file.dict(annot['BS']);
  final border = _numbers(file, annot['Border']);
  final width = (_double(file, bs?['W']) ?? (border != null && border.length >= 3 ? border[2] : 1)) * place.unit;
  final colour = _numbers(file, annot['C']);
  final bordered = width > 0 && colour != null && colour.isNotEmpty;
  // Words start a little way inside a frame, as every program sets them.
  final pad = bordered ? width + 2 : (framed ? 2.0 : 0.0);
  final insets = BoxInsets(
    inner.left - bounds.left + pad,
    inner.top - bounds.top + pad,
    bounds.right - inner.right + pad,
    bounds.bottom - inner.bottom + pad,
  );
  final box = insets.inside(bounds);
  return box.width < 4 || box.height < 4 ? BoxInsets.zero : insets;
}

/// The annotations on page [page] that go with the one at [index]: the
/// replies and review states answering it, its group and their note
/// windows, which are taken off the page with it.
Set<int> markThread(PdfFile file, int page, int index) {
  final pages = file.pages;
  if (page < 0 || page >= pages.length) return <int>{index};
  final annots = file.resolve(pages[page]['Annots']);
  if (annots is! List || index < 0 || index >= annots.length) return <int>{index};
  return annotationThread(file, List<Object?>.of(annots), <int>{index});
}

InkEdit? _ink(
  PdfFile file,
  Map<String, Object?> annot,
  int page,
  PagePlace place,
) {
  final list = file.resolve(annot['InkList']);
  if (list is! List) return null;
  final strokes = <List<Offset>>[];
  for (final raw in list) {
    final values = _numbers(file, raw);
    if (values == null || values.length < 2) continue;
    strokes.add([
      for (var i = 0; i + 1 < values.length; i += 2)
        place.reader(values[i], values[i + 1]),
    ]);
  }
  if (strokes.isEmpty) return null;
  final bs = file.dict(annot['BS']);
  var width = _double(file, bs?['W']);
  if (width == null) {
    final border = _numbers(file, annot['Border']);
    width = border != null && border.length >= 3 ? border[2] : 1;
  }
  return InkEdit(
    page,
    strokes: strokes,
    width: (width <= 0 ? 1 : width) * place.unit,
    color: _colourOf(file, annot['C']) ?? 0xFF000000,
    opacity: _opacity(file, annot),
  );
}

PageEdit? _markup(
  PdfFile file,
  Map<String, Object?> annot,
  int page,
  PagePlace place,
  Rect bounds, {
  required bool highlight,
}) {
  final quads = _numbers(file, annot['QuadPoints']);
  final rects = <Rect>[];
  if (quads != null) {
    for (var i = 0; i + 7 < quads.length; i += 8) {
      final points = [
        for (var j = 0; j < 8; j += 2)
          place.reader(quads[i + j], quads[i + j + 1]),
      ];
      var l = double.infinity, t = double.infinity;
      var r = double.negativeInfinity, b = double.negativeInfinity;
      for (final p in points) {
        if (p.dx < l) l = p.dx;
        if (p.dx > r) r = p.dx;
        if (p.dy < t) t = p.dy;
        if (p.dy > b) b = p.dy;
      }
      rects.add(Rect.fromLTRB(l, t, r, b));
    }
  }
  if (rects.isEmpty) rects.add(bounds);
  final colour = _colourOf(file, annot['C']);
  final opacity = _opacity(file, annot);
  return highlight
      ? HighlightEdit(page, rects: rects, color: colour ?? 0xFFFFD84D, opacity: opacity)
      : StrikeEdit(page, rects: rects, color: colour ?? 0xFFD23B3B, opacity: opacity);
}

double _opacity(PdfFile file, Map<String, Object?> annot) =>
    (_double(file, annot['CA']) ?? 1).clamp(0.0, 1.0).toDouble();

/// A PDF text string as text.
String pdfTextString(PdfString value) => decodePdfText(value.bytes);

int _int(PdfFile file, Object? raw) {
  final v = file.resolve(raw);
  return v is num ? v.toInt() : 0;
}

double? _double(PdfFile file, Object? raw) {
  final v = file.resolve(raw);
  return v is num ? v.toDouble() : null;
}

List<double>? _numbers(PdfFile file, Object? raw) {
  final v = file.resolve(raw);
  if (v is! List) return null;
  final out = <double>[];
  for (final e in v) {
    final n = file.resolve(e);
    if (n is! num) return null;
    out.add(n.toDouble());
  }
  return out;
}

int _argb(double r, double g, double b) {
  int c(double v) => (v.clamp(0, 1) * 255).round();
  return 0xFF000000 | (c(r) << 16) | (c(g) << 8) | c(b);
}

int? _colourOf(PdfFile file, Object? raw) {
  final c = _numbers(file, raw);
  if (c == null) return null;
  return switch (c.length) {
    1 => _argb(c[0], c[0], c[0]),
    3 => _argb(c[0], c[1], c[2]),
    4 => _argb(
      (1 - c[0]) * (1 - c[3]),
      (1 - c[1]) * (1 - c[3]),
      (1 - c[2]) * (1 - c[3]),
    ),
    _ => null,
  };
}

int? _daColour(String da) {
  final n = r'([0-9]*\.?[0-9]+)';
  final rgb = RegExp('$n\\s+$n\\s+$n\\s+rg').firstMatch(da);
  if (rgb != null) {
    return _argb(
      double.parse(rgb.group(1)!),
      double.parse(rgb.group(2)!),
      double.parse(rgb.group(3)!),
    );
  }
  final cmyk = RegExp('$n\\s+$n\\s+$n\\s+$n\\s+k').firstMatch(da);
  if (cmyk != null) {
    final v = [for (var i = 1; i <= 4; i++) double.parse(cmyk.group(i)!)];
    return _argb(
      (1 - v[0]) * (1 - v[3]),
      (1 - v[1]) * (1 - v[3]),
      (1 - v[2]) * (1 - v[3]),
    );
  }
  final grey = RegExp('$n\\s+g(?![a-zA-Z])').firstMatch(da);
  if (grey != null) {
    final g = double.parse(grey.group(1)!);
    return _argb(g, g, g);
  }
  return null;
}
