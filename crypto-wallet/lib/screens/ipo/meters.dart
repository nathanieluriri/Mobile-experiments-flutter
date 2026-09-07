import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../utils/random.dart';
import '../../widgets/rolling_number.dart';

const double _trackHeight = 16;
const double _canvasHeight = 36;
const double _trackTop = (_canvasHeight - _trackHeight) / 2;
const List<Color> _fillColors = [
  AppColors.accent,
  AppColors.accentPurple,
  AppColors.accentPink,
];

const List<({double seed, double speed, double drift, double radius})> _particles = [
  (seed: 0.08, speed: 0.36, drift: 2.4, radius: 1.7),
  (seed: 0.31, speed: 0.22, drift: 3.1, radius: 1.3),
  (seed: 0.52, speed: 0.45, drift: 2.0, radius: 1.9),
  (seed: 0.69, speed: 0.28, drift: 2.8, radius: 1.4),
  (seed: 0.87, speed: 0.4, drift: 2.2, radius: 1.6),
];

/// Subscription demand as a glowing gradient bar with drifting particles.
class DemandMeter extends StatefulWidget {
  const DemandMeter({super.key, required this.percent});

  final double percent;

  @override
  State<DemandMeter> createState() => _DemandMeterState();
}

class _DemandMeterState extends State<DemandMeter> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController.unbounded(vsync: this);
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1000),
  )..forward();
  double _trackWidth = 0;

  void _syncFill(double width) {
    if (width != _trackWidth) {
      _trackWidth = width;
      _fill.animateWith(springTo(Springs.roll, _fill.value, widget.percent / 100 * width));
    }
  }

  @override
  void didUpdateWidget(DemandMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.percent != widget.percent && _trackWidth > 0) {
      _fill.animateWith(
        springTo(Springs.roll, _fill.value, widget.percent / 100 * _trackWidth),
      );
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Subscription', style: text(13, weight: FontWeight.w600, color: AppColors.subtle)),
                  const SizedBox(height: 2),
                  Text('Demand across all investors', style: text(12, color: AppColors.cents)),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RollingNumber(
                    value: '${widget.percent.round()}',
                    fontSize: 30,
                    color: AppColors.ink,
                    keyMode: RollingKeyMode.value,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('%', style: text(18, weight: FontWeight.w700, color: AppColors.subtle)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _syncFill(constraints.maxWidth);
                }
              });
              return AnimatedBuilder(
                animation: Listenable.merge([_fill, _clock]),
                builder: (context, _) {
                  // The glow is clipped to the 36 px canvas like the original.
                  return ClipRect(
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, _canvasHeight),
                      painter: _DemandPainter(
                        fillWidth: _fill.value.clamp(0.0, constraints.maxWidth),
                        seconds: _clock.value * 1000,
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Oversubscribed 2.4x', style: text(12, color: AppColors.subtle)),
              Text('Filling fast', style: text(12, weight: FontWeight.w600, color: AppColors.gain)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemandPainter extends CustomPainter {
  _DemandPainter({required this.fillWidth, required this.seconds});

  final double fillWidth;
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = const Radius.circular(_trackHeight / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, _trackTop, size.width, _trackHeight), radius),
      Paint()..color = AppColors.chip,
    );
    if (fillWidth <= 0) {
      return;
    }
    final fillRect = Rect.fromLTWH(0, _trackTop, fillWidth, _trackHeight);
    final shader = ui.Gradient.linear(
      Offset.zero,
      Offset(math.max(fillWidth, 1), 0),
      _fillColors,
      const [0, 0.5, 1],
    );
    canvas.saveLayer(null, Paint()..color = const Color(0x8CFFFFFF));
    canvas.drawRRect(
      RRect.fromRectAndRadius(fillRect, radius),
      Paint()
        ..shader = shader
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.restore();
    canvas.drawRRect(RRect.fromRectAndRadius(fillRect, radius), Paint()..shader = shader);

    for (final p in _particles) {
      final t = (p.seed + seconds * p.speed * 0.12) % 1;
      final cx = 8 + t * math.max(0, fillWidth - 16);
      final cy = _canvasHeight / 2 + math.sin(seconds * (0.8 + p.speed) + p.seed * 20) * p.drift;
      final opacity = 0.35 + math.sin(seconds * 1.6 + p.seed * 30) * 0.3;
      canvas.drawCircle(
        Offset(cx, cy),
        p.radius,
        Paint()..color = AppColors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_DemandPainter oldDelegate) =>
      oldDelegate.fillWidth != fillWidth || oldDelegate.seconds != seconds;
}

/// Drifts the street estimate somewhere inside the range, away from the edges.
double nextPriceEstimate(double low, double high, math.Random random) {
  final pad = (high - low) * 0.12;
  return low + pad + random.nextDouble() * (high - low - pad * 2);
}

const double _priceCanvasHeight = 44;
const double _priceTrackHeight = 8;
const double _priceTrackY = (_priceCanvasHeight - _priceTrackHeight) / 2;
const double _knobRadius = 9;
const double _edge = _knobRadius + 4;
const Duration _priceUpdate = Duration(milliseconds: 4200);

/// The offering price range with a knob that follows the live street estimate.
class PriceRangeCard extends StatefulWidget {
  const PriceRangeCard({super.key, required this.low, required this.high});

  final int low;
  final int high;

  @override
  State<PriceRangeCard> createState() => _PriceRangeCardState();
}

class _PriceRangeCardState extends State<PriceRangeCard> with TickerProviderStateMixin {
  late double _estimate = (widget.low + widget.high) / 2 + 0.2;
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: 0.5,
  );
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastUpdate = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
    _moveTo(_estimate);
  }

  void _tick(Duration elapsed) {
    if (elapsed - _lastUpdate >= _priceUpdate) {
      _lastUpdate += _priceUpdate;
      setState(() {
        _estimate = nextPriceEstimate(widget.low.toDouble(), widget.high.toDouble(), appRandom);
      });
      _moveTo(_estimate);
    }
  }

  void _moveTo(double estimate) {
    final target = (estimate - widget.low) / (widget.high - widget.low);
    _position.animateWith(springTo(Springs.roll, _position.value, target));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Price Range', style: text(13, weight: FontWeight.w600, color: AppColors.subtle)),
          const SizedBox(height: 8),
          Row(
            children: [
              RollingNumber(
                value: '\$${widget.low}',
                fontSize: 30,
                color: AppColors.ink,
                keyMode: RollingKeyMode.value,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(kRangeDash, style: text(24, weight: FontWeight.w600, color: AppColors.cents)),
              ),
              RollingNumber(
                value: '\$${widget.high}',
                fontSize: 30,
                color: AppColors.ink,
                keyMode: RollingKeyMode.value,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              return AnimatedBuilder(
                animation: _position,
                builder: (context, _) {
                  final knobX = _edge + _position.value * math.max(0, constraints.maxWidth - _edge * 2);
                  return ClipRect(
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, _priceCanvasHeight),
                      painter: _PricePainter(knobX: knobX),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Street estimate', style: text(12, color: AppColors.subtle)),
              RollingNumber(
                value: '\$${_estimate.toStringAsFixed(2)}',
                fontSize: 14,
                color: AppColors.ink,
                keyMode: RollingKeyMode.value,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PricePainter extends CustomPainter {
  _PricePainter({required this.knobX});

  final double knobX;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(_priceTrackHeight / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, _priceTrackY, size.width, _priceTrackHeight),
        radius,
      ),
      Paint()..color = AppColors.chip,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, _priceTrackY, knobX, _priceTrackHeight),
        radius,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(math.max(knobX, 1), 0),
          const [AppColors.accentSoft, AppColors.accent],
        ),
    );
    final center = Offset(knobX, _priceCanvasHeight / 2);
    canvas.drawCircle(
      center,
      _knobRadius + 5,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.35)
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(center, _knobRadius, Paint()..color = AppColors.white);
    canvas.drawCircle(center, 4.5, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_PricePainter oldDelegate) => oldDelegate.knobX != knobX;
}
