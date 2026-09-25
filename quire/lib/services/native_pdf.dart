import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

/// The channel the phone's own PDF renderer answers on: PdfRenderer on
/// Android, PDFKit on iOS.
const kNativePdfChannel = MethodChannel('ng.com.uriri.quire/pages');

/// The most pixels one page is rendered at. A page at four times the width of
/// a phone is already past what anybody reads, and every pixel is four bytes
/// held while the page is on screen.
const kNativePageMaxPixels = 4096 * 4096;

/// One document open in the phone's own PDF renderer.
///
/// quire's engine still reads every page: its text is what the search, the
/// back of the sheet, the find highlights and the signature's snapping are
/// built from. What the phone draws is only the picture of the page, set in
/// the file's own fonts rather than in the app's, which is the difference
/// between a page that looks like its print and one that reads like it.
///
/// Every failure here is quiet and total: a document the phone will not open,
/// a page it will not draw, or a phone with no renderer at all, as under
/// test, all leave quire drawing the page itself.
class NativePdf {
  NativePdf._(this._id, this.pageCount)
    : drawsMarks = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

  final int _id;

  /// Whether the phone draws a page's annotations with it. PDFKit does.
  /// Android's PdfRenderer never does, so there a mark saved into the file,
  /// words, ink, a highlight or a picture, is drawn by quire over the page.
  final bool drawsMarks;

  /// How many pages the phone found, which may disagree with quire's count on
  /// a damaged file. A page past it is drawn by quire.
  final int pageCount;

  bool _closed = false;

  /// Opens the file at [path], or [bytes] when there is no file, or null when
  /// the phone cannot. A file under a password is not opened here: the
  /// password is never kept, and the page is drawn by quire, which holds the
  /// key for as long as the document is open.
  static Future<NativePdf?> open({String? path, Uint8List? bytes}) async {
    if (path == null && bytes == null) return null;
    try {
      final opened = await kNativePdfChannel.invokeMapMethod<String, Object?>(
        'open',
        <String, Object?>{'path': ?path, if (path == null) 'bytes': bytes},
      );
      final id = opened?['id'];
      final pages = opened?['pages'];
      if (id is! int || pages is! int || pages <= 0) return null;
      return NativePdf._(id, pages);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Page [page] drawn [width] by [height] pixels on white, or null when the
  /// phone could not draw it.
  Future<ui.Image?> render(int page, int width, int height) async {
    if (_closed || page < 0 || page >= pageCount) return null;
    if (width <= 0 || height <= 0 || width * height > kNativePageMaxPixels) {
      return null;
    }
    final Map<String, Object?>? drawn;
    try {
      drawn = await kNativePdfChannel.invokeMapMethod<String, Object?>(
        'render',
        <String, Object?>{
          'id': _id,
          'page': page,
          'width': width,
          'height': height,
        },
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    final pixels = drawn?['pixels'];
    final w = drawn?['width'];
    final h = drawn?['height'];
    if (pixels is! Uint8List || w is! int || h is! int) return null;
    if (pixels.length != w * h * 4) return null;
    final image = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      image.complete,
    );
    return image.future;
  }

  /// Lets the phone drop the document. Safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await kNativePdfChannel.invokeMethod<void>('close', <String, Object?>{
        'id': _id,
      });
    } on MissingPluginException {
      // Nothing was open.
    } on PlatformException {
      // Already gone.
    }
  }
}
