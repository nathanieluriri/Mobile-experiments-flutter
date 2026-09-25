import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/crypt.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/pdf/rc4.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/render_plan.dart';

import 'support/fixtures.dart';

// ---------------------------------------------------------------- fixtures

Uint8List bundled(String name) =>
    File('assets/documents/$name').readAsBytesSync();

/// Every protected PDF sitting in this machine's downloads folder.
///
/// These are somebody's real documents and their passwords are not known here,
/// so they are used for exactly two things: that the handler reads their
/// revision, and that it refuses them cleanly. Nothing is named, nothing is
/// read out of them, and no password is ever guessed at. Finding them by shape
/// rather than by filename is deliberate, so the check carries no trace of
/// whose files they are.
List<PdfSecurity> protectedDownloads() {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null) return const <PdfSecurity>[];
  final folder = Directory('$home${Platform.pathSeparator}Downloads');
  if (!folder.existsSync()) return const <PdfSecurity>[];

  final out = <PdfSecurity>[];
  for (final entry in folder.listSync().whereType<File>()) {
    if (!entry.path.toLowerCase().endsWith('.pdf')) continue;
    final security = PdfFile.securityOf(entry.readAsBytesSync());
    if (security != null) out.add(security);
  }
  return out;
}

/// Runs [check] over each protected file's bytes, one at a time, so no more
/// than one of somebody's documents is held in memory at once.
void forEachProtectedDownload(void Function(Uint8List bytes) check) {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home == null) return;
  final folder = Directory('$home${Platform.pathSeparator}Downloads');
  if (!folder.existsSync()) return;
  for (final entry in folder.listSync().whereType<File>()) {
    if (!entry.path.toLowerCase().endsWith('.pdf')) continue;
    final bytes = entry.readAsBytesSync();
    if (PdfFile.securityOf(bytes) != null) check(bytes);
  }
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String s) => Uint8List.fromList(<int>[
  for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
]);

/// Every line of text in reading order, which is the comparison that proves a
/// decrypted file is the same document as its plain original.
List<String> allText(PdfFile file) => <String>[
  for (final page in file.pages)
    for (final run in mergeRuns(ContentInterpreter(file).run(page).texts))
      run.text,
];

/// The decoded bytes of a page's first content stream.
Uint8List contentOf(PdfFile file, int index) {
  final contents = file.resolve(file.pages[index]['Contents']);
  final stream = contents is List
      ? file.resolve(contents.first) as PdfStream
      : contents as PdfStream;
  return file.decodeStream(stream);
}

/// Assembles a PDF whose trailer names an /Encrypt dictionary, so a cipher
/// this reader refuses can be stated in the open rather than hidden in a blob.
Uint8List encryptedShell(String encryptDict) {
  final out = <int>[];
  void add(String s) => out.addAll(ascii.encode(s));
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>',
    encryptDict,
  ];
  add('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    add('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefAt = out.length;
  add('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    add('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  add(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R /Encrypt 4 0 R '
    '/ID [<0102030405060708090a0b0c0d0e0f10> '
    '<0102030405060708090a0b0c0d0e0f10>] >>\n',
  );
  add('startxref\n$xrefAt\n%%EOF\n');
  return Uint8List.fromList(out);
}

// The owner entry and file identifier the synthetic key tests derive against.
// They are arbitrary but fixed, so a failure names a step rather than a mood.
final Uint8List syntheticOwner = Uint8List.fromList(
  List<int>.generate(32, (i) => i),
);
final Uint8List syntheticId = fromHex('0102030405060708090a0b0c0d0e0f10');

void main() {
  // --------------------------------------------------------------- ciphers

  group('MD5', () {
    // The published vectors, plus the three lengths where the padding block
    // either just fits, just overflows, or lands exactly on the boundary.
    test('matches the published vectors', () {
      expect(hex(md5(const <int>[])), 'd41d8cd98f00b204e9800998ecf8427e');
      expect(hex(md5(ascii.encode('abc'))), '900150983cd24fb0d6963f7d28e17f72');
      expect(
        hex(md5(ascii.encode('a' * 80))),
        'b15af9cdabbaea0516866a33d8fd0f98',
      );
    });

    test('pads correctly on either side of the block boundary', () {
      expect(
        hex(md5(ascii.encode('x' * 55))),
        '04364420e25c512fd958a70738aa8f72',
      );
      expect(
        hex(md5(ascii.encode('x' * 56))),
        '668a72d5ba17f08e62dabcafad6db14b',
      );
      expect(
        hex(md5(ascii.encode('x' * 64))),
        'c1bb4f81d892b2d57947682aeb252456',
      );
    });
  });

  group('RC4', () {
    test('matches the published vector', () {
      expect(
        hex(rc4(ascii.encode('Key'), ascii.encode('Plaintext'))),
        'bbf316e8d940af0ad3',
      );
      expect(
        hex(rc4(ascii.encode('Secret'), ascii.encode('Attack at dawn'))),
        '45a01f645fc35b383552544b9bf5',
      );
    });

    test('is its own inverse, which is why one function serves both ways', () {
      final key = ascii.encode('pressroom');
      final clear = Uint8List.fromList(List<int>.generate(500, (i) => i & 0xff));
      expect(rc4(key, rc4(key, clear)), clear);
    });
  });

  // ------------------------------------------------------------ algorithm 2

  group('Algorithm 2, the file encryption key', () {
    test('a 40-bit revision 2 key with a negative /P', () {
      // The single easiest step to get wrong. /P is signed, and one of the two
      // real files on this machine carries -60, so it has to be written as a
      // four byte little endian two's complement value.
      final key = fileEncryptionKey(
        password32: padPassword(const <int>[]),
        ownerEntry: syntheticOwner,
        permissions: -60,
        firstId: syntheticId,
        revision: 2,
        keyBytes: 5,
      );
      expect(hex(key), '0b1216c01c');
    });

    test('a negative /P is not the same as its low sixteen bits', () {
      // -60 masked into 32 bits is 0xFFFFFFC4. A reader that dropped the sign
      // and wrote 0x0000FFC4 would derive a key that fails with no clue why,
      // so the two are pinned apart here rather than left to chance.
      Uint8List keyFor(int permissions) => fileEncryptionKey(
        password32: padPassword(const <int>[]),
        ownerEntry: syntheticOwner,
        permissions: permissions,
        firstId: syntheticId,
        revision: 2,
        keyBytes: 5,
      );
      expect(hex(keyFor(-60)), '0b1216c01c');
      expect(hex(keyFor(0x0000ffc4)), '316a9a44d9');
      expect(hex(keyFor(-60)), isNot(hex(keyFor(0x0000ffc4))));
    });

    test('a 128-bit revision 3 key runs the 50 rehashes', () {
      final key = fileEncryptionKey(
        password32: padPassword(ascii.encode('quire')),
        ownerEntry: syntheticOwner,
        permissions: -60,
        firstId: syntheticId,
        revision: 3,
        keyBytes: 16,
      );
      expect(hex(key), '0504c59f8a02cb8cf4dabe6d96ddc5d2');
    });

    test('a password past 32 bytes is truncated, not hashed whole', () {
      final long = 'q' * 40;
      final truncated = 'q' * 32;
      Uint8List keyFor(String password) => fileEncryptionKey(
        password32: padPassword(ascii.encode(password)),
        ownerEntry: syntheticOwner,
        permissions: -60,
        firstId: syntheticId,
        revision: 3,
        keyBytes: 16,
      );
      expect(keyFor(long), keyFor(truncated));
    });

    test('the key derived for the locked fixture is the expected one', () {
      // Cross checked against an independent implementation reading the same
      // file, so this pins the whole of Algorithm 2 against real /O, /P and
      // /ID values rather than a synthetic case.
      final security = PdfFile.securityOf(bundled('press-lease-locked.pdf'))!;
      final key = fileEncryptionKey(
        password32: padPassword(ascii.encode('quire')),
        ownerEntry: security.ownerEntry,
        permissions: security.permissions,
        firstId: fromHex('7175697265d0cf11e0a1b11ae10000f1'),
        revision: security.revision,
        keyBytes: security.keyBytes,
      );
      expect(hex(key), 'd5bdd30b184882f4c1b384ae2ae094dc');
    });

    test('the key derived for the owner only fixture is the expected one', () {
      final security = PdfFile.securityOf(bundled('press-lease-owner.pdf'))!;
      final key = fileEncryptionKey(
        password32: padPassword(const <int>[]),
        ownerEntry: security.ownerEntry,
        permissions: security.permissions,
        firstId: fromHex('7175697265d0cf11e0a1b11ae10000f1'),
        revision: security.revision,
        keyBytes: security.keyBytes,
      );
      expect(hex(key), '5bc93133ac801fdf65be6d170cbba951');
    });
  });

  // ------------------------------------------------------------ algorithm 1

  group('Algorithm 1, the per object key', () {
    test('mixes the object and generation numbers in the right order', () {
      final fileKey = fromHex('0b1216c01c');
      expect(hex(objectEncryptionKey(fileKey, 12, 3)), 'd846894b8f095aa92822');
    });

    test('a 128-bit key is capped at 16 bytes, not 21', () {
      final fileKey = fromHex('d5bdd30b184882f4c1b384ae2ae094dc');
      expect(objectEncryptionKey(fileKey, 1, 0).length, 16);
      expect(
        hex(objectEncryptionKey(fileKey, 1, 0)),
        '9364b3ba6d139b72d0b2825d117fad7d',
      );
      expect(
        hex(objectEncryptionKey(fileKey, 4, 0)),
        'b7c763a3ca49bae57ff2bbb6a4d2a8bd',
      );
      expect(
        hex(objectEncryptionKey(fileKey, 7, 0)),
        '64a844d937fde198b5dc613c906ce6bb',
      );
    });

    test('a 40-bit key grows to its length plus five', () {
      expect(objectEncryptionKey(fromHex('0b1216c01c'), 1, 0).length, 10);
    });

    test('every object gets a different key', () {
      final fileKey = fromHex('d5bdd30b184882f4c1b384ae2ae094dc');
      final keys = <String>{
        for (var n = 1; n <= 20; n++) hex(objectEncryptionKey(fileKey, n, 0)),
      };
      expect(keys.length, 20);
    });
  });

  // ------------------------------------------------------- algorithms 4 to 6

  group('Algorithms 4 and 5, the /U oracle', () {
    test('revision 2 encrypts the pad string with the file key', () {
      final key = fromHex('0b1216c01c');
      expect(
        hex(userEntryFor(fileKey: key, firstId: syntheticId, revision: 2)),
        '68439636a9a8477b977d4a65aa7bc302'
        '9bfe8a92d190f8e5b87bba97429caa35',
      );
    });

    test('revision 3 runs the twenty keyed passes', () {
      final key = fromHex('0504c59f8a02cb8cf4dabe6d96ddc5d2');
      expect(
        hex(userEntryFor(fileKey: key, firstId: syntheticId, revision: 3)),
        startsWith('419f2ef0524eae5ab0935fe675f04a06'),
      );
    });

    test('a fixture /U matches what the derived key predicts', () {
      final security = PdfFile.securityOf(bundled('press-lease-locked.pdf'))!;
      final expected = userEntryFor(
        fileKey: fromHex('d5bdd30b184882f4c1b384ae2ae094dc'),
        firstId: fromHex('7175697265d0cf11e0a1b11ae10000f1'),
        revision: 3,
      );
      expect(
        hex(Uint8List.sublistView(expected, 0, 16)),
        hex(Uint8List.sublistView(security.userEntry, 0, 16)),
      );
    });
  });

  // -------------------------------------------------------- the owner file

  group('a file locked only against its owner', () {
    test('opens with no password at all', () {
      final file = PdfFile.open(bundled('press-lease-owner.pdf'));
      expect(file.encrypted, isTrue);
      expect(file.locked, isFalse);
      expect(file.security!.revision, 3);
      expect(file.pageCount, 2);
    });

    test('reads as the same document as the plain original', () {
      // The strongest assertion here. Page count, every content stream byte
      // and every line of text match the file it was made from, which is the
      // whole chain proved end to end rather than a key compared to itself.
      final plain = PdfFile.open(bundled('press-lease.pdf'));
      final locked = PdfFile.open(bundled('press-lease-owner.pdf'));
      expect(locked.pageCount, plain.pageCount);
      for (var page = 0; page < plain.pageCount; page++) {
        expect(contentOf(locked, page), contentOf(plain, page), reason: '$page');
      }
      expect(allText(locked), allText(plain));
      expect(allText(locked), isNotEmpty);
    });

    test('its decrypted content stream matches byte for byte', () {
      // The same stream decrypted by a separate implementation in another
      // language hashes to this, so the comparison is across readers rather
      // than between two runs of the same code.
      final file = PdfFile.open(bundled('press-lease-owner.pdf'));
      expect(hex(md5(contentOf(file, 0))), 'cf88edec77991d87149ebc24e43759e5');
      expect(hex(md5(contentOf(file, 1))), '69fb9e906f34bb56cabffa3a0e2ddeb0');
    });

    test('its permissions withhold printing, and it opens anyway', () {
      // Permissions are the owner's statement about the file, not a gate on
      // reading it. A reader that refused here would be refusing a file every
      // conforming reader opens.
      final file = PdfFile.open(bundled('press-lease-owner.pdf'));
      const printBit = 1 << 2;
      expect(file.security!.permissions & printBit, 0);
      expect(file.pageCount, 2);
    });

    test('the ladder never sends it to a protected sheet', () {
      final file = PdfFile.open(bundled('press-lease-owner.pdf'));
      expect(file.locked, isFalse,
          reason: 'the empty password opened it, so nothing is withheld');
      expect(planFor(null, threw: false), RenderPlan.damaged);
      final list = ContentInterpreter(file).run(file.pages.first);
      expect(planFor(list, threw: false), RenderPlan.rich);
    });
  });

  // ------------------------------------------------------- the user file

  group('a file with a real user password', () {
    test('no password is locked, and says so without blaming anyone', () {
      expect(
        () => PdfFile.open(bundled('press-lease-locked.pdf')),
        throwsA(
          isA<PdfLocked>()
              .having((e) => e.wrongPassword, 'wrongPassword', isFalse)
              .having((e) => e.cipher, 'cipher', kCipherRc4),
        ),
      );
    });

    test('a wrong password is told apart from no password', () {
      expect(
        () => PdfFile.open(bundled('press-lease-locked.pdf'), password: 'wrong'),
        throwsA(
          isA<PdfLocked>()
              .having((e) => e.wrongPassword, 'wrongPassword', isTrue)
              .having((e) => e.cipher, 'cipher', kCipherRc4),
        ),
      );
    });

    test('the user password opens it as the plain original', () {
      final plain = PdfFile.open(bundled('press-lease.pdf'));
      final opened = PdfFile.open(
        bundled('press-lease-locked.pdf'),
        password: 'quire',
      );
      expect(opened.pageCount, plain.pageCount);
      expect(allText(opened), allText(plain));
      expect(contentOf(opened, 0), contentOf(plain, 0));
    });

    test('the owner password opens it too', () {
      final opened = PdfFile.open(
        bundled('press-lease-locked.pdf'),
        password: 'pressroom',
      );
      expect(opened.pageCount, 2);
      expect(allText(opened), allText(PdfFile.open(bundled('press-lease.pdf'))));
    });

    test('a near miss is still a miss', () {
      for (final password in <String>['Quire', 'quire ', 'quir', 'quiree']) {
        expect(
          () => PdfFile.open(
            bundled('press-lease-locked.pdf'),
            password: password,
          ),
          throwsA(isA<PdfLocked>()),
          reason: password,
        );
      }
    });

    test('a locked file maps onto the rung that asks for a password', () {
      try {
        PdfFile.open(bundled('press-lease-locked.pdf'));
        fail('the locked fixture opened without a password');
      } on PdfLocked catch (locked) {
        expect(planForLocked(locked), RenderPlan.needsPassword);
        expect(
          planFor(null, locked: locked, threw: true),
          RenderPlan.needsPassword,
        );
      }
    });
  });

  // ----------------------------------------------------- unsupported ciphers

  group('a cipher this reader does not implement', () {
    test('AESV2 is named rather than attempted', () {
      final bytes = encryptedShell(
        '<< /Filter /Standard /V 4 /R 4 /Length 128 /P -4 '
        '/CF << /StdCF << /CFM /AESV2 /Length 16 >> >> '
        '/StmF /StdCF /StrF /StdCF '
        '/O <${'00' * 32}> /U <${'00' * 32}> >>',
      );
      expect(
        () => PdfFile.open(bytes, password: 'anything'),
        throwsA(
          isA<PdfLocked>()
              .having((e) => e.cipher, 'cipher', 'AESV2')
              .having((e) => e.wrongPassword, 'wrongPassword', isFalse),
        ),
      );
    });

    test('AESV3 is named rather than attempted', () {
      final bytes = encryptedShell(
        '<< /Filter /Standard /V 5 /R 6 /Length 256 /P -4 '
        '/O <${'00' * 48}> /U <${'00' * 48}> >>',
      );
      expect(
        () => PdfFile.open(bytes),
        throwsA(isA<PdfLocked>().having((e) => e.cipher, 'cipher', 'AESV3')),
      );
    });

    test('a handler that is not the standard one is named too', () {
      final bytes = encryptedShell(
        '<< /Filter /FOPP_Handler /V 2 /R 3 /Length 128 /P -4 '
        '/O <${'00' * 32}> /U <${'00' * 32}> >>',
      );
      expect(
        () => PdfFile.open(bytes),
        throwsA(
          isA<PdfLocked>().having((e) => e.cipher, 'cipher', 'FOPP_Handler'),
        ),
      );
    });

    test('an unsupported cipher gets its own rung, not the password one', () {
      const locked = PdfLocked(wrongPassword: false, cipher: 'AESV2');
      expect(planForLocked(locked), RenderPlan.unsupportedCipher);
      expect(
        planFor(null, locked: locked, threw: true),
        RenderPlan.unsupportedCipher,
      );
    });

    test('a /V 4 file whose crypt filter is RC4 is still RC4', () {
      final bytes = encryptedShell(
        '<< /Filter /Standard /V 4 /R 4 /Length 128 /P -4 '
        '/CF << /StdCF << /CFM /V2 /Length 16 >> >> '
        '/StmF /StdCF /StrF /StdCF '
        '/O <${'00' * 32}> /U <${'00' * 32}> >>',
      );
      expect(PdfFile.securityOf(bytes)!.cipher, kCipherRc4);
      expect(PdfFile.securityOf(bytes)!.keyBytes, 16);
      expect(
        () => PdfFile.open(bytes),
        throwsA(isA<PdfLocked>().having((e) => e.cipher, 'cipher', kCipherRc4)),
      );
    });
  });

  // ------------------------------------------------------ the ladder itself

  group('the fallback ladder', () {
    test('an unencrypted file reports no security at all', () {
      expect(PdfFile.securityOf(bundled('press-lease.pdf')), isNull);
      expect(PdfFile.open(bundled('press-lease.pdf')).encrypted, isFalse);
    });

  });

  // ---------------------------------------------------- the store's own rung

  group('what the reader is told', () {
    // The rung has to survive the trip from the engine to the sheet, because
    // the one thing that must never happen is a document that opened as
    // nothing being drawn as a page that is still loading.
    test('an owner only file arrives as an ordinary readable document', () {
      final store = DocumentStore.ready(
        entryFor(kPressLease),
        bundled('press-lease-owner.pdf'),
      );
      expect(store.locked, isNull);
      expect(store.plan, RenderPlan.rich);
      expect(store.pdfPageCount, 2);
    });

    test('a file with a user password asks for one rather than tearing', () {
      final store = DocumentStore.ready(
        entryFor(kPressLease),
        bundled('press-lease-locked.pdf'),
      );
      expect(store.state, ParseState.ready);
      expect(store.plan, RenderPlan.needsPassword);
      expect(store.pdfPageCount, 0);
      expect(
        store.locked,
        isA<PdfLocked>()
            .having((e) => e.wrongPassword, 'wrongPassword', isFalse)
            .having((e) => e.cipher, 'cipher', kCipherRc4),
      );
    });

    test('a cipher we do not implement gets the rung that says so', () {
      final store = DocumentStore.ready(
        entryFor(kPressLease),
        encryptedShell(
          '<< /Filter /Standard /V 5 /R 6 /Length 256 /P -4 '
          '/O <${'00' * 48}> /U <${'00' * 48}> >>',
        ),
      );
      expect(store.plan, RenderPlan.unsupportedCipher);
      expect(store.locked!.cipher, 'AESV3');
    });
  });

  // ------------------------------------------------------ real locked files

  group('the protected files on this machine', () {
    // The two that live here are a 128-bit /V 2 /R 3 file and a 40-bit /V 1
    // /R 2 one, which is the whole range this handler claims. Neither password
    // is known, so what they prove is identification and clean refusal. On a
    // machine without them the group skips rather than passing on nothing.
    test('are read at the revision they declare', () {
      final found = protectedDownloads();
      if (found.length < 2) {
        markTestSkipped('no pair of protected files on this machine');
        return;
      }
      for (final security in found) {
        expect(security.cipher, kCipherRc4);
        expect(security.keyBytes, anyOf(5, 16));
      }
      final revisions = <String>{
        for (final s in found) 'V${s.version} R${s.revision} ${s.keyBytes}B',
      };
      expect(revisions, contains('V2 R3 16B'));
      expect(revisions, contains('V1 R2 5B'));
    });

    test('refuse an empty password and a wrong one, differently', () {
      var seen = 0;
      forEachProtectedDownload((bytes) {
        seen++;
        expect(
          () => PdfFile.open(bytes),
          throwsA(
            isA<PdfLocked>()
                .having((e) => e.wrongPassword, 'wrongPassword', isFalse)
                .having((e) => e.cipher, 'cipher', kCipherRc4),
          ),
        );
        expect(
          () => PdfFile.open(bytes, password: 'not-the-password'),
          throwsA(
            isA<PdfLocked>()
                .having((e) => e.wrongPassword, 'wrongPassword', isTrue)
                .having((e) => e.cipher, 'cipher', kCipherRc4),
          ),
        );
      });
      if (seen == 0) markTestSkipped('no protected files on this machine');
    });
  });
}
