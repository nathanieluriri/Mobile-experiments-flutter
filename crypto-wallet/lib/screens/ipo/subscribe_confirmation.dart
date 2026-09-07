import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/enter.dart';
import '../../widgets/haptics.dart';
import '../../widgets/loading_ring.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rolling_number.dart';
import 'company_logo.dart';

const Duration _processing = Duration(milliseconds: 1700);
const double _ring = 120;

enum _Stage { review, processing, success }

/// Review, place and confirm a subscription in a card over a blurred screen.
class SubscribeConfirmation extends StatefulWidget {
  const SubscribeConfirmation({
    super.key,
    required this.ipo,
    required this.amountUsd,
    required this.estimate,
    required this.onCancel,
    required this.onDone,
  });

  final Ipo ipo;
  final int amountUsd;
  final AllocationEstimate estimate;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  State<SubscribeConfirmation> createState() => _SubscribeConfirmationState();
}

class _SubscribeConfirmationState extends State<SubscribeConfirmation>
    with TickerProviderStateMixin {
  _Stage _stage = _Stage.review;
  Timer? _timer;
  late final AnimationController _slide = AnimationController.unbounded(vsync: this, value: 340)
    ..animateWith(springTo(Springs.sheet, 340, 0));
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();

  String get _allocationText =>
      '${widget.estimate.allocationPercent}% · ~${widget.estimate.shares} shares';

  void _confirm() {
    setState(() => _stage = _Stage.processing);
    _timer = Timer(_processing, () {
      if (!mounted) {
        return;
      }
      setState(() => _stage = _Stage.success);
      Haptics.success();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slide.dispose();
    _fade.dispose();
    super.dispose();
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: text(13, color: AppColors.subtle)),
          Text(value, style: text(14, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _review() {
    final ipo = widget.ipo;
    return Column(
      key: const ValueKey('review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.outline,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ),
        Row(
          children: [
            CompanyLogo(size: 46, gradient: ipo.gradient, monogram: ipo.monogram),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ipo.company, style: text(17, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${ipo.ticker} · ${ipo.exchange}', style: text(12, color: AppColors.subtle)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Investment', style: text(11, color: AppColors.cents)),
                RollingNumber(
                  value: '\$${groupThousands('${widget.amountUsd}')}',
                  fontSize: 18,
                  color: AppColors.ink,
                  keyMode: RollingKeyMode.value,
                ),
              ],
            ),
          ],
        ),
        Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 20), color: AppColors.outline),
        _detailRow('Estimated Allocation', _allocationText),
        _detailRow('Expected Listing', ipo.listingDate),
        _detailRow('Price Range', formatPriceRange(ipo.priceLow, ipo.priceHigh)),
        const SizedBox(height: 20),
        PrimaryButton(enabled: true, onPress: _confirm, label: 'Confirm Subscription'),
        const SizedBox(height: 12),
        PressableScale(
          onPress: widget.onCancel,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text('Cancel', style: text(14, weight: FontWeight.w600, color: AppColors.subtle)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _processingStage() {
    final ipo = widget.ipo;
    return Padding(
      key: const ValueKey('processing'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _ring,
            height: _ring,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const LoadingRing(size: _ring),
                CompanyLogo(size: 44, gradient: ipo.gradient, monogram: ipo.monogram),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Placing subscription', style: text(16, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '\$${groupThousands('${widget.amountUsd}')} · ${ipo.ticker}',
            style: text(13, color: AppColors.subtle),
          ),
        ],
      ),
    );
  }

  Widget _success() {
    final ipo = widget.ipo;
    return Padding(
      key: const ValueKey('success'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Enter(
              kind: EnterKind.zoomIn,
              delay: const Duration(milliseconds: 60),
              springDamping: 13,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CompanyLogo(size: 72, gradient: ipo.gradient, monogram: ipo.monogram),
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Enter(
                      kind: EnterKind.zoomIn,
                      delay: const Duration(milliseconds: 420),
                      springDamping: 12,
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.gain,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.card, width: 3),
                        ),
                        child: const Icon(LucideIcons.check, size: 15, color: AppColors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Enter(
            kind: EnterKind.fadeInDown,
            delay: const Duration(milliseconds: 220),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text('Subscription Confirmed', style: text(19, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  "You're in line for ${ipo.company}'s listing",
                  style: text(13, color: AppColors.subtle),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Enter(
            kind: EnterKind.fadeInDown,
            delay: const Duration(milliseconds: 340),
            duration: const Duration(milliseconds: 320),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.screen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  _detailRow('Investment', '\$${groupThousands('${widget.amountUsd}')}'),
                  _detailRow('Estimated Allocation', _allocationText),
                  _detailRow('Expected Listing', ipo.listingDate),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Enter(
            kind: EnterKind.fadeInDown,
            delay: const Duration(milliseconds: 460),
            duration: const Duration(milliseconds: 320),
            child: PressableScale(
              haptic: HapticKind.press,
              onPress: widget.onDone,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Text('Done', style: text(15, weight: FontWeight.w700, color: AppColors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: _fade,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _stage == _Stage.review ? widget.onCancel : null,
                child: const ColoredBox(color: Color(0x40000000)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 0,
          child: AnimatedBuilder(
            animation: Listenable.merge([_slide, _fade]),
            builder: (context, child) {
              return Opacity(
                opacity: (_fade.value * 1.2).clamp(0.0, 1.0),
                child: Transform.translate(offset: Offset(0, _slide.value), child: child),
              );
            },
            child: Container(
              padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: bottomInset + 20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                reverseDuration: const Duration(milliseconds: 140),
                child: switch (_stage) {
                  _Stage.review => _review(),
                  _Stage.processing => Center(child: _processingStage()),
                  _Stage.success => _success(),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
