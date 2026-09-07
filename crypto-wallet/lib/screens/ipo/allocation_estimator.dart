import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/haptics.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/refreshable_value.dart';
import '../../widgets/rolling_number.dart';
import 'rings.dart';

const double _knob = 26;
const double _track = 8;
const int _step = 100;
const List<int> _presets = [500, 1000, 2500, 5000, 10000];

({AllocationTier tier, double tierScore}) _tierFor(int allocationPercent) {
  if (allocationPercent >= 80) {
    return (tier: AllocationTier.high, tierScore: 0.92);
  }
  if (allocationPercent >= 55) {
    return (tier: AllocationTier.medium, tierScore: 0.6);
  }
  return (tier: AllocationTier.low, tierScore: 0.3);
}

/// How many shares an investment of [amountUsd] is likely to receive.
AllocationEstimate computeAllocationEstimate(Ipo ipo, int amountUsd) {
  final midPrice = (ipo.priceLow + ipo.priceHigh) / 2;
  final oversubscription = ipo.demandPercent / 100 + 0.55;
  final sizePressure = math.min(0.5, amountUsd / ipo.maxInvestment) * 0.9;
  final allocationPercent = math.max(
    18,
    math.min(96, ((1 / oversubscription - sizePressure) * 130).round()),
  );
  final filledUsd = amountUsd * (allocationPercent / 100);
  final shares = (filledUsd / midPrice).floor();
  final tier = _tierFor(allocationPercent);
  return AllocationEstimate(
    shares: shares,
    allocationPercent: allocationPercent,
    totalUsd: shares * midPrice,
    tier: tier.tier,
    tierScore: tier.tierScore,
  );
}

/// Investment amount slider with presets, the resulting estimate and the
/// probability ring.
class AllocationEstimator extends StatefulWidget {
  const AllocationEstimator({
    super.key,
    required this.ipo,
    required this.amount,
    required this.onAmountChange,
    required this.estimate,
    required this.refreshing,
  });

  final Ipo ipo;
  final int amount;
  final ValueChanged<int> onAmountChange;
  final AllocationEstimate estimate;
  final bool refreshing;

  @override
  State<AllocationEstimator> createState() => _AllocationEstimatorState();
}

class _AllocationEstimatorState extends State<AllocationEstimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fraction = AnimationController.unbounded(
    vsync: this,
    value: (widget.amount - widget.ipo.minInvestment) / _range,
  );
  double _trackWidth = 0;

  int get _range => widget.ipo.maxInvestment - widget.ipo.minInvestment;

  @override
  void initState() {
    super.initState();
    _fraction.addListener(_emit);
  }

  void _emit() {
    final raw = widget.ipo.minInvestment + _fraction.value.clamp(0.0, 1.0) * _range;
    final next = math.min(
      widget.ipo.maxInvestment,
      math.max(widget.ipo.minInvestment, (raw / _step).round() * _step),
    );
    if (next != widget.amount) {
      if (next % 1000 == 0) {
        Haptics.selection();
      }
      widget.onAmountChange(next);
    }
  }

  void _selectPreset(int preset) {
    _fraction.animateWith(
      springTo(Springs.roll, _fraction.value, (preset - widget.ipo.minInvestment) / _range),
    );
  }

  void _dragTo(double x) {
    if (_trackWidth <= 0) {
      return;
    }
    _fraction.stop();
    _fraction.value = (x / _trackWidth).clamp(0.0, 1.0);
  }

  void _tapTo(double x) {
    if (_trackWidth <= 0) {
      return;
    }
    _fraction.animateWith(
      springTo(Springs.roll, _fraction.value, (x / _trackWidth).clamp(0.0, 1.0)),
    );
  }

  @override
  void dispose() {
    _fraction.dispose();
    super.dispose();
  }

  Widget _estimateRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: text(13, color: AppColors.subtle)),
          RefreshableValue(
            refreshing: widget.refreshing,
            shimmerWidth: 64,
            shimmerHeight: 15,
            child: RollingNumber(
              value: value,
              fontSize: 15,
              color: emphasize ? AppColors.accent : AppColors.ink,
              keyMode: RollingKeyMode.value,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ipo = widget.ipo;
    final estimate = widget.estimate;
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
            children: [
              Text('Investment', style: text(13, weight: FontWeight.w600, color: AppColors.subtle)),
              Text(
                '\$${groupThousands('${ipo.minInvestment}')} – \$${groupThousands('${ipo.maxInvestment}')}',
                style: text(12, color: AppColors.cents),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text('\$', style: text(34, weight: FontWeight.w700, color: AppColors.cents)),
              ),
              RollingNumber(
                value: groupThousands('${widget.amount}'),
                fontSize: 34,
                color: AppColors.ink,
                keyMode: RollingKeyMode.value,
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              _trackWidth = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => _dragTo(d.localPosition.dx),
                onTapUp: (d) => _tapTo(d.localPosition.dx),
                child: SizedBox(
                  height: 40,
                  child: AnimatedBuilder(
                    animation: _fraction,
                    builder: (context, _) {
                      final f = _fraction.value.clamp(0.0, 1.0);
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(_track / 2),
                            child: SizedBox(
                              height: _track,
                              width: double.infinity,
                              child: Stack(
                                children: [
                                  const ColoredBox(color: AppColors.chip, child: SizedBox.expand()),
                                  Transform.translate(
                                    offset: Offset(-(1 - f) * _trackWidth, 0),
                                    child: Container(
                                      height: _track,
                                      decoration: BoxDecoration(
                                        color: AppColors.accent,
                                        borderRadius: BorderRadius.circular(_track / 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: Offset(f * math.max(0, _trackWidth - _knob), 0),
                            child: Container(
                              width: _knob,
                              height: _knob,
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.outline, width: 0.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.ink.withValues(alpha: 0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < _presets.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: PressableScale(
                    scaleTo: 0.94,
                    haptic: HapticKind.selection,
                    onPress: () => _selectPreset(_presets[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.amount == _presets[i] ? AppColors.ink : AppColors.chip,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _presets[i] >= 1000
                            ? '\$${formatNumber(_presets[i] / 1000)}K'
                            : '\$${_presets[i]}',
                        style: text(
                          12,
                          weight: FontWeight.w600,
                          color: widget.amount == _presets[i] ? AppColors.white : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 16),
            color: AppColors.outline,
          ),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    children: [
                      _estimateRow('Estimated Shares', '${estimate.shares}'),
                      _estimateRow('Estimated Allocation', '${estimate.allocationPercent}%'),
                      _estimateRow(
                        'Investment Total',
                        '\$${groupThousands(estimate.totalUsd.toStringAsFixed(2))}',
                        emphasize: true,
                      ),
                    ],
                  ),
                ),
              ),
              ProbabilityRing(size: 96, tier: estimate.tier, score: estimate.tierScore),
            ],
          ),
        ],
      ),
    );
  }
}
