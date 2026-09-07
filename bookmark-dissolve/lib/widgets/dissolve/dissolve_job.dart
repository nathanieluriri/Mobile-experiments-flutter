import 'dart:ui' as ui;

/// One card coming apart, or one card being put back together.
class DissolveJob {
  const DissolveJob({
    required this.id,
    required this.image,
    required this.origin,
    required this.size,
    required this.reverse,
    this.onDone,
  });

  /// Distinguishes this job from another over the same card.
  final int id;

  /// The snapshot the particles are cut from.
  final ui.Image image;

  /// Where the card sat when it was snapshotted, in overlay coordinates.
  final ui.Offset origin;

  /// The card's size in logical pixels.
  final ui.Size size;

  /// Whether the card is reassembling rather than coming apart.
  final bool reverse;

  /// Run once the run finishes, before the job is dropped.
  final void Function()? onDone;
}
