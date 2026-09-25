import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/library.dart';

/// The channel the platform hands documents over on.
const kIncomingChannel = 'ng.com.uriri.quire/incoming';

/// What the platform calls when a document arrives while the app is running.
const kIncomingOpened = 'opened';

/// What this asks the platform for when it starts.
const kIncomingInitial = 'getInitialFile';

/// What a document handed over from a notice starts with, to tell it from a
/// path to a copy in the cache.
const kDeviceOpenPrefix = 'quire-device:';

/// Why a document another app offered was not taken.
enum IncomingRefusal {
  /// The path came through but there is nothing at it. A share sheet can hand
  /// over a reference to something already deleted, and a content uri the
  /// platform copied out can fail to land.
  missing,

  /// A kind of file quire does not read. The manifest asks for seven of them,
  /// and a launcher will still occasionally send an eighth.
  unreadable;

  /// What the desk says about it, in the reader's terms rather than the
  /// platform's.
  String get line => switch (this) {
    IncomingRefusal.missing => 'That file is no longer there.',
    IncomingRefusal.unreadable => 'quire does not read that kind of file.',
  };
}

/// A document handed to quire by another app.
class IncomingDocument {
  const IncomingDocument({
    required this.path,
    required this.format,
    this.deviceName,
  });

  final String path;
  final DocFormat format;

  /// The document's name when it is one in a folder on the phone, opened
  /// from a notice that it had arrived. Such a document is read where it
  /// lies, not copied in.
  final String? deviceName;

  bool get onDevice => deviceName != null;

  /// The file's own name, which is what it goes onto the desk as.
  ///
  /// The platform side copies the file in behind a millisecond stamp, so two
  /// files with one name cannot overwrite each other on the way in. The stamp
  /// is how the copy is kept apart, not part of what the document is called.
  String get name {
    final named = deviceName;
    if (named != null) return named;
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    final file = cut < 0 ? path : path.substring(cut + 1);
    return file.replaceFirst(RegExp(r'^\d{10,}_'), '');
  }
}

/// Documents arriving from outside the app: a file manager, a mail client, a
/// share sheet.
///
/// Two ways in, and they are genuinely different. A cold start has the
/// document waiting before there is anything to show it on, so it has to be
/// asked for once the app is up. A warm open arrives at any moment, on top of
/// whatever the reader was already doing.
///
/// Everything the platform sends is checked here rather than trusted. A share
/// sheet can hand over a file that has already been deleted, and a launcher can
/// send a kind of file the manifest never asked for, and neither of those
/// should reach the parser.
class IncomingDocuments extends ChangeNotifier {
  IncomingDocuments({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kIncomingChannel);

  final MethodChannel _channel;

  /// The document waiting to be opened, if one is.
  IncomingDocument? _waiting;
  IncomingDocument? get waiting => _waiting;

  /// Why the last one was turned away, if it was.
  IncomingRefusal? _refused;
  IncomingRefusal? get refused => _refused;

  /// True once [boot] has asked the platform what it started with.
  bool _booted = false;
  bool get booted => _booted;

  /// Asks the platform for the document the app was started on, and starts
  /// listening for the ones that arrive later.
  ///
  /// A platform that does not answer is a platform with nothing to hand over,
  /// which is every platform this app has not been taught about and also the
  /// ordinary case of being opened from the launcher.
  Future<void> boot() async {
    _channel.setMethodCallHandler(_onCall);
    String? path;
    try {
      path = await _channel.invokeMethod<String>(kIncomingInitial);
    } on MissingPluginException {
      path = null;
    } on PlatformException {
      path = null;
    }
    _booted = true;
    if (path == null || path.isEmpty) {
      notifyListeners();
      return;
    }
    _offer(path);
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != kIncomingOpened) return null;
    final path = call.arguments;
    if (path is String && path.isNotEmpty) _offer(path);
    return null;
  }

  /// Takes the waiting document, and clears it.
  ///
  /// Handed over rather than read, because a document that stayed here after
  /// it had been opened would be opened again by the next thing that looked.
  IncomingDocument? take() {
    final held = _waiting;
    if (held == null) return null;
    _waiting = null;
    notifyListeners();
    return held;
  }

  /// Forgets the last refusal, once it has been said.
  void clearRefusal() {
    if (_refused == null) return;
    _refused = null;
    notifyListeners();
  }

  void _offer(String path) {
    if (path.startsWith(kDeviceOpenPrefix)) {
      _offerDevice(path.substring(kDeviceOpenPrefix.length));
      return;
    }
    final format = formatOfPath(path);
    if (format == null) {
      _waiting = null;
      _refused = IncomingRefusal.unreadable;
      notifyListeners();
      return;
    }
    if (!File(path).existsSync()) {
      _waiting = null;
      _refused = IncomingRefusal.missing;
      notifyListeners();
      return;
    }
    _waiting = IncomingDocument(path: path, format: format);
    _refused = null;
    notifyListeners();
  }

  /// A document in a folder on the phone, as `<uri>` then a new line then
  /// its name, which a notice hands over when it is tapped.
  void _offerDevice(String handed) {
    final cut = handed.indexOf('\n');
    final uri = cut < 0 ? handed : handed.substring(0, cut);
    final name = cut < 0 ? '' : handed.substring(cut + 1);
    final format = formatOfPath(name);
    if (format == null || !uri.startsWith('content://')) {
      _waiting = null;
      _refused = IncomingRefusal.unreadable;
      notifyListeners();
      return;
    }
    _waiting = IncomingDocument(path: uri, format: format, deviceName: name);
    _refused = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// The format [path] names, or null for one quire does not read.
///
/// The extension and nothing else. Sniffing the bytes would be a better
/// answer to what a file is, and it is the loader's answer: this only has to
/// decide whether the file is worth handing to the loader at all.
DocFormat? formatOfPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return null;
  final tail = path.substring(dot + 1).toLowerCase();
  // .doc, .xls and .ppt are not mapped on to their zipped successors: they
  // are compound files, and every one handed over would read as damaged.
  final wanted = tail == 'markdown' ? 'md' : tail;
  return DocFormat.forExtension(wanted);
}
