import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/document.dart';
import 'csv_parser.dart';
import 'docx_parser.dart';
import 'markdown_parser.dart';
import 'xlsx_parser.dart';

/// The result of trying to read one file.
///
/// Every load returns one of these, including the failures. A parser that
/// throws and a parser that quietly produces nothing both end up here with
/// [error] set, because a blank page that claims success is the worse of the
/// two failures: it lies about what is in the file.
class LoadedDocument {
  const LoadedDocument({
    required this.name,
    required this.format,
    required this.bytes,
    this.document,
    this.error,
  });

  /// The file name the bytes came in under.
  final String name;

  /// 'pdf', 'docx', 'xlsx', 'csv', 'md', or 'unknown'.
  final String format;

  /// The original bytes, kept because a PDF is opened by the page engine
  /// rather than parsed into [QuireDocument] here.
  final Uint8List bytes;

  /// The parsed document, or null for a PDF and for every failure.
  final QuireDocument? document;

  /// What went wrong, or null.
  final Object? error;

  /// True when nothing readable came back.
  bool get failed => error != null;

  /// True when this file belongs to the page engine rather than the block
  /// model.
  bool get isPdf => format == 'pdf';
}

/// Sniffs a file and hands it to the right parser.
///
/// The two exceptions that escape the office parsers are [ArchiveException]
/// (garbage bytes, a truncated zip, an empty file) and [FormatException] (a
/// valid zip whose payload is not the format the name promised). Both are
/// caught here, so a damaged file is a designed state upstream and never a
/// crash and never a dialog.
abstract final class DocumentLoader {
  /// Reads [bytes] as the format implied by [name] and its magic bytes.
  static LoadedDocument load(Uint8List bytes, String name) {
    final format = sniff(bytes, name);
    final title = titleFor(name);
    if (format == 'pdf') {
      return LoadedDocument(name: name, format: format, bytes: bytes);
    }
    try {
      final doc = _parse(bytes, format, title);
      if (_isEmpty(doc)) {
        throw FormatException('$format file holds no content', name);
      }
      return LoadedDocument(
        name: name,
        format: format,
        bytes: bytes,
        document: doc,
      );
    } on ArchiveException catch (e) {
      return LoadedDocument(
          name: name, format: format, bytes: bytes, error: e);
    } on FormatException catch (e) {
      return LoadedDocument(
          name: name, format: format, bytes: bytes, error: e);
    }
  }

  static QuireDocument _parse(Uint8List bytes, String format, String title) {
    switch (format) {
      case 'docx':
        return DocxParser(bytes).parse(title: title);
      case 'xlsx':
        return xlsxToDocument(XlsxParser(bytes).parse(), title);
      case 'csv':
        return csvToDocument(readCsv(bytes), title);
      case 'md':
        return MarkdownParser(_decodeText(bytes)).parse(title: title);
      default:
        throw FormatException('unrecognised format', title);
    }
  }

  /// True when a parse succeeded but produced nothing worth painting.
  ///
  /// This is the silent failure the boundary exists to catch. A reader that
  /// shows an empty sheet and reports success sends the reader looking for a
  /// bug in their own eyes.
  static bool _isEmpty(QuireDocument doc) {
    for (final section in doc.sections) {
      for (final block in section.blocks) {
        switch (block) {
          case TableBlock():
            for (final row in block.rows) {
              for (final cell in row.cells) {
                if (cell.text.trim().isNotEmpty) return false;
              }
            }
          case ParagraphBlock():
            if (block.text.trim().isNotEmpty) return false;
          case HeadingBlock():
            if (block.text.trim().isNotEmpty) return false;
          case ListItemBlock():
            if (block.text.trim().isNotEmpty) return false;
          case CodeBlock():
            if (block.text.trim().isNotEmpty) return false;
          case ImageBlock():
            return false;
          case DividerBlock():
            break;
        }
      }
    }
    return true;
  }

  /// Decides the format from the magic bytes first and the extension second.
  ///
  /// The bytes are the authority because a renamed file is common and a lying
  /// extension would send a spreadsheet to the Word parser, which throws a
  /// [FormatException] that reads like corruption rather than a mismatch.
  static String sniff(Uint8List bytes, String name) {
    final ext = extensionOf(name);
    if (_startsWith(bytes, const [0x25, 0x50, 0x44, 0x46])) return 'pdf';
    if (_startsWith(bytes, const [0x50, 0x4B, 0x03, 0x04])) {
      final inside = _zipFlavour(bytes);
      if (inside != null) return inside;
      if (ext == 'docx' || ext == 'xlsx') return ext;
      return 'unknown';
    }
    switch (ext) {
      case 'pdf':
        return 'pdf';
      case 'csv':
      case 'tsv':
        return 'csv';
      case 'md':
      case 'markdown':
      case 'txt':
        return 'md';
      case 'docx':
      case 'xlsx':
        // The name promises a container that is not there.
        return ext;
      default:
        return 'unknown';
    }
  }

  /// Looks inside a zip for the one part that names the format.
  ///
  /// Reading the container rather than trusting the extension is what lets a
  /// .docx that is really a workbook parse as a workbook.
  static String? _zipFlavour(Uint8List bytes) {
    try {
      final zip = ZipDecoder().decodeBytes(bytes, verify: false);
      var hasWord = false;
      var hasSheet = false;
      for (final f in zip.files) {
        if (f.name == 'word/document.xml') hasWord = true;
        if (f.name == 'xl/workbook.xml') hasSheet = true;
      }
      if (hasWord) return 'docx';
      if (hasSheet) return 'xlsx';
      return null;
    } on ArchiveException {
      return null;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static bool _startsWith(Uint8List bytes, List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// Text bytes, BOM stripped, never throwing on a stray byte.
  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// The lowercased extension of [name] without its dot.
  static String extensionOf(String name) {
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    final base = slash < 0 ? name : name.substring(slash + 1);
    final dot = base.lastIndexOf('.');
    return dot <= 0 ? '' : base.substring(dot + 1).toLowerCase();
  }

  /// The display title of a file: extension stripped, hyphens and underscores
  /// turned to spaces, every word capitalised.
  static String titleFor(String name) {
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    var base = slash < 0 ? name : name.substring(slash + 1);
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    final words = base
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1));
    return words.join(' ');
  }
}
