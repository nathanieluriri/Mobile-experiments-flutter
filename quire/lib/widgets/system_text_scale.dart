import 'package:flutter/widgets.dart';

/// The most the phone's text size setting enlarges the app's own words.
const kMaxChromeTextScale = 1.3;

/// The phone's text size setting as the phone gave it, before the app's
/// chrome clamped it, for text that reflows and so can honour all of it.
class SystemTextScale extends InheritedWidget {
  const SystemTextScale({
    super.key,
    required this.scaler,
    required super.child,
  });

  final TextScaler scaler;

  /// The setting above [context], or the one its [MediaQuery] carries where
  /// nothing clamped it.
  static TextScaler of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SystemTextScale>()?.scaler ??
      MediaQuery.textScalerOf(context);

  @override
  bool updateShouldNotify(SystemTextScale old) => old.scaler != scaler;
}
