import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

/// The bars over a dark app that runs from edge to edge, as the splash does.
const kSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

void main() {
  // First, so that anything the three lines below raise has somewhere to go.
  installFailureHandlers();
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(kSystemBars);
  runApp(const App());
}
