import 'dart:math' as math;
import 'dart:typed_data';

import 'document.dart';
import 'objects.dart';

/// A PDF function: numbers in, numbers out. Shadings are made of them, and so
/// are the tint transforms of Separation and DeviceN colours.
abstract class PdfFunction {
  const PdfFunction();

  List<double> call(List<double> input);

  /// [raw] read as a function, or null when it is not one this reader knows.
  /// An array of functions is one function with an output per member.
  static PdfFunction? read(PdfFile doc, Object? raw, [int depth = 0]) {
    if (depth > 8) return null;
    final value = doc.resolve(raw);
    if (value is List) {
      final parts = <PdfFunction>[];
      for (final item in value) {
        final part = read(doc, item, depth + 1);
        if (part == null) return null;
        parts.add(part);
      }
      return parts.isEmpty ? null : _Joined(parts);
    }
    final dict = value is PdfStream ? value.dict : doc.dict(value);
    if (dict == null) return null;
    final type = (doc.resolve(dict['FunctionType']) as num?)?.toInt();
    final domain = _numbers(doc, dict['Domain']) ?? const [0.0, 1.0];
    final range = _numbers(doc, dict['Range']);
    try {
      switch (type) {
        case 0:
          if (value is! PdfStream) return null;
          return _Sampled.read(doc, value, domain, range);
        case 2:
          return _Exponential(
            domain,
            _numbers(doc, dict['C0']) ?? const [0.0],
            _numbers(doc, dict['C1']) ?? const [1.0],
            (doc.resolve(dict['N']) as num?)?.toDouble() ?? 1,
          );
        case 3:
          final functions = <PdfFunction>[];
          final raws = doc.resolve(dict['Functions']);
          if (raws is! List) return null;
          for (final item in raws) {
            final part = read(doc, item, depth + 1);
            if (part == null) return null;
            functions.add(part);
          }
          return _Stitched(
            domain,
            functions,
            _numbers(doc, dict['Bounds']) ?? const [],
            _numbers(doc, dict['Encode']) ?? const [],
          );
        case 4:
          if (value is! PdfStream) return null;
          final program = _Calculator.parse(doc.decodeStream(value));
          if (program == null) return null;
          return _Calculator(domain, range ?? const [], program);
      }
    } on Object {
      return null;
    }
    return null;
  }
}

List<double>? _numbers(PdfFile doc, Object? raw) {
  final value = doc.resolve(raw);
  if (value is! List) return null;
  final out = <double>[];
  for (final item in value) {
    final n = doc.resolve(item);
    if (n is! num) return null;
    out.add(n.toDouble());
  }
  return out;
}

double _clampTo(double v, List<double> bounds, int i) {
  if (bounds.length < 2 * i + 2) return v;
  final lo = bounds[2 * i], hi = bounds[2 * i + 1];
  return v < lo ? lo : (v > hi ? hi : v);
}

class _Joined extends PdfFunction {
  const _Joined(this.parts);
  final List<PdfFunction> parts;

  @override
  List<double> call(List<double> input) =>
      [for (final part in parts) ...part(input)];
}

class _Exponential extends PdfFunction {
  const _Exponential(this.domain, this.c0, this.c1, this.n);
  final List<double> domain, c0, c1;
  final double n;

  @override
  List<double> call(List<double> input) {
    final x = _clampTo(input.isEmpty ? 0 : input.first, domain, 0);
    final t = n == 1 ? x : math.pow(x, n).toDouble();
    return [
      for (var i = 0; i < c0.length && i < c1.length; i++)
        c0[i] + t * (c1[i] - c0[i]),
    ];
  }
}

class _Stitched extends PdfFunction {
  const _Stitched(this.domain, this.functions, this.bounds, this.encode);
  final List<double> domain, bounds, encode;
  final List<PdfFunction> functions;

  @override
  List<double> call(List<double> input) {
    final x = _clampTo(input.isEmpty ? 0 : input.first, domain, 0);
    var k = 0;
    while (k < bounds.length && x >= bounds[k]) {
      k++;
    }
    k = k.clamp(0, functions.length - 1);
    final lo = k == 0 ? domain[0] : bounds[k - 1];
    final hi = k < bounds.length ? bounds[k] : domain[1];
    final e0 = encode.length > 2 * k ? encode[2 * k] : 0.0;
    final e1 = encode.length > 2 * k + 1 ? encode[2 * k + 1] : 1.0;
    final t = hi == lo ? e0 : e0 + (x - lo) * (e1 - e0) / (hi - lo);
    return functions[k]([t]);
  }
}

class _Sampled extends PdfFunction {
  _Sampled(this.domain, this.range, this.size, this.outputs, this.samples,
      this.encode, this.decode);

  static _Sampled? read(
    PdfFile doc,
    PdfStream stream,
    List<double> domain,
    List<double>? range,
  ) {
    final dict = stream.dict;
    final size = _numbers(doc, dict['Size'])?.map((e) => e.toInt()).toList();
    final bits = (doc.resolve(dict['BitsPerSample']) as num?)?.toInt() ?? 8;
    if (size == null || size.isEmpty || range == null) return null;
    if (size.any((s) => s < 1 || s > 65536)) return null;
    final outputs = range.length ~/ 2;
    final count = size.fold<int>(1, (a, b) => a * b) * outputs;
    if (count <= 0 || count > 1 << 20) return null;
    final data = doc.decodeStream(stream);
    final max = (1 << bits) - 1;
    final samples = Float64List(count);
    var bit = 0;
    for (var i = 0; i < count; i++) {
      var v = 0;
      for (var b = 0; b < bits; b++) {
        final at = bit >> 3;
        final on = at < data.length && (data[at] >> (7 - (bit & 7))) & 1 == 1;
        v = (v << 1) | (on ? 1 : 0);
        bit++;
      }
      samples[i] = v / max;
    }
    final encode = _numbers(doc, dict['Encode']) ??
        [for (final s in size) ...[0.0, (s - 1).toDouble()]];
    final decode = _numbers(doc, dict['Decode']) ?? range;
    return _Sampled(domain, range, size, outputs, samples, encode, decode);
  }

  final List<double> domain, range, encode, decode;
  final List<int> size;
  final int outputs;
  final Float64List samples;

  @override
  List<double> call(List<double> input) {
    // Interpolated along the first input, nearest along the rest, which is
    // exact for the one input functions shadings are made of.
    var offset = 0;
    var stride = outputs;
    var frac = 0.0, lo = 0, hi = 0;
    for (var i = 0; i < size.length; i++) {
      final x = _clampTo(i < input.length ? input[i] : 0, domain, i);
      final d0 = domain.length > 2 * i ? domain[2 * i] : 0.0;
      final d1 = domain.length > 2 * i + 1 ? domain[2 * i + 1] : 1.0;
      final e0 = encode[2 * i], e1 = encode[2 * i + 1];
      var e = d1 == d0 ? e0 : e0 + (x - d0) * (e1 - e0) / (d1 - d0);
      e = e.clamp(0, (size[i] - 1).toDouble());
      if (i == 0) {
        lo = e.floor();
        hi = math.min(lo + 1, size[0] - 1);
        frac = e - lo;
      } else {
        offset += e.round() * stride;
      }
      stride *= size[i];
    }
    return [
      for (var o = 0; o < outputs; o++)
        () {
          final a = samples[offset + lo * outputs + o];
          final b = samples[offset + hi * outputs + o];
          final v = a + (b - a) * frac;
          final r = decode[2 * o] + v * (decode[2 * o + 1] - decode[2 * o]);
          return _clampTo(r, range, o);
        }(),
    ];
  }
}

/// A PostScript calculator function, the subset of PostScript a type 4
/// function may use: arithmetic, comparison, booleans and `if`/`ifelse`.
class _Calculator extends PdfFunction {
  const _Calculator(this.domain, this.range, this.program);
  final List<double> domain, range;
  final List<Object> program;

  /// The procedure in [source] as numbers, operator names and nested lists,
  /// or null when it is not one.
  static List<Object>? parse(Uint8List source) {
    final text = String.fromCharCodes(source);
    final tokens = RegExp(r'[{}]|[^\s{}]+').allMatches(text).map((m) => m[0]!);
    final stack = <List<Object>>[];
    List<Object>? top;
    for (final token in tokens) {
      if (token == '{') {
        final next = <Object>[];
        if (stack.isNotEmpty) stack.last.add(next);
        stack.add(next);
      } else if (token == '}') {
        if (stack.isEmpty) return null;
        top = stack.removeLast();
      } else {
        if (stack.isEmpty) return null;
        final n = num.tryParse(token);
        stack.last.add(n ?? token);
      }
      if (stack.length > 64) return null;
    }
    return stack.isEmpty ? top : null;
  }

  @override
  List<double> call(List<double> input) {
    final stack = <Object>[
      for (var i = 0; i < input.length; i++) _clampTo(input[i], domain, i),
    ];
    var steps = 0;
    void run(List<Object> proc) {
      for (final item in proc) {
        if (++steps > 10000) throw const FormatException('runaway');
        if (item is num || item is List) {
          stack.add(item);
          continue;
        }
        _op(item as String, stack, run);
      }
    }

    run(program);
    final out = stack.whereType<num>().map((e) => e.toDouble()).toList();
    final n = range.length ~/ 2;
    final tail = out.length > n && n > 0 ? out.sublist(out.length - n) : out;
    return [for (var i = 0; i < tail.length; i++) _clampTo(tail[i], range, i)];
  }

  static void _op(
    String op,
    List<Object> s,
    void Function(List<Object>) run,
  ) {
    num n() => s.removeLast() as num;
    bool b() => s.removeLast() as bool;
    switch (op) {
      case 'add':
        final y = n(), x = n();
        s.add(x + y);
      case 'sub':
        final y = n(), x = n();
        s.add(x - y);
      case 'mul':
        final y = n(), x = n();
        s.add(x * y);
      case 'div':
        final y = n(), x = n();
        s.add(y == 0 ? 0.0 : x / y);
      case 'idiv':
        final y = n().toInt(), x = n().toInt();
        s.add(y == 0 ? 0 : x ~/ y);
      case 'mod':
        final y = n().toInt(), x = n().toInt();
        s.add(y == 0 ? 0 : x.remainder(y));
      case 'neg':
        s.add(-n());
      case 'abs':
        s.add(n().abs());
      case 'ceiling':
        s.add(n().ceilToDouble());
      case 'floor':
        s.add(n().floorToDouble());
      case 'round':
        s.add((n() + 0.5).floorToDouble());
      case 'truncate':
        s.add(n().truncateToDouble());
      case 'sqrt':
        s.add(math.sqrt(n()));
      case 'sin':
        s.add(math.sin(n() * math.pi / 180));
      case 'cos':
        s.add(math.cos(n() * math.pi / 180));
      case 'atan':
        final den = n(), numer = n();
        var a = math.atan2(numer, den) * 180 / math.pi;
        if (a < 0) a += 360;
        s.add(a);
      case 'exp':
        final e = n(), base = n();
        s.add(math.pow(base, e).toDouble());
      case 'ln':
        s.add(math.log(n()));
      case 'log':
        s.add(math.log(n()) / math.ln10);
      case 'cvi':
        s.add(n().truncate());
      case 'cvr':
        s.add(n().toDouble());
      case 'eq':
        final y = s.removeLast(), x = s.removeLast();
        s.add(x == y);
      case 'ne':
        final y = s.removeLast(), x = s.removeLast();
        s.add(x != y);
      case 'gt':
        final y = n(), x = n();
        s.add(x > y);
      case 'ge':
        final y = n(), x = n();
        s.add(x >= y);
      case 'lt':
        final y = n(), x = n();
        s.add(x < y);
      case 'le':
        final y = n(), x = n();
        s.add(x <= y);
      case 'and':
        final y = s.removeLast(), x = s.removeLast();
        s.add(x is bool && y is bool ? x && y : (x as num).toInt() & (y as num).toInt());
      case 'or':
        final y = s.removeLast(), x = s.removeLast();
        s.add(x is bool && y is bool ? x || y : (x as num).toInt() | (y as num).toInt());
      case 'xor':
        final y = s.removeLast(), x = s.removeLast();
        s.add(x is bool && y is bool ? x != y : (x as num).toInt() ^ (y as num).toInt());
      case 'not':
        final x = s.removeLast();
        s.add(x is bool ? !x : ~(x as num).toInt());
      case 'bitshift':
        final by = n().toInt(), x = n().toInt();
        s.add(by >= 0 ? x << by : x >> -by);
      case 'true':
        s.add(true);
      case 'false':
        s.add(false);
      case 'if':
        final proc = s.removeLast() as List<Object>;
        if (b()) run(proc);
      case 'ifelse':
        final no = s.removeLast() as List<Object>;
        final yes = s.removeLast() as List<Object>;
        run(b() ? yes : no);
      case 'pop':
        s.removeLast();
      case 'exch':
        final y = s.removeLast(), x = s.removeLast();
        s
          ..add(y)
          ..add(x);
      case 'dup':
        s.add(s.last);
      case 'copy':
        final count = n().toInt();
        s.addAll(s.sublist(s.length - count));
      case 'index':
        final at = n().toInt();
        s.add(s[s.length - 1 - at]);
      case 'roll':
        final j = n().toInt(), count = n().toInt();
        if (count > 0) {
          final part = s.sublist(s.length - count);
          s.removeRange(s.length - count, s.length);
          final shift = j % count;
          s
            ..addAll(part.sublist(count - shift))
            ..addAll(part.sublist(0, count - shift));
        }
      default:
        throw FormatException('unknown operator $op');
    }
  }
}

/// A colour space read far enough to turn a colour's components into ARGB.
class PdfColourSpace {
  PdfColourSpace._(this.components, this._convert);

  final int components;
  final int Function(List<double>) _convert;

  int argb(List<double> c) => _convert(c);

  static final gray = PdfColourSpace._(1, (c) => _rgb(c[0], c[0], c[0]));
  static final rgb = PdfColourSpace._(3, (c) => _rgb(c[0], c[1], c[2]));
  static final cmyk = PdfColourSpace._(4, (c) => _rgb(
        (1 - c[0]) * (1 - c[3]),
        (1 - c[1]) * (1 - c[3]),
        (1 - c[2]) * (1 - c[3]),
      ));

  /// [raw] as a colour space, or null for one this reader cannot convert,
  /// which is a pattern, an indexed space in a shading, or Lab.
  static PdfColourSpace? read(PdfFile doc, Object? raw, [int depth = 0]) {
    if (depth > 4) return null;
    final value = doc.resolve(raw);
    if (value is PdfName) {
      return switch (value.value) {
        'DeviceGray' || 'G' || 'CalGray' => gray,
        'DeviceRGB' || 'RGB' || 'CalRGB' => rgb,
        'DeviceCMYK' || 'CMYK' => cmyk,
        _ => null,
      };
    }
    if (value is! List || value.isEmpty) return null;
    final family = doc.resolve(value.first);
    final name = family is PdfName ? family.value : '';
    switch (name) {
      case 'ICCBased':
        final stream = value.length > 1 ? doc.resolve(value[1]) : null;
        final n = stream is PdfStream
            ? (doc.resolve(stream.dict['N']) as num?)?.toInt()
            : null;
        return switch (n) { 1 => gray, 3 => rgb, 4 => cmyk, _ => null };
      case 'CalGray':
        return gray;
      case 'CalRGB':
        return rgb;
      case 'Separation' || 'DeviceN':
        if (value.length < 4) return null;
        final names = doc.resolve(value[1]);
        final count = name == 'Separation' ? 1 : (names is List ? names.length : 0);
        final alternate = read(doc, value[2], depth + 1);
        final tint = PdfFunction.read(doc, value[3]);
        if (count <= 0 || alternate == null || tint == null) return null;
        return PdfColourSpace._(count, (c) {
          final out = tint(c);
          if (out.length < alternate.components) return 0xFF000000;
          return alternate.argb(out);
        });
    }
    return null;
  }

  static int _rgb(double r, double g, double b) {
    int ch(double v) => (v.clamp(0.0, 1.0) * 255).round();
    return 0xFF000000 | (ch(r) << 16) | (ch(g) << 8) | ch(b);
  }
}

/// How many colours a shading is sampled into along its axis. Past this the
/// steps are finer than eight bit colour can show.
const kShadingSamples = 64;

/// An axial or radial shading, sampled into colours evenly spread along its
/// parameter.
class PdfShading {
  PdfShading._({
    required this.type,
    required this.coords,
    required this.colors,
    required this.extendStart,
    required this.extendEnd,
  });

  /// 2 for axial, 3 for radial.
  final int type;

  /// x0 y0 x1 y1 for axial, x0 y0 r0 x1 y1 r1 for radial, in the space the
  /// shading was painted in.
  final List<double> coords;
  final List<int> colors;
  final bool extendStart, extendEnd;

  /// [raw] read as a shading this reader can draw, or null. [unsupported]
  /// hears the type of one it cannot.
  static PdfShading? read(
    PdfFile doc,
    Object? raw, {
    void Function(String)? unsupported,
  }) {
    final value = doc.resolve(raw);
    final dict = value is PdfStream ? value.dict : doc.dict(value);
    if (dict == null) return null;
    final type = (doc.resolve(dict['ShadingType']) as num?)?.toInt() ?? 0;
    if (type != 2 && type != 3) {
      unsupported?.call('sh:type$type');
      return null;
    }
    final coords = _numbers(doc, dict['Coords']);
    final space = PdfColourSpace.read(doc, dict['ColorSpace']);
    final function = PdfFunction.read(doc, dict['Function']);
    if (coords == null ||
        coords.length != (type == 2 ? 4 : 6) ||
        space == null ||
        function == null) {
      unsupported?.call('sh:unreadable');
      return null;
    }
    final domain = _numbers(doc, dict['Domain']) ?? const [0.0, 1.0];
    final extend = doc.resolve(dict['Extend']);
    bool extendAt(int i) =>
        extend is List && extend.length == 2 && doc.resolve(extend[i]) == true;
    final t0 = domain.isNotEmpty ? domain[0] : 0.0;
    final t1 = domain.length > 1 ? domain[1] : 1.0;
    final colors = <int>[];
    for (var i = 0; i < kShadingSamples; i++) {
      final t = t0 + (t1 - t0) * i / (kShadingSamples - 1);
      try {
        final out = function([t]);
        colors.add(
          out.length >= space.components ? space.argb(out) : 0xFF000000,
        );
      } on Object {
        unsupported?.call('sh:function');
        return null;
      }
    }
    return PdfShading._(
      type: type,
      coords: coords,
      colors: colors,
      extendStart: extendAt(0),
      extendEnd: extendAt(1),
    );
  }
}
