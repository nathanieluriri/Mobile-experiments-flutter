/// The bundled documents, and hand built pages for the states that have no
/// file behind them.
///
/// Bytes and parses are cached per test file, so a suite that touches the same
/// document twenty times parses it once. Everything here is deterministic:
/// nothing reads a clock and nothing reaches outside the bundle.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/format/document_loader.dart';
import 'package:quire/model/document.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/widgets/marked_text.dart';

final Map<String, Uint8List> _bytes = <String, Uint8List>{};
final Map<String, LoadedDocument> _loaded = <String, LoadedDocument>{};

/// The six bundled documents by their file names.
const String kFieldGuide = 'field-guide-to-paper.pdf';
const String kPressLease = 'press-lease.pdf';
const String kHouseStyle = 'house-style.docx';
const String kPressRunCosts = 'press-run-costs.xlsx';
const String kSubscribers = 'subscribers.csv';
const String kBinderyNotes = 'bindery-notes.md';

/// The raw bytes of a bundled document.
Future<Uint8List> documentBytes(String fileName) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final held = _bytes[fileName];
  if (held != null) return held;
  final data = await rootBundle.load('assets/documents/$fileName');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  _bytes[fileName] = bytes;
  return bytes;
}

/// A bundled document run through the loader, cached.
Future<LoadedDocument> loadedDocument(String fileName) async {
  final held = _loaded[fileName];
  if (held != null) return held;
  final result = DocumentLoader.load(await documentBytes(fileName), fileName);
  _loaded[fileName] = result;
  return result;
}

/// A bundled document's parsed model. Fails the test if it did not parse.
Future<QuireDocument> parsedDocument(String fileName) async {
  final result = await loadedDocument(fileName);
  final doc = result.document;
  if (doc == null) {
    throw StateError('$fileName did not parse: ${result.error}');
  }
  return doc;
}

/// The desk entry for a bundled document.
LibraryEntry entryFor(String fileName) =>
    libraryEntries.firstWhere((e) => e.fileName == fileName);

/// A document's title where the desk draws it, in a list row or on a grid
/// card.
///
/// It is never a plain [Text]: a title can be struck through by the search,
/// so it is laid out and painted by [MarkedText] in one pass and `find.text`
/// would miss every one of them.
Finder documentTitled(String title) => find.byWidgetPredicate(
      (widget) => widget is MarkedText && widget.text == title,
      description: 'document titled "$title"',
    );

/// A store already holding a parsed bundled document.
Future<DocumentStore> storeFor(String fileName) async =>
    DocumentStore.ready(entryFor(fileName), await documentBytes(fileName));

/// A page carrying real text and nothing else. The default rung.
PageDisplayList richPage() {
  final list = PageDisplayList(widthPts: 612, heightPts: 792, rotation: 0);
  list.texts.add(textRun('The grain runs the long way.', seq: 1));
  list.paths.add(rulePath(seq: 2));
  return list;
}

/// A page whose only content is one large image in [encoding].
///
/// Coverage is deliberately over [kScanCoverageForFixtures] so the plan reads
/// it as a scan rather than as a decorative picture.
PageDisplayList scanPage({String encoding = 'jpeg'}) {
  final list = PageDisplayList(widthPts: 612, heightPts: 792, rotation: 0);
  list.images.add(imageCmd(
    rect: const <double>[0, 0, 612, 792],
    encoding: encoding,
    bytes: encoding == 'jpeg' || encoding.startsWith('raw')
        ? Uint8List.fromList(const <int>[0xFF, 0xD8, 0xFF])
        : null,
    seq: 1,
  ));
  return list;
}

/// A page with real text plus one image this reader cannot decode.
PageDisplayList textWithUndecodableImagePage() {
  final list = PageDisplayList(widthPts: 612, heightPts: 792, rotation: 0);
  list.texts.add(textRun('Figure 2, the fold tester.', seq: 1));
  list.images.add(imageCmd(
    rect: const <double>[72, 200, 300, 400],
    encoding: 'jpx',
    bytes: null,
    seq: 2,
  ));
  return list;
}

/// A page with no text, no paths and no images.
PageDisplayList blankPage() =>
    PageDisplayList(widthPts: 612, heightPts: 792, rotation: 0);

/// The coverage threshold the fixtures are built against.
const double kScanCoverageForFixtures = 0.4;

/// One merged text run, with the fields a painter needs already sane.
TextRunCmd textRun(
  String text, {
  double x = 72,
  double y = 96,
  double fontSize = 11,
  double widthPts = 240,
  int seq = 0,
  int color = 0xFF000000,
}) =>
    TextRunCmd(
      text: text,
      x: x,
      y: y,
      fontSize: fontSize,
      widthPts: widthPts,
      fontKey: 'F1',
      bold: false,
      italic: false,
      serif: true,
      mono: false,
      color: color,
      rotated: false,
      seq: seq,
    );

/// A one point horizontal rule, the cheapest real path a page can carry.
PathCmd rulePath({int seq = 0}) => PathCmd(
      segs: const <PathSeg>[
        PathSeg(PathOp.move, <double>[72, 120]),
        PathSeg(PathOp.line, <double>[540, 120]),
      ],
      fill: false,
      stroke: true,
      fillColor: 0xFF000000,
      strokeColor: 0xFF000000,
      lineWidth: 1,
      evenOdd: false,
      seq: seq,
    );

/// One image command placed at [rect] in top left page space.
ImageCmd imageCmd({
  required List<double> rect,
  required String encoding,
  required Uint8List? bytes,
  int seq = 0,
  String name = 'Im0',
  int width = 1200,
  int height = 1600,
}) =>
    ImageCmd(
      name: name,
      rect: rect,
      bytes: bytes,
      encoding: encoding,
      width: width,
      height: height,
      seq: seq,
    );

/// A genuine one page file whose only content is a filled rectangle.
///
/// It stands for the scanned page: a page the engine reads all the way
/// through and which turns out to carry no text layer at all. None of the six
/// bundled documents is one, and the back of a sheet has a designed answer for
/// exactly that case, so the case has to exist somewhere for the answer to be
/// tested against. The bytes are assembled here rather than checked in as a
/// blob, so what makes this page textless is visible.
Uint8List pageWithoutTextLayer() {
  final content = ascii.encode('0 0 0 rg 72 72 468 648 re f\n');
  final objects = <List<int>>[
    ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    ascii.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    ascii.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << >> /Contents 4 0 R >>',
    ),
    <int>[
      ...ascii.encode('<< /Length ${content.length} >>\nstream\n'),
      ...content,
      ...ascii.encode('\nendstream'),
    ],
  ];
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
  add('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
  add('startxref\n$startXref\n%%EOF\n');
  return Uint8List.fromList(out);
}
