import 'dart:io' show ZLibCodec;
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// The most bytes one stage of a stream's filters may decode to.
///
/// A file says nothing true about how large its streams become. One Flate
/// stage cannot expand past about 1032 to one, but stages chain, and two
/// Flate stages take a kilobyte to a gigabyte. LZW goes further on its own.
/// A phone cannot draw what lies past this anyway: it is a scanned A4 page at
/// 600 dpi with room to spare.
const kMaxDecodedBytes = 128 * 1024 * 1024;

/// How many times its input one stage may decode to, above every ratio a
/// real encoder reaches: Flate's ceiling is about 1032, LZW's about 2730 and
/// run length's 128.
const kMaxDecodeRatio = 4096;

/// The limit one stage decoding [inputLength] bytes is held to.
int decodeLimit(int inputLength) {
  final ratio = inputLength * kMaxDecodeRatio + kMaxDecodeRatio;
  return ratio < kMaxDecodedBytes ? ratio : kMaxDecodedBytes;
}

/// Thrown when a stream decodes past [decodeLimit], before the memory is
/// asked for rather than after.
class PdfStreamTooLarge extends FormatException {
  const PdfStreamTooLarge() : super('stream decodes past its limit');
}

/// A growing buffer that refuses to grow past [limit].
class _Bytes {
  _Bytes(this.limit);
  final int limit;
  Uint8List _buffer = Uint8List(256);
  int length = 0;

  void _room(int extra) {
    final need = length + extra;
    if (need > limit) throw const PdfStreamTooLarge();
    if (need <= _buffer.length) return;
    var size = _buffer.length * 2;
    if (size < need) size = need;
    if (size > limit) size = limit;
    _buffer = Uint8List(size)..setRange(0, length, _buffer);
  }

  void add(int byte) {
    _room(1);
    _buffer[length++] = byte;
  }

  void addAll(List<int> bytes) {
    _room(bytes.length);
    _buffer.setRange(length, length + bytes.length, bytes);
    length += bytes.length;
  }

  Uint8List take() => Uint8List.sublistView(_buffer, 0, length);
}

class _CappedSink implements Sink<List<int>> {
  _CappedSink(int limit) : out = _Bytes(limit);
  final _Bytes out;

  @override
  void add(List<int> chunk) => out.addAll(chunk);

  @override
  void close() {}
}

/// [data] inflated through zlib a slice at a time, so a stream that runs past
/// [limit] is stopped as it passes it rather than once it has all arrived.
Uint8List _inflateCapped(Uint8List data, int limit, {required bool raw}) {
  final sink = _CappedSink(limit);
  final input = ZLibCodec(raw: raw).decoder.startChunkedConversion(sink);
  const slice = 16 * 1024;
  for (var at = 0; at < data.length; at += slice) {
    final end = at + slice < data.length ? at + slice : data.length;
    input.addSlice(data, at, end, false);
  }
  input.close();
  return sink.out.take();
}

/// Inflate, tolerating a raw deflate payload or leading junk, and refusing
/// with [PdfStreamTooLarge] past [decodeLimit].
Uint8List inflate(Uint8List data) {
  if (data.isEmpty) return data;
  final limit = decodeLimit(data.length);
  try {
    return _inflateCapped(data, limit, raw: false);
  } on PdfStreamTooLarge {
    rethrow;
  } catch (_) {}
  try {
    return _inflateCapped(data, limit, raw: true);
  } on PdfStreamTooLarge {
    rethrow;
  } catch (_) {}
  // Some writers emit a stray byte or a broken final block. Retry with an
  // offset, then fall back to a lenient raw inflate that keeps what it got.
  for (var skip = 1; skip < 3 && skip < data.length; skip++) {
    try {
      return _inflateCapped(Uint8List.sublistView(data, skip), limit, raw: false);
    } on PdfStreamTooLarge {
      rethrow;
    } catch (_) {}
  }
  try {
    final out = _CappedOutput(limit);
    Inflate(data, output: out);
    return out.getBytes();
  } on PdfStreamTooLarge {
    rethrow;
  } catch (_) {}
  throw const FormatException('inflate failed');
}

class _CappedOutput extends OutputMemoryStream {
  _CappedOutput(this.limit);
  final int limit;

  void _check(int extra) {
    if (length + extra > limit) throw const PdfStreamTooLarge();
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
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
  final out = _Bytes(decodeLimit(data.length));
  var i = 0;
  while (i < data.length) {
    final n = data[i++];
    if (n == 128) break;
    if (n < 128) {
      final end = (i + n + 1).clamp(0, data.length);
      out.addAll(Uint8List.sublistView(data, i, end));
      i = end;
    } else {
      if (i >= data.length) break;
      final b = data[i++];
      for (var k = 0; k < 257 - n; k++) {
        out.add(b);
      }
    }
  }
  return out.take();
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
  // All three are read out of the file. A row longer than the data is not a
  // row at all, and the buffers below are sized by it: /Columns 2^40 asked
  // for a terabyte and /Columns -1 divided by zero. Nonsense is handed back
  // undecoded, which reads as damage rather than as a crash.
  if (colors < 1 || colors > 32) return data;
  if (bpc != 1 && bpc != 2 && bpc != 4 && bpc != 8 && bpc != 16) return data;
  if (columns < 1 || columns > data.length * 8) return data;
  final bpp = ((colors * bpc + 7) >> 3).clamp(1, 64);
  final rowLen = (columns * colors * bpc + 7) >> 3;
  if (rowLen > data.length) return data;
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
