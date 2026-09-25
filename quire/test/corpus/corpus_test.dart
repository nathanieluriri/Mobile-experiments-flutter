import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/standard_metrics.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/objects.dart';

/// Where the corpus lives: QUIRE_CORPUS, or test/corpus/pdfs, which git
/// ignores. The files are never committed, and none is quoted here.
Directory _corpus() => Directory(
      Platform.environment['QUIRE_CORPUS'] ?? 'test/corpus/pdfs',
    );

/// Words that suggest a file belongs to somebody. Such a file is not opened,
/// and nothing about it is printed.
final _personal = RegExp(
  r'statement|invoice|receipt|payslip|salary|passport|licen[cs]e|'
  r'bank|tax|medical|resume|\bcv\b|contract|lease|id[-_ ]?card|@',
  caseSensitive: false,
);

/// The filters [PdfFile.decodeStream] decodes, by every name they go by.
const _decoded = {
  'FlateDecode', 'Fl', 'LZWDecode', 'LZW', 'ASCII85Decode', 'A85',
  'ASCIIHexDecode', 'AHx', 'RunLengthDecode', 'RL',
  // Handed on to the image layer rather than decoded here.
  'DCTDecode', 'DCT', 'JPXDecode', 'CCITTFaxDecode', 'CCF', 'JBIG2Decode',
};

/// How each font a page names is drawn: by its own embedded program, from
/// the standard fourteen's metrics, or by a guess at its widths.
String _fontKind(PdfFile file, Map<String, Object?> font) {
  final subtype = (file.resolve(font['Subtype']) as PdfName?)?.value ?? '?';
  var descriptor = file.dict(font['FontDescriptor']);
  if (subtype == 'Type0') {
    final descendants = file.resolve(font['DescendantFonts']);
    if (descendants is List && descendants.isNotEmpty) {
      descriptor = file.dict(file.dict(descendants.first)?['FontDescriptor']);
    }
  }
  final embedded = descriptor != null &&
      (descriptor['FontFile'] != null ||
          descriptor['FontFile2'] != null ||
          descriptor['FontFile3'] != null);
  var base = ((file.resolve(font['BaseFont']) as PdfName?)?.value ?? '')
      .toLowerCase();
  if (base.indexOf('+') == 6) base = base.substring(7);
  base = base.replaceFirst('arial', 'helvetica');
  if (subtype == 'Type3') return 'Type3';
  if (embedded) return '$subtype embedded';
  if (isStandardFontName(base)) return '$subtype standard';
  if (font['Widths'] != null) return '$subtype widths only';
  return '$subtype guessed';
}

class _Report {
  final lines = <String>[];
  final totals = <String, int>{};

  void count(String what, [int by = 1]) =>
      totals.update(what, (n) => n + by, ifAbsent: () => by);
}

void _read(File entry, String label, _Report report) {
  final bytes = entry.readAsBytesSync();
  final PdfFile file;
  try {
    file = PdfFile.open(bytes);
  } on PdfLocked catch (e) {
    report.lines.add('$label: locked (${e.cipher})');
    report.count('locked');
    return;
  } on Object catch (e) {
    report.lines.add('$label: does not open (${e.runtimeType})');
    report.count('does not open');
    return;
  }
  report.count('files');

  final filters = <String>{};
  for (final number in file.xref.keys) {
    final object = file.getObject(number);
    if (object is PdfStream) {
      for (final name in file.streamFilters(object)) {
        if (!_decoded.contains(name)) filters.add(name);
      }
    }
  }

  final fonts = <String, int>{};
  final pages = file.pageCount;
  var glyphs = 0;
  final empty = <int>[];
  final problems = <String>{};
  for (var i = 0; i < pages; i++) {
    final page = file.pages[i];
    final resources = file.dict(page['Resources']);
    final pageFonts = file.dict(resources?['Font']);
    pageFonts?.forEach((_, value) {
      final font = file.dict(value);
      if (font != null) fonts.update(_fontKind(file, font), (n) => n + 1, ifAbsent: () => 1);
    });
    final interpreter = ContentInterpreter(file);
    final PageDisplayList list;
    try {
      list = interpreter.run(page);
    } on Object catch (e) {
      problems.add('page ${i + 1} throws ${e.runtimeType}');
      report.count('pages that throw');
      continue;
    }
    report.count('pages');
    final pageGlyphs =
        list.texts.fold<int>(0, (n, t) => n + t.text.runes.length);
    glyphs += pageGlyphs;
    final drawn = list.texts.length + list.paths.length + list.images.length;
    if (drawn == 0 && file.pageContent(page).length > 64) {
      empty.add(i + 1);
      report.count('empty pages with content');
    }
    for (final op in interpreter.unsupported) {
      problems.add('skips $op');
      report.count('skips $op');
    }
    if (interpreter.missingFonts.isNotEmpty) {
      problems.add('${interpreter.missingFonts.length} fonts missing, '
          '${interpreter.droppedShows} shows dropped');
      report.count('shows dropped', interpreter.droppedShows);
    }
    if (interpreter.unmappedGlyphs > 0) {
      report.count('unmapped glyphs', interpreter.unmappedGlyphs);
      problems.add('unmapped glyphs');
    }
    final box = file.mediaBox(page);
    if (box[0] != 0 || box[1] != 0) problems.add('box origin off zero');
    if (page['UserUnit'] != null) problems.add('UserUnit');
  }
  for (final kind in fonts.keys) {
    report.count('font: $kind', fonts[kind]!);
  }
  for (final name in filters) {
    report.count('filter not decoded: $name');
  }
  report.lines.add(
    '$label: $pages pages, $glyphs glyphs'
    '${empty.isEmpty ? '' : ', EMPTY pages ${empty.join(' ')}'}'
    '${filters.isEmpty ? '' : ', filters ${filters.join(' ')}'}'
    '${problems.isEmpty ? '' : ', ${problems.join('; ')}'}'
    ', fonts ${fonts.entries.map((e) => '${e.key} x${e.value}').join(', ')}',
  );
}

void main() {
  final folder = _corpus();
  test(
    'the corpus reads',
    () {
      final report = _Report();
      final files = folder
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      var index = 0;
      for (final entry in files) {
        final name = entry.uri.pathSegments.last;
        index++;
        if (_personal.hasMatch(name)) {
          report.count('skipped as personal');
          continue;
        }
        // Named by the corpus's own labels only under QUIRE_CORPUS_NAMES,
        // so a report can be shared without saying what is in the folder.
        final label = Platform.environment['QUIRE_CORPUS_NAMES'] == '1'
            ? name
            : 'file $index';
        _read(entry, label, report);
      }
      final out = StringBuffer()
        ..writeln('corpus: ${files.length} files')
        ..writeAll(report.lines, '\n')
        ..writeln()
        ..writeln('totals:');
      final keys = report.totals.keys.toList()..sort();
      for (final key in keys) {
        out.writeln('  $key: ${report.totals[key]}');
      }
      Directory('build/corpus').createSync(recursive: true);
      File('build/corpus/report.txt').writeAsStringSync(out.toString());
      // ignore: avoid_print
      print(out);
    },
    skip: folder.existsSync() ? false : 'no corpus at ${folder.path}',
    timeout: Timeout.none,
  );
}
