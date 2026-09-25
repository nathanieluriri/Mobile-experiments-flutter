import '../pdf/crypt.dart';
import '../pdf/display_list.dart';
import '../pdf/document.dart';

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

  /// The file is encrypted and nobody has supplied a password that opens it.
  /// The password sheet asks for one.
  needsPassword,

  /// The file is encrypted with a cipher this version does not decrypt. Its
  /// own sheet names the cipher and says so, and never says `locked`, because
  /// `locked` implies a password would help and here none would.
  unsupportedCipher,

  /// The parser threw. The torn sheet says so.
  damaged,
}

/// The share of a page that must be image before it counts as a scan.
const double kScanCoverage = 0.4;

/// Image encodings this reader can actually turn into pixels.
const Set<String> kDecodableImageEncodings = {'jpeg', 'raw-rgb', 'raw-gray'};

/// Which of the two protected rungs a [PdfLocked] belongs on.
///
/// The cipher is the whole question. One of these states asks for something
/// the reader can supply, the other says plainly that nothing they type will
/// help, and a reader who is offered a field for a file no field can open has
/// been sent to type a password for nothing.
RenderPlan planForLocked(PdfLocked locked) => locked.cipher == kCipherRc4
    ? RenderPlan.needsPassword
    : RenderPlan.unsupportedCipher;

/// Picks the rung for one page.
///
/// [locked] is tested before [threw] on purpose: a file nobody has the key to
/// usually fails to interpret as well, and asking for its password is true and
/// useful, while telling somebody their file is damaged is neither.
RenderPlan planFor(
  PageDisplayList? list, {
  PdfLocked? locked,
  required bool threw,
}) {
  if (locked != null) return planForLocked(locked);
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
