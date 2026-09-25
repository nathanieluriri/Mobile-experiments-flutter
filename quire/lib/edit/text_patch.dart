import 'dart:convert';
import 'dart:typed_data';

/// A Markdown or CSV file opened for editing as the text it is.
///
/// These are the formats that really do round trip, so a save writes the
/// whole text again. It writes it the way the file was written, though: the
/// same line endings, the same byte order mark, and a last newline only if
/// the file had one. Somebody who changed one word did not ask for every line
/// of their file to change under version control.
class TextPatch {
  TextPatch._(
    this._original,
    this.text,
    this._lineEnd,
    this._bom,
    this._endsWithNewline,
  );

  /// Reads [bytes] as UTF-8, or as Latin-1 where they are not.
  factory TextPatch.read(Uint8List bytes) {
    var start = 0;
    final bom = bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    if (bom) start = 3;
    final body = Uint8List.sublistView(bytes, start);
    String raw;
    try {
      raw = utf8.decode(body);
    } on FormatException {
      raw = latin1.decode(body);
    }
    final crlf = '\r\n'.allMatches(raw).length;
    final lf = '\n'.allMatches(raw).length - crlf;
    final lineEnd = crlf > lf ? '\r\n' : '\n';
    final endsWithNewline = raw.endsWith('\n');
    var text = raw.replaceAll('\r\n', '\n');
    if (endsWithNewline) text = text.substring(0, text.length - 1);
    return TextPatch._(bytes, text, lineEnd, bom, endsWithNewline);
  }

  final Uint8List _original;

  /// The text as it is edited: lines joined by `\n`, and no last newline.
  final String text;

  final String _lineEnd;
  final bool _bom;
  final bool _endsWithNewline;

  /// [edited] written the way the file was: its line endings, its byte order
  /// mark and its last newline.
  ///
  /// Text that was not changed is the file that was read, byte for byte,
  /// whatever it was encoded in.
  Uint8List write(String edited) {
    if (edited == text) return _original;
    var body = edited.replaceAll('\r\n', '\n');
    if (_endsWithNewline) body = '$body\n';
    if (_lineEnd != '\n') body = body.replaceAll('\n', _lineEnd);
    final out = BytesBuilder(copy: false);
    if (_bom) out.add(const [0xEF, 0xBB, 0xBF]);
    out.add(utf8.encode(body));
    return out.takeBytes();
  }
}
