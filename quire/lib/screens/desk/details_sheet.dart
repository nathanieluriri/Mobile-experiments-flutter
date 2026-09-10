import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';
import 'desk_sheet.dart';
import 'document_card.dart';

/// Everything the desk knows about one document, stated plainly.
///
/// Every number here is one the app worked out for itself by reading the file,
/// so this is also the honest answer to what has actually been parsed: a
/// document nobody has opened says so rather than inventing a page count.
class DetailsSheet extends StatelessWidget {
  const DetailsSheet({
    super.key,
    required this.entry,
    required this.store,
    required this.starred,
    required this.binned,
  });

  final LibraryEntry entry;

  /// What has been read of the file, or null if nothing has.
  final DocumentStore? store;

  final bool starred;
  final bool binned;

  /// The pages, rows or words, or a line saying nothing has read it yet.
  String get _contents {
    final units = cardUnits(entry, store);
    if (units != null) {
      return '${groupedNumber(units.count)} ${units.lower}';
    }
    return store == null ? 'Not read yet' : 'Nothing this reader can count';
  }

  String get _where => switch (entry.source) {
    DocSource.asset => 'Shipped with quire',
    DocSource.file => 'Brought in from the phone',
  };

  String get _reading {
    final held = store;
    if (held == null || !held.opened) return 'Not opened yet';
    final percent = (held.progress * 100).round();
    return '${held.positionLabel}, $percent per cent in';
  }

  String get _marks {
    final held = store;
    final count = held?.signatures.length ?? 0;
    if (count == 0) return 'None';
    return count == 1 ? '1 signature' : '$count signatures';
  }

  @override
  Widget build(BuildContext context) {
    final held = store;
    return DeskSheet(
      title: entry.title,
      note: 'What the desk knows about this document',
      children: [
        DeskSheetFact(name: 'File', value: entry.fileName),
        DeskSheetFact(name: 'Format', value: entry.format.mark),
        DeskSheetFact(name: 'Size', value: entry.sizeLabel),
        DeskSheetFact(name: 'Contents', value: _contents),
        if (held != null && held.wordCount > 0)
          DeskSheetFact(
            name: 'Reading time',
            value: '${held.minutes} minutes',
          ),
        const DeskSheetRule(),
        DeskSheetFact(name: 'Where it came from', value: _where),
        DeskSheetFact(name: 'Reading', value: _reading),
        DeskSheetFact(
          name: 'Times opened',
          value: '${held?.opens ?? 0}',
        ),
        DeskSheetFact(name: 'Signatures', value: _marks),
        DeskSheetFact(name: 'Starred', value: starred ? 'Yes' : 'No'),
        if (binned) const DeskSheetFact(name: 'Bin', value: 'Waiting in it'),
      ],
    );
  }
}
