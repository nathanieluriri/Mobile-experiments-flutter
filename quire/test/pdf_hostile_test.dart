import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/filters.dart';
import 'package:quire/pdf/lexer.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/pdf/seal.dart';

import 'support/pdf_bytes.dart';

Uint8List _ascii(String s) => Uint8List.fromList(ascii.encode(s));

/// Three objects that make a document of one empty page.
List<List<int>> _onePageObjects() => [
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>'),
    ];

/// A document whose only cross reference is a stream naming itself as its
/// own /XRefStm.
Uint8List _selfNamedXrefStream() {
  final out = <int>[];
  void add(String s) => out.addAll(latin1.encode(s));
  add('%PDF-1.7\n');
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>',
  ];
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    add('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final at = out.length;
  offsets.add(at);
  final rows = <int>[0, 0, 0, 0, 0, 0xff, 0xff];
  for (final offset in offsets) {
    rows
      ..add(1)
      ..addAll([
        (offset >> 24) & 0xff,
        (offset >> 16) & 0xff,
        (offset >> 8) & 0xff,
        offset & 0xff,
      ])
      ..addAll([0, 0]);
  }
  add('4 0 obj\n<< /Type /XRef /Size 5 /W [1 4 2] /Root 1 0 R '
      '/XRefStm $at /Length ${rows.length} >>\nstream\n');
  out.addAll(rows);
  add('\nendstream\nendobj\nstartxref\n$at\n%%EOF\n');
  return Uint8List.fromList(out);
}

/// [objects] with a classic trailer whose /XRefStm points at that same
/// table.
Uint8List _selfNamedHybrid() {
  final plain = ascii.decode(buildPdf(_onePageObjects()));
  final at = int.parse(
    RegExp(r'startxref\n(\d+)').firstMatch(plain)!.group(1)!,
  );
  return _ascii(plain.replaceFirst('/Root 1 0 R ', '/Root 1 0 R /XRefStm $at '));
}

/// A page tree that is a chain of [depth] /Pages nodes with one page at the
/// bottom.
Uint8List _pageChain(int depth) {
  final objects = <List<int>>[
    obj('<< /Type /Catalog /Pages 2 0 R >>'),
  ];
  for (var i = 0; i < depth; i++) {
    final number = i + 2;
    objects.add(obj('<< /Type /Pages /Kids [${number + 1} 0 R] /Count 1 >>'));
  }
  objects.add(obj('<< /Type /Page /MediaBox [0 0 200 200] >>'));
  return buildPdf(objects);
}

/// [base] with one object appended in an incremental update.
Uint8List _appended(Uint8List base, String body, {String trailerExtra = ''}) {
  final file = PdfFile.open(base, password: 'p');
  final number = file.xref.keys.reduce((a, b) => a > b ? a : b) + 1;
  final out = BytesBuilder()..add(base);
  final at = out.length;
  out.add(latin1.encode('$number 0 obj\n$body\nendobj\n'));
  final xrefAt = out.length;
  final root = file.trailer['Root'] as PdfRef;
  out.add(latin1.encode(
    'xref\n$number 1\n${at.toString().padLeft(10, '0')} 00000 n \n'
    'trailer\n<< /Size ${number + 1} /Root ${root.number} 0 R '
    '/Prev ${file.startxref} $trailerExtra>>\nstartxref\n$xrefAt\n%%EOF\n',
  ));
  return out.takeBytes();
}

void main() {
  group('nesting a file chooses', () {
    test('two hundred thousand [ are refused rather than overflowing', () {
      final lexer = PdfLexer(_ascii('[' * 200000));
      expect(lexer.parseObject, throwsA(isA<PdfTooDeep>()));
    });

    test('a hundred thousand << are refused rather than overflowing', () {
      final lexer = PdfLexer(_ascii('<< /A ' * 100000));
      expect(lexer.parseObject, throwsA(isA<PdfTooDeep>()));
    });

    test('nesting up to the limit still reads', () {
      const depth = kMaxPdfNesting;
      Object? value = PdfLexer(
        _ascii('${'[' * depth}(bottom)${']' * depth}'),
      ).parseObject();
      for (var i = 0; i < depth; i++) {
        value = (value! as List).single;
      }
      expect((value! as PdfString).asLatin1, 'bottom');
    });

    test('a refusal leaves the lexer ready for the next object', () {
      final lexer = PdfLexer(_ascii('${'[' * 300} [1 2]'));
      expect(lexer.parseObject, throwsA(isA<PdfTooDeep>()));
      lexer.pos = 301;
      expect(lexer.parseObject(), [1, 2]);
    });

    test('an object nested too deep reads as absent, not as a crash', () {
      final bytes = buildPdf([
        ..._onePageObjects(),
        obj('${'[' * 200000}${']' * 200000}'),
      ]);
      final file = PdfFile.open(bytes);
      expect(file.pageCount, 1);
      expect(file.getObject(4), isNull);
    });

    test('a page tree sixty thousand deep does not run the stack out', () {
      final file = PdfFile.open(_pageChain(60000));
      // The walk stops at the limit, and the scan over every object that
      // follows an empty tree still finds the one page.
      expect(file.pageCount, 1);
    });

    test('a page tree within the limit is walked as a tree', () {
      final file = PdfFile.open(_pageChain(200));
      expect(file.pageCount, 1);
      expect(file.pageRefs.single, const PdfRef(202, 0));
    });

    test('a trailer whose /XRefStm names its own table is read once', () {
      final file = PdfFile.open(_selfNamedHybrid());
      expect(file.recoveredByScan, isFalse);
      expect(file.pageCount, 1);
    });

    test('a cross reference stream naming itself as /XRefStm is read once',
        () {
      final file = PdfFile.open(_selfNamedXrefStream());
      expect(file.recoveredByScan, isFalse);
      expect(file.pageCount, 1);
    });

    test('an encrypted file with a deep object opens and reads the rest', () {
      final sealed = sealedPdf(buildPdf(_onePageObjects()), 'p');
      final deep = _appended(
        sealed,
        '${'[' * 5000}(x)${']' * 5000}',
        trailerExtra: _encryptTail(sealed),
      );
      final file = PdfFile.open(deep, password: 'p');
      expect(file.pageCount, 1);
      expect(file.getObject(file.xref.keys.reduce((a, b) => a > b ? a : b)),
          isNull);
    });
  });

  group('what a stream decodes to', () {
    test('a predictor row of 2^40 columns hands the data back undecoded', () {
      final data = Uint8List.fromList(List<int>.filled(64, 7));
      final out = applyPredictor(
        data,
        predictor: 12,
        colors: 1,
        bpc: 8,
        columns: 1099511627776,
      );
      expect(out, same(data));
    });

    test('negative, zero and absurd parameters hand the data back', () {
      final data = Uint8List.fromList(List<int>.filled(64, 7));
      for (final (columns, colors, bpc) in [
        (-1, 1, 8),
        (0, 1, 8),
        (4, 0, 8),
        (4, -3, 8),
        (4, 1, 0),
        (4, 1, 3),
        (4, 1000, 8),
        (65, 1, 8),
      ]) {
        for (final predictor in [2, 10, 12, 15]) {
          expect(
            applyPredictor(data,
                predictor: predictor,
                colors: colors,
                bpc: bpc,
                columns: columns),
            same(data),
            reason: 'columns $columns colors $colors bpc $bpc',
          );
        }
      }
    });

    test('a real PNG up predictor still decodes', () {
      final data = Uint8List.fromList([2, 1, 2, 3, 2, 1, 1, 1]);
      expect(
        applyPredictor(data, predictor: 12, colors: 1, bpc: 8, columns: 3),
        [1, 2, 3, 2, 3, 4],
      );
    });

    test('an xref stream with /Columns 2^40 opens rather than asking for a '
        'terabyte', () {
      final bytes = buildPdf([
        ..._onePageObjects(),
        streamObj(
          '/Filter /FlateDecode /DecodeParms << /Predictor 12 '
          '/Columns 1099511627776 >>',
          ZLibCodec().encode(List<int>.filled(32, 0)),
        ),
      ]);
      final file = PdfFile.open(bytes);
      final stream = file.getObject(4)! as PdfStream;
      expect(file.decodeStream(stream).length, 32);
    });

    test('Flate stages chained into a gigabyte are refused on the way', () {
      final twice = _twiceCompressed();
      expect(twice.length, lessThan(64 * 1024));
      final stage = inflate(twice);
      expect(stage.length, greaterThan(200 * 1024));
      expect(() => inflate(stage), throwsA(isA<PdfStreamTooLarge>()));
    });

    test('a doubly compressed stream in a file reads as refused', () {
      final twice = _twiceCompressed();
      final bytes = buildPdf([
        ..._onePageObjects(),
        streamObj('/Filter [/FlateDecode /FlateDecode]', twice),
      ]);
      final file = PdfFile.open(bytes);
      final stream = file.getObject(4)! as PdfStream;
      expect(() => file.decodeStream(stream),
          throwsA(isA<PdfStreamTooLarge>()));
    });

    test('an LZW stream that never clears its table stays bounded', () {
      // Code 258 onward, each naming the newest entry, grows every string by
      // one byte. Without a full table stopping it, the table and the output
      // grow quadratically in the codes read.
      final codes = <int>[65];
      for (var c = 258; c < 4096 + 200000; c++) {
        codes.add(c < 4096 ? c : 4095);
      }
      expect(ascii.decode(lzwDecode(_packCodes([65, 258, 259, 257]))),
          'AAAAAA');
      final bytes = _packCodes(codes);
      expect(() => lzwDecode(bytes), throwsA(isA<PdfStreamTooLarge>()));
    });

    test('run length at its own ceiling still decodes', () {
      final data = Uint8List.fromList(
        [for (var i = 0; i < 1 << 16; i++) ...[129, 0]],
      );
      expect(runLengthDecode(data).length, (1 << 16) * 128);
    });

    test('the limit sits above every ratio a real encoder reaches', () {
      expect(decodeLimit(1), greaterThan(2730));
      expect(decodeLimit(1 << 30), kMaxDecodedBytes);
    });
  });
}

Uint8List? _twice;

/// Two hundred and fifty six megabytes of zeros, compressed twice.
Uint8List _twiceCompressed() => _twice ??= Uint8List.fromList(
      ZLibCodec(level: 9).encode(
        ZLibCodec(level: 9).encode(Uint8List(256 * 1024 * 1024)),
      ),
    );

/// The /Encrypt and /ID a sealed file's trailer carries, for an update to
/// repeat.
String _encryptTail(Uint8List sealed) {
  final file = PdfFile.open(sealed, password: 'p');
  final encrypt = file.trailer['Encrypt'] as PdfRef;
  final id = (file.trailer['ID'] as List)
      .cast<PdfString>()
      .map((s) => '<${s.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>')
      .join(' ');
  return '/Encrypt ${encrypt.number} 0 R /ID [$id] ';
}

/// [codes] packed as LZW codes, widening from nine to twelve bits the way a
/// decoder with EarlyChange 1 expects.
Uint8List _packCodes(List<int> codes) {
  final out = <int>[];
  var buffer = 0, bits = 0, width = 9, table = 258;
  for (var i = 0; i < codes.length; i++) {
    buffer = (buffer << width) | codes[i];
    bits += width;
    while (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
    buffer &= (1 << bits) - 1;
    if (i > 0 && table < 4096) table++;
    if (table >= (1 << width) && width < 12) width++;
  }
  if (bits > 0) out.add((buffer << (8 - bits)) & 0xff);
  return Uint8List.fromList(out);
}
