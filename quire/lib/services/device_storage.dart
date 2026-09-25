import 'package:flutter/services.dart';

import '../data/library.dart';
import 'incoming_documents.dart' show formatOfPath;

/// The channel the phone's folders answer on.
const kDeviceStorageChannel = MethodChannel('ng.com.uriri.quire/storage');

/// A folder on the phone the reader handed to quire, which quire may read and
/// make folders in for as long as the grant lasts.
class AdoptedFolder {
  const AdoptedFolder({required this.tree, required this.name});

  /// The grant, as the phone names it. It is also the folder's identity.
  final String tree;

  /// What the phone calls the folder.
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{'tree': tree, 'name': name};

  static AdoptedFolder? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final tree = json['tree'];
    final name = json['name'];
    if (tree is! String || name is! String) return null;
    return AdoptedFolder(tree: tree, name: name);
  }

  @override
  bool operator ==(Object other) => other is AdoptedFolder && other.tree == tree;

  @override
  int get hashCode => tree.hashCode;
}

/// One thing inside an adopted folder: a folder or a document.
class DeviceItem {
  const DeviceItem({
    required this.tree,
    required this.document,
    required this.uri,
    required this.name,
    required this.folder,
    required this.size,
    required this.modified,
  });

  /// The adopted folder it was reached through.
  final String tree;

  /// Its id inside that folder, which is how its own contents are asked for.
  final String document;

  /// The address a document is read from.
  final String uri;
  final String name;
  final bool folder;
  final int size;

  /// Milliseconds since the epoch, or 0 when the phone does not say.
  final int modified;

  /// What quire would read it as, or null for a file it does not read.
  DocFormat? get format => folder ? null : formatOfPath(name);

  /// This document as the desk holds one: read in place from the phone.
  LibraryEntry get entry => LibraryEntry.onDevice(
        uri: uri,
        name: name,
        format: format!,
        bytes: size,
      );

  static DeviceItem? fromJson(String tree, Object? json) {
    if (json is! Map) return null;
    final document = json['document'];
    final uri = json['uri'];
    final name = json['name'];
    if (document is! String || uri is! String || name is! String) return null;
    return DeviceItem(
      tree: tree,
      document: document,
      uri: uri,
      name: name,
      folder: json['folder'] == true,
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: (json['modified'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What the phone said when a folder could not be read: the grant was taken
/// back, or the folder was deleted or moved.
class DeviceFolderGone implements Exception {
  const DeviceFolderGone();
}

/// The folders on the phone, through the platform.
///
/// Every answer from the phone is untrusted: a name, a size and an address
/// are read as data, and a document is read through the same loader as a
/// file shared in from anywhere else.
class DeviceStorage {
  const DeviceStorage([this._channel = kDeviceStorageChannel]);

  final MethodChannel _channel;

  /// Asks the reader to choose a folder. Null when they did not, or when the
  /// phone has no way to ask.
  Future<AdoptedFolder?> adopt() async {
    try {
      final picked = await _channel.invokeMapMethod<String, Object?>('adopt');
      return AdoptedFolder.fromJson(picked);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// True when the phone can hand folders over at all.
  Future<bool> get available async {
    try {
      await _channel.invokeListMethod<Object?>('granted');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return true;
    }
  }

  /// What is directly inside [folder] of [tree], its root when null. Throws
  /// [DeviceFolderGone] when it cannot be read any more.
  Future<List<DeviceItem>> list(String tree, {String? folder}) async {
    try {
      final rows = await _channel.invokeListMethod<Object?>('list', {
        'tree': tree,
        'document': ?folder,
      });
      final items = <DeviceItem>[
        for (final row in rows ?? const <Object?>[])
          ?DeviceItem.fromJson(tree, row),
      ];
      items.sort(_folderFirst);
      return items;
    } on PlatformException {
      throw const DeviceFolderGone();
    } on MissingPluginException {
      throw const DeviceFolderGone();
    }
  }

  /// Every document quire reads under [tree], down to [depth] folders deep
  /// and no more than [limit] of them, so a folder of a thousand
  /// photographs cannot hold the desk up.
  Future<List<DeviceItem>> documents(
    String tree, {
    int depth = 3,
    int limit = 500,
  }) async {
    final out = <DeviceItem>[];
    Future<void> walk(String? folder, int level) async {
      if (out.length >= limit) return;
      final items = await list(tree, folder: folder);
      for (final item in items) {
        if (out.length >= limit) return;
        if (item.folder) {
          if (level < depth) {
            try {
              await walk(item.document, level + 1);
            } on DeviceFolderGone {
              // A subfolder that cannot be read keeps nothing from the rest.
            }
          }
        } else if (item.format != null) {
          out.add(item);
        }
      }
    }

    await walk(null, 0);
    return out;
  }

  /// Makes a folder called [name] inside [folder] of [tree], on the phone.
  Future<DeviceItem?> makeFolder(
    String tree,
    String name, {
    String? folder,
  }) async {
    try {
      final made = await _channel.invokeMapMethod<String, Object?>(
        'makeFolder',
        {'tree': tree, 'name': name, 'document': ?folder},
      );
      return DeviceItem.fromJson(tree, made);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The bytes of the document at [uri].
  Future<Uint8List> read(String uri) async {
    final bytes = await _channel.invokeMethod<Uint8List>('read', {'uri': uri});
    if (bytes == null) throw const DeviceFolderGone();
    return bytes;
  }

  /// Gives the grant for [tree] back to the phone.
  Future<void> release(String tree) async {
    try {
      await _channel.invokeMethod<void>('release', {'tree': tree});
    } on PlatformException {
      // Already gone.
    } on MissingPluginException {
      // Nothing was held.
    }
  }
}

int _folderFirst(DeviceItem a, DeviceItem b) {
  if (a.folder != b.folder) return a.folder ? -1 : 1;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
