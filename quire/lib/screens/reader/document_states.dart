import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../helpers/tear_path.dart';
import '../../painting/tear_painter.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/shadows.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The size of the folded mark on the locked sheet.
const kLockedMarkWidth = 64.0;
const kLockedMarkHeight = 82.0;

/// How far in the folded mark's own corner turns, at this size.
const kLockedMarkFold = 19.0;

/// The column the locked sheet's explanation is set in.
const kLockedMeasure = 280.0;

/// The pill under it.
const kLockedButtonWidth = 168.0;
const kLockedButtonHeight = 44.0;

/// How far above the tear the damaged sheet says what happened.
const kDamageTextAbove = 40.0;

/// One honest line about why a document would not open.
///
/// Exactly two exception types escape the loader: a zip that will not open,
/// and a valid package with the wrong payload inside it. Each gets a sentence
/// in the document's own terms, because a reader who is told what happened to
/// their file can decide what to do about it, while one who is told `Error`
/// can only try again.
String damageReasonFor(Object? error) {
  if (error == null) return 'The file ends before its page table.';
  if (error is FormatException) {
    return 'The file is a package, but not the one its name promises.';
  }
  return 'The file ends before its table of contents.';
}

/// Whether a document's raw bytes decode as text.
///
/// It is what decides whether a damaged sheet can offer to open the file as
/// plain text: a truncated CSV or Markdown file is still readable, while a
/// half written zip is not, and offering the same button for both would be a
/// promise the app cannot keep.
bool decodesAsText(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  try {
    utf8.decode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

/// The sheet a locked document shows.
///
/// It is not a dialog and not an alert. A file that was saved with a password
/// is a real, ordinary thing to run into, so it gets a designed sheet that
/// says so and offers the one move that makes sense.
class LockedSheet extends StatelessWidget {
  const LockedSheet({super.key, this.onLeave});

  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kSheetWidth,
      height: kSheetHeight,
      decoration: BoxDecoration(
        color: AppColors.leaf,
        borderRadius: kPeelableCorner,
        boxShadow: AppShadows.leafRest(),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: kLockedMarkWidth,
              height: kLockedMarkHeight,
              child: CustomPaint(painter: _FoldedMarkPainter()),
            ),
            const SizedBox(height: kSpace20),
            Text(
              'This file is locked.',
              style: AppText.title.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: kSpace8),
            SizedBox(
              width: kLockedMeasure,
              child: Text(
                'It was saved with a password. quire cannot open it.',
                textAlign: TextAlign.center,
                style: AppText.bodyTight.copyWith(color: AppColors.inkSoft),
              ),
            ),
            const SizedBox(height: kSpace20),
            PaperPress(
              onTap: onLeave,
              shadow: false,
              borderRadius: BorderRadius.circular(kPillRadius),
              semanticLabel: 'Back to the desk',
              child: Container(
                width: kLockedButtonWidth,
                height: kLockedButtonHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kPillRadius),
                  border: Border.all(color: AppColors.rule),
                ),
                child: Center(
                  child: Text(
                    'Back to the desk',
                    style: AppText.label.copyWith(color: AppColors.ink),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's own folded mark, drawn as an outline rather than filled.
///
/// The fold is the app's whole vocabulary, so the one place it says something
/// is wrong is also the one place it is drawn hollow.
class _FoldedMarkPainter extends CustomPainter {
  const _FoldedMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = AppColors.rule
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final body = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - kLockedMarkFold)
      ..lineTo(size.width - kLockedMarkFold, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(body, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height - kLockedMarkFold)
        ..lineTo(size.width - kLockedMarkFold, size.height - kLockedMarkFold)
        ..lineTo(size.width - kLockedMarkFold, size.height),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_FoldedMarkPainter old) => false;
}

/// The sheet a document that will not parse shows: a piece of paper that has
/// actually been torn, with the desk showing through the loss.
///
/// The reason is stated in one honest line. A reader who is told what happened
/// to their file can decide what to do about it; one who is told `Error` can
/// only try again.
class DamagedSheet extends StatelessWidget {
  DamagedSheet({
    super.key,
    this.reason = 'The file ends before its page table.',
    this.onLeave,
    this.onOpenAsText,
  }) : tear = tearPolyline(kSheetWidth, kSheetHeight * kTearFraction);

  /// One line, in the document's own terms, saying what went wrong.
  final String reason;

  final VoidCallback? onLeave;

  /// Offered only when the raw bytes decode as text.
  final VoidCallback? onOpenAsText;

  /// The ragged edge, built once with the sheet and never per frame.
  final List<Offset> tear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kSheetWidth,
      height: kSheetHeight,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TornSheet(tear))),
          Positioned(
            left: 0,
            right: 0,
            bottom: kSheetHeight * (1 - kTearFraction) + kDamageTextAbove,
            child: Column(
              children: [
                Text(
                  'This leaf is damaged.',
                  style: AppText.title.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: kSpace8),
                SizedBox(
                  width: kLockedMeasure,
                  child: Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: AppText.docMeta.copyWith(color: AppColors.inkSoft),
                  ),
                ),
                const SizedBox(height: kSpace20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TextButton(
                      label: 'Back to the desk',
                      color: AppColors.ink,
                      onTap: onLeave,
                    ),
                    if (onOpenAsText != null) const SizedBox(width: kSpace8),
                    if (onOpenAsText != null)
                      _TextButton(
                        label: 'Open as plain text',
                        color: AppColors.thread,
                        onTap: onOpenAsText,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The torn sheet itself, with the contact shadow a whole sheet would cast.
///
/// The shadow is drawn from the tear path rather than from a rectangle, so the
/// missing part of the sheet is missing from its shadow too.
class _TornSheet extends CustomPainter {
  const _TornSheet(this.tear);

  final List<Offset> tear;

  @override
  void paint(Canvas canvas, Size size) {
    final body = tornSheetPath(size.width, tear);
    canvas.save();
    canvas.translate(0, 3);
    canvas.drawPath(
      body,
      Paint()
        ..color = AppColors.shadowInk.withValues(alpha: 0.08)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          blurForShadowRadius(10),
        ),
    );
    canvas.restore();
    TearPainter(tear: tear).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_TornSheet old) => old.tear != tear;
}

/// A word that acts, with nothing drawn around it.
class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      shadow: false,
      borderRadius: BorderRadius.circular(kChipRadius),
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpace12,
          vertical: kSpace8,
        ),
        child: Text(label, style: AppText.label.copyWith(color: color)),
      ),
    );
  }
}
