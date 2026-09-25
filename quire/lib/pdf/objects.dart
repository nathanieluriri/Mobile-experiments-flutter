import 'dart:typed_data';

/// A PDF name, e.g. /Type. Stored without the slash.
class PdfName {
  const PdfName(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is PdfName && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '/$value';
}

/// An indirect reference, e.g. `12 0 R`.
class PdfRef {
  const PdfRef(this.number, this.generation);
  final int number;
  final int generation;
  @override
  bool operator ==(Object other) =>
      other is PdfRef && other.number == number && other.generation == generation;
  @override
  int get hashCode => Object.hash(number, generation);
  @override
  String toString() => '$number $generation R';
}

/// A literal or hex string. Kept as raw bytes because encoding depends on font.
class PdfString {
  const PdfString(this.bytes);
  final Uint8List bytes;
  String get asLatin1 => String.fromCharCodes(bytes);
  @override
  String toString() => 'PdfString(${bytes.length}B)';
}

/// A stream object: its dictionary plus the still-encoded bytes.
class PdfStream {
  PdfStream(this.dict, this.raw);
  final Map<String, Object?> dict;
  final Uint8List raw;
  @override
  String toString() => 'PdfStream(${dict.keys.toList()}, ${raw.length}B)';
}
