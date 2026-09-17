/// Putting a password on a document: the standard security handler of
/// ISO 32000-1 run in the direction crypt.dart does not.
///
/// crypt.dart is given an /O and a /U somebody else derived and works out
/// whether a typed password implies them. Here quire derives its own:
/// Algorithm 3 for /O, Algorithm 5 for /U, Algorithm 2 for the file key, and
/// then every string and every stream in the document goes out under its own
/// object key. Without this file quire can open a protected document and can
/// never make one, so a reader who wants their own file kept to themselves has
/// to send it somewhere else to be sealed, which is the opposite of the
/// promise the password sheet makes on the way in.
///
/// What it writes is RC4 with a 128 bit key, /V 2 and /R 3, because that is
/// exactly what quire's own reader opens: a file quire seals is a file quire
/// can open, and every other reader old enough to matter takes it as well. It
/// is worth being plain about what that is not. RC4 and MD5 are both long
/// broken, and a key derived from a typed password is never better than the
/// password. This keeps an ordinary document away from ordinary eyes, on a
/// shared phone or in a mail attachment. It is not a safe, and nobody should
/// be sold it as one.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'crypt.dart';
import 'document.dart';
import 'objects.dart';
import 'writer.dart';

/// The handler quire writes: RC4, /V 2, /R 3, 128 bit key.
///
/// Nothing else would do. /V 1 is 40 bits, which is weaker for nothing in
/// return, and /V 4 and /V 5 are AES, which this reader cannot open, so quire
/// would be writing files it would then have to refuse.
const int kSealVersion = 2;
const int kSealRevision = 3;
const int kSealKeyBits = 128;

/// What a sealed document says may be done with it once it is open.
///
/// Every permission the format defines is granted: printing, copying,
/// annotating, filling in forms, assembling, and extraction for a screen
/// reader. The seal here is about getting in at all, and once somebody has
/// typed the password, holding back their own printer would be theatre: /P is
/// advice, honoured only by readers that choose to, and the reader in front of
/// the file is the person who knew its password. Bits 1 and 2 are reserved and
/// stay clear, which is what makes the value -4 rather than -1.
const int kSealedPermissions = -4;

/// [bytes] rewritten so that nothing in it can be read without [password].
///
/// [ownerPassword] is the second way in, for whoever is keeping the document
/// rather than reading it. Left empty it is the user password, which is what
/// Algorithm 3 asks for and means the file has exactly one password.
///
/// Throws [PdfWriteError] when the document cannot be sealed as it stands,
/// with a sentence that can go straight in front of a reader.
Uint8List sealedPdf(
  Uint8List bytes,
  String password, {
  String ownerPassword = '',
}) {
  // An empty password seals nothing. quire tries the empty password on every
  // protected file before it asks anybody anything, and so does every other
  // conforming reader, so the file would come back looking locked and open for
  // the whole world, which is worse than handing back no file at all.
  if (password.isEmpty) {
    throw const PdfWriteError('A password is needed to protect this document.');
  }

  final PdfFile file;
  try {
    file = PdfFile.open(bytes);
  } on PdfLocked {
    throw const PdfWriteError('This document already has a password on it.');
  }
  // A file that opened on the empty password is still an encrypted file: most
  // protected documents in the world carry an owner password alone. Sealing it
  // again would stack a second handler on the first, and a file with two is a
  // file with none.
  if (file.encrypted) {
    throw const PdfWriteError('This document already has a password on it.');
  }
  // Sealing is a rewrite, not an addition, so it can only put back what it
  // could read. A file whose cross reference had to be recovered by scanning
  // is one quire is already reading by guesswork, and a guess written out as
  // the new original would lose whatever it guessed wrong, permanently.
  if (file.recoveredByScan) {
    throw const PdfWriteError(
      'This document is too damaged to protect without losing part of it.',
    );
  }
  if (file.pageCount == 0) {
    throw const PdfWriteError('This document has no pages to protect.');
  }
  return _PdfSeal(file, password, ownerPassword).write();
}

/// One document on its way out under a password.
class _PdfSeal {
  _PdfSeal(this.file, String password, String ownerPassword)
    : _user = _passwordBytes(password),
      _owner = _passwordBytes(ownerPassword);

  final PdfFile file;
  final Uint8List _user;
  final Uint8List _owner;

  static const int _keyBytes = kSealKeyBits ~/ 8;

  /// A stamp taken over the document's own bytes.
  ///
  /// It stands in for the file identifier when the document has none, and it
  /// is the second half of that identifier either way. Taking it from the
  /// bytes rather than from a clock or a random source is what makes sealing
  /// repeatable: the same document under the same password gives back the same
  /// file, so a copy can be told from a change by looking at it.
  late final Uint8List _stamp = md5(file.bytes);

  /// A password is bytes, not text. The handler pads Latin-1 code units, so a
  /// character past 255 is taken a byte at a time. This has to agree with the
  /// reader's own reading of a typed password to the byte, or quire would seal
  /// a file under one password and ask for another.
  static Uint8List _passwordBytes(String password) {
    final out = Uint8List(password.length);
    for (var i = 0; i < password.length; i++) {
      out[i] = password.codeUnitAt(i) & 0xff;
    }
    return out;
  }

  Uint8List write() {
    // The catalogue is the one thing the new trailer cannot be written without,
    // and it is checked before any work is done rather than after all of it.
    final root = _flatten(file.trailer['Root']);
    if (root is! PdfRef) {
      throw const PdfWriteError('This document has no catalogue to protect.');
    }

    final first = _firstId();
    final owner = ownerEntryFor(
      ownerPassword: _owner,
      userPassword: _user,
      revision: kSealRevision,
      keyBytes: _keyBytes,
    );
    final key = fileEncryptionKey(
      password32: padPassword(_user),
      ownerEntry: owner,
      permissions: kSealedPermissions,
      firstId: first,
      revision: kSealRevision,
      keyBytes: _keyBytes,
    );
    final encrypt = <String, Object?>{
      'Filter': const PdfName('Standard'),
      'V': kSealVersion,
      'R': kSealRevision,
      'Length': kSealKeyBits,
      'P': kSealedPermissions,
      'O': PdfString(owner),
      'U': PdfString(_userEntry(key, first)),
    };

    // The key the file is written with is the key quire's own reader works out
    // of the dictionary above, read back through the same parser a reader
    // would use, rather than a second copy kept alongside it. A dictionary
    // that had drifted from the derivation by one field would produce a file
    // that opens for nobody, and there is no recovering from that afterwards:
    // this is where it stops.
    final crypt = PdfCrypt.unlock(
      PdfSecurity.read(encrypt, (value) => value),
      first,
      padPassword(_user),
    );
    if (crypt == null) {
      throw const PdfWriteError('This document could not be protected.');
    }
    final writer = PdfObjectWriter(crypt.decrypt);

    final numbers = file.xref.keys.where((n) => n > 0).toList()..sort();
    final encryptNumber = (numbers.isEmpty ? 0 : numbers.last) + 1;
    final out = BytesBuilder(copy: false)..add(_header());
    final offsets = <int, int>{};
    for (final number in numbers) {
      final object = file.getObject(number);
      if (object == null || _plumbing(object)) continue;
      if (_signed(object)) {
        throw const PdfWriteError(
          'This document carries a digital signature that protecting it '
          'would break.',
        );
      }
      offsets[number] = out.length;
      out.add(_object(writer, number, object));
    }
    offsets[encryptNumber] = out.length;
    // The /Encrypt dictionary is the one object written in clear. Its /O and
    // /U are what a reader checks a password against, so a reader that had to
    // decrypt them first would need the key it is trying to find.
    out.add(writer.object(encryptNumber, 0, encrypt, encrypt: false));

    final startxref = out.length;
    final trailer = <String, Object?>{
      'Size': encryptNumber + 1,
      'Root': root,
      'Info': _flatten(file.trailer['Info']),
      'Encrypt': PdfRef(encryptNumber, 0),
      'ID': <Object?>[PdfString(first), PdfString(_stamp)],
    };
    final tail = StringBuffer(PdfObjectWriter.xrefTable(offsets, (_) => 0))
      ..write('trailer\n');
    writer.write(tail, trailer, 0, 0, encrypt: false);
    tail.write('\n');
    return (out
          ..add(latin1.encode(tail.toString()))
          ..add(ascii.encode('startxref\n$startxref\n%%EOF\n')))
        .takeBytes();
  }

  // ----------------------------------------------------------------- keys

  /// Algorithm 5 step (e): /U is 32 bytes, of which revision 3 fills 16.
  ///
  /// The specification calls the other 16 arbitrary padding and
  /// [PdfCrypt.unlock] compares only the first 16, so what goes there is a
  /// free choice. It is the head of the handler's own padding string, which is
  /// what the writers already in the world put there, and it is fixed: bytes
  /// from a clock or a counter would make two seals of one document differ for
  /// a reason no reader could see.
  Uint8List _userEntry(Uint8List key, Uint8List first) {
    final value = userEntryFor(
      fileKey: key,
      firstId: first,
      revision: kSealRevision,
    );
    if (value.length >= 32) return Uint8List.sublistView(value, 0, 32);
    final out = Uint8List(32)..setRange(0, value.length, value);
    out.setRange(value.length, 32, kPasswordPad);
    return out;
  }

  /// The first string of the trailer's /ID, which Algorithm 2 mixes into the
  /// key, or a stamp of the document's bytes when the trailer carries none.
  ///
  /// The document keeps whatever identity it arrived with, so anything that
  /// tracked this file by its /ID still recognises it. A file with no /ID at
  /// all cannot be sealed until it has one, since the key derivation would
  /// otherwise mix in nothing.
  Uint8List _firstId() {
    final id = file.resolve(file.trailer['ID']);
    if (id is List && id.isNotEmpty) {
      final first = file.resolve(id.first);
      if (first is PdfString && first.bytes.isNotEmpty) return first.bytes;
    }
    return _stamp;
  }

  // -------------------------------------------------------------- objects

  /// True for an object belonging to the old file's plumbing rather than to
  /// the document.
  ///
  /// Compressed object streams and cross reference streams are rebuilt here as
  /// plain objects and a plain table, so carrying the originals across would
  /// leave a stale second copy of half the file inside it. A linearization
  /// dictionary is worse than stale: it states byte offsets into a file that no
  /// longer exists, and a reader that believes it lands in the middle of an
  /// encrypted stream.
  bool _plumbing(Object object) {
    final dict = object is PdfStream ? object.dict : object;
    if (dict is! Map<String, Object?>) return false;
    if (dict.containsKey('Linearized')) return true;
    final type = dict['Type'];
    return type == const PdfName('XRef') || type == const PdfName('ObjStm');
  }

  /// True for a signature dictionary.
  ///
  /// A digital signature covers a byte range of the file it was made in, and
  /// sealing moves every byte in the document. The signature would survive as
  /// an object and fail as a claim, which is the one outcome worse than
  /// refusing: a reader would be shown a broken seal on a document that was
  /// never tampered with.
  bool _signed(Object object) {
    final dict = object is PdfStream ? object.dict : object;
    return dict is Map<String, Object?> && dict['Type'] == const PdfName('Sig');
  }

  /// One indirect object, encrypted under its own key.
  Uint8List _object(PdfObjectWriter writer, int number, Object object) {
    if (object is! PdfStream) {
      return writer.object(number, 0, _flatten(object));
    }
    final body = writer.encryptBytes(object.raw, number, 0);
    // The length is restated from the bytes actually written. A source whose
    // /Length was wrong was read by hunting for its endstream, and carrying
    // that wrong number into a file whose streams are now ciphertext would
    // leave a reader decrypting the wrong bytes with nothing to tell it so.
    final dict = _flatten(object.dict) as Map<String, Object?>
      ..['Length'] = body.length;
    final head = StringBuffer('$number 0 obj\n');
    writer.write(head, dict, number, 0, encrypt: true);
    head.write('\nstream\n');
    return (BytesBuilder(copy: false)
          ..add(latin1.encode(head.toString()))
          ..add(body)
          ..add(ascii.encode('\nendstream\nendobj\n')))
        .takeBytes();
  }

  /// [value] with every reference in it pointed at generation 0.
  ///
  /// quire's cross reference does not keep generation numbers, so an object's
  /// own generation is not knowable here and every object is written as
  /// generation 0. The references have to follow: a reader that honours
  /// generations, and Adobe's does, would chase `12 5 R` past the `12 0` this
  /// file holds and find nothing at all. It is also what flattens a document
  /// that had been added to over several updates back into one revision.
  Object? _flatten(Object? value) {
    if (value is PdfRef) return PdfRef(value.number, 0);
    if (value is List) {
      return <Object?>[for (final item in value) _flatten(item)];
    }
    if (value is Map<String, Object?>) {
      return <String, Object?>{
        for (final entry in value.entries) entry.key: _flatten(entry.value),
      };
    }
    return value;
  }

  /// The header, with the version raised where it has to be.
  ///
  /// RC4 at 128 bits arrived in PDF 1.4, so a file that called itself 1.3 and
  /// carries a /V 2 handler is a contradiction, and a strict reader is within
  /// its rights to refuse the handler rather than the version.
  Uint8List _header() {
    final take = file.bytes.length < 16 ? file.bytes.length : 16;
    final head = latin1.decode(file.bytes.sublist(0, take), allowInvalid: true);
    final said = RegExp(r'^%PDF-1\.(\d)').firstMatch(head);
    final minor = said == null ? 4 : int.parse(said.group(1)!);
    // The four high bytes on the second line are the mark that tells anything
    // moving this file about that it is binary. An encrypted stream is binary
    // from its first byte, and a transfer that helpfully repaired its line
    // endings would leave nothing readable behind.
    return Uint8List.fromList(<int>[
      ...ascii.encode('%PDF-1.${minor < 4 ? 4 : minor}\n%'),
      0xe2,
      0xe3,
      0xcf,
      0xd3,
      0x0a,
    ]);
  }
}
