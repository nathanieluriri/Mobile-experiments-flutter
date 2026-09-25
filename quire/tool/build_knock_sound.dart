/// Writes `android/app/src/main/res/raw/quire_knock.wav`, the sound of the
/// notice that a document has arrived: a short, soft double knock on wood.
///
/// It is written here rather than dropped in as a recording, so what it is
/// can be read and changed. Each knock is two damped tones, the low body of a
/// panel and a higher click of its surface, over a millisecond of noise for
/// the strike. The second knock comes 65 ms after the first and a little
/// softer, the way a hand knocks twice.
///
/// If it does not sound good on a phone, the notice should use the phone's
/// own sound instead: a bad notification sound is uninstalled faster than a
/// missing one. The channel is `new_documents_v1`, and a released channel's
/// sound cannot be changed, so a different sound after release needs `_v2`.
///
/// Run it from the app directory:
///
///     dart run tool/build_knock_sound.dart
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int kRate = 44100;
const double kLength = 0.130;

/// Peak level, well short of full scale: a knock, not a bang.
const double kLevel = 0.42;

void main() {
  final samples = Float64List((kRate * kLength).round());
  _knock(samples, at: 0.000, gain: 1.00);
  _knock(samples, at: 0.065, gain: 0.78);
  _fadeOut(samples, 0.008);
  File('android/app/src/main/res/raw/quire_knock.wav')
      .writeAsBytesSync(wav(samples));
}

/// One knock starting [at] seconds in.
void _knock(Float64List out, {required double at, required double gain}) {
  final start = (at * kRate).round();
  var seed = 0x1234567 + start;
  double noise() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x3fffffff - 1;
  }

  var lowPassed = 0.0;
  for (var i = 0; start + i < out.length; i++) {
    final t = i / kRate;
    final body = 0.62 * math.sin(2 * math.pi * 520 * t) * math.exp(-t / 0.011);
    final surface =
        0.30 * math.sin(2 * math.pi * 1650 * t) * math.exp(-t / 0.005);
    lowPassed += 0.35 * (noise() - lowPassed);
    final strike = 0.25 * lowPassed * math.exp(-t / 0.0012);
    out[start + i] += gain * kLevel * (body + surface + strike);
  }
}

void _fadeOut(Float64List out, double seconds) {
  final n = (seconds * kRate).round();
  for (var i = 0; i < n; i++) {
    out[out.length - 1 - i] *= i / n;
  }
}

/// [samples] as 16 bit mono PCM in a WAV container.
Uint8List wav(Float64List samples) {
  final data = ByteData(44 + samples.length * 2);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, kRate, Endian.little)
    ..setUint32(28, kRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}
