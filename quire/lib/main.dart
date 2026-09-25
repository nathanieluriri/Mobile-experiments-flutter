import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'arrival/arrival_handoff.dart';
import 'services/licences.dart';

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

void main(List<String> args) {
  // First, so that anything the three lines below raise has somewhere to go.
  installFailureHandlers();
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(kSystemBars);
  runApp(App(splashHandedOver: args.contains(kArrivalHandsOver)));
}
