import 'dart:ui' show Color;

/// One audiobook, playlist or now playing track.
class Story {
  const Story({
    required this.id,
    required this.title,
    required this.studio,
    required this.seed,
    required this.tint,
  });

  final String id;
  final String title;
  final String studio;

  /// Names the bundled picture, `assets/images/<seed>.jpg`.
  final String seed;

  /// Card colour, and the placeholder behind the picture.
  final Color tint;

  String get artwork => 'assets/images/$seed.jpg';
}
