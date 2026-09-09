import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../constants/gooey_fab.dart';
import '../../painting/goo_circles_painter.dart';
import '../../theme/colors.dart';
import '../press_fade.dart';
import 'fab_action_pill.dart';
import 'gooey_fab_controller.dart';

/// The action button, which stretches three more buttons out of itself.
///
/// The circles go into one layer, get blurred, then run through a colour
/// matrix that snaps alpha back to a hard edge. Where two blurred circles
/// overlap, the combined alpha crosses the threshold, so they read as one body
/// joined by a neck that thins and finally parts. The pills a finger actually
/// hits are ordinary widgets stacked over that layer, driven by the same
/// values, so what you touch is always where you saw it.
class GooeyFab extends StatefulWidget {
  const GooeyFab({super.key, this.onSelected});

  /// Called with the index of the chosen action in [kFabActions], after the
  /// button has started closing. An index rather than three callbacks because
  /// the actions are a list: adding a fourth should not mean naming it twice.
  final ValueChanged<int>? onSelected;

  @override
  State<GooeyFab> createState() => _GooeyFabState();
}

class _GooeyFabState extends State<GooeyFab> with TickerProviderStateMixin {
  late final GooeyFabController _controller = GooeyFabController(vsync: this);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onOpenChanged);
  }

  void _onOpenChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onOpenChanged);
    _controller.dispose();
    super.dispose();
  }

  void _toggle() => _controller.toggle();

  void _select(int index) {
    _toggle();
    widget.onSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _controller.isOpen;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !isOpen,
            child: AnimatedBuilder(
              animation: _controller.scrim,
              builder: (context, child) => ColoredBox(
                color: AppColors.scrim.withValues(
                  alpha: AppColors.scrim.a * _controller.scrim.value,
                ),
                child: child,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: kFabCanvasBottomOffset,
          width: kFabCanvasWidth,
          height: kFabCanvasHeight,
          child: Stack(
            // A pill is as wide as its label, so the canvas is sized for the
            // longest one rather than the other way round. Clipping here would
            // shave a word off a longer label instead of showing it.
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(child: _GooLayer(controller: _controller)),
              ),
              // Furthest first, so the pill nearest the thumb is the one on
              // top while they are all still stacked over each other.
              for (var i = kFabActions.length - 1; i >= 0; i--)
                FabActionPill(
                  action: kFabActions[i],
                  drive: _controller.actionDrive(i),
                  interactive: isOpen,
                  onPressed: () => _select(i),
                ),
              _FabButton(progress: _controller.progress, onTap: _toggle),
            ],
          ),
        ),
      ],
    );
  }
}

/// The button itself: a 60 squircle in `accent` that becomes a 56 circle in
/// `accentBright`, with the plus turning 135 degrees into a close.
///
/// It is drawn over the goo rather than being part of it, because a squircle
/// cannot be a goo circle and because the open button changes colour while the
/// body it stretches stays `accent`. The circle underneath it stays a little
/// smaller than this shape at both ends, so no goo shows round its edge.
class _FabButton extends StatelessWidget {
  const _FabButton({required this.progress, required this.onTap});

  final Animation<double> progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final value = progress.value;
        final open = value.clamp(0.0, 1.0);
        final size = ui.lerpDouble(kFabRestSize, kFabOpenSize, open)!;
        return Positioned(
          left: kFabCenterX - size / 2,
          top: kFabCenterY - size / 2,
          width: size,
          height: size,
          child: PaperPress(
            onTap: onTap,
            semanticLabel: 'Actions',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(AppColors.accent, AppColors.accentBright, open),
                borderRadius: BorderRadius.circular(
                  ui.lerpDouble(kFabRestRadius, kFabOpenRadius, open)!,
                ),
              ),
              child: Center(
                child: Transform.rotate(
                  // The unclamped value on purpose: the spring overshoots, and
                  // the glyph turning a few degrees past the close and settling
                  // back is the same overshoot the body has.
                  angle: value * kFabOpenRotationDegrees * math.pi / 180,
                  child: Icon(
                    LucideIcons.plus,
                    size: kFabGlyphSize,
                    color: Color.lerp(
                      AppColors.onAccent,
                      AppColors.onAccentBright,
                      open,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Blur then threshold over every circle, so circles that overlap fuse.
class _GooLayer extends StatelessWidget {
  const _GooLayer({required this.controller});

  final GooeyFabController controller;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(kGooAlphaThresholdMatrix),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: kGooBlurSigma,
            sigmaY: kGooBlurSigma,
            tileMode: TileMode.decal,
          ),
          child: AnimatedBuilder(
            animation: controller.animations,
            builder: (context, _) => CustomPaint(
              painter: GooCirclesPainter(
                actionCentresY: <double>[
                  for (var i = 0; i < kFabActions.length; i++)
                    kFabCenterY +
                        controller.actionDrive(i).value * kFabActions[i].offsetY,
                ],
                buttonDiameter: ui.lerpDouble(
                  kGooButtonRestDiameter,
                  kGooButtonOpenDiameter,
                  controller.progress.value.clamp(0.0, 1.0),
                )!,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
