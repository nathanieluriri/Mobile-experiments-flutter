import 'dart:typed_data';
import 'display_list.dart';
import 'document.dart';
import 'font.dart';
import 'lexer.dart';
import 'objects.dart';

class _GState {
  _GState(this.ctm, this.fill, this.stroke, this.lineWidth,
      [this.fillAlpha = 1.0, this.strokeAlpha = 1.0]);
  Mat ctm;
  int fill;
  int stroke;
  double lineWidth;

  /// Constant alpha from an /ExtGState, kept apart from the colour so a later
  /// `rg` or `g` inherits it instead of clearing it.
  double fillAlpha;
  double strokeAlpha;

  int get fillColor => _withAlpha(fill, fillAlpha);
  int get strokeColor => _withAlpha(stroke, strokeAlpha);

  _GState clone() =>
      _GState(ctm, fill, stroke, lineWidth, fillAlpha, strokeAlpha);

  static int _withAlpha(int argb, double alpha) {
    if (alpha >= 1) return argb;
    final a = (alpha.clamp(0.0, 1.0) * 255).round();
    return (argb & 0x00FFFFFF) | (a << 24);
  }
}

/// Interprets a page content stream into a paintable display list.
class ContentInterpreter {
  ContentInterpreter(this.doc, {this.maxOps = 400000});
  final PdfFile doc;
  final int maxOps;

  int opsRun = 0;
  int _seq = 0;
  int unknownOps = 0;
  final Set<String> unsupported = {};

  PageDisplayList run(Map<String, Object?> page) {
    final mb = doc.mediaBox(page);
    final cropRaw = doc.resolve(page['CropBox']);
    var box = mb;
    if (cropRaw is List && cropRaw.length == 4) {
      box = cropRaw.map((e) => ((doc.resolve(e) as num?) ?? 0).toDouble()).toList();
    }
    final x0 = box[0] < box[2] ? box[0] : box[2];
    final y0 = box[1] < box[3] ? box[1] : box[3];
    final w = (box[2] - box[0]).abs();
    final h = (box[3] - box[1]).abs();
    var rot = ((doc.resolve(page['Rotate']) as num?)?.toInt() ?? 0) % 360;
    if (rot < 0) rot += 360;
    // Rotate is stated in whole quarter turns; anything else is not a turn
    // this format has, and the page is taken as it lies.
    if (rot % 90 != 0) rot = 0;
    final quarter = rot ~/ 90;
    // A quarter turn swaps the page over: a sheet stored on its side is a
    // page that is taller than it is wide once it has been turned upright.
    final turned = quarter.isOdd;
    final out = PageDisplayList(
      widthPts: turned ? h : w,
      heightPts: turned ? w : h,
      rotation: rot,
    );

    // PDF space is bottom-left origin; flip into top-left screen space, and
    // turn the page by what /Rotate says, which is what a scanner writes when
    // it feeds a sheet in sideways. Without this the page is drawn as it is
    // stored rather than as it is meant to be read.
    final base = switch (quarter) {
      1 => Mat(0, 1, 1, 0, -y0, -x0),
      2 => Mat(-1, 0, 0, 1, x0 + w, -y0),
      3 => Mat(0, -1, -1, 0, y0 + h, x0 + w),
      _ => Mat(1, 0, 0, -1, -x0, y0 + h),
    };
    final content = doc.pageContent(page);
    final res = doc.dict(page['Resources']) ?? const {};
    _exec(content, res, base, out, 0);
    return out;
  }

  // ------------------------------------------------------------ execution

  void _exec(Uint8List content, Map<String, Object?> res, Mat base,
      PageDisplayList out, int depth) {
    if (depth > 8) return;
    final fontCache = <String, PdfFont?>{};
    final lx = PdfLexer(content);
    final stack = <Object?>[];
    var gs = _GState(base, 0xFF000000, 0xFF000000, 1);
    final gsStack = <_GState>[];

    // Text state
    var tm = const Mat.identity();
    var tlm = const Mat.identity();
    PdfFont? font;
    var fontKey = '';
    var fontSize = 0.0;
    var charSpacing = 0.0, wordSpacing = 0.0, leading = 0.0, rise = 0.0;
    var hScale = 1.0;
    var renderMode = 0;

    // Path building
    var segs = <PathSeg>[];
    var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
    var pendingClip = false;

    double num_(int back) {
      final i = stack.length - back;
      if (i < 0 || i >= stack.length) return 0;
      final v = stack[i];
      return v is num ? v.toDouble() : 0;
    }

    void emit(PdfFont f, String text, Mat at, double advance) {
      final m = tm.mul(gs.ctm);
      final angle = m.angle;
      final rotated = angle.abs() > 0.01;
      final mono = f.baseFont.toLowerCase().contains('courier') ||
          f.baseFont.toLowerCase().contains('mono');
      out.texts.add(TextRunCmd(
        text: text,
        x: at.e,
        y: at.f,
        fontSize: (fontSize * m.heightY * f.sizeScale).abs(),
        widthPts: advance * m.scaleX,
        fontKey: fontKey,
        bold: f.isBold,
        italic: f.isItalic || m.slanted,
        serif: f.isSerif,
        mono: mono,
        color: gs.fillColor,
        rotated: rotated,
        angle: rotated ? angle : 0,
        spaceWidthPts:
            (f.spaceWidth / 1000.0 * fontSize * hScale * m.scaleX).abs(),
        seq: _seq++,
      ));
    }

    void showText(Uint8List bytes) {
      final f = font;
      if (f == null) return;
      // Render modes 3 and 7 are the invisible OCR layer laid over a scan.
      // The glyphs must not be painted, but they must still advance the text
      // matrix, or every visible run after them lands in the wrong place.
      final invisible = renderMode == 3 || renderMode == 7;
      final runs = f.decode(bytes);
      if (f.vertical) {
        // Each glyph hangs below the one before it, centred on the pen, so
        // each is its own run: the lines a person reads run down the page.
        for (final r in runs) {
          if (r.text.trim().isNotEmpty && !invisible) {
            final at = Mat(1, 0, 0, 1, -r.width / 2000.0 * fontSize,
                    -0.88 * fontSize + rise)
                .mul(tm)
                .mul(gs.ctm);
            emit(f, r.text, at, r.width / 1000.0 * fontSize * hScale);
          }
          var down = f.verticalAdvance / 1000.0 * fontSize + charSpacing;
          if (r.bytes == 1 && r.code == 32) down += wordSpacing;
          tm = Mat(1, 0, 0, 1, 0, down).mul(tm);
        }
        return;
      }
      final sb = StringBuffer();
      final start = Mat(1, 0, 0, 1, 0, rise).mul(tm).mul(gs.ctm);
      var advance = 0.0;
      for (final r in runs) {
        sb.write(r.text);
        var adv = r.width / 1000.0 * fontSize + charSpacing;
        if (r.bytes == 1 && r.code == 32) adv += wordSpacing;
        advance += adv * hScale;
      }
      final text = sb.toString();
      if (text.trim().isNotEmpty && !invisible) {
        emit(f, text, start, advance);
      }
      tm = Mat(1, 0, 0, 1, advance, 0).mul(tm);
    }

    void emitPath({required bool fill, required bool stroke, required bool eo}) {
      if (segs.isNotEmpty && (fill || stroke)) {
        final t = <PathSeg>[];
        for (final s in segs) {
          final p = <double>[];
          for (var i = 0; i + 1 < s.pts.length; i += 2) {
            p
              ..add(gs.ctm.tx(s.pts[i], s.pts[i + 1]))
              ..add(gs.ctm.ty(s.pts[i], s.pts[i + 1]));
          }
          t.add(PathSeg(s.op, p));
        }
        out.paths.add(PathCmd(
          segs: t,
          fill: fill,
          stroke: stroke,
          fillColor: gs.fillColor,
          strokeColor: gs.strokeColor,
          lineWidth: gs.lineWidth * gs.ctm.scaleY,
          evenOdd: eo,
          seq: _seq++,
        ));
      }
      segs = <PathSeg>[];
      pendingClip = false;
    }

    while (!lx.atEnd) {
      if (opsRun++ > maxOps) return;
      final o = lx.parseObject();
      if (o == null) break;
      if (o is! PdfKeyword) {
        stack.add(o);
        if (stack.length > 64) stack.removeAt(0);
        continue;
      }
      final op = o.value;
      switch (op) {
        case 'q':
          gsStack.add(gs.clone());
          break;
        case 'Q':
          if (gsStack.isNotEmpty) gs = gsStack.removeLast();
          break;
        case 'cm':
          gs.ctm = Mat(num_(6), num_(5), num_(4), num_(3), num_(2), num_(1))
              .mul(gs.ctm);
          break;
        case 'w':
          gs.lineWidth = num_(1);
          break;
        case 'BT':
          tm = const Mat.identity();
          tlm = tm;
          break;
        case 'ET':
          break;
        case 'Tf':
          fontSize = num_(1);
          final nameObj = stack.length >= 2 ? stack[stack.length - 2] : null;
          if (nameObj is PdfName) {
            fontKey = nameObj.value;
            if (!fontCache.containsKey(fontKey)) {
              fontCache[fontKey] = _loadFont(res, fontKey);
            }
            font = fontCache[fontKey];
          }
          break;
        case 'Td':
          tlm = Mat(1, 0, 0, 1, num_(2), num_(1)).mul(tlm);
          tm = tlm;
          break;
        case 'TD':
          leading = -num_(1);
          tlm = Mat(1, 0, 0, 1, num_(2), num_(1)).mul(tlm);
          tm = tlm;
          break;
        case 'Tm':
          tlm = Mat(num_(6), num_(5), num_(4), num_(3), num_(2), num_(1));
          tm = tlm;
          break;
        case 'T*':
          tlm = Mat(1, 0, 0, 1, 0, -leading).mul(tlm);
          tm = tlm;
          break;
        case 'TL':
          leading = num_(1);
          break;
        case 'Tc':
          charSpacing = num_(1);
          break;
        case 'Tw':
          wordSpacing = num_(1);
          break;
        case 'Tz':
          hScale = num_(1) / 100.0;
          break;
        case 'Ts':
          rise = num_(1);
          break;
        case 'Tr':
          renderMode = num_(1).toInt();
          break;
        case 'Tj':
          final s = stack.isNotEmpty ? stack.last : null;
          if (s is PdfString) showText(s.bytes);
          break;
        case "'":
          tlm = Mat(1, 0, 0, 1, 0, -leading).mul(tlm);
          tm = tlm;
          final s = stack.isNotEmpty ? stack.last : null;
          if (s is PdfString) showText(s.bytes);
          break;
        case '"':
          wordSpacing = num_(3);
          charSpacing = num_(2);
          tlm = Mat(1, 0, 0, 1, 0, -leading).mul(tlm);
          tm = tlm;
          final s = stack.isNotEmpty ? stack.last : null;
          if (s is PdfString) showText(s.bytes);
          break;
        case 'TJ':
          final arr = stack.isNotEmpty ? stack.last : null;
          if (arr is List) {
            for (final e in arr) {
              if (e is PdfString) {
                showText(e.bytes);
              } else if (e is num) {
                final shift = -e.toDouble() / 1000.0 * fontSize * hScale;
                tm = Mat(1, 0, 0, 1, shift, 0).mul(tm);
              }
            }
          }
          break;
        case 'm':
          cx = num_(2);
          cy = num_(1);
          sx = cx;
          sy = cy;
          segs.add(PathSeg(PathOp.move, [cx, cy]));
          break;
        case 'l':
          cx = num_(2);
          cy = num_(1);
          segs.add(PathSeg(PathOp.line, [cx, cy]));
          break;
        case 'c':
          segs.add(PathSeg(PathOp.cubic,
              [num_(6), num_(5), num_(4), num_(3), num_(2), num_(1)]));
          cx = num_(2);
          cy = num_(1);
          break;
        case 'v':
          segs.add(PathSeg(PathOp.cubic,
              [cx, cy, num_(4), num_(3), num_(2), num_(1)]));
          cx = num_(2);
          cy = num_(1);
          break;
        case 'y':
          segs.add(PathSeg(PathOp.cubic,
              [num_(4), num_(3), num_(2), num_(1), num_(2), num_(1)]));
          cx = num_(2);
          cy = num_(1);
          break;
        case 'h':
          segs.add(const PathSeg(PathOp.close, []));
          cx = sx;
          cy = sy;
          break;
        case 're':
          final x = num_(4), y = num_(3), rw = num_(2), rh = num_(1);
          segs
            ..add(PathSeg(PathOp.move, [x, y]))
            ..add(PathSeg(PathOp.line, [x + rw, y]))
            ..add(PathSeg(PathOp.line, [x + rw, y + rh]))
            ..add(PathSeg(PathOp.line, [x, y + rh]))
            ..add(const PathSeg(PathOp.close, []));
          cx = x;
          cy = y;
          sx = x;
          sy = y;
          break;
        case 'n':
          emitPath(fill: false, stroke: false, eo: false);
          break;
        case 'f':
        case 'F':
          emitPath(fill: true, stroke: false, eo: false);
          break;
        case 'f*':
          emitPath(fill: true, stroke: false, eo: true);
          break;
        case 'S':
          emitPath(fill: false, stroke: true, eo: false);
          break;
        case 's':
          segs.add(const PathSeg(PathOp.close, []));
          emitPath(fill: false, stroke: true, eo: false);
          break;
        case 'B':
        case 'b':
          emitPath(fill: true, stroke: true, eo: false);
          break;
        case 'B*':
        case 'b*':
          emitPath(fill: true, stroke: true, eo: true);
          break;
        case 'W':
        case 'W*':
          pendingClip = true;
          break;
        case 'g':
          gs.fill = _gray(num_(1));
          break;
        case 'G':
          gs.stroke = _gray(num_(1));
          break;
        case 'rg':
          gs.fill = _rgb(num_(3), num_(2), num_(1));
          break;
        case 'RG':
          gs.stroke = _rgb(num_(3), num_(2), num_(1));
          break;
        case 'k':
          gs.fill = _cmyk(num_(4), num_(3), num_(2), num_(1));
          break;
        case 'K':
          gs.stroke = _cmyk(num_(4), num_(3), num_(2), num_(1));
          break;
        case 'sc':
        case 'scn':
          final c = _fromComponents(stack);
          if (c != null) gs.fill = c;
          break;
        case 'SC':
        case 'SCN':
          final c = _fromComponents(stack);
          if (c != null) gs.stroke = c;
          break;
        case 'Do':
          final n = stack.isNotEmpty ? stack.last : null;
          if (n is PdfName) _doXObject(res, n.value, gs, out, depth);
          break;
        case 'BI':
          _inlineImage(lx, gs, out);
          break;
        case 'sh':
          unsupported.add('sh');
          break;
        case 'gs':
          final n = stack.isNotEmpty ? stack.last : null;
          if (n is PdfName) {
            _applyExtGState(res, n.value, gs);
          }
          break;
        case 'BX':
        case 'EX':
        case 'MP':
        case 'DP':
        case 'BMC':
        case 'BDC':
        case 'EMC':
        case 'ri':
        case 'i':
        case 'j':
        case 'J':
        case 'M':
        case 'd':
        case 'd0':
        case 'd1':
        case 'cs':
        case 'CS':
          break;
        default:
          unknownOps++;
          if (op.isNotEmpty) unsupported.add(op);
      }
      if (op != 'W' && op != 'W*') {
        stack.clear();
      }
      if (pendingClip && (op == 'W' || op == 'W*')) {
        // clip is applied by the next path-painting op; we ignore clipping.
      }
    }
  }

  /// Applies one named /ExtGState to the live graphics state.
  ///
  /// /ca and /CA are the constant alphas a producer uses for a highlight, a
  /// watermark or a drop shadow. Ignoring them paints those flat and opaque,
  /// which is the single most visible way a page comes out wrong.
  void _applyExtGState(Map<String, Object?> res, String name, _GState gs) {
    final states = doc.dict(res['ExtGState']);
    final ext = doc.dict(states?[name]);
    if (ext == null) return;
    final ca = doc.resolve(ext['ca']);
    if (ca is num) gs.fillAlpha = ca.toDouble().clamp(0.0, 1.0);
    final upperCa = doc.resolve(ext['CA']);
    if (upperCa is num) gs.strokeAlpha = upperCa.toDouble().clamp(0.0, 1.0);
    final lw = doc.resolve(ext['LW']);
    if (lw is num) gs.lineWidth = lw.toDouble();
    // A soft mask is a whole compositing model, not a constant, so a page that
    // asks for one is recorded rather than approximated.
    final smask = doc.resolve(ext['SMask']);
    if (smask is Map<String, Object?>) unsupported.add('gs:SMask');
  }

  PdfFont? _loadFont(Map<String, Object?> res, String key) {
    final fonts = doc.dict(res['Font']);
    final f = doc.dict(fonts?[key]);
    if (f == null) return null;
    try {
      return PdfFont.load(doc, f);
    } catch (_) {
      return null;
    }
  }

  void _doXObject(Map<String, Object?> res, String name, _GState gs,
      PageDisplayList out, int depth) {
    final xo = doc.dict(res['XObject']);
    final obj = doc.resolve(xo?[name]);
    if (obj is! PdfStream) return;
    final sub = (doc.resolve(obj.dict['Subtype']) as PdfName?)?.value;
    if (sub == 'Form') {
      final mtxRaw = doc.resolve(obj.dict['Matrix']);
      var m = gs.ctm;
      if (mtxRaw is List && mtxRaw.length == 6) {
        final v = mtxRaw.map((e) => ((doc.resolve(e) as num?) ?? 0).toDouble())
            .toList();
        m = Mat(v[0], v[1], v[2], v[3], v[4], v[5]).mul(gs.ctm);
      }
      final formRes = doc.dict(obj.dict['Resources']) ?? res;
      _exec(doc.decodeStream(obj), formRes, m, out, depth + 1);
      return;
    }
    if (sub == 'Image') {
      out.images.add(_imageCmd(name, obj, gs.ctm));
    }
  }

  /// Resolves a /ColorSpace entry far enough to know how to read pixels.
  ///
  /// The array forms matter as much as the names: a screenshot arrives as
  /// [/Indexed /DeviceRGB n <palette>] and almost everything from a print
  /// workflow arrives as [/ICCBased s]. Treating either as unknown turns a
  /// perfectly readable picture into an empty box on the page.
  _ColourSpace _colourSpace(Object? raw) {
    final v = doc.resolve(raw);
    if (v is PdfName) return _ColourSpace(_kindOfName(v.value));
    if (v is List && v.isNotEmpty) {
      final head = doc.resolve(v.first);
      final family = head is PdfName ? head.value : '';
      switch (family) {
        case 'Indexed':
        case 'I':
          if (v.length < 4) return const _ColourSpace(_CsKind.unknown);
          final base = _colourSpace(v[1]);
          final table = _paletteBytes(doc.resolve(v[3]));
          if (table == null) return const _ColourSpace(_CsKind.unknown);
          return _ColourSpace(_CsKind.indexed,
              palette: _paletteAsRgb(table, base.kind));
        case 'ICCBased':
          final stream = doc.resolve(v.length > 1 ? v[1] : null);
          final n = stream is PdfStream
              ? (doc.resolve(stream.dict['N']) as num?)?.toInt() ?? 0
              : 0;
          if (n == 1) return const _ColourSpace(_CsKind.gray);
          if (n == 3) return const _ColourSpace(_CsKind.rgb);
          if (n == 4) return const _ColourSpace(_CsKind.cmyk);
          return const _ColourSpace(_CsKind.unknown);
        case 'CalRGB':
          return const _ColourSpace(_CsKind.rgb);
        case 'CalGray':
          return const _ColourSpace(_CsKind.gray);
      }
    }
    return const _ColourSpace(_CsKind.unknown);
  }

  static _CsKind _kindOfName(String name) {
    switch (name) {
      case 'DeviceRGB':
      case 'RGB':
        return _CsKind.rgb;
      case 'DeviceGray':
      case 'G':
        return _CsKind.gray;
      case 'DeviceCMYK':
      case 'CMYK':
        return _CsKind.cmyk;
      default:
        return _CsKind.unknown;
    }
  }

  /// The palette of an /Indexed space, which a file may write inline as a
  /// string or indirectly as a stream.
  Uint8List? _paletteBytes(Object? lookup) {
    if (lookup is PdfString) return lookup.bytes;
    if (lookup is PdfStream) return doc.decodeStream(lookup);
    return null;
  }

  /// Widens a palette in any base space to three bytes an entry, so the
  /// expansion below only ever has one shape to write.
  static Uint8List _paletteAsRgb(Uint8List table, _CsKind base) {
    switch (base) {
      case _CsKind.gray:
        final out = Uint8List(table.length * 3);
        for (var i = 0; i < table.length; i++) {
          out[i * 3] = table[i];
          out[i * 3 + 1] = table[i];
          out[i * 3 + 2] = table[i];
        }
        return out;
      case _CsKind.cmyk:
        return _cmykToRgb(table);
      case _CsKind.rgb:
      case _CsKind.indexed:
      case _CsKind.unknown:
        return table;
    }
  }

  /// Expands indexed samples into RGB triplets.
  ///
  /// Each row is padded to a whole byte. Forgetting that shears every row of a
  /// 1, 2 or 4 bit image sideways by a fraction of a pixel, which reads as a
  /// picture torn on the diagonal.
  static Uint8List _expandIndexed(
      Uint8List data, Uint8List palette, int width, int height, int bpc) {
    if (width <= 0 || height <= 0 || bpc <= 0 || bpc > 8) return Uint8List(0);
    final out = Uint8List(width * height * 3);
    final rowBytes = (width * bpc + 7) >> 3;
    final perByte = 8 ~/ bpc;
    final mask = (1 << bpc) - 1;
    final entries = palette.length ~/ 3;
    var o = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final at = y * rowBytes + x ~/ perByte;
        if (at >= data.length) return out;
        final shift = 8 - bpc * (x % perByte + 1);
        final index = (data[at] >> shift) & mask;
        if (index < entries) {
          out[o] = palette[index * 3];
          out[o + 1] = palette[index * 3 + 1];
          out[o + 2] = palette[index * 3 + 2];
        }
        o += 3;
      }
    }
    return out;
  }

  /// True when the stream is a stencil mask rather than a picture.
  ///
  /// The lexer hands back bare keywords, so `true` arrives as a keyword and
  /// not as a Dart bool. A mask paints the current fill colour through its
  /// one bits and has no colour of its own, so it must not be widened into a
  /// grey image that would paint black where the page wanted nothing.
  bool _isImageMask(PdfStream s) {
    final v = doc.resolve(s.dict['ImageMask'] ?? s.dict['IM']);
    return v == true || (v is PdfKeyword && v.value == 'true');
  }

  /// True when a /Decode array reverses the meaning of a one bit sample.
  bool _decodeInverts(PdfStream s) {
    final d = doc.resolve(s.dict['Decode'] ?? s.dict['D']);
    if (d is List && d.length >= 2) {
      final first = doc.resolve(d[0]);
      return first is num && first > 0.5;
    }
    return false;
  }

  /// Unpacks a one bit grey image into one byte a pixel.
  ///
  /// Line art, signatures and fax pages arrive this way. Left packed, the
  /// bytes are meaningless to an image decoder and the page falls back to a
  /// placeholder box over a picture that was perfectly readable.
  static Uint8List _expandBilevel(Uint8List data, int width, int height,
      {bool invert = false}) {
    if (width <= 0 || height <= 0) return Uint8List(0);
    final out = Uint8List(width * height);
    final rowBytes = (width + 7) >> 3;
    var o = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final at = y * rowBytes + (x >> 3);
        if (at >= data.length) return out;
        var bit = (data[at] >> (7 - (x & 7))) & 1;
        if (invert) bit ^= 1;
        out[o++] = bit == 1 ? 0xFF : 0x00;
      }
    }
    return out;
  }

  /// Converts 8 bit CMYK samples to RGB with the same subtractive formula the
  /// `k` operator uses, so a filled rectangle and a picture of one agree.
  static Uint8List _cmykToRgb(Uint8List data) {
    final pixels = data.length ~/ 4;
    final out = Uint8List(pixels * 3);
    for (var i = 0, o = 0; i < pixels; i++, o += 3) {
      final c = data[i * 4], m = data[i * 4 + 1];
      final y = data[i * 4 + 2], k = data[i * 4 + 3];
      out[o] = ((255 - c) * (255 - k)) ~/ 255;
      out[o + 1] = ((255 - m) * (255 - k)) ~/ 255;
      out[o + 2] = ((255 - y) * (255 - k)) ~/ 255;
    }
    return out;
  }

  ImageCmd _imageCmd(String name, PdfStream s, Mat ctm) {
    final w = (doc.resolve(s.dict['Width'] ?? s.dict['W']) as num?)?.toInt() ?? 0;
    final h = (doc.resolve(s.dict['Height'] ?? s.dict['H']) as num?)?.toInt() ?? 0;
    // The unit square maps to the image placement rect.
    final xs = <double>[
      ctm.tx(0, 0), ctm.tx(1, 0), ctm.tx(0, 1), ctm.tx(1, 1),
    ];
    final ys = <double>[
      ctm.ty(0, 0), ctm.ty(1, 0), ctm.ty(0, 1), ctm.ty(1, 1),
    ];
    xs.sort();
    ys.sort();
    final filters = doc.streamFilters(s);
    String enc;
    Uint8List? bytes;
    if (filters.contains('DCTDecode') || filters.contains('DCT')) {
      enc = 'jpeg';
      bytes = s.raw;
    } else if (filters.contains('JPXDecode')) {
      enc = 'jpx';
    } else if (filters.contains('CCITTFaxDecode') || filters.contains('CCF')) {
      enc = 'ccitt';
    } else if (filters.contains('JBIG2Decode')) {
      enc = 'jbig2';
    } else {
      final bpc =
          (doc.resolve(s.dict['BitsPerComponent'] ?? s.dict['BPC']) as num?)
                  ?.toInt() ??
              8;
      final space = _colourSpace(s.dict['ColorSpace'] ?? s.dict['CS']);
      if (bpc == 8 && space.kind == _CsKind.rgb) {
        enc = 'raw-rgb';
        bytes = doc.decodeStream(s);
      } else if (bpc == 8 && space.kind == _CsKind.gray) {
        enc = 'raw-gray';
        bytes = doc.decodeStream(s);
      } else if (bpc == 8 && space.kind == _CsKind.cmyk) {
        enc = 'raw-rgb';
        bytes = _cmykToRgb(doc.decodeStream(s));
      } else if (space.kind == _CsKind.indexed && space.palette != null) {
        enc = 'raw-rgb';
        bytes = _expandIndexed(doc.decodeStream(s), space.palette!, w, h, bpc);
      } else if (bpc == 1 &&
          space.kind == _CsKind.gray &&
          !_isImageMask(s)) {
        enc = 'raw-gray';
        bytes = _expandBilevel(doc.decodeStream(s), w, h,
            invert: _decodeInverts(s));
      } else if (bpc == 1) {
        enc = 'raw-bilevel';
        bytes = doc.decodeStream(s);
      } else {
        enc = 'unsupported';
      }
    }
    if (enc == 'jpx' || enc == 'ccitt' || enc == 'jbig2' ||
        enc == 'unsupported') {
      unsupported.add('image:$enc');
    }
    return ImageCmd(
      name: name,
      rect: [xs.first, ys.first, xs.last, ys.last],
      bytes: bytes,
      encoding: enc,
      width: w,
      height: h,
      seq: _seq++,
    );
  }

  void _inlineImage(PdfLexer lx, _GState gs, PageDisplayList out) {
    // BI <key value>* ID <binary> EI
    final d = <String, Object?>{};
    while (!lx.atEnd) {
      final k = lx.parseObject();
      if (k is PdfKeyword && k.value == 'ID') break;
      final v = lx.parseObject();
      if (k is PdfName) d[k.value] = v;
      if (v is PdfKeyword && v.value == 'ID') break;
    }
    var p = lx.pos;
    if (p < lx.bytes.length && isWhite(lx.bytes[p])) p++;
    final start = p;
    while (p + 1 < lx.bytes.length) {
      if (lx.bytes[p] == 0x45 &&
          lx.bytes[p + 1] == 0x49 &&
          (p == 0 || isWhite(lx.bytes[p - 1])) &&
          (p + 2 >= lx.bytes.length || isWhite(lx.bytes[p + 2]))) {
        break;
      }
      p++;
    }
    final data = Uint8List.sublistView(lx.bytes, start, p);
    lx.pos = (p + 2).clamp(0, lx.bytes.length);
    out.images.add(_imageCmd('inline', PdfStream(d, data), gs.ctm));
  }

  static int _gray(double v) {
    final g = (v.clamp(0, 1) * 255).round();
    return 0xFF000000 | (g << 16) | (g << 8) | g;
  }

  static int _rgb(double r, double g, double b) =>
      0xFF000000 |
      ((r.clamp(0, 1) * 255).round() << 16) |
      ((g.clamp(0, 1) * 255).round() << 8) |
      (b.clamp(0, 1) * 255).round();

  static int _cmyk(double c, double m, double y, double k) => _rgb(
        (1 - c.clamp(0, 1)) * (1 - k.clamp(0, 1)),
        (1 - m.clamp(0, 1)) * (1 - k.clamp(0, 1)),
        (1 - y.clamp(0, 1)) * (1 - k.clamp(0, 1)),
      );

  static int? _fromComponents(List<Object?> stack) {
    final nums = stack.whereType<num>().map((e) => e.toDouble()).toList();
    switch (nums.length) {
      case 1:
        return _gray(nums[0]);
      case 3:
        return _rgb(nums[0], nums[1], nums[2]);
      case 4:
        return _cmyk(nums[0], nums[1], nums[2], nums[3]);
      default:
        return null;
    }
  }
}

/// The families of colour space this engine can read pixels in.
enum _CsKind { rgb, gray, cmyk, indexed, unknown }

/// A resolved colour space: its family, plus the RGB palette when indexed.
class _ColourSpace {
  const _ColourSpace(this.kind, {this.palette});
  final _CsKind kind;
  final Uint8List? palette;
}
