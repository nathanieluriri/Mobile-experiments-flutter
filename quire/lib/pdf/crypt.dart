import 'dart:typed_data';

import 'objects.dart';
import 'rc4.dart';

/// The standard security handler of ISO 32000-1 section 7.6, for the RC4
/// ciphers: /V 1 and 2, and /V 4 whose crypt filter is /V2.
///
/// Every step here is a key derivation. RC4 itself is twenty lines; what makes
/// an encrypted file open or come back as uniform noise is whether the bytes
/// fed into MD5 are exactly the bytes the specification names, in exactly its
/// order. There is no near miss. That is why the user password check exists as
/// a free oracle and is run before a single stream is touched.

/// The 32 byte padding string of Algorithm 2, step (a).
const List<int> kPasswordPad = <int>[
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
  0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
  0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
];

/// The cipher name reported for a file this reader can decrypt given the right
/// password.
const String kCipherRc4 = 'RC4';

/// A password padded to the 32 bytes Algorithm 2 wants: the password's own
/// bytes first, truncated at 32, then as much of [kPasswordPad] as fits.
Uint8List padPassword(List<int> password) {
  final out = Uint8List(32);
  final take = password.length < 32 ? password.length : 32;
  out.setRange(0, take, password);
  out.setRange(take, 32, kPasswordPad);
  return out;
}

/// Algorithm 2: the file encryption key.
///
/// [permissions] is written as a four byte little endian two's complement
/// value. /P is routinely negative (one real file carries -60), and treating it
/// as unsigned or as big endian derives a key that fails with no clue why.
Uint8List fileEncryptionKey({
  required Uint8List password32,
  required Uint8List ownerEntry,
  required int permissions,
  required Uint8List firstId,
  required int revision,
  required int keyBytes,
  bool encryptMetadata = true,
}) {
  final input = BytesBuilder(copy: false)
    ..add(password32)
    ..add(ownerEntry);

  final p = ByteData(4)..setUint32(0, permissions & 0xffffffff, Endian.little);
  input
    ..add(p.buffer.asUint8List())
    ..add(firstId);

  // Revision 4 added a metadata switch, and a file that leaves its metadata in
  // clear has to say so inside the key, or two readers would disagree about
  // every other object in it.
  if (revision >= 4 && !encryptMetadata) {
    input.add(const <int>[0xff, 0xff, 0xff, 0xff]);
  }

  var hash = md5(input.takeBytes());
  if (revision >= 3) {
    for (var i = 0; i < 50; i++) {
      hash = md5(Uint8List.sublistView(hash, 0, keyBytes));
    }
  }
  return Uint8List.fromList(Uint8List.sublistView(hash, 0, keyBytes));
}

/// Algorithm 1: the key one object's strings and streams are encrypted with.
///
/// Every object carries its own key, derived from its own object and
/// generation numbers, so a stream decrypted with the numbers of the object
/// that merely pointed at it comes back as noise.
Uint8List objectEncryptionKey(Uint8List fileKey, int number, int generation) {
  final input = Uint8List(fileKey.length + 5)
    ..setRange(0, fileKey.length, fileKey);
  var at = fileKey.length;
  input[at++] = number & 0xff;
  input[at++] = (number >> 8) & 0xff;
  input[at++] = (number >> 16) & 0xff;
  input[at++] = generation & 0xff;
  input[at] = (generation >> 8) & 0xff;

  final hash = md5(input);
  final take = fileKey.length + 5 < 16 ? fileKey.length + 5 : 16;
  return Uint8List.fromList(Uint8List.sublistView(hash, 0, take));
}

/// Algorithms 4 and 5: what /U must hold when [fileKey] is the right key.
///
/// This is the oracle. Recomputing /U costs one MD5 and at most twenty RC4
/// passes, so a wrong password is known to be wrong before anything is
/// decrypted, and a right password proves the key as well as itself.
Uint8List userEntryFor({
  required Uint8List fileKey,
  required Uint8List firstId,
  required int revision,
}) {
  if (revision < 3) return rc4(fileKey, padPassword(const <int>[]));

  final seed = BytesBuilder(copy: false)
    ..add(kPasswordPad)
    ..add(firstId);
  var value = rc4(fileKey, md5(seed.takeBytes()));
  for (var i = 1; i <= 19; i++) {
    value = rc4(_keyXor(fileKey, i), value);
  }
  return value;
}

/// Algorithm 3: what /O must hold for [ownerPassword] to reach a file whose
/// user password is [userPassword].
///
/// This is [PdfCrypt.unlockAsOwner] read backwards, and the two only make
/// sense together. /O is not a hash of the owner password: it is the user
/// password locked up with it, which is what lets an owner open a file whose
/// user password nobody ever wrote down, and why deriving it needs both.
Uint8List ownerEntryFor({
  required List<int> ownerPassword,
  required List<int> userPassword,
  required int revision,
  required int keyBytes,
}) {
  // Step (a): an owner password left blank is the user password. A file sealed
  // with one password still needs a well formed /O, or the owner's way in
  // would decrypt to noise instead of to that password.
  final owner = ownerPassword.isEmpty ? userPassword : ownerPassword;
  var hash = md5(padPassword(owner));
  if (revision >= 3) {
    for (var i = 0; i < 50; i++) {
      hash = md5(hash);
    }
  }
  final key = Uint8List.sublistView(hash, 0, keyBytes);

  var value = padPassword(userPassword);
  if (revision < 3) return rc4(key, value);
  // Twenty passes, keyed 0 to 19, which unlockAsOwner peels off from 19 down.
  // Run them in the other order and the file opens for nobody.
  for (var i = 0; i <= 19; i++) {
    value = rc4(_keyXor(key, i), value);
  }
  return value;
}

Uint8List _keyXor(Uint8List key, int step) {
  final out = Uint8List(key.length);
  for (var i = 0; i < key.length; i++) {
    out[i] = key[i] ^ step;
  }
  return out;
}

/// The /Encrypt dictionary reduced to the fields the standard handler needs.
class PdfSecurity {
  const PdfSecurity({
    required this.cipher,
    required this.version,
    required this.revision,
    required this.keyBytes,
    required this.ownerEntry,
    required this.userEntry,
    required this.permissions,
    required this.encryptMetadata,
    required this.encryptStreams,
    required this.encryptStrings,
  });

  /// [kCipherRc4] when this reader can decrypt the file given the right
  /// password, otherwise the cipher's own name, for example `AESV2`.
  final String cipher;
  final int version;
  final int revision;
  final int keyBytes;
  final Uint8List ownerEntry;
  final Uint8List userEntry;
  final int permissions;
  final bool encryptMetadata;
  final bool encryptStreams;
  final bool encryptStrings;

  /// Reads the dictionary. [lookup] resolves indirect references, because /O,
  /// /U and /Length are all allowed to be indirect objects.
  static PdfSecurity read(
    Map<String, Object?> dict,
    Object? Function(Object?) lookup,
  ) {
    int intAt(String key, int fallback) {
      final v = lookup(dict[key]);
      return v is num ? v.toInt() : fallback;
    }

    Uint8List stringAt(String key) {
      final v = lookup(dict[key]);
      return v is PdfString ? v.bytes : Uint8List(0);
    }

    final filter = lookup(dict['Filter']);
    final version = intAt('V', 0);
    final revision = intAt('R', version >= 4 ? 4 : 2);
    var keyBytes = _clampKeyBytes(version == 1 ? 40 : intAt('Length', 40));

    final metadata = lookup(dict['EncryptMetadata']);
    var streams = true;
    var strings = true;
    String cipher;

    if (filter is! PdfName || filter.value != 'Standard') {
      cipher = filter is PdfName ? filter.value : 'unknown';
    } else if (version == 1 || version == 2) {
      cipher = kCipherRc4;
    } else if (version == 4) {
      String nameAt(String key) {
        final v = lookup(dict[key]);
        return v is PdfName ? v.value : 'Identity';
      }

      final stmF = nameAt('StmF');
      final strF = nameAt('StrF');
      streams = stmF != 'Identity';
      strings = strF != 'Identity';
      final filters = lookup(dict['CF']);
      final named = streams ? stmF : strF;
      final entry =
          filters is Map<String, Object?> ? lookup(filters[named]) : null;
      final selected = entry is Map<String, Object?> ? entry : null;
      final method = selected == null ? null : lookup(selected['CFM']);
      final cfm = method is PdfName ? method.value : 'None';
      if (cfm == 'V2') {
        cipher = kCipherRc4;
        final len = selected == null ? null : lookup(selected['Length']);
        // A crypt filter states its length in bytes, but writers exist that
        // put bits here, so a value that can only be bits is divided down.
        if (len is num) {
          final v = len.toInt();
          keyBytes = _clampKeyBytes(v > 40 ? v : v * 8);
        }
      } else if (!streams && !strings) {
        cipher = kCipherRc4;
      } else {
        cipher = cfm;
      }
    } else {
      cipher = version == 5 ? 'AESV3' : 'V$version';
    }

    return PdfSecurity(
      cipher: cipher,
      version: version,
      revision: revision,
      keyBytes: keyBytes,
      ownerEntry: stringAt('O'),
      userEntry: stringAt('U'),
      permissions: intAt('P', 0),
      encryptMetadata: metadata is! bool || metadata,
      encryptStreams: streams,
      encryptStrings: strings,
    );
  }

  static int _clampKeyBytes(int bits) {
    final bytes = bits ~/ 8;
    if (bytes < 5) return 5;
    if (bytes > 16) return 16;
    return bytes;
  }
}

/// A file key that has already been proved against /U, plus the per object
/// derivation every string and stream goes through.
class PdfCrypt {
  const PdfCrypt(this.fileKey, this.security);
  final Uint8List fileKey;
  final PdfSecurity security;

  /// Algorithm 6. Returns null when [password32] is not the user password,
  /// which is how a wrong password is told from a right one.
  static PdfCrypt? unlock(
    PdfSecurity security,
    Uint8List firstId,
    Uint8List password32,
  ) {
    final key = fileEncryptionKey(
      password32: password32,
      ownerEntry: security.ownerEntry,
      permissions: security.permissions,
      firstId: firstId,
      revision: security.revision,
      keyBytes: security.keyBytes,
      encryptMetadata: security.encryptMetadata,
    );
    final expected = userEntryFor(
      fileKey: key,
      firstId: firstId,
      revision: security.revision,
    );
    // Revision 3 pads /U out to 32 bytes with arbitrary bytes, so only the
    // first 16 carry a claim and comparing all 32 would reject a good key.
    final compare = security.revision < 3 ? 32 : 16;
    if (security.userEntry.length < compare || expected.length < compare) {
      return null;
    }
    for (var i = 0; i < compare; i++) {
      if (security.userEntry[i] != expected[i]) return null;
    }
    return PdfCrypt(key, security);
  }

  /// Algorithm 7: recovers the user password out of /O with the owner
  /// password, then hands it to [unlock]. An owner who typed their own
  /// password should not be told it is the wrong one.
  static PdfCrypt? unlockAsOwner(
    PdfSecurity security,
    Uint8List firstId,
    List<int> ownerPassword,
  ) {
    if (security.ownerEntry.length < 32) return null;
    var hash = md5(padPassword(ownerPassword));
    if (security.revision >= 3) {
      for (var i = 0; i < 50; i++) {
        hash = md5(hash);
      }
    }
    final key = Uint8List.sublistView(hash, 0, security.keyBytes);

    var value = Uint8List.fromList(
      Uint8List.sublistView(security.ownerEntry, 0, 32),
    );
    if (security.revision < 3) {
      value = rc4(key, value);
    } else {
      for (var i = 19; i >= 0; i--) {
        value = rc4(_keyXor(key, i), value);
      }
    }
    return unlock(security, firstId, value);
  }

  /// The bytes of one string or stream, in clear.
  Uint8List decrypt(Uint8List data, int number, int generation) =>
      rc4(objectEncryptionKey(fileKey, number, generation), data);
}

// ------------------------------------------------------------------- MD5

const List<int> _md5Shifts = <int>[
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

const List<int> _md5Sines = <int>[
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, //
  0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
  0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
  0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
  0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
  0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
];

/// MD5, written out here rather than pulled in as a dependency.
///
/// The standard security handler needs exactly one hash, and the parsing layer
/// staying package free is what keeps it testable on the host with no device
/// in sight.
Uint8List md5(List<int> message) {
  var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;

  final length = message.length;
  final padded = Uint8List(((length + 8) ~/ 64 + 1) * 64);
  padded.setRange(0, length, message);
  padded[length] = 0x80;
  final view = ByteData.sublistView(padded);
  final bits = length * 8;
  view
    ..setUint32(padded.length - 8, bits & 0xffffffff, Endian.little)
    ..setUint32(padded.length - 4, (bits >> 32) & 0xffffffff, Endian.little);

  final block = Uint32List(16);
  for (var chunk = 0; chunk < padded.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      block[i] = view.getUint32(chunk + i * 4, Endian.little);
    }
    var a = a0, b = b0, c = c0, d = d0;
    for (var i = 0; i < 64; i++) {
      int f, g;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) & 15;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) & 15;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) & 15;
      }
      f = (f + a + _md5Sines[i] + block[g]) & 0xffffffff;
      final s = _md5Shifts[i];
      a = d;
      d = c;
      c = b;
      b = (b + (((f << s) | (f >> (32 - s))) & 0xffffffff)) & 0xffffffff;
    }
    a0 = (a0 + a) & 0xffffffff;
    b0 = (b0 + b) & 0xffffffff;
    c0 = (c0 + c) & 0xffffffff;
    d0 = (d0 + d) & 0xffffffff;
  }

  final out = Uint8List(16);
  ByteData.sublistView(out)
    ..setUint32(0, a0, Endian.little)
    ..setUint32(4, b0, Endian.little)
    ..setUint32(8, c0, Endian.little)
    ..setUint32(12, d0, Endian.little);
  return out;
}
