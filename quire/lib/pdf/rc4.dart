import 'dart:typed_data';

/// RC4, the stream cipher the PDF standard security handler uses for /V 1 and
/// /V 2 files.
///
/// One function serves both directions because RC4 is symmetric: the cipher
/// produces a keystream and XORs it into the data, so decrypting is the same
/// operation as encrypting. That is also why the whole of PDF decryption is a
/// key derivation problem rather than a cipher problem.
Uint8List rc4(List<int> key, List<int> data) {
  if (key.isEmpty) return Uint8List.fromList(data);

  final s = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    s[i] = i;
  }

  // Key scheduling.
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xff;
    final swap = s[i];
    s[i] = s[j];
    s[j] = swap;
  }

  // Keystream generation.
  final out = Uint8List(data.length);
  var a = 0;
  var b = 0;
  for (var k = 0; k < data.length; k++) {
    a = (a + 1) & 0xff;
    b = (b + s[a]) & 0xff;
    final swap = s[a];
    s[a] = s[b];
    s[b] = swap;
    out[k] = data[k] ^ s[(s[a] + s[b]) & 0xff];
  }
  return out;
}
