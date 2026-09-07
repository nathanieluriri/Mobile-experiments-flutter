import 'dart:ui';

/// One sticky note. A note carries either a body or a checklist, never both in
/// the shipped fixtures, but the shape allows either.
class Note {
  const Note({
    required this.id,
    required this.color,
    required this.title,
    this.body,
    this.checklist,
    this.meta,
    this.tags = const [],
    this.date,
  });

  final String id;
  final Color color;
  final String title;
  final String? body;
  final List<String>? checklist;
  final String? meta;
  final List<String> tags;
  final String? date;
}
