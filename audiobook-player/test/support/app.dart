import 'package:audiobook_player/app.dart';
import 'package:audiobook_player/state/player_controller.dart';
import 'package:flutter/widgets.dart';

/// Playback where the reference recording found it: 148 seconds into the
/// track, stopped. Screenshots use it so they line up with the recording.
const capturedPlayback = PlayerStart(positionSeconds: 148, isPlaying: false);

/// The app, opened on [initialTab] with [start] on the transport.
Widget bookApp({PlayerStart start = capturedPlayback, int initialTab = 0}) =>
    App(start: start, initialTab: initialTab);
