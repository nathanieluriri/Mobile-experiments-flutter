import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'haptics.dart';

const double _dragCloseVelocity = 800;
const double _dragCloseRatio = 0.35;

/// A sheet that springs up over a blurred, dimmed backdrop and can be dragged
/// away. Place it as the last child of a full-screen Stack.
class AppBottomSheet extends StatefulWidget {
  const AppBottomSheet({
    super.key,
    required this.open,
    required this.onClose,
    required this.title,
    required this.child,
  });

  final bool open;
  final VoidCallback onClose;
  final String title;
  final Widget child;

  @override
  State<AppBottomSheet> createState() => _AppBottomSheetState();
}

class _AppBottomSheetState extends State<AppBottomSheet>
    with SingleTickerProviderStateMixin {
  final GlobalKey _sheetKey = GlobalKey();
  late final AnimationController _translateY;
  bool _mounted = false;
  double _windowHeight = 874;
  double _dragStart = 0;

  double get _sheetHeight {
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.height ?? _windowHeight * 0.5;
  }

  @override
  void initState() {
    super.initState();
    _translateY = AnimationController.unbounded(vsync: this);
    if (widget.open) {
      _present();
    }
  }

  @override
  void didUpdateWidget(AppBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) {
      _present();
    } else if (!widget.open && oldWidget.open && _mounted) {
      _dismiss(0);
    }
  }

  void _present() {
    setState(() => _mounted = true);
    Haptics.tap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _translateY.value = _windowHeight;
      _translateY.animateWith(springTo(Springs.sheet, _windowHeight, 0));
    });
  }

  void _dismiss(double velocity) {
    _translateY
        .animateWith(springTo(Springs.sheet, _translateY.value, _windowHeight, velocity: velocity))
        .whenComplete(() {
      if (!mounted) {
        return;
      }
      setState(() => _mounted = false);
      widget.onClose();
    });
  }

  void _onDragStart(DragStartDetails details) {
    _translateY.stop();
    _dragStart = details.globalPosition.dy - _translateY.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final translation = details.globalPosition.dy - _dragStart;
    _translateY.value =
        translation >= 0 ? translation : -math.pow(translation.abs(), 0.72).toDouble();
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final shouldClose =
        velocity > _dragCloseVelocity || _translateY.value > _sheetHeight * _dragCloseRatio;
    if (shouldClose) {
      _dismiss(velocity);
    } else {
      _translateY.animateWith(
        springTo(Springs.sheet, _translateY.value, 0, velocity: velocity),
      );
    }
  }

  @override
  void dispose() {
    _translateY.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _windowHeight = MediaQuery.sizeOf(context).height;
    if (!_mounted) {
      return const SizedBox.shrink();
    }
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return AnimatedBuilder(
      animation: _translateY,
      builder: (context, _) {
        final y = _translateY.value;
        final backdrop = (1 - y / _sheetHeight).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: backdrop,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 13, sigmaY: 13),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: const ColoredBox(color: Color(0x4D000000)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Transform.translate(
                offset: Offset(0, y),
                child: GestureDetector(
                  onVerticalDragStart: _onDragStart,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: Container(
                    key: _sheetKey,
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 12,
                      bottom: bottomInset + 16,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.outline,
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(widget.title, style: text(20, weight: FontWeight.w700)),
                        ),
                        widget.child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
