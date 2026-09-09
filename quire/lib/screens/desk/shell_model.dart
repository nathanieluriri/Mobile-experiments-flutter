import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';

/// The five tabs across the top of the library.
///
/// A tab is a filter over formats, not a folder: nothing moves when you change
/// one, which is why the list is allowed to reorder without a dissolve.
enum DeskTab {
  recent('RECENT'),
  pdf('PDF'),
  docs('DOCS'),
  sheets('SHEETS'),
  notes('NOTES');

  const DeskTab(this.label);

  /// Written uppercase in the source so a golden reads what the source says.
  final String label;

  /// True when [entry] belongs under this tab.
  ///
  /// SHEETS holds both spreadsheet formats, because the difference between a
  /// workbook and a comma separated file is a parser's problem and not a
  /// reader's.
  bool holds(LibraryEntry entry) => switch (this) {
        DeskTab.recent => true,
        DeskTab.pdf => entry.format == DocFormat.pdf,
        DeskTab.docs => entry.format == DocFormat.docx,
        DeskTab.sheets =>
          entry.format == DocFormat.xlsx || entry.format == DocFormat.csv,
        DeskTab.notes => entry.format == DocFormat.md,
      };
}

/// What the list is ordered by. The first group of the sort menu.
enum SortField {
  name('Name'),
  dateModified('Date modified'),
  dateOpened('Date opened'),
  size('Size');

  const SortField(this.label);

  /// What the sort row prints on the left.
  final String label;
}

/// Which way round that order runs. The second group of the sort menu.
///
/// One switch for all four fields, so it reads `New to old` even when the
/// field is a name: the two rows are a direction, and giving each field its
/// own pair of words would be four vocabularies for one control.
enum SortOrder {
  newToOld('New to old'),
  oldToNew('Old to new');

  const SortOrder(this.label);

  final String label;
}

/// List or grid. The two toggles on the right of the sort row.
enum DeskView { list, grid }

/// The nine places the drawer can take you.
///
/// Seven of them have nothing to hold: quire ships one bundled library and has
/// no account, so there is no star, no bin and no activity behind these rows.
/// They are still here, and each one says plainly what would be there, because
/// a row that does nothing when you tap it is worse than a row that is not on
/// the list at all.
enum DrawerDestination {
  recent(
    label: 'Recent',
    icon: LucideIcons.clock,
    library: true,
  ),
  allFiles(
    label: 'All files',
    icon: LucideIcons.layers,
    library: true,
  ),
  starred(
    label: 'Starred',
    icon: LucideIcons.star,
    headline: 'Nothing starred',
    body: 'A document you star is kept at the top of this list, ahead of '
        'whatever you read last.',
  ),
  signed(
    label: 'Signed',
    icon: LucideIcons.penTool,
    headline: 'Nothing signed',
    body: 'Draw a signature on a PDF and it is listed here, with the page you '
        'set the mark into.',
  ),
  offline(
    label: 'Offline',
    icon: LucideIcons.circleCheck,
    headline: 'All six are offline',
    body: 'quire ships its library inside the app, so every document you have '
        'is already on this device. Nothing here waits on a network.',
  ),
  bin(
    label: 'Bin',
    icon: LucideIcons.trash2,
    headline: 'The bin is empty',
    body: 'A document you remove is offered back for four seconds, then it is '
        'gone. Nothing is kept to be emptied later.',
  ),
  activity(
    label: 'Activity',
    icon: LucideIcons.bell,
    headline: 'No activity',
    body: 'Opens, edits and signatures would be listed here once there is '
        'somebody other than you to have made them.',
  ),
  settings(
    label: 'Settings',
    icon: LucideIcons.settings,
    headline: 'Nothing to set',
    body: 'One theme, one family, one library. Everything quire could offer a '
        'switch for, it has already decided.',
  ),
  about(
    label: 'About quire',
    icon: LucideIcons.circleHelp,
    headline: 'quire',
    body: 'A reader for PDF, Word, spreadsheet, CSV and Markdown files. It '
        'renders them, searches inside them, and signs a PDF with a mark you '
        'draw yourself.',
  );

  const DrawerDestination({
    required this.label,
    required this.icon,
    this.library = false,
    this.headline = '',
    this.body = '',
  });

  final String label;
  final IconData icon;

  /// True for the two rows that reach the documents themselves.
  final bool library;

  /// What the destination says when it has nothing to show. Empty for the two
  /// rows that show the library instead.
  final String headline;
  final String body;
}

/// The last row of the first group, which the divider sits under.
const kDrawerLastOfGroup = DrawerDestination.activity;

/// The library under [tab], ordered by [field] and [order].
///
/// [visible] has already had the search applied to it, so this is only ever
/// the two decisions the shell itself owns.
List<LibraryEntry> shellEntries(
  List<LibraryEntry> visible,
  DeskTab tab,
  SortField field,
  SortOrder order,
  DocumentStore? Function(LibraryEntry entry) storeOf,
) {
  final out = visible.where(tab.holds).toList();
  final natural = <LibraryEntry>[...out]..sort(
      (a, b) => _compare(a, b, field, visible, storeOf),
    );
  return order == SortOrder.newToOld ? natural : natural.reversed.toList();
}

/// The order [field] means when it is read forwards: newest, largest, or first
/// alphabetically.
///
/// Nothing here reads a clock. The manifest is the order the library was put
/// together in, newest first, so it is the modification order already, and how
/// recently something was opened is a count the store keeps rather than a
/// timestamp. That is what lets the desk sort itself identically on every run.
int _compare(
  LibraryEntry a,
  LibraryEntry b,
  SortField field,
  List<LibraryEntry> manifest,
  DocumentStore? Function(LibraryEntry entry) storeOf,
) {
  final byManifest = manifest.indexOf(a).compareTo(manifest.indexOf(b));
  switch (field) {
    case SortField.name:
      final byName = a.title.compareTo(b.title);
      return byName != 0 ? byName : byManifest;
    case SortField.size:
      final bySize = b.bytes.compareTo(a.bytes);
      return bySize != 0 ? bySize : byManifest;
    case SortField.dateModified:
      return byManifest;
    case SortField.dateOpened:
      final byOpens = (storeOf(b)?.opens ?? 0).compareTo(storeOf(a)?.opens ?? 0);
      return byOpens != 0 ? byOpens : byManifest;
  }
}
