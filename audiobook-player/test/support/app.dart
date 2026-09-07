import 'package:audiobook_player/app.dart';
import 'package:audiobook_player/state/player_controller.dart';
import 'package:flutter/widgets.dart';

/// The transport fixture the screenshots are captured at: 148 seconds into
/// the track, stopped.
const capturedPlayback = PlayerStart(positionSeconds: 148, isPlaying: false);

/// The app, opened on [initialTab] with [start] on the transport.
Widget bookApp({PlayerStart start = capturedPlayback, int initialTab = 0}) =>
    App(start: start, initialTab: initialTab);
