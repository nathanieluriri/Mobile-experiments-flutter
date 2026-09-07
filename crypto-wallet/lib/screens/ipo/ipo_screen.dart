import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/fixtures.dart';
import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/random.dart';
import '../../widgets/enter.dart';
import '../../widgets/flow_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/shimmer.dart';
import 'allocation_estimator.dart';
import 'ipo_cards.dart';
import 'meters.dart';
import 'subscribe_confirmation.dart';

const Duration _load = Duration(milliseconds: 1200);
const Duration _demandTick = Duration(milliseconds: 5200);
const Duration _estimateDelay = Duration(milliseconds: 420);
const double _demandCap = 97;
const double _subscribeBump = 1.6;
const int _defaultAmount = 1000;

/// The IPO market: one featured offering to explore and subscribe to.
class IpoScreen extends StatefulWidget {
  const IpoScreen({super.key});

  @override
  State<IpoScreen> createState() => _IpoScreenState();
}

class _IpoScreenState extends State<IpoScreen> with SingleTickerProviderStateMixin {
  final Ipo _ipo = featuredIpo;
  bool _loading = true;
  int _amount = _defaultAmount;
  bool _confirming = false;
  bool _subscribed = false;
  double _demand = featuredIpo.demandPercent;
  Duration _remaining = featuredIpo.countdown;
  late AllocationEstimate _estimate = computeAllocationEstimate(_ipo, _amount);
  bool _refreshing = false;

  Timer? _loadTimer;
  Timer? _demandTimer;
  Timer? _countdownTimer;
  Timer? _estimateTimer;
  late final AnimationController _recede = AnimationController.unbounded(vsync: this);

  @override
  void initState() {
    super.initState();
    _loadTimer = Timer(_load, () {
      setState(() => _loading = false);
      _demandTimer = Timer.periodic(_demandTick, (_) {
        setState(() {
          _demand = (_demand + 0.4 + appRandom.nextDouble() * 0.8).clamp(0, _demandCap);
        });
      });
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_confirming) {
        return;
      }
      setState(() {
        _remaining -= const Duration(seconds: 1);
        if (_remaining.isNegative) {
          _remaining = Duration.zero;
        }
      });
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _demandTimer?.cancel();
    _countdownTimer?.cancel();
    _estimateTimer?.cancel();
    _recede.dispose();
    super.dispose();
  }

  CountdownParts get _countdown {
    String two(int value) => value.toString().padLeft(2, '0');
    return CountdownParts(
      days: two(_remaining.inDays),
      hours: two(_remaining.inHours % 24),
      minutes: two(_remaining.inMinutes % 60),
    );
  }

  void _setAmount(int amount) {
    setState(() {
      _amount = amount;
      _refreshing = true;
    });
    _estimateTimer?.cancel();
    _estimateTimer = Timer(_estimateDelay, () {
      setState(() {
        _estimate = computeAllocationEstimate(_ipo, _amount);
        _refreshing = false;
      });
    });
  }

  void _setConfirming(bool confirming) {
    setState(() => _confirming = confirming);
    _recede.animateWith(springTo(Springs.screen, _recede.value, confirming ? 1 : 0));
  }

  void _done() {
    _setConfirming(false);
    setState(() {
      _subscribed = true;
      _demand = (_demand + _subscribeBump).clamp(0, _demandCap);
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final canSubscribe = !_loading && !_subscribed && _amount >= _ipo.minInvestment;
    return Scaffold(
      backgroundColor: AppColors.screen,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              SizedBox(height: padding.top),
              FlowHeader(
                title: 'IPO Market',
                subtitle: 'Discover and invest in upcoming public offerings',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _recede,
                  builder: (context, child) {
                    final r = _recede.value;
                    return Transform.translate(
                      offset: Offset(0, -r * 6),
                      child: Transform.scale(scale: 1 - r * 0.02, child: child),
                    );
                  },
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(top: 12, bottom: padding.bottom + 96),
                    child: _loading
                        ? const IpoSkeleton()
                        : IpoContent(
                            ipo: _ipo,
                            related: relatedIpos,
                            countdown: _countdown,
                            paused: _confirming,
                            subscribed: _subscribed,
                            demand: _demand,
                            amount: _amount,
                            onAmountChange: _setAmount,
                            estimate: _estimate,
                            refreshing: _refreshing,
                          ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: padding.bottom + 12,
            child: PrimaryButton(
              enabled: canSubscribe,
              onPress: () => _setConfirming(true),
              label: _subscribed ? 'Subscribed' : 'Subscribe to IPO',
            ),
          ),
          if (_confirming)
            SubscribeConfirmation(
              ipo: _ipo,
              amountUsd: _amount,
              estimate: _estimate,
              onCancel: () => _setConfirming(false),
              onDone: _done,
            ),
        ],
      ),
    );
  }
}

/// Every card of the offering, staggered into view.
class IpoContent extends StatelessWidget {
  const IpoContent({
    super.key,
    required this.ipo,
    required this.related,
    required this.countdown,
    required this.paused,
    required this.subscribed,
    required this.demand,
    required this.amount,
    required this.onAmountChange,
    required this.estimate,
    required this.refreshing,
  });

  final Ipo ipo;
  final List<RelatedIpo> related;
  final CountdownParts countdown;
  final bool paused;
  final bool subscribed;
  final double demand;
  final int amount;
  final ValueChanged<int> onAmountChange;
  final AllocationEstimate estimate;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    const section = EdgeInsets.symmetric(horizontal: 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: section,
          child: Enter(
            child: IpoHeroCard(
              ipo: ipo,
              countdown: countdown,
              paused: paused,
              subscribed: subscribed,
            ),
          ),
        ),
        Padding(
          padding: section.copyWith(top: 12),
          child: Enter(
            delay: const Duration(milliseconds: 90),
            child: DemandMeter(percent: demand),
          ),
        ),
        Padding(
          padding: section,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel(label: 'Offering Details'),
              IpoDetailsList(details: ipo.details, baseDelay: 180),
            ],
          ),
        ),
        Padding(
          padding: section.copyWith(top: 12),
          child: Enter(
            delay: const Duration(milliseconds: 320),
            child: PriceRangeCard(low: ipo.priceLow, high: ipo.priceHigh),
          ),
        ),
        Padding(
          padding: section.copyWith(top: 12),
          child: Enter(
            delay: const Duration(milliseconds: 400),
            child: CompanyOverviewCard(ipo: ipo),
          ),
        ),
        Padding(
          padding: section,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel(label: 'Financials'),
              FinancialMetricsGrid(metrics: ipo.metrics, baseDelay: 480),
            ],
          ),
        ),
        const Padding(padding: section, child: SectionLabel(label: 'Allocation Estimator')),
        Padding(
          padding: section,
          child: Enter(
            delay: const Duration(milliseconds: 560),
            child: AllocationEstimator(
              ipo: ipo,
              amount: amount,
              onAmountChange: onAmountChange,
              estimate: estimate,
              refreshing: refreshing,
            ),
          ),
        ),
        const SectionLabel(label: 'Journey to IPO', inset: true),
        CompanyTimeline(events: ipo.timeline, baseDelay: 640),
        const SectionLabel(label: 'Upcoming IPOs', inset: true),
        RelatedIpoCarousel(ipos: related, baseDelay: 720),
      ],
    );
  }
}

/// Shimmer placeholders shaped like the first cards.
class IpoSkeleton extends StatelessWidget {
  const IpoSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.sizeOf(context).width - 40;
    final gridItem = (cardWidth - 10) / 2;
    Widget card({required double radius, required EdgeInsets padding, required Widget child}) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card(
            radius: 28,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Shimmer(width: 58, height: 58, radius: 17),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Shimmer(width: 128, height: 18, radius: 8),
                        SizedBox(height: 8),
                        Shimmer(width: 90, height: 12, radius: 6),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Shimmer(width: 84, height: 11, radius: 5),
                          SizedBox(height: 8),
                          Shimmer(width: 100, height: 14, radius: 7),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Shimmer(width: 70, height: 11, radius: 5),
                          SizedBox(height: 8),
                          Shimmer(width: 88, height: 14, radius: 7),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Shimmer(width: 130, height: 11, radius: 5),
                        SizedBox(height: 8),
                        Shimmer(width: 168, height: 28, radius: 9),
                      ],
                    ),
                    const Shimmer(width: 62, height: 62, radius: 31),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          card(
            radius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Shimmer(width: 96, height: 13, radius: 6),
                    Shimmer(width: 64, height: 26, radius: 9),
                  ],
                ),
                const SizedBox(height: 16),
                Shimmer(width: cardWidth - 40, height: 16, radius: 8),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Shimmer(width: cardWidth, height: 64, radius: 20),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < 4; i++) Shimmer(width: gridItem, height: 92, radius: 20),
            ],
          ),
        ],
      ),
    );
  }
}
