import 'package:flutter/foundation.dart';

/// Scroll distance below which the dock always shows its labels.
const _armAt = 28.0;

/// Scroll travel in one direction that flips the dock.
const _directionThreshold = 8.0;

/// Latches the dock between its labelled and compact shapes as a list scrolls.
///
/// Scrolling down past the arming distance shrinks it, scrolling back up grows
/// it again, and every flip re-anchors so the next change needs a fresh push.
class TabBarController extends ChangeNotifier {
  bool _compact = false;
  double _anchor = 0;

  /// Whether the dock is showing icons only.
  bool get compact => _compact;

  /// Grows the dock, which every tab press does.
  void expand() => _set(false);

  /// Feeds a scroll position in, clamped to the list's own range.
  void handleScroll(double offset, double maxOffset) {
    final y = clampDouble(offset, 0, maxOffset < 0 ? 0 : maxOffset);
    if (y <= _armAt) {
      _anchor = y;
      _set(false);
      return;
    }
    final dy = y - _anchor;
    if (dy > _directionThreshold) {
      _anchor = y;
      _set(true);
    } else if (dy < -_directionThreshold) {
      _anchor = y;
      _set(false);
    }
  }

  void _set(bool next) {
    if (next == _compact) return;
    _compact = next;
    notifyListeners();
  }
}
