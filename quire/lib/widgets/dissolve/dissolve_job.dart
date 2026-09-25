import 'dart:ui' as ui;

import '../../constants/dissolve.dart';

/// One sheet coming apart, or one sheet being put back together.
class DissolveJob {
  const DissolveJob({
    required this.id,
    required this.image,
    required this.origin,
    required this.size,
    required this.reverse,
    required this.duration,
    this.motion = ParticleMotionSet.dust,
    this.onDone,
  });

  /// Distinguishes this job from another over the same sheet, and seeds its
  /// particles, so two runs never take the same paths.
  final int id;

  /// The snapshot the particles are cut from.
  final ui.Image image;

  /// Where the sheet sat when it was snapshotted, in overlay coordinates.
  final ui.Offset origin;

  /// The sheet's size in logical pixels.
  final ui.Size size;

  /// Whether the sheet is reassembling rather than coming apart.
  final bool reverse;

  /// How long this run takes.
  final Duration duration;

  /// Which physics the grains travel under.
  final ParticleMotionSet motion;

  /// Run once the run finishes, before the job is dropped.
  final void Function()? onDone;
}
