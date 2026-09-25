import 'package:flutter/widgets.dart';

import 'player_controller.dart';

/// Hands the one [PlayerController] to every screen under it.
class PlayerScope extends InheritedNotifier<PlayerController> {
  const PlayerScope({
    super.key,
    required PlayerController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Reads the controller and rebuilds when the transport changes.
  static PlayerController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerScope>()!.notifier!;

  /// Reads the controller without subscribing, for use inside callbacks.
  static PlayerController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerScope>()!.notifier!;
}
