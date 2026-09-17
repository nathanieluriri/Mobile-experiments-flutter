/// Putting a password on a document, checked by opening it again.
///
/// quire's reader is an independent witness to quire's writer here: the seal
/// derives /O, /U and a file key, and the reader, which knows nothing about
/// the seal, has to arrive at the same key from the file alone and hand back
/// the same pages and the same words. Anything less and the reader would be
/// making files nobody, including quire, could open.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/crypt.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/pdf/seal.dart';
import 'package:quire/pdf/writer.dart';

import 'support/fixtures.dart';

/// The password the round trips use. It is not a good password and is not
/// meant to be: what is being proved is that the bytes survive it.
const String kPassword = 'the grain runs the long way';

/// Every line of text in reading order, which is the comparison that shows a
/// sealed document is still the document that went into it.
List<String> allText(PdfFile file) => <String>[
  for (final page in file.pages)
    for (final run in mergeRuns(ContentInterpreter(file).run(page).texts))
      run.text,
];

/// The still encoded bytes of a page's first content stream, exactly as they
/// sit in the file.
Uint8List rawContent(PdfFile file, int index) {
  final contents = file.resolve(file.pages[index]['Contents']);
  final stream = contents is List
      ? file.resolve(contents.first) as PdfStream
      : contents as PdfStream;
  return stream.raw;
}

/// True when [haystack] holds [needle] end to end.
bool holds(Uint8List haystack, Uint8List needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var same = true;
    for (var k = 0; k < needle.length; k++) {
      if (haystack[i + k] != needle[k]) {
        same = false;
        break;
      }
    }
    if (same) return true;
  }
  return false;
}

/// The first string of a file's /ID, which Algorithm 2 mixes into the key.
Uint8List firstId(PdfFile file) {
  final id = file.resolve(file.trailer['ID']) as List<Object?>;
  return (file.resolve(id.first) as PdfString).bytes;
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String text) => Uint8List.fromList(<int>[
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);

/// A one page file carrying a digital signature over its own bytes.
///
/// Sealing moves every byte in the document, so the signature would survive as
/// an object and fail as a claim. The file is assembled here because no
/// bundled document is signed and the refusal has to be provable.
Uint8List pdfWithSignature() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R '
        '/AcroForm << /SigFlags 3 /Fields [5 0 R] >> >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << >> >>',
    '<< /Length 12 >>\nstream\n0 0 m 1 1 l\nendstream',
    '<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached '
        '/ByteRange [0 100 200 300] /Contents <00ff> >>',
  ];
  final out = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefAt = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefAt\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(out.toString()));
}

/// A file whose catalogue, page tree and page live inside an object stream,
/// found through a cross reference stream.
///
/// Neither bundled document is one and nearly every PDF made this decade is.
/// The seal has to take such a file apart and put it back as plain objects,
/// because an object stream is encrypted as one object and the objects inside
/// it are not encrypted again, so carrying one across would leave a second,
/// readable copy of the document inside the sealed file. It is assembled here
/// rather than checked in as a blob so that what makes it compressed is
/// visible.
Uint8List pdfWithCompressedObjects() {
  final content = ascii.encode('BT /F1 12 Tf 72 720 Td (Compressed.) Tj ET\n');
  final bodies = <String>[
    '<< /Type /Catalog /Pages 3 0 R >>',
    '<< /Type /Pages /Kids [4 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 3 0 R /MediaBox [0 0 612 792] /Resources '
        '<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '>> >> >> /Contents 5 0 R >>',
  ];
  final pairs = <String>[];
  final packed = StringBuffer();
  for (var i = 0; i < bodies.length; i++) {
    pairs.add('${i + 2} ${packed.length}');
    packed.write('${bodies[i]}\n');
  }
  final head = '${pairs.join(' ')}\n';
  final objstm = '$head$packed';

  final out = BytesBuilder();
  void add(String text) => out.add(latin1.encode(text));
  add('%PDF-1.5\n');
  final stmAt = out.length;
  add(
    '1 0 obj\n<< /Type /ObjStm /N ${bodies.length} /First ${head.length} '
    '/Length ${objstm.length} >>\nstream\n$objstm\nendstream\nendobj\n',
  );
  final contentAt = out.length;
  add('5 0 obj\n<< /Length ${content.length} >>\nstream\n');
  out.add(content);
  add('\nendstream\nendobj\n');

  final xrefAt = out.length;
  final rows = BytesBuilder();
  void row(int type, int a, int b) => rows.add(<int>[
    type,
    (a >> 24) & 0xff,
    (a >> 16) & 0xff,
    (a >> 8) & 0xff,
    a & 0xff,
    (b >> 8) & 0xff,
    b & 0xff,
  ]);
  row(0, 0, 65535);
  row(1, stmAt, 0);
  for (var i = 0; i < bodies.length; i++) {
    row(2, 1, i);
  }
  row(1, contentAt, 0);
  row(1, xrefAt, 0);
  final table = rows.takeBytes();
  add(
    '6 0 obj\n<< /Type /XRef /Size 7 /W [1 4 2] /Root 2 0 R '
    '/Length ${table.length} >>\nstream\n',
  );
  out
    ..add(table)
    ..add(ascii.encode('\nendstream\nendobj\nstartxref\n$xrefAt\n%%EOF\n'));
  return out.takeBytes();
}

void main() {
  // ------------------------------------------------------- the round trip

  group('a sealed document', () {
    for (final name in <String>[kPressLease, kFieldGuide]) {
      test('$name opens again in quire, whole, under its password', () async {
        final original = await documentBytes(name);
        final sealed = sealedPdf(original, kPassword);

        final before = PdfFile.open(original);
        final after = PdfFile.open(sealed, password: kPassword);
        expect(after.pageCount, greaterThan(0));
        expect(after.pageCount, before.pageCount);
        expect(allText(after), allText(before));
      });
    }

    test('is ciphertext on disk, not the original with a note on it', () async {
      final original = await documentBytes(kPressLease);
      final plain = rawContent(PdfFile.open(original), 0);
      final sealed = sealedPdf(original, kPassword);

      // The check that matters more than the page count: the bytes a reader
      // would find by looking are not the bytes the document was made of.
      expect(holds(original, plain), isTrue);
      expect(holds(sealed, plain), isFalse);
    });

    test('states the handler quire itself can open', () async {
      final sealed = sealedPdf(await documentBytes(kPressLease), kPassword);
      final security = PdfFile.securityOf(sealed)!;
      expect(security.cipher, kCipherRc4);
      expect(security.version, kSealVersion);
      expect(security.revision, kSealRevision);
      expect(security.keyBytes, kSealKeyBits ~/ 8);
      expect(security.permissions, kSealedPermissions);
      expect(security.ownerEntry.length, 32);
      expect(security.userEntry.length, 32);
    });

    test('made of compressed objects comes back as plain ones', () {
      final original = pdfWithCompressedObjects();
      final before = PdfFile.open(original);
      expect(before.pageCount, 1);

      final sealed = sealedPdf(original, kPassword);
      final after = PdfFile.open(sealed, password: kPassword);
      expect(after.pageCount, 1);
      expect(
        after.pageContent(after.pages.first),
        before.pageContent(before.pages.first),
      );

      // The object stream and the cross reference stream are gone, and with
      // them the only two things in the file that could have carried a
      // readable copy of an object the seal had already encrypted.
      final text = latin1.decode(sealed, allowInvalid: true);
      expect(text, isNot(contains('ObjStm')));
      expect(text, isNot(contains('/XRef')));
      final plain = latin1.decode(original, allowInvalid: true);
      expect(plain, contains('Compressed'));
      expect(text, isNot(contains('Compressed')));
    });

    test('carries a file identifier the original never had', () async {
      final original = await documentBytes(kPressLease);
      // Without one there is nothing to derive a key from, so the seal has to
      // make it, and it has to survive into the trailer in clear.
      expect(PdfFile.open(original).trailer['ID'], isNull);

      final sealed = PdfFile.open(
        sealedPdf(original, kPassword),
        password: kPassword,
      );
      expect(firstId(sealed).length, 16);
      expect(latin1.decode(sealed.bytes, allowInvalid: true), contains('/ID'));
    });
  });

  // --------------------------------------------------------- the passwords

  group('the password on a sealed document', () {
    test('a wrong one is turned down the way any locked file does', () async {
      final sealed = sealedPdf(await documentBytes(kPressLease), kPassword);
      expect(
        () => PdfFile.open(sealed, password: 'not it'),
        throwsA(
          isA<PdfLocked>()
              .having((e) => e.wrongPassword, 'wrongPassword', isTrue)
              .having((e) => e.cipher, 'cipher', kCipherRc4),
        ),
      );
    });

    test('a near miss is still a miss', () async {
      final sealed = sealedPdf(await documentBytes(kPressLease), 'quire');
      for (final password in <String>['Quire', 'quire ', 'quir', 'quiree']) {
        expect(
          () => PdfFile.open(sealed, password: password),
          throwsA(isA<PdfLocked>()),
          reason: password,
        );
      }
    });

    test('no password at all is locked rather than blamed', () async {
      final sealed = sealedPdf(await documentBytes(kPressLease), kPassword);
      expect(
        () => PdfFile.open(sealed),
        throwsA(
          isA<PdfLocked>()
              .having((e) => e.wrongPassword, 'wrongPassword', isFalse)
              .having((e) => e.cipher, 'cipher', kCipherRc4),
        ),
      );
    });

    test('an owner password opens it as well as the reader password', () async {
      final original = await documentBytes(kPressLease);
      final sealed = sealedPdf(original, 'reader', ownerPassword: 'keeper');

      final asReader = PdfFile.open(sealed, password: 'reader');
      final asOwner = PdfFile.open(sealed, password: 'keeper');
      expect(asOwner.pageCount, asReader.pageCount);
      expect(allText(asOwner), allText(PdfFile.open(original)));
    });

    test('the owner way in is not a second user password', () async {
      final sealed = sealedPdf(
        await documentBytes(kPressLease),
        'reader',
        ownerPassword: 'keeper',
      );
      final security = PdfFile.securityOf(sealed)!;
      final id = firstId(PdfFile.open(sealed, password: 'reader'));

      // Algorithm 6 knows nothing of the owner password: it is /O, opened by
      // Algorithm 7, that hands the user password back.
      expect(
        PdfCrypt.unlock(security, id, padPassword(ascii.encode('keeper'))),
        isNull,
      );
      expect(
        PdfCrypt.unlockAsOwner(security, id, ascii.encode('keeper')),
        isNotNull,
      );
    });

    test('one password alone still leaves a usable owner way in', () async {
      final sealed = sealedPdf(await documentBytes(kPressLease), 'reader');
      final security = PdfFile.securityOf(sealed)!;
      final id = firstId(PdfFile.open(sealed, password: 'reader'));
      expect(
        PdfCrypt.unlockAsOwner(security, id, ascii.encode('reader')),
        isNotNull,
      );
    });
  });

  // ------------------------------------------------------- the derivations

  group('the entries quire derives', () {
    // press-lease-locked.pdf was made by another tool from press-lease.pdf,
    // with the user password 'quire' and the owner password 'pressroom'. Its
    // /O depends on nothing but those two passwords, so quire deriving the
    // same 32 bytes is Algorithm 3 checked against an implementation that owes
    // this one nothing. Its /ID and /P then carry that through Algorithm 2 to
    // the key, and Algorithm 5 to /U.
    final lease = fromHex('7175697265d0cf11e0a1b11ae10000f1');

    test('match the tool that made the bundled locked document', () {
      final owner = ownerEntryFor(
        ownerPassword: ascii.encode('pressroom'),
        userPassword: ascii.encode('quire'),
        revision: kSealRevision,
        keyBytes: kSealKeyBits ~/ 8,
      );
      expect(
        hex(owner),
        '2d95f3177fe5eba84981f4d9f06a12fe58ba03f662e7976e45324b566881a1e6',
      );

      final key = fileEncryptionKey(
        password32: padPassword(ascii.encode('quire')),
        ownerEntry: owner,
        permissions: kSealedPermissions,
        firstId: lease,
        revision: kSealRevision,
        keyBytes: kSealKeyBits ~/ 8,
      );
      expect(hex(key), 'd5bdd30b184882f4c1b384ae2ae094dc');

      final user = userEntryFor(
        fileKey: key,
        firstId: lease,
        revision: kSealRevision,
      );
      expect(hex(user), '0ad4ab3383481352f7a3cd75f59ed86a');
    });

    test('an owner password left empty is the user password', () {
      // Step (a) of Algorithm 3, which is what makes a one password file's /O
      // well formed rather than derived from nothing.
      expect(
        ownerEntryFor(
          ownerPassword: const <int>[],
          userPassword: ascii.encode('quire'),
          revision: kSealRevision,
          keyBytes: kSealKeyBits ~/ 8,
        ),
        ownerEntryFor(
          ownerPassword: ascii.encode('quire'),
          userPassword: ascii.encode('quire'),
          revision: kSealRevision,
          keyBytes: kSealKeyBits ~/ 8,
        ),
      );
    });
  });

  // ------------------------------------------------------- the same answer

  group('sealing the same document twice', () {
    test('gives back the same bytes', () async {
      final original = await documentBytes(kPressLease);
      expect(sealedPdf(original, kPassword), sealedPdf(original, kPassword));
    });

    test('gives back different bytes under a different password', () async {
      final original = await documentBytes(kPressLease);
      expect(sealedPdf(original, 'one'), isNot(sealedPdf(original, 'another')));
    });
  });

  // ---------------------------------------------------- what it will not do

  group('a document quire will not seal', () {
    Matcher refused(String word) => throwsA(
      isA<PdfWriteError>().having((e) => e.message, 'message', contains(word)),
    );

    test('one it sealed already, rather than sealing it twice', () async {
      final sealed = sealedPdf(await documentBytes(kPressLease), kPassword);
      expect(() => sealedPdf(sealed, 'again'), refused('already'));
    });

    test('one somebody else locked, which it cannot even read', () async {
      final locked = await documentBytes('press-lease-locked.pdf');
      expect(() => sealedPdf(locked, kPassword), refused('already'));
    });

    test('one carrying an owner password and no user password', () async {
      // It opens with no password asked for, so nothing here looks locked. It
      // is still encrypted, and a second handler on top of the first would
      // leave a file with neither.
      final owned = await documentBytes('press-lease-owner.pdf');
      expect(PdfFile.open(owned).pageCount, greaterThan(0));
      expect(() => sealedPdf(owned, kPassword), refused('already'));
    });

    test('one whose digital signature a rewrite would break', () {
      // It would survive as an object and fail as a claim, and a broken seal
      // on an untampered document is worse than no seal at all.
      expect(PdfFile.open(pdfWithSignature()).pageCount, 1);
      expect(
        () => sealedPdf(pdfWithSignature(), kPassword),
        refused('signature'),
      );
    });

    test('one with an empty password, which would seal nothing', () async {
      final original = await documentBytes(kPressLease);
      expect(() => sealedPdf(original, ''), refused('password is needed'));
    });
  });
}
