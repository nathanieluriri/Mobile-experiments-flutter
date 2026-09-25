import 'dart:typed_data';
import 'dart:ui' as ui;

/// The widest a signature picture is ever decoded at.
///
/// A signature is a mark a few hundred points across on a page. A photograph
/// of one off a phone camera is four thousand pixels wide, and carrying that
/// around costs sixty megabytes of memory to draw something the size of a
/// stamp, and puts the same sixty megabytes into any PDF it is written to.
const kPictureMaxWidth = 1400;

/// Decodes [bytes] as a picture, no wider than [kPictureMaxWidth].
///
/// The descriptor is read before the pixels, so a small picture is decoded at
/// its own size rather than being blown up to the cap.
Future<ui.Image> decodePicture(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final wide = descriptor.width > kPictureMaxWidth;
  final codec = await descriptor.instantiateCodec(
    targetWidth: wide ? kPictureMaxWidth : null,
  );
  final frame = await codec.getNextFrame();
  descriptor.dispose();
  return frame.image;
}

/// One picture's pixels, straightened out into the two planes a PDF wants:
/// colour and, separately, how opaque each of those pixels is.
class PicturePlanes {
  const PicturePlanes({
    required this.width,
    required this.height,
    required this.rgb,
    required this.alpha,
    required this.opaque,
  });

  final int width;
  final int height;

  /// Three bytes a pixel, row by row from the top.
  final Uint8List rgb;

  /// One byte a pixel, in the same order.
  final Uint8List alpha;

  /// True when every pixel is fully opaque, which is a picture that needs no
  /// mask written for it at all.
  final bool opaque;
}

/// Reads [image] into [PicturePlanes].
///
/// Flutter hands over premultiplied RGBA, so a pixel that is half transparent
/// arrives with its colour already halved. Undoing that matters here: a PDF
/// keeps the two apart, and writing premultiplied colour beside a mask paints
/// the mark twice as pale as it was.
Future<PicturePlanes?> picturePlanes(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;
  final pixels = data.buffer.asUint8List();
  final count = image.width * image.height;
  final rgb = Uint8List(count * 3);
  final alpha = Uint8List(count);
  var opaque = true;
  for (var i = 0; i < count; i++) {
    final a = pixels[i * 4 + 3];
    alpha[i] = a;
    if (a != 255) opaque = false;
    if (a == 0) {
      // Nothing was drawn here, so the colour under the mask is arbitrary.
      // White keeps a viewer that ignores the mask from printing a black box.
      rgb[i * 3] = 255;
      rgb[i * 3 + 1] = 255;
      rgb[i * 3 + 2] = 255;
      continue;
    }
    for (var c = 0; c < 3; c++) {
      final value = a == 255
          ? pixels[i * 4 + c]
          : (pixels[i * 4 + c] * 255 / a).round().clamp(0, 255);
      rgb[i * 3 + c] = value;
    }
  }
  return PicturePlanes(
    width: image.width,
    height: image.height,
    rgb: rgb,
    alpha: alpha,
    opaque: opaque,
  );
}
