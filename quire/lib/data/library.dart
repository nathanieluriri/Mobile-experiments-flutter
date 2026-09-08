/// The six documents quire ships with.
///
/// Everything here is a literal, byte counts included, so laying out the desk
/// needs no file system read and no parse: the first frame of the app is
/// correct before a single document has been opened.
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
}

/// One document on the desk.
class LibraryEntry {
  const LibraryEntry({
    required this.assetPath,
    required this.title,
    required this.format,
    required this.bytes,
  });

  /// Where the bundle holds the file.
  final String assetPath;

  /// The display title: the file name, hyphens turned to spaces, title cased.
  final String title;
  final DocFormat format;

  /// The file's exact size on disk, a literal so no read is needed.
  final int bytes;

  /// The file name with its extension, for the back of the card.
  String get fileName {
    final slash = assetPath.lastIndexOf('/');
    return slash < 0 ? assetPath : assetPath.substring(slash + 1);
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
}

/// The desk, in the order it is laid out.
const List<LibraryEntry> libraryEntries = <LibraryEntry>[
  LibraryEntry(
    assetPath: 'assets/documents/field-guide-to-paper.pdf',
    title: 'Field Guide To Paper',
    format: DocFormat.pdf,
    bytes: 313458,
  ),
  LibraryEntry(
    assetPath: 'assets/documents/press-lease.pdf',
    title: 'Press Lease',
    format: DocFormat.pdf,
    bytes: 20966,
  ),
  LibraryEntry(
    assetPath: 'assets/documents/house-style.docx',
    title: 'House Style',
    format: DocFormat.docx,
    bytes: 11362,
  ),
  LibraryEntry(
    assetPath: 'assets/documents/press-run-costs.xlsx',
    title: 'Press Run Costs',
    format: DocFormat.xlsx,
    bytes: 9601,
  ),
  LibraryEntry(
    assetPath: 'assets/documents/subscribers.csv',
    title: 'Subscribers',
    format: DocFormat.csv,
    bytes: 6578,
  ),
  LibraryEntry(
    assetPath: 'assets/documents/bindery-notes.md',
    title: 'Bindery Notes',
    format: DocFormat.md,
    bytes: 6132,
  ),
];
