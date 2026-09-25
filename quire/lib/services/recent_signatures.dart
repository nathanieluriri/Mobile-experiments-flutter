import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// How many signatures the pad keeps to be used again.
///
/// Ten is more names than one person signs with and few enough to see in one
/// sweep of the strip, which is the whole point of keeping them: finding the
/// one you want has to be quicker than drawing it again.
const kRecentSignatureLimit = 10;

/// A signature kept to be used again: either the ribbons a hand drew, or the
/// file of a picture somebody brought in.
class SavedSignature {
  const SavedSignature({
    required this.outlines,
    required this.bounds,
    this.encoded,
    this.picture,
  });

  /// Each ribbon as a closed polygon in the unit square of [bounds]. Empty
  /// for a picture.
  final List<List<ui.Offset>> outlines;

  /// The box the mark was drawn in, which is what gives it its proportions.
  final ui.Rect bounds;

  /// The picture's own file, for a signature that is one.
  final Uint8List? encoded;

  /// That picture decoded, once it has been.
  final ui.Image? picture;

  bool get isPicture => encoded != null;

  /// The same signature with its picture decoded.
  SavedSignature withPicture(ui.Image decoded) => SavedSignature(
        outlines: outlines,
        bounds: bounds,
        encoded: encoded,
        picture: decoded,
      );

  /// True when [other] is the same signature, so using a kept one again moves
  /// it to the front rather than keeping it twice.
  bool sameAs(SavedSignature other) {
    final a = encoded;
    final b = other.encoded;
    if (a != null || b != null) {
      if (a == null || b == null || a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    if (outlines.length != other.outlines.length) return false;
    for (var i = 0; i < outlines.length; i++) {
      final mine = outlines[i];
      final theirs = other.outlines[i];
      if (mine.length != theirs.length) return false;
      for (var j = 0; j < mine.length; j++) {
        if ((mine[j] - theirs[j]).distance > 1e-6) return false;
      }
    }
    return true;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'bounds': <double>[bounds.left, bounds.top, bounds.width, bounds.height],
        'outlines': <Object?>[
          for (final outline in outlines)
            <Object?>[
              for (final point in outline) <double>[point.dx, point.dy],
            ],
        ],
        if (encoded != null) 'picture': base64Encode(encoded!),
      };

  /// The signature read back, or null for data that does not make one.
  static SavedSignature? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final box = json['bounds'];
    final raw = json['outlines'];
    if (box is! List<Object?> || raw is! List<Object?>) return null;
    final numbers = _doubles(box);
    if (numbers == null || numbers.length != 4) return null;
    Uint8List? bytes;
    final picture = json['picture'];
    if (picture is String && picture.isNotEmpty) {
      try {
        bytes = base64Decode(picture);
      } on FormatException {
        return null;
      }
    }
    final outlines = <List<ui.Offset>>[];
    for (final outline in raw) {
      if (outline is! List<Object?>) return null;
      final points = <ui.Offset>[];
      for (final point in outline) {
        final pair = point is List<Object?> ? _doubles(point) : null;
        if (pair == null || pair.length != 2) return null;
        points.add(ui.Offset(pair[0], pair[1]));
      }
      outlines.add(points);
    }
    if (bytes == null && outlines.isEmpty) return null;
    return SavedSignature(
      outlines: outlines,
      bounds: ui.Rect.fromLTWH(numbers[0], numbers[1], numbers[2], numbers[3]),
      encoded: bytes,
    );
  }

  static List<double>? _doubles(List<Object?> raw) {
    final out = <double>[];
    for (final value in raw) {
      if (value is! num) return null;
      out.add(value.toDouble());
    }
    return out;
  }
}

/// [kept] with [used] at the front, once, and nothing past the limit.
List<SavedSignature> rememberSignature(
  List<SavedSignature> kept,
  SavedSignature used,
) =>
    <SavedSignature>[
      used,
      ...kept.where((s) => !s.sameAs(used)),
    ].take(kRecentSignatureLimit).toList();
