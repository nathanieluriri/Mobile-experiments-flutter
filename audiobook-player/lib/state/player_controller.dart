import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

import '../data/now_playing.dart';
import '../models/story.dart';
import '../theme/layout.dart';
import '../theme/motion.dart';

/// The playback state the app opens on. The app itself opens at the start of
/// the track with the transport running; other values exist so a screenshot can
/// be taken of a track that is part way through.
class PlayerStart {
  const PlayerStart({this.positionSeconds = 0, this.isPlaying = true});

  final double positionSeconds;
  final bool isPlaying;
}

/// Now playing, the transport, and how far the sheet is open.
///
/// [sheetProgress] runs 0 at the mini player and 1 at the full sheet. It is
/// unbounded so the settle spring can overshoot the way it does on a phone.
class PlayerController extends ChangeNotifier {
  PlayerController({
    required TickerProvider vsync,
    PlayerStart start = const PlayerStart(),
  }) : sheetProgress = AnimationController.unbounded(vsync: vsync),
       playbackPosition = AnimationController(
         vsync: vsync,
         duration: const Duration(seconds: Playback.trackDurationSeconds),
         value: start.positionSeconds / Playback.trackDurationSeconds,
       ),
       _isPlaying = start.isPlaying {
    if (_isPlaying) {
      playbackPosition.forward();
    }
  }

  final AnimationController sheetProgress;

  /// 0 at the start of the track, 1 at its end.
  final AnimationController playbackPosition;

  final Story track = nowPlayingTrack;

  bool _isPlaying;
  bool get isPlaying => _isPlaying;

  double get positionSeconds =>
      playbackPosition.value * Playback.trackDurationSeconds;

  double _dragStartProgress = 0;

  void togglePlay() {
    _isPlaying = !_isPlaying;
    if (_isPlaying) {
      playbackPosition.forward();
    } else {
      playbackPosition.stop();
    }
    notifyListeners();
  }

  void expandSheet() => _settleTo(1);

  void collapseSheet() => _settleTo(0);

  /// Collapses or expands depending on which side of the middle the sheet is.
  void toggleSheet() =>
      sheetProgress.value > 0.5 ? collapseSheet() : expandSheet();

  void onDragStart() {
    sheetProgress.stop();
    _dragStartProgress = sheetProgress.value;
  }

  /// [translationY] is the whole distance travelled since the drag began, and
  /// [range] the drag it takes to open the sheet from shut.
  void onDragUpdate(double translationY, double range) {
    sheetProgress.value = (_dragStartProgress - translationY / range).clamp(
      0.0,
      1.0,
    );
  }

  void onDragEnd(double velocityY) {
    final shouldExpand =
        velocityY < -flickVelocity ||
        (velocityY < flickVelocity && sheetProgress.value > 0.5);
    _settleTo(shouldExpand ? 1 : 0);
  }

  void _settleTo(double target) {
    sheetProgress.animateWith(
      SpringSimulation(sheetSpring, sheetProgress.value, target, 0),
    );
  }

  @override
  void dispose() {
    sheetProgress.dispose();
    playbackPosition.dispose();
    super.dispose();
  }
}
