import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../painting/signature_painter.dart';
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

/// The glyph inside the back pill.
const kSignBackIcon = 20.0;

/// The signature pad: one sheet, one line to sign above, and one way off it.
///
/// It is paper on the desk like every other surface in the app. A dark pad
/// would be the only screen in quire that is not, and a signature is not a
/// different kind of act from reading, it is the last one.
class SignScreen extends StatefulWidget {
  const SignScreen({super.key, this.pad, this.onCommit, this.onBack});

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
    if (_pad.isEmpty) return;
    widget.onCommit?.call(_pad.mark);
  }

  @override
  Widget build(BuildContext context) {
    final hasInk = !_pad.isEmpty;
    return ColoredBox(
      color: AppColors.deskGround,
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
            child: SignPad(controller: _pad),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: kSignHintTop,
            child: Center(
              child: Text(
                'Sign above the line.',
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
              enabled: hasInk,
              onTap: _pad.undo,
            ),
          ),
          Positioned(
            left: kSignToolLeft + kSignToolGap,
            top: kSignToolTop,
            child: _Tool(
              icon: LucideIcons.trash2,
              label: 'Clear the pad',
              enabled: hasInk,
              onTap: _pad.clear,
            ),
          ),
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
                    color: AppColors.thread,
                    borderRadius: BorderRadius.circular(kPillRadius),
                  ),
                  child: Center(
                    child: Text(
                      'Place on page',
                      style: AppText.label.copyWith(color: AppColors.leaf),
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
          color: AppColors.leaf,
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
