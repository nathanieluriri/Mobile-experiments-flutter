import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';
import '../../services/revisions.dart';
import '../desk/desk_sheet.dart';

const _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `25 Sep, 14:05`.
String revisionWhen(DateTime at) {
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]}, ${two(t.hour)}:${two(t.minute)}';
}

/// `412 KB`.
String revisionSize(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// What was picked on the list.
sealed class RevisionChoice {
  const RevisionChoice();
}

class PickedRevision extends RevisionChoice {
  const PickedRevision(this.number);
  final int number;
}

class ForgetOthers extends RevisionChoice {
  const ForgetOthers();
}

/// Every version of a document: the original it arrived as, and each save
/// since, newest first, with the one being read marked.
class RevisionsSheet extends StatelessWidget {
  const RevisionsSheet({super.key, required this.history});

  final History history;

  @override
  Widget build(BuildContext context) {
    final newest = history.revisions.reversed.toList();
    return DeskSheet(
      title: 'Revisions',
      note: history.revisions.isEmpty
          ? 'Nothing has been saved yet. The original is always kept.'
          : 'Every save is kept here. The original is always kept.',
      children: <Widget>[
        for (final r in newest)
          DeskSheetRow(
            label: r.number == history.current
                ? 'Revision ${r.number}, being read'
                : 'Revision ${r.number}',
            icon: r.number == history.current
                ? LucideIcons.bookOpen
                : LucideIcons.history,
            note: <String>[
              revisionWhen(r.created),
              revisionSize(r.size),
              if (r.note.isNotEmpty) r.note,
            ].join(' · '),
            onTap: () => Navigator.of(context).pop(PickedRevision(r.number)),
          ),
        DeskSheetRow(
          label: history.current == 0
              ? 'The original, being read'
              : 'The original',
          icon: history.current == 0 ? LucideIcons.bookOpen : LucideIcons.fileText,
          note: 'As it arrived. It cannot be deleted from here.',
          onTap: () => Navigator.of(context).pop(const PickedRevision(0)),
        ),
        if (history.revisions.length > 1 ||
            (history.revisions.length == 1 && history.current == 0))
          DeskSheetRow(
            label: 'Forget the others',
            icon: LucideIcons.trash2,
            destructive: true,
            note: 'Keeps the one being read and the original.',
            onTap: () => Navigator.of(context).pop(const ForgetOthers()),
          ),
      ],
    );
  }
}

/// What can be done with one revision.
enum RevisionAction { read, delete }

class RevisionActionsSheet extends StatelessWidget {
  const RevisionActionsSheet({
    super.key,
    required this.number,
    required this.current,
  });

  final int number;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return DeskSheet(
      title: number == 0 ? 'The original' : 'Revision $number',
      children: <Widget>[
        DeskSheetRow(
          label: 'Read this one',
          icon: LucideIcons.bookOpen,
          enabled: !current,
          note: current
              ? 'It is the one being read.'
              : 'It is saved again as the newest, so nothing is lost.',
          onTap: () => Navigator.of(context).pop(RevisionAction.read),
        ),
        if (number != 0)
          DeskSheetRow(
            label: 'Delete this revision',
            icon: LucideIcons.trash2,
            destructive: true,
            onTap: () => Navigator.of(context).pop(RevisionAction.delete),
          ),
      ],
    );
  }
}

/// Asks once before something that cannot be taken back.
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.note,
    required this.action,
  });

  final String title;
  final String note;
  final String action;

  @override
  Widget build(BuildContext context) {
    return DeskSheet(
      title: title,
      note: note,
      children: <Widget>[
        DeskSheetRow(
          label: action,
          icon: LucideIcons.trash2,
          destructive: true,
          onTap: () => Navigator.of(context).pop(true),
        ),
        DeskSheetRow(
          label: 'Keep it',
          icon: LucideIcons.x,
          onTap: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

/// The whole round: the list, what to do with the one picked, and the one
/// question asked before anything is deleted. Returns a line for the band,
/// or null when nothing changed.
Future<String?> showRevisions(
  BuildContext context,
  LibraryStore library,
  LibraryEntry entry,
) async {
  final history = await library.historyOf(entry);
  if (!context.mounted) return null;
  final choice = await showDeskSheet<RevisionChoice>(
    context,
    (context) => RevisionsSheet(history: history),
  );
  if (choice == null || !context.mounted) return null;
  switch (choice) {
    case ForgetOthers():
      final sure = await showDeskSheet<bool>(
        context,
        (context) => const ConfirmSheet(
          title: 'Forget the other revisions?',
          note: 'They are deleted from this phone and cannot be brought back. '
              'The one being read and the original stay.',
          action: 'Forget them',
        ),
      );
      if (sure != true) return null;
      await library.forgetRevisions(entry);
      return 'The other revisions are gone.';
    case PickedRevision(:final number):
      final action = await showDeskSheet<RevisionAction>(
        context,
        (context) => RevisionActionsSheet(
          number: number,
          current: number == history.current,
        ),
      );
      if (action == null || !context.mounted) return null;
      switch (action) {
        case RevisionAction.read:
          await library.restoreRevision(entry, number);
          return number == 0 ? 'Back to the original.' : 'Back to revision $number.';
        case RevisionAction.delete:
          final sure = await showDeskSheet<bool>(
            context,
            (context) => ConfirmSheet(
              title: 'Delete revision $number?',
              note: 'It is deleted from this phone and cannot be brought back.',
              action: 'Delete it',
            ),
          );
          if (sure != true) return null;
          await library.deleteRevision(entry, number);
          return 'Revision $number is gone.';
      }
  }
}
