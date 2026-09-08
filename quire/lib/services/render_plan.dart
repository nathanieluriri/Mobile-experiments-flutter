import '../pdf/display_list.dart';

/// How a page is going to be presented, decided before a pixel is painted.
///
/// The rung is chosen from the display list itself, so a scan, a locked file
/// and a damaged file are designed states rather than error handlers, and the
/// one thing that never happens is a blank white page presented as success.
enum RenderPlan {
  /// The default. Text, paths and images, one ordered pass.
  rich,

  /// An unsupported image encoding appeared but there is real text. Paint the
  /// text and the paths, and outline the image's rect with a label instead of
  /// leaving a hole the reader cannot account for.
  textOnly,

  /// No text and the page is mostly one decodable image. An honest scan.
  scan,

  /// No text and the page is mostly one image in an encoding this reader does
  /// not decode. The designed scan card says so.
  scanUnreadable,

  /// The trailer carries an encryption dictionary. The lock sheet says so.
  locked,

  /// The parser threw. The torn sheet says so.
  damaged,
}

/// The share of a page that must be image before it counts as a scan.
const double kScanCoverage = 0.4;

/// Image encodings this reader can actually turn into pixels.
const Set<String> kDecodableImageEncodings = {'jpeg', 'raw-rgb', 'raw-gray'};

/// Picks the rung for one page.
///
/// [encrypted] is tested before [threw] on purpose: an encrypted file usually
/// fails to interpret as well, and telling a reader their file is locked is
/// true and useful, while telling them it is damaged is neither.
RenderPlan planFor(
  PageDisplayList? list, {
  required bool encrypted,
  required bool threw,
}) {
  if (encrypted) return RenderPlan.locked;
  if (threw || list == null) return RenderPlan.damaged;

  final hasText = list.texts.isNotEmpty;
  if (!hasText && list.imageCoverage > kScanCoverage) {
    return _anyDecodable(list) ? RenderPlan.scan : RenderPlan.scanUnreadable;
  }
  if (hasText && _anyUndecodable(list)) return RenderPlan.textOnly;
  return RenderPlan.rich;
}

/// True when at least one image on the page can be decoded, which is what
/// separates a readable scan from a card that has to explain itself.
bool _anyDecodable(PageDisplayList list) {
  for (final image in list.images) {
    if (image.bytes != null &&
        kDecodableImageEncodings.contains(image.encoding)) {
      return true;
    }
  }
  return false;
}

bool _anyUndecodable(PageDisplayList list) {
  for (final image in list.images) {
    if (image.bytes == null ||
        !kDecodableImageEncodings.contains(image.encoding)) {
      return true;
    }
  }
  return false;
}
