/// The documents on the desk: the six quire ships with, and the shape of any
/// the reader brings in.
///
/// The shipped six are literals, byte counts included, so laying out the desk
/// needs no file system read and no parse: the first frame of the app is
/// correct before a single document has been opened. A document the reader
/// opens from the phone is the same shape, made at import from what the file
/// says about itself.
library;

/// The five formats quire reads.
enum DocFormat {
  pdf('PDF', 'pdf'),
  docx('DOC', 'docx'),
  xlsx('XLS', 'xlsx'),
  csv('CSV', 'csv'),
  md('MD', 'md');

  const DocFormat(this.mark, this.extension);

  /// The letters printed on the type mark.
  final String mark;

  /// The file extension, which is also the string a parsed document reports as
  /// its source format.
  final String extension;

  /// The format a file's extension names, or null for one quire does not read.
  static DocFormat? forExtension(String extension) {
    final wanted = extension.toLowerCase();
    for (final format in DocFormat.values) {
      if (format.extension == wanted) return format;
    }
    return null;
  }
}

/// Where a document's bytes live.
enum DocSource {
  /// Inside the app, shipped with it.
  asset,

  /// In the app's own storage, copied there when the reader opened it.
  file,
}

/// One document on the desk.
class LibraryEntry {
  const LibraryEntry({
    required this.path,
    required this.title,
    required this.format,
    required this.bytes,
    this.source = DocSource.asset,
  });

  /// A document the reader opened from the phone, described by its file.
  ///
  /// The title is the file name treated the way the shipped titles were:
  /// extension off, hyphens and underscores to spaces, each word capitalised,
  /// so a file called `press-run-costs.xlsx` sits beside Press Run Costs
  /// without looking like it came in through a different door.
  factory LibraryEntry.imported({
    required String path,
    required DocFormat format,
    required int bytes,
  }) =>
      LibraryEntry(
        path: path,
        title: titleFor(path),
        format: format,
        bytes: bytes,
        source: DocSource.file,
      );

  /// The same document under a different name.
  ///
  /// Only the title changes. The path is what the desk keys everything else
  /// by, from the reading position to the signatures, so a rename that moved
  /// it would be a rename that lost the reading.
  LibraryEntry renamed(String title) => LibraryEntry(
    path: path,
    title: title.trim().isEmpty ? this.title : title.trim(),
    format: format,
    bytes: bytes,
    source: source,
  );

  /// Where the bytes are: an asset path, or a path on the file system.
  final String path;

  /// The display title: the file name, hyphens turned to spaces, title cased.
  final String title;
  final DocFormat format;

  /// The file's exact size, a literal for the shipped six so no read is
  /// needed, and the file's length for the rest.
  final int bytes;

  final DocSource source;

  /// The file name with its extension, for the back of the card.
  String get fileName {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    final cut = slash > backslash ? slash : backslash;
    return cut < 0 ? path : path.substring(cut + 1);
  }

  /// The letters on the type mark.
  String get mark => format.mark;

  /// The size as the card prints it, in binary kilobytes.
  ///
  /// Binary rather than decimal because it is what every file browser on the
  /// devices this runs on shows, and a reader comparing the two should see the
  /// same number.
  String get sizeLabel {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  /// The title a file at [path] gets on the desk.
  static String titleFor(String path) {
    var name = path;
    final cut = name.lastIndexOf(RegExp(r'[/\\]'));
    if (cut >= 0) name = name.substring(cut + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    final words = name
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1));
    final title = words.join(' ');
    return title.isEmpty ? 'Untitled' : title;
  }
}

/// The shipped documents, in the order the desk lays them out.
const List<LibraryEntry> libraryEntries = <LibraryEntry>[
  LibraryEntry(
    path: 'assets/documents/field-guide-to-paper.pdf',
    title: 'Field Guide To Paper',
    format: DocFormat.pdf,
    bytes: 313458,
  ),
  LibraryEntry(
    path: 'assets/documents/press-lease.pdf',
    title: 'Press Lease',
    format: DocFormat.pdf,
    bytes: 20966,
  ),
  LibraryEntry(
    path: 'assets/documents/house-style.docx',
    title: 'House Style',
    format: DocFormat.docx,
    bytes: 11362,
  ),
  LibraryEntry(
    path: 'assets/documents/press-run-costs.xlsx',
    title: 'Press Run Costs',
    format: DocFormat.xlsx,
    bytes: 9601,
  ),
  LibraryEntry(
    path: 'assets/documents/subscribers.csv',
    title: 'Subscribers',
    format: DocFormat.csv,
    bytes: 6578,
  ),
  LibraryEntry(
    path: 'assets/documents/bindery-notes.md',
    title: 'Bindery Notes',
    format: DocFormat.md,
    bytes: 6132,
  ),
];
