/// Fixed measurements shared by the shell, the tab bar and the player sheet.
abstract final class Layout {
  static const tabBarHeight = 56.0;
  static const miniPlayerHeight = 76.0;
  static const screenTopPadding = 16.0;
  static const scrollBottomClearance = 32.0;
}

/// Playback is visual only; these numbers drive the bar and the labels.
abstract final class Playback {
  static const trackDurationSeconds = 180;
  static const skipIntervalSeconds = 15;
}
