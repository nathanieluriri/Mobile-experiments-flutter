/// The bundled documents, and hand built pages for the states that have no
/// file behind them.
///
/// Bytes and parses are cached per test file, so a suite that touches the same
/// document twenty times parses it once. Everything here is deterministic:
/// nothing reads a clock and nothing reaches outside the bundle.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/format/document_loader.dart';
import 'package:quire/model/document.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/services/document_store.dart';

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
