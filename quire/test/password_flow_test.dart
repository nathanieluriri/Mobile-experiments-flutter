import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/document_loader.dart';
import 'package:quire/pdf/crypt.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/pdf/rc4.dart';
import 'package:quire/screens/reader/document_states.dart';
import 'package:quire/screens/reader/password_sheet.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/render_plan.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// The password the fixtures below are sealed with. It is written here rather
/// than passed around so a test that types it and a test that builds the file
/// can never drift apart.
const String kUserPassword = 'quarto';
const String kOwnerPassword = 'vellum';

/// A real password protected workbook, saved by Excel and shipped whole.
///
/// It is here because the bug this replaces was a lie told about a real file:
/// the loader met an OLE compound file, the unzip threw, and quire told
/// somebody their intact spreadsheet was damaged. A hand built header would
/// prove the sniff and nothing else.
const String kSealedLedger = 'sealed-ledger.xlsx';

void main() {
  group('the two primitives the standard handler is defined in terms of', () {
    // Written out rather than pulled in as a package, so they are worth the
    // published vectors.
    test('md5', () {
      expect(_hexOf(md5(const <int>[])),
          'd41d8cd98f00b204e9800998ecf8427e');
      expect(_hexOf(md5('abc'.codeUnits)),
          '900150983cd24fb0d6963f7d28e17f72');
      expect(
        _hexOf(md5('The quick brown fox jumps over the lazy dog'
            .codeUnits)),
        '9e107d9d372bb6826bd81d3542a419d6',
      );
      expect(
        _hexOf(md5('12345678901234567890123456789012345678901234567890'
            '123456789012345678901234567890'.codeUnits)),
        '57edf4a22be3c955ac49da2e2107b67a',
        reason: 'eighty bytes, which is two blocks and a padded tail',
      );
    });

    test('rc4, which is its own inverse', () {
      expect(_hexOf(rc4('Key'.codeUnits, 'Plaintext'.codeUnits)),
          'bbf316e8d940af0ad3');
      expect(_hexOf(rc4('Wiki'.codeUnits, 'pedia'.codeUnits)), '1021bf0420');
      final round = rc4('Key'.codeUnits, rc4('Key'.codeUnits, 'Plaintext'
          .codeUnits));
      expect(String.fromCharCodes(round), 'Plaintext');
    });
  });

  group('a file that needs nothing typed opens with nothing asked', () {
    test('an owner password only file opens on the empty password', () {
      // The user password is empty, which is what an owner password only file
      // means: printing and copying are restricted, reading is not.
      final file = PdfFile.open(ownerPasswordOnlyPdf());
      expect(file.encrypted, isTrue);
      expect(file.pageCount, 1);
    });

    test('and its text really is decrypted, not merely present', () {
      final file = PdfFile.open(ownerPasswordOnlyPdf());
      final page = file.pages.first;
      final stream = file.resolve(page['Contents']);
      final content = utf8.decode(
        file.decodeStream(stream! as PdfStream),
        allowMalformed: true,
      );
      expect(content, contains(kSealedLine));
    });

    testWidgets('the reader never puts a sheet up for it', (tester) async {
      final store = DocumentStore(entryFor(kPressLease))
        ..loadFrom(ownerPasswordOnlyPdf());

      // Asserted before the first frame as well as after it. A prompt that
      // flashed for one frame and went away would still have taught somebody
      // that quire asks for passwords it does not need.
      expect(store.locked, isNull);
      expect(store.plan, RenderPlan.rich);

      await _pumpHost(tester, store);
      expect(find.byType(PasswordSheet), findsNothing);
      expect(find.byType(ProtectedSheet), findsNothing);
      await settle(tester);
      expect(find.byType(PasswordSheet), findsNothing);
      expect(find.byType(ProtectedSheet), findsNothing);
      expect(find.byType(SheetSurface), findsOneWidget);
    });
  });

  group('a file that does need a password', () {
    test('says so without claiming anything was typed', () {
      try {
        PdfFile.open(userPasswordPdf());
        fail('a file with a real user password must not just open');
      } on PdfLocked catch (locked) {
        expect(locked.wrongPassword, isFalse);
        expect(locked.cipher, kCipherRc4);
      }
    });

    test('and tells a wrong password apart from no password at all', () {
      try {
        PdfFile.open(userPasswordPdf(), password: 'not it');
        fail('the wrong password must not open it');
      } on PdfLocked catch (locked) {
        expect(locked.wrongPassword, isTrue);
      }
    });

    test('the right password opens it, and so does the owner password', () {
      expect(
        PdfFile.open(userPasswordPdf(), password: kUserPassword).pageCount,
        1,
      );
      expect(
        PdfFile.open(userPasswordPdf(), password: kOwnerPassword).pageCount,
        1,
        reason: 'somebody handed one password does not know which one it is',
      );
    });

    test('40-bit and 128-bit are both read', () {
      for (final version in <int>[1, 2]) {
        final bytes = userPasswordPdf(version: version);
        expect(
          PdfFile.open(bytes, password: kUserPassword).pageCount,
          1,
          reason: '/V $version',
        );
        expect(
          () => PdfFile.open(bytes),
          throwsA(isA<PdfLocked>()),
          reason: '/V $version on no password',
        );
      }
    });

    testWidgets('the reader asks for it', (tester) async {
      final store = DocumentStore(entryFor(kPressLease))
        ..loadFrom(userPasswordPdf());
      expect(store.plan, RenderPlan.needsPassword);
      expect(store.wrongPassword, isFalse);

      await _pumpHost(tester, store);
      expect(find.byType(PasswordSheet), findsOneWidget);
      expect(find.text(kPasswordTitle), findsOneWidget);
    });

    testWidgets('a wrong password changes the message and clears the field', (
      tester,
    ) async {
      final store = DocumentStore(entryFor(kPressLease))
        ..loadFrom(userPasswordPdf());
      await _pumpHost(tester, store);

      await tester.enterText(find.byType(EditableText), 'not it');
      await tester.pump();
      expect(_typed(tester), 'not it');

      await tester.tap(find.text('Open'));
      await settle(tester);

      expect(find.byType(PasswordSheet), findsOneWidget);
      expect(find.text(kPasswordWrongTitle), findsOneWidget);
      expect(find.text(kPasswordTitle), findsNothing);
      expect(_typed(tester), isEmpty, reason: 'the field clears on submit');
      expect(store.wrongPassword, isTrue);
      expect(store.plan, RenderPlan.needsPassword);
    });

    testWidgets('the right password opens the document and the sheet goes', (
      tester,
    ) async {
      final store = DocumentStore(entryFor(kPressLease))
        ..loadFrom(userPasswordPdf());
      await _pumpHost(tester, store);

      await tester.enterText(find.byType(EditableText), kUserPassword);
      await tester.pump();
      await tester.tap(find.text('Open'));
      await settle(tester);

      expect(find.byType(PasswordSheet), findsNothing);
      expect(store.locked, isNull);
      expect(store.plan, RenderPlan.rich);
      expect(store.pdfPageCount, 1);
      expect(find.byType(SheetSurface), findsOneWidget);
    });

    testWidgets('a rejection never locks anybody out', (tester) async {
      final store = DocumentStore(entryFor(kPressLease))
        ..loadFrom(userPasswordPdf());
      await _pumpHost(tester, store);

      for (final wrong in <String>['one', 'two', 'three', 'four', 'five']) {
        await tester.enterText(find.byType(EditableText), wrong);
        await tester.pump();
        await tester.tap(find.text('Open'));
        await settle(tester);
      }
      expect(find.byType(PasswordSheet), findsOneWidget);

      await tester.enterText(find.byType(EditableText), kUserPassword);
      await tester.pump();
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.byType(PasswordSheet), findsNothing);
    });
  });

  group('a cipher this version does not decrypt', () {
    test('is named rather than guessed at', () {
      try {
        PdfFile.open(aesPdf());
        fail('AES must not be attempted');
      } on PdfLocked catch (locked) {
        expect(locked.cipher, 'AESV2');
        expect(locked.wrongPassword, isFalse);
      }
    });

    test('and a password does not make it any more openable', () {
      try {
        PdfFile.open(aesPdf(), password: kUserPassword);
        fail('AES must not be attempted');
      } on PdfLocked catch (locked) {
        expect(locked.cipher, 'AESV2');
        expect(
          locked.wrongPassword,
          isFalse,
          reason: 'nothing was rejected, because nothing was tried',
        );
      }
    });

    testWidgets('the reader says so and offers no field', (tester) async {
      final store = DocumentStore(entryFor(kPressLease))..loadFrom(aesPdf());
      expect(store.plan, RenderPlan.unsupportedCipher);
      expect(store.cipher, 'AESV2');

      await _pumpHost(tester, store);
      expect(find.byType(UnsupportedCipherSheet), findsOneWidget);
      expect(find.byType(PasswordSheet), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.textContaining('AESV2'), findsOneWidget);
    });
  });

  group('a sealed Word or Excel file is not a damaged one', () {
    test('the loader knows an OLE compound file from a zip', () {
      final loaded = DocumentLoader.load(sealedDocx(), 'house-style.docx');
      expect(loaded.protected, isTrue);
      expect(loaded.failed, isTrue, reason: 'nothing readable came back');
      expect(loaded.error, isA<ProtectedPackage>());
      expect((loaded.error! as ProtectedPackage).cipher, kOfficeCipher);
    });

    test('an ordinary docx is still an ordinary docx', () async {
      final loaded = await loadedDocument(kHouseStyle);
      expect(loaded.protected, isFalse);
      expect(loaded.failed, isFalse);
    });

    testWidgets('a real protected workbook is read the same way', (
      tester,
    ) async {
      final bytes = await documentBytes(kSealedLedger);
      expect(bytes.sublist(0, 8), kOleMagic);
      expect(
        bytes.sublist(0, 4),
        isNot(const <int>[0x50, 0x4B, 0x03, 0x04]),
        reason: 'this is exactly the file the unzip used to choke on',
      );

      final store = DocumentStore(entryFor(kPressRunCosts))..loadFrom(bytes);
      expect(store.plan, RenderPlan.unsupportedCipher);
      await _pumpHost(tester, store);
      expect(find.byType(UnsupportedCipherSheet), findsOneWidget);
      expect(find.byType(DamagedSheet), findsNothing);
    });

    test('a genuinely truncated package is still damage', () {
      final loaded = DocumentLoader.load(
        Uint8List.fromList(const <int>[0x50, 0x4B, 0x03, 0x04, 0x00]),
        'house-style.docx',
      );
      expect(loaded.protected, isFalse);
      expect(loaded.failed, isTrue);
    });

    testWidgets('the reader calls it protected, never damaged', (tester) async {
      final store = DocumentStore(entryFor(kHouseStyle))
        ..loadFrom(sealedDocx());
      expect(store.plan, RenderPlan.unsupportedCipher);
      expect(store.cipher, kOfficeCipher);

      await _pumpHost(tester, store);
      expect(find.byType(UnsupportedCipherSheet), findsOneWidget);
      expect(find.byType(DamagedSheet), findsNothing);
      expect(find.textContaining('damaged'), findsNothing);
      expect(find.textContaining(kOfficeCipher), findsOneWidget);
    });
  });

  group('their goldens', () {
    setUp(() {
      // A caret that is blinking is a moving part, and these sheets are
      // captured with the field live because that is how they arrive.
      EditableText.debugDeterministicCursor = true;
      addTearDown(() => EditableText.debugDeterministicCursor = false);
    });

    testWidgets('reader__password', (tester) async {
      final store = DocumentStore(entryFor(kPressLease))
        ..loadFrom(userPasswordPdf());
      await _pumpHost(tester, store);
      await settle(tester);
      await capture(tester, 'reader__password');
    });

    testWidgets('reader__password_wrong', (tester) async {
      final store = DocumentStore(entryFor(kPressLease))
        ..loadFrom(userPasswordPdf());
      await _pumpHost(tester, store);
      await tester.enterText(find.byType(EditableText), 'not it');
      await tester.pump();
      await tester.tap(find.text('Open'));
      await settle(tester);
      await capture(tester, 'reader__password_wrong');
    });

    testWidgets('reader__unsupported_cipher', (tester) async {
      final store = DocumentStore(entryFor(kPressLease))..loadFrom(aesPdf());
      await _pumpHost(tester, store);
      await settle(tester);
      await capture(tester, 'reader__unsupported_cipher');
    });
  });
}

/// The whole reader over one document, which is the only way to prove that a
/// sheet does not appear: a test that pumped the sheet directly could only
/// prove the sheet draws.
Future<void> _pumpHost(WidgetTester tester, DocumentStore store) async {
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderHost(store: store, onLeave: () {}),
    ),
  );
}

/// What is actually sitting in the password field.
String _typed(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

// ------------------------------------------------------------------ fixtures

/// The one line of text the encrypted fixtures carry, so a test can prove the
/// content stream was decrypted rather than merely read.
const String kSealedLine = 'THE GRAIN RUNS THE LONG WAY';

/// The /ID every fixture is built with. Fixed, because the file key is derived
/// from it and a random one would make these files different every run.
final Uint8List _fixtureId = Uint8List.fromList(
  List<int>.generate(16, (i) => (i * 17 + 3) & 0xFF),
);

/// The permissions word: everything but printing, which is the restriction an
/// owner password is nearly always set to impose.
const int _fixtureP = -44;

/// A one page PDF sealed with the RC4 standard security handler.
///
/// It is assembled here rather than checked in as a blob so that what makes
/// the file locked is visible, and so the same builder can produce the owner
/// password only case and the user password case from one set of rules.
Uint8List rc4Pdf({
  required String userPassword,
  required String ownerPassword,
  int version = 2,
}) {
  final revision = version == 1 ? 2 : 3;
  final keyLength = version == 1 ? 5 : 16;
  final owner = _ownerEntry(ownerPassword, userPassword, revision, keyLength);
  final fileKey = _fileKey(userPassword, owner, revision, keyLength);
  final user = _userEntry(fileKey, revision);

  final content = ascii.encode(
    'BT /F1 18 Tf 24 150 Td ($kSealedLine) Tj ET\n',
  );
  final sealed = rc4(_objectKey(fileKey, 4), content);
  return _assemble(
    <List<int>>[
      ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'),
      ascii.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      ascii.encode(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] '
        '/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 '
        '/BaseFont /Helvetica >> >> >> /Contents 4 0 R >>',
      ),
      <int>[
        ...ascii.encode('<< /Length ${sealed.length} >>\nstream\n'),
        ...sealed,
        ...ascii.encode('\nendstream'),
      ],
      ascii.encode(
        '<< /Filter /Standard /V $version /R $revision '
        '${version == 1 ? '' : '/Length ${keyLength * 8} '}'
        '/P $_fixtureP /O <${_hex(owner)}> /U <${_hex(user)}> >>',
      ),
    ],
    trailerExtra: '/Encrypt 5 0 R /ID [<${_hex(_fixtureId)}> '
        '<${_hex(_fixtureId)}>] ',
  );
}

/// A file restricted for its owner and open to everybody else, which is what
/// most protected PDFs in the world actually are.
Uint8List ownerPasswordOnlyPdf() =>
    rc4Pdf(userPassword: '', ownerPassword: kOwnerPassword);

/// A file that genuinely will not open until somebody types something.
Uint8List userPasswordPdf({int version = 2}) => rc4Pdf(
  userPassword: kUserPassword,
  ownerPassword: kOwnerPassword,
  version: version,
);

/// A file sealed with AES, which this version detects and refuses honestly.
///
/// The /O and /U entries are filler: nothing ever looks at them, because the
/// cipher is read first and the file is put down before a password is tried.
Uint8List aesPdf() {
  final filler = Uint8List(32);
  return _assemble(
    <List<int>>[
      ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'),
      ascii.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      ascii.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] >>'),
      ascii.encode(
        '<< /Filter /Standard /V 4 /R 4 /Length 128 /P $_fixtureP '
        '/CF << /StdCF << /CFM /AESV2 /Length 16 >> >> '
        '/StmF /StdCF /StrF /StdCF '
        '/O <${_hex(filler)}> /U <${_hex(filler)}> >>',
      ),
    ],
    trailerExtra: '/Encrypt 4 0 R /ID [<${_hex(_fixtureId)}> '
        '<${_hex(_fixtureId)}>] ',
  );
}

/// The first bytes of a password protected .docx: not a zip at all, but an OLE
/// compound file wrapping an EncryptedPackage stream.
///
/// The eight byte signature and the stream name are the whole point, so they
/// are exactly what is built. The rest is the sector padding a real container
/// carries, and nothing in quire ever looks inside it.
Uint8List sealedDocx() {
  final out = <int>[...kOleMagic];
  while (out.length < 512) {
    out.add(0);
  }
  for (final unit in 'EncryptedPackage'.codeUnits) {
    out
      ..add(unit)
      ..add(0);
  }
  while (out.length < 1536) {
    out.add(0);
  }
  return Uint8List.fromList(out);
}

/// Algorithm 3: the /O entry, which hides the user password behind the owner
/// password.
Uint8List _ownerEntry(
  String owner,
  String user,
  int revision,
  int keyLength,
) {
  var digest = md5(_padded(owner));
  if (revision >= 3) {
    for (var i = 0; i < 50; i++) {
      digest = md5(digest);
    }
  }
  final key = Uint8List.fromList(digest.sublist(0, keyLength));
  if (revision == 2) return rc4(key, _padded(user));
  var block = Uint8List.fromList(_padded(user));
  for (var i = 0; i <= 19; i++) {
    block = rc4(_xor(key, i), block);
  }
  return block;
}

/// Algorithm 2: the file key.
Uint8List _fileKey(
  String user,
  Uint8List owner,
  int revision,
  int keyLength,
) {
  var digest = md5(<int>[
    ..._padded(user),
    ...owner,
    _fixtureP & 0xFF,
    (_fixtureP >> 8) & 0xFF,
    (_fixtureP >> 16) & 0xFF,
    (_fixtureP >> 24) & 0xFF,
    ..._fixtureId,
  ]);
  if (revision >= 3) {
    for (var i = 0; i < 50; i++) {
      digest = md5(digest.sublist(0, keyLength));
    }
  }
  return Uint8List.fromList(digest.sublist(0, keyLength));
}

/// Algorithms 4 and 5: the /U entry.
Uint8List _userEntry(Uint8List fileKey, int revision) {
  if (revision == 2) return rc4(fileKey, kPasswordPad);
  var block = rc4(
    fileKey,
    md5(<int>[...kPasswordPad, ..._fixtureId]),
  );
  for (var i = 1; i <= 19; i++) {
    block = rc4(_xor(fileKey, i), block);
  }
  // The specification says the second sixteen bytes are arbitrary. A reader
  // that compared them would reject files that open everywhere else, so they
  // are deliberately not the padding a naive implementation would expect.
  return Uint8List.fromList(<int>[
    ...block,
    ...List<int>.generate(16, (i) => (i * 7 + 11) & 0xFF),
  ]);
}

Uint8List _objectKey(Uint8List fileKey, int number) {
  final digest = md5(<int>[
    ...fileKey,
    number & 0xFF,
    (number >> 8) & 0xFF,
    (number >> 16) & 0xFF,
    0,
    0,
  ]);
  final length = fileKey.length + 5 > 16 ? 16 : fileKey.length + 5;
  return Uint8List.fromList(digest.sublist(0, length));
}

List<int> _padded(String password) {
  final out = <int>[...password.codeUnits.take(32)];
  var at = 0;
  while (out.length < 32) {
    out.add(kPasswordPad[at++]);
  }
  return out;
}

Uint8List _xor(Uint8List key, int value) =>
    Uint8List.fromList(<int>[for (final byte in key) byte ^ value]);

String _hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The file around the objects: header, bodies, xref table, trailer.
Uint8List _assemble(List<List<int>> objects, {String trailerExtra = ''}) {
  final out = <int>[];
  void add(String text) => out.addAll(ascii.encode(text));
  add('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    add('${i + 1} 0 obj\n');
    out.addAll(objects[i]);
    add('\nendobj\n');
  }
  final startXref = out.length;
  add('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    add('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  add('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R $trailerExtra>>\n');
  add('startxref\n$startXref\n%%EOF\n');
  return Uint8List.fromList(out);
}
