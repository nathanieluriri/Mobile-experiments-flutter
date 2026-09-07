import 'dart:ui';

/// One card in the marquee.
class MarqueeItem {
  const MarqueeItem({
    required this.id,
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.tilt,
  });

  final String id;

  /// Card title. Newlines are deliberate: every name is laid out over at most
  /// two lines and the break points are chosen per name.
  final String name;

  final Color backgroundColor;
  final Color textColor;

  /// Degrees of the card's own lean, on top of the lean the arc gives it.
  final double tilt;

  /// Picture shipped with the app for this item.
  String get imageAsset => 'assets/images/$id.jpg';
}
