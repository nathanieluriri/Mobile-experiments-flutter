import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../painting/signature_painter.dart';
import '../../services/picture.dart';
import '../../services/recent_signatures.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import 'sign_pad.dart';

/// The two small buttons under the pad.
const kSignToolSize = 34.0;
const kSignToolTop = 436.0;
const kSignToolLeft = 20.0;
const kSignToolGap = 42.0;
const kSignToolIcon = 18.0;

/// How faint a tool is with nothing to act on.
const kSignToolDisabled = 0.3;

/// The pill that takes the signature to the page.
const kCommitPillTop = 762.0;
const kCommitPillHeight = 54.0;

/// How faint the pill is before there is any ink.
const kCommitPillDead = 0.35;

/// Where the hint sits under the pad.
const kSignHintTop = 404.0;

/// The picture the reader chose, laid out on the pad in place of ink.
const kPicturePadInset = 16.0;

/// The glyph inside the back pill.
const kSignBackIcon = 20.0;

/// The strip of signatures used before, under the tools.
const kRecentLabelTop = 494.0;
const kRecentStripTop = 518.0;
const kRecentTileWidth = 128.0;
const kRecentTileHeight = 72.0;
const kRecentTileGap = 10.0;
const kRecentTileRadius = 10.0;
const kRecentTileInset = 10.0;

/// The signature pad: one sheet, one line to sign above, and one way off it.
///
/// It is paper on the desk like every other surface in the app. A dark pad
/// would be the only screen in quire that is not, and a signature is not a
/// different kind of act from reading, it is the last one.
class SignScreen extends StatefulWidget {
  const SignScreen({
    super.key,
    this.pad,
    this.onCommit,
    this.onBack,
    this.recent = const <SavedSignature>[],
    this.onForget,
  });

  /// Signatures used before, newest first, offered so a name does not have
  /// to be drawn again every time it is needed.
  final List<SavedSignature> recent;

  /// Takes one of [recent] off the strip.
  final ValueChanged<SavedSignature>? onForget;

  /// The ink. One is made here when the caller does not bring its own.
  final SignPadController? pad;

  /// Called with the finished signature when the pill is pressed.
  final ValueChanged<SignatureMark>? onCommit;

  final VoidCallback? onBack;

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen>
    with SingleTickerProviderStateMixin {
  SignPadController? _own;
  SignPadController get _pad => widget.pad ?? (_own ??= SignPadController());

  /// A mark the reader brought in or picked from the recent ones instead of
  /// drawing one, if they did.
  SignatureMark? _picture;

  /// Which recent signature [_picture] is, when it is one.
  SavedSignature? _recent;

  /// True while the phone's picker is up, so a second tap does not open a
  /// second one over it.
  bool _picking = false;

  /// The pill waking up. It runs on the first stroke and never runs back, so
  /// undoing to nothing leaves the pill lit but dead rather than blinking.
  late final AnimationController _live = AnimationController(
    vsync: this,
    duration: kLift,
  );

  @override
  void initState() {
    super.initState();
    _pad.addListener(_onInk);
  }

  @override
  void dispose() {
    _pad.removeListener(_onInk);
    _live.dispose();
    _own?.dispose();
    super.dispose();
  }

  /// Whether the pill and the two tools were alive at the last build.
  bool _hadInk = false;

  /// Only the arrival or the loss of ink changes this screen. Every other
  /// notification is the pad redrawing a stroke, which the pad does itself.
  void _onInk() {
    if (!_pad.isEmpty && _live.status == AnimationStatus.dismissed) {
      _live.forward();
    }
    if (_pad.isEmpty == !_hadInk) return;
    _hadInk = !_pad.isEmpty;
    setState(() {});
  }

  void _commit() {
    final picture = _picture;
    if (picture != null) {
      widget.onCommit?.call(picture);
      return;
    }
    if (_pad.isEmpty) return;
    widget.onCommit?.call(_pad.mark);
  }

  /// Takes a picture of a signature off the phone in place of a drawn one.
  ///
  /// A photograph of a signature on paper is a signature, and it is usually a
  /// better one than a fingertip can make. What comes back is decoded once,
  /// no wider than a page needs, and shown on the pad where the ink would
  /// have been, so the same button places it.
  Future<void> _choosePicture() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      final image = await decodePicture(bytes);
      if (!mounted) return;
      _pad.clear();
      setState(() {
        _picture = SignatureMark.picture(image, bytes);
        _recent = null;
      });
      if (_live.status == AnimationStatus.dismissed) _live.forward();
    } on Object {
      // A file the phone offered and the engine cannot read. There is nothing
      // to say about it that is more use than the pad staying as it was.
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Puts the picture away, which puts the pad back.
  void _clearPicture() {
    setState(() {
      _picture = null;
      _recent = null;
    });
  }

  /// Puts a signature used before on the pad, ready to place. Picking the one
  /// already there puts it away again.
  void _pickRecent(SavedSignature signature) {
    if (_recent == signature) {
      _clearPicture();
      return;
    }
    _pad.clear();
    setState(() {
      _picture = markOf(signature);
      _recent = signature;
    });
    if (_live.status == AnimationStatus.dismissed) _live.forward();
  }

  void _forgetRecent(SavedSignature signature) {
    if (_recent == signature) _clearPicture();
    widget.onForget?.call(signature);
  }

  /// The recent signatures that can be drawn now. A picture read back from
  /// disk waits until it has been decoded.
  List<SavedSignature> get _shown => <SavedSignature>[
        for (final signature in widget.recent)
          if (!signature.isPicture || signature.picture != null) signature,
      ];

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    final hasInk = picture != null || !_pad.isEmpty;
    return ColoredBox(
      color: AppColors.ground,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: kScreenPadding,
            top: kHeadBandTop + (kHeadBandHeight - kHeaderButtonSize) / 2,
            child: _BackPill(onTap: widget.onBack),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: kHeadBandTop,
            height: kHeadBandHeight,
            child: Center(
              child: Text(
                'Signature',
                style: AppText.title.copyWith(color: AppColors.ink),
              ),
            ),
          ),
          Positioned(
            left: kPadLeft,
            top: kPadTop,
            child: picture == null
                ? SignPad(controller: _pad)
                : _PicturePad(mark: picture),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: kSignHintTop,
            child: Center(
              child: Text(
                switch ((picture, _recent)) {
                  (null, _) =>
                    'Sign above the line, or bring a picture of your mark.',
                  (_, null) => 'This picture will be set into the page.',
                  _ => 'This signature will be set into the page.',
                },
                style: AppText.hint.copyWith(color: AppColors.inkFaint),
              ),
            ),
          ),
          Positioned(
            left: kSignToolLeft,
            top: kSignToolTop,
            child: _Tool(
              icon: LucideIcons.undo2,
              label: 'Undo the last stroke',
              enabled: picture == null && !_pad.isEmpty,
              onTap: _pad.undo,
            ),
          ),
          Positioned(
            left: kSignToolLeft + kSignToolGap,
            top: kSignToolTop,
            child: _Tool(
              icon: LucideIcons.trash2,
              label: switch ((picture, _recent)) {
                (null, _) => 'Clear the pad',
                (_, null) => 'Put the picture away',
                _ => 'Put the signature away',
              },
              enabled: hasInk,
              onTap: picture == null ? _pad.clear : _clearPicture,
            ),
          ),
          Positioned(
            left: kSignToolLeft + kSignToolGap * 2,
            top: kSignToolTop,
            child: _Tool(
              icon: LucideIcons.image,
              label: 'Use a picture of your signature',
              enabled: !_picking,
              onTap: _choosePicture,
            ),
          ),
          if (_shown.isNotEmpty) ...<Widget>[
            Positioned(
              left: kSignToolLeft,
              top: kRecentLabelTop,
              child: Text(
                'RECENT SIGNATURES',
                style: AppText.micro.copyWith(color: AppColors.inkFaint),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: kRecentStripTop,
              height: kRecentTileHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: kSignToolLeft),
                itemCount: _shown.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: kRecentTileGap),
                itemBuilder: (context, index) {
                  final signature = _shown[index];
                  return _RecentTile(
                    mark: markOf(signature),
                    chosen: _recent == signature,
                    label: 'Use recent signature ${index + 1}',
                    onTap: () => _pickRecent(signature),
                    onLongPress: () => _forgetRecent(signature),
                  );
                },
              ),
            ),
          ],
          Positioned(
            left: kScreenPadding,
            top: kCommitPillTop,
            width: kPadWidth,
            height: kCommitPillHeight,
            child: AnimatedBuilder(
              animation: _live,
              builder: (context, child) => Opacity(
                opacity:
                    kCommitPillDead +
                    (1 - kCommitPillDead) * easeOutQuad.transform(_live.value),
                child: child,
              ),
              child: PaperPress(
                onTap: _commit,
                enabled: hasInk,
                semanticLabel: 'Place the signature on the page',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(kPillRadius),
                  ),
                  child: Center(
                    child: Text(
                      'Place on page',
                      style: AppText.label.copyWith(color: AppColors.onAccent),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [signature] as a mark the pad and the page can draw.
SignatureMark markOf(SavedSignature signature) => SignatureMark(
      signature.outlines,
      signature.bounds,
      picture: signature.picture,
      encoded: signature.encoded,
    );

/// [mark] as a signature to keep.
SavedSignature savedOf(SignatureMark mark) => SavedSignature(
      outlines: mark.outlines,
      bounds: mark.bounds,
      encoded: mark.encoded,
      picture: mark.picture,
    );

/// One signature used before, on a slip of paper the size of a stamp.
///
/// A long press takes it off the strip, which is the one thing a kept
/// signature can have done to it besides being used.
class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.mark,
    required this.chosen,
    required this.label,
    required this.onTap,
    required this.onLongPress,
  });

  final SignatureMark mark;
  final bool chosen;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: label,
      washRadius: kRecentTileRadius,
      child: Container(
        width: kRecentTileWidth,
        height: kRecentTileHeight,
        decoration: BoxDecoration(
          color: AppColors.page,
          borderRadius: BorderRadius.circular(kRecentTileRadius),
          border: Border.all(
            color: chosen ? AppColors.accentBright : AppColors.hairline,
            width: chosen ? 2 : kHairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(kRecentTileInset),
          child: CustomPaint(painter: _PicturePainter(mark)),
        ),
      ),
    );
  }
}

/// The one way off this screen, shaped exactly like the reader's.
class _BackPill extends StatelessWidget {
  const _BackPill({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      semanticLabel: 'Back to the document',
      child: Container(
        width: kHeaderButtonSize,
        height: kHeaderButtonSize,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(kHeaderButtonRadius),
          border: AppEdges.all(context),
        ),
        child: const Center(
          child: Icon(
            LucideIcons.cornerUpLeft,
            size: kSignBackIcon,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// Undo and clear: the whole of the pad's editing vocabulary, because there is
/// no colour to pick and no thickness to set.
class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : kSignToolDisabled,
      child: PaperPress(
        onTap: onTap,
        enabled: enabled,
        semanticLabel: label,
        child: SizedBox(
          width: kSignToolSize,
          height: kSignToolSize,
          child: Center(
            child: Icon(
              icon,
              size: kSignToolIcon,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

/// The pad with a picture on it instead of ink.
///
/// The same rectangle, the same paper, so the screen does not rearrange
/// itself around which kind of mark somebody chose. The picture sits inside
/// it whole, at its own proportions, because a signature stretched to fit a
/// box is not that person's signature any more.
class _PicturePad extends StatelessWidget {
  const _PicturePad({required this.mark});

  final SignatureMark mark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kPadWidth,
      height: kPadHeight,
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(kPadRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(kPicturePadInset),
        child: CustomPaint(painter: _PicturePainter(mark)),
      ),
    );
  }
}

class _PicturePainter extends CustomPainter {
  const _PicturePainter(this.mark);

  final SignatureMark mark;

  @override
  void paint(Canvas canvas, Size size) {
    final aspect = mark.aspect;
    var width = size.width;
    var height = width * aspect;
    if (height > size.height) {
      height = size.height;
      width = aspect == 0 ? size.width : height / aspect;
    }
    mark.paintInto(
      canvas,
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: width,
        height: height,
      ),
    );
  }

  @override
  bool shouldRepaint(_PicturePainter old) => old.mark != mark;
}
