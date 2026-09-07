import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../constants/gooey_fab.dart';
import '../../painting/feather_icons.dart';
import '../../painting/goo_circles_painter.dart';
import '../../theme/colors.dart';
import 'fab_action_button.dart';
import 'gooey_fab_controller.dart';

/// A floating action button that stretches two more buttons out of itself.
///
/// The circles go into one layer, get blurred, then run through a colour matrix
/// that snaps alpha back to a hard edge. Where two blurred circles overlap the
/// combined alpha crosses the threshold, so they read as one blob joined by a
/// neck. The buttons a finger actually hits are ordinary widgets stacked over
/// that layer, driven by the same values.
class GooeyFab extends StatefulWidget {
  const GooeyFab({super.key, this.onVideoCall, this.onVoiceCall});

  final VoidCallback? onVideoCall;
  final VoidCallback? onVoiceCall;

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

  void _select(VoidCallback? action) {
    _toggle();
    action?.call();
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
              animation: _controller.progress,
              builder: (context, child) {
                final progress = _controller.progress.value.clamp(0.0, 1.0);
                if (progress < 0.001) {
                  // Nothing to filter, but the layer still takes the tap that
                  // dismisses the button.
                  return child!;
                }
                return ClipRect(
                  child: BackdropFilter(
                    filter: backdropFilterAt(progress),
                    child: ColoredBox(
                      color: AppColors.onInk.withValues(alpha: progress * backdropWashOpacity),
                      child: child,
                    ),
                  ),
                );
              },
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
          bottom: fabCanvasBottomOffset,
          width: fabCanvasWidth,
          height: fabCanvasHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(child: _GooLayer(controller: _controller)),
              ),
              FabActionButton(
                drive: _controller.videoDrive,
                offsetY: videoActionOffsetY,
                interactive: isOpen,
                onPressed: () => _select(widget.onVideoCall),
                child: const FeatherIcon(
                  FeatherGlyph.video,
                  size: videoIconSize,
                  color: AppColors.onInk,
                ),
              ),
              FabActionButton(
                drive: _controller.voiceDrive,
                offsetY: voiceActionOffsetY,
                interactive: isOpen,
                onPressed: () => _select(widget.onVoiceCall),
                child: const FeatherIcon(
                  FeatherGlyph.phone,
                  size: voiceIconSize,
                  color: AppColors.onInk,
                ),
              ),
              Positioned(
                left: fabCenterX - fabDiameter / 2,
                top: fabCenterY - fabDiameter / 2,
                width: fabDiameter,
                height: fabDiameter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _controller.progress,
                      builder: (context, child) => Transform.rotate(
                        angle:
                            _controller.progress.value *
                            plusIconOpenRotationDegrees *
                            math.pi /
                            180,
                        child: child,
                      ),
                      child: const FeatherIcon(
                        FeatherGlyph.plus,
                        size: plusIconSize,
                        color: AppColors.onInk,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Blur then threshold over the three circles, so overlapping circles fuse.
class _GooLayer extends StatelessWidget {
  const _GooLayer({required this.controller});

  final GooeyFabController controller;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(gooAlphaThresholdMatrix),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: gooBlurSigma,
            sigmaY: gooBlurSigma,
            tileMode: TileMode.decal,
          ),
          child: AnimatedBuilder(
            animation: controller.animations,
            builder: (context, _) => CustomPaint(
              painter: GooCirclesPainter(
                voiceCenterY: fabCenterY + controller.voiceDrive.value * voiceActionOffsetY,
                videoCenterY: fabCenterY + controller.videoDrive.value * videoActionOffsetY,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
