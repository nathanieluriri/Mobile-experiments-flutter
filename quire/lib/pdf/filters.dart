import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Inflate, tolerating a raw deflate payload or leading junk.
Uint8List inflate(Uint8List data) {
  if (data.isEmpty) return data;
  const zlib = ZLibDecoder();
  try {
    return zlib.decodeBytes(data);
  } catch (_) {}
  try {
    return zlib.decodeBytes(data, raw: true);
  } catch (_) {}
  // Some writers emit a stray byte or a broken final block. Retry with an
  // offset, then fall back to a lenient raw inflate that keeps what it got.
  for (var skip = 1; skip < 3 && skip < data.length; skip++) {
    try {
      return zlib.decodeBytes(data.sublist(skip));
    } catch (_) {}
  }
  try {
    return Inflate(data).getBytes();
  } catch (_) {}
  throw const FormatException('inflate failed');
}

Uint8List ascii85Decode(Uint8List data) {
  final out = <int>[];
  var tuple = 0, count = 0;
  for (var i = 0; i < data.length; i++) {
    final c = data[i];
    if (c == 0x7e) break; // ~>
    if (c <= 0x20 || c == 0) continue;
    if (c == 0x7a && count == 0) {
      out.addAll(const [0, 0, 0, 0]);
      continue;
    }
    if (c < 0x21 || c > 0x75) continue;
    tuple = tuple * 85 + (c - 0x21);
    if (++count == 5) {
      out..add((tuple >> 24) & 0xff)..add((tuple >> 16) & 0xff)
         ..add((tuple >> 8) & 0xff)..add(tuple & 0xff);
      tuple = 0;
      count = 0;
    }
  }
  if (count > 0) {
    for (var i = count; i < 5; i++) {
      tuple = tuple * 85 + 84;
    }
    final full = [(tuple >> 24) & 0xff, (tuple >> 16) & 0xff,
                  (tuple >> 8) & 0xff, tuple & 0xff];
    out.addAll(full.take(count - 1));
  }
  return Uint8List.fromList(out);
}

Uint8List asciiHexDecode(Uint8List data) {
  final out = <int>[];
  int? hi;
  for (final c in data) {
    if (c == 0x3e) break;
    int v;
    if (c >= 0x30 && c <= 0x39) {
      v = c - 0x30;
    } else if (c >= 0x41 && c <= 0x46) {
      v = c - 0x37;
    } else if (c >= 0x61 && c <= 0x66) {
      v = c - 0x57;
    } else {
      continue;
    }
    if (hi == null) {
      hi = v;
    } else {
      out.add(hi * 16 + v);
      hi = null;
    }
  }
  if (hi != null) out.add(hi * 16);
  return Uint8List.fromList(out);
}

Uint8List runLengthDecode(Uint8List data) {
  final out = <int>[];
  var i = 0;
  while (i < data.length) {
    final n = data[i++];
    if (n == 128) break;
    if (n < 128) {
      final end = (i + n + 1).clamp(0, data.length);
      out.addAll(data.sublist(i, end));
      i = end;
    } else {
      if (i >= data.length) break;
      final b = data[i++];
      for (var k = 0; k < 257 - n; k++) {
        out.add(b);
      }
    }
  }
  return Uint8List.fromList(out);
}

/// PNG and TIFF predictors (needed for xref streams and many images).
Uint8List applyPredictor(
  Uint8List data, {
  required int predictor,
  required int colors,
  required int bpc,
  required int columns,
}) {
  if (predictor <= 1) return data;
  final bpp = ((colors * bpc + 7) >> 3).clamp(1, 64);
  final rowLen = (columns * colors * bpc + 7) >> 3;
  if (predictor == 2) {
    if (bpc != 8) return data;
    final out = Uint8List.fromList(data);
    final rows = out.length ~/ rowLen;
    for (var r = 0; r < rows; r++) {
      final base = r * rowLen;
      for (var i = bpp; i < rowLen; i++) {
        out[base + i] = (out[base + i] + out[base + i - bpp]) & 0xff;
      }
    }
    return out;
  }
  // PNG predictors: each row is prefixed with a filter-type byte.
  final stride = rowLen + 1;
  final rows = data.length ~/ stride;
  final out = Uint8List(rows * rowLen);
  final prev = Uint8List(rowLen);
  final cur = Uint8List(rowLen);
  for (var r = 0; r < rows; r++) {
    final ft = data[r * stride];
    final src = r * stride + 1;
    for (var i = 0; i < rowLen; i++) {
      cur[i] = data[src + i];
    }
    switch (ft) {
      case 0:
        break;
      case 1:
        for (var i = bpp; i < rowLen; i++) {
          cur[i] = (cur[i] + cur[i - bpp]) & 0xff;
        }
        break;
      case 2:
        for (var i = 0; i < rowLen; i++) {
          cur[i] = (cur[i] + prev[i]) & 0xff;
        }
        break;
      case 3:
        for (var i = 0; i < rowLen; i++) {
          final left = i >= bpp ? cur[i - bpp] : 0;
          cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 0xff;
        }
        break;
      case 4:
        for (var i = 0; i < rowLen; i++) {
          final a = i >= bpp ? cur[i - bpp] : 0;
          final b = prev[i];
          final c = i >= bpp ? prev[i - bpp] : 0;
          final p = a + b - c;
          final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
          final pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
          cur[i] = (cur[i] + pr) & 0xff;
        }
        break;
      default:
        break;
    }
    out.setRange(r * rowLen, r * rowLen + rowLen, cur);
    prev.setRange(0, rowLen, cur);
  }
  return out;
}
