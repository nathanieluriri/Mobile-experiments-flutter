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

  Note copyWith({
    Color? color,
    String? title,
    String? body,
    List<String>? checklist,
    String? meta,
    List<String>? tags,
    String? date,
  }) {
    return Note(
      id: id,
      color: color ?? this.color,
      title: title ?? this.title,
      body: body ?? this.body,
      checklist: checklist ?? this.checklist,
      meta: meta ?? this.meta,
      tags: tags ?? this.tags,
      date: date ?? this.date,
    );
  }

  /// Every word a search can match: the title, the body, the checklist items,
  /// the counter line and the tags, folded to lower case once.
  String get searchText => [
        title,
        ?body,
        ...?checklist,
        ?meta,
        ...tags,
      ].join(' ').toLowerCase();

  Map<String, Object?> toJson() => {
        'id': id,
        'color': color.toARGB32(),
        'title': title,
        if (body != null) 'body': body,
        if (checklist != null) 'checklist': checklist,
        if (meta != null) 'meta': meta,
        if (tags.isNotEmpty) 'tags': tags,
        if (date != null) 'date': date,
      };

  /// Reads a note back. Returns null for anything that is not a complete note,
  /// so one bad entry cannot take the whole list down with it.
  static Note? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final color = json['color'];
    final title = json['title'];
    if (id is! String || color is! int || title is! String) {
      return null;
    }
    return Note(
      id: id,
      color: Color(color),
      title: title,
      body: json['body'] is String ? json['body'] as String : null,
      checklist: _strings(json['checklist']),
      meta: json['meta'] is String ? json['meta'] as String : null,
      tags: _strings(json['tags']) ?? const [],
      date: json['date'] is String ? json['date'] as String : null,
    );
  }

  static List<String>? _strings(Object? value) {
    if (value is! List) {
      return null;
    }
    return value.whereType<String>().toList();
  }
}
