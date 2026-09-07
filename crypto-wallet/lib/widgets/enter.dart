import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/theme.dart';

/// The ways a widget can appear.
enum EnterKind {
  /// Fade in while settling down from 25 px above.
  fadeInDown,

  /// Fade in over 320 ms while rising 18 px and growing from 97 percent.
  liftIn,

  /// Fade in over 380 ms while popping from 78 percent.
  scaleFadeIn,

  /// Spring from nothing to full size.
  zoomIn,

  /// Fade only.
  fadeIn,
}

/// Runs an entering animation on [child] after [delay].
class Enter extends StatefulWidget {
  const Enter({
    super.key,
    required this.child,
    this.kind = EnterKind.liftIn,
    this.delay = Duration.zero,
    this.duration,
    this.springDamping,
  });

  final Widget child;
  final EnterKind kind;
  final Duration delay;

  /// Overrides the timed part's duration.
  final Duration? duration;

  /// Damping for [EnterKind.zoomIn].
  final double? springDamping;

  @override
  State<Enter> createState() => _EnterState();
}

class _EnterState extends State<Enter> with TickerProviderStateMixin {
  late final AnimationController _timed = AnimationController(
    vsync: this,
    duration: widget.duration ?? _defaultDuration,
  );
  late final AnimationController _spring = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _delay;

  Duration get _defaultDuration => switch (widget.kind) {
    EnterKind.fadeInDown => const Duration(milliseconds: 300),
    EnterKind.liftIn => const Duration(milliseconds: 320),
    EnterKind.scaleFadeIn => const Duration(milliseconds: 380),
    EnterKind.zoomIn => const Duration(milliseconds: 300),
    EnterKind.fadeIn => const Duration(milliseconds: 300),
  };

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _start();
    } else {
      _delay = Timer(widget.delay, _start);
    }
  }

  void _start() {
    if (!mounted) {
      return;
    }
    _timed.forward();
    switch (widget.kind) {
      case EnterKind.liftIn:
        _spring.animateWith(springTo(Springs.layout, 0, 1));
      case EnterKind.scaleFadeIn:
        _spring.animateWith(springTo(Springs.pop, 0, 1));
      case EnterKind.zoomIn:
        _spring.animateWith(
          SpringSimulation(
            SpringDescription(
              mass: 1,
              stiffness: 100,
              damping: widget.springDamping ?? 10,
            ),
            0,
            1,
            0,
          ),
        );
      case EnterKind.fadeInDown:
      case EnterKind.fadeIn:
        break;
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _timed.dispose();
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_timed, _spring]),
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOutQuad.transform(_timed.value);
        final s = _spring.value;
        switch (widget.kind) {
          case EnterKind.fadeInDown:
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, -25 * (1 - t)),
                child: child,
              ),
            );
          case EnterKind.liftIn:
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - s)),
                child: Transform.scale(scale: 0.97 + 0.03 * s, child: child),
              ),
            );
          case EnterKind.scaleFadeIn:
            return Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.78 + 0.22 * s, child: child),
            );
          case EnterKind.zoomIn:
            return Transform.scale(scale: s, child: child);
          case EnterKind.fadeIn:
            return Opacity(opacity: t, child: child);
        }
      },
    );
  }
}
