import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../helpers/tear_path.dart';
import '../../painting/tear_painter.dart';
import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The size of the folded mark a designed state stands under.
const kFoldedMarkWidth = 64.0;
const kFoldedMarkHeight = 82.0;

/// How far in the folded mark's own corner turns, at this size.
const kFoldedMarkFold = 19.0;

/// The column a designed state's explanation is set in.
const kStateMeasure = 280.0;

/// The pill under it.
const kStateButtonWidth = 168.0;
const kStateButtonHeight = 44.0;

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

/// The app's own folded mark, drawn as an outline rather than filled, at the
/// head of every state that is not a page.
///
/// The fold is the app's whole vocabulary, so the places it says something is
/// not ordinary are the places it is drawn hollow.
class FoldedMark extends StatelessWidget {
  const FoldedMark({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: kFoldedMarkWidth,
    height: kFoldedMarkHeight,
    child: CustomPaint(painter: _FoldedMarkPainter()),
  );
}

class _FoldedMarkPainter extends CustomPainter {
  const _FoldedMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // The mark is a drawing, not a rule between two surfaces, so it is drawn
    // in a glyph colour. At rule value on this sheet it would be a smudge.
    final stroke = Paint()
      ..color = AppColors.inkFaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final body = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - kFoldedMarkFold)
      ..lineTo(size.width - kFoldedMarkFold, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(body, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height - kFoldedMarkFold)
        ..lineTo(size.width - kFoldedMarkFold, size.height - kFoldedMarkFold)
        ..lineTo(size.width - kFoldedMarkFold, size.height),
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
          Positioned.fill(
            child: CustomPaint(
              painter: _TornSheet(tear, edge: hairline(context)),
            ),
          ),
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
                  width: kStateMeasure,
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
                        color: AppColors.accentBright,
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

/// The torn sheet itself, edged like every other sheet in the app.
///
/// [TearPainter] runs its own hairline along the tear, in [AppColors.damage],
/// because that edge is the damage. The three edges that did not tear get the
/// ordinary rule, so a ruined leaf is still recognisably the same stock as a
/// whole one.
class _TornSheet extends CustomPainter {
  const _TornSheet(this.tear, {required this.edge});

  final List<Offset> tear;

  /// One physical pixel at the view's device pixel ratio.
  final double edge;

  @override
  void paint(Canvas canvas, Size size) {
    TearPainter(tear: tear, edgeWidth: edge).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_TornSheet old) => old.tear != tear || old.edge != edge;
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
