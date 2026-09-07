import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/enter.dart';
import '../../widgets/haptics.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/rolling_number.dart';
import 'company_logo.dart';
import 'rings.dart';

/// Section heading above a group of cards.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.inset = false});

  final String label;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        bottom: 10,
        left: inset ? 20 : 0,
        right: inset ? 20 : 0,
      ),
      child: Text(
        label,
        style: text(13, weight: FontWeight.w600, color: AppColors.subtle),
      ),
    );
  }
}

class _StatusPulse extends StatefulWidget {
  const _StatusPulse();

  @override
  State<_StatusPulse> createState() => _StatusPulseState();
}

class _StatusPulseState extends State<_StatusPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final p = Eases.iosInOut.transform(_pulse.value);
        return Opacity(
          opacity: 0.55 + p * 0.45,
          child: Transform.scale(
            scale: 0.85 + p * 0.3,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.gain,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CountdownUnit extends StatelessWidget {
  const _CountdownUnit({required this.value, required this.unit});

  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RollingNumber(
          value: value,
          fontSize: 26,
          color: AppColors.ink,
          keyMode: RollingKeyMode.value,
        ),
        const SizedBox(height: 2),
        Text(
          unit,
          style: text(11, weight: FontWeight.w500, color: AppColors.subtle),
        ),
      ],
    );
  }
}

/// Company, status, listing facts and the closing countdown.
class IpoHeroCard extends StatelessWidget {
  const IpoHeroCard({
    super.key,
    required this.ipo,
    required this.countdown,
    required this.paused,
    required this.subscribed,
  });

  final Ipo ipo;
  final CountdownParts countdown;
  final bool paused;
  final bool subscribed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Enter(
                kind: EnterKind.scaleFadeIn,
                delay: const Duration(milliseconds: 80),
                child: CompanyLogo(
                  size: 58,
                  gradient: ipo.gradient,
                  monogram: ipo.monogram,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ipo.company, style: text(20, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '${ipo.ticker} · ${ipo.industry}',
                      style: text(13, color: AppColors.subtle),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: subscribed ? AppColors.accentSoft : AppColors.gainSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!subscribed) ...[
                      const _StatusPulse(),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      subscribed ? 'Subscribed' : 'Open',
                      style: text(
                        12,
                        weight: FontWeight.w600,
                        color: subscribed ? AppColors.accent : AppColors.gain,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expected Listing',
                      style: text(12, color: AppColors.subtle),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ipo.listingDate,
                      style: text(15, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Price Range',
                      style: text(12, color: AppColors.subtle),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatPriceRange(ipo.priceLow, ipo.priceHigh),
                      style: text(15, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 20),
            color: AppColors.outline,
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Subscription closes in',
                      style: text(12, color: AppColors.subtle),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _CountdownUnit(value: countdown.days, unit: 'Days'),
                        const SizedBox(width: 24),
                        _CountdownUnit(value: countdown.hours, unit: 'Hours'),
                        const SizedBox(width: 24),
                        _CountdownUnit(
                          value: countdown.minutes,
                          unit: 'Minutes',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              CountdownRing(size: 62, progress: 0.64, paused: paused),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _detailIcon(String name) {
  return switch (name) {
    'bar-chart-2' => LucideIcons.barChart2,
    'download' => LucideIcons.download,
    'briefcase' => LucideIcons.briefcase,
    'zap' => LucideIcons.zap,
    'globe' => LucideIcons.globe,
    _ => LucideIcons.info,
  };
}

/// The offering facts, one white row each.
class IpoDetailsList extends StatelessWidget {
  const IpoDetailsList({super.key, required this.details, this.baseDelay = 0});

  final List<IpoDetail> details;
  final int baseDelay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < details.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Enter(
            delay: Duration(milliseconds: baseDelay + i * 70),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _detailIcon(details[i].icon),
                      size: 17,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          details[i].label,
                          style: text(12, color: AppColors.subtle),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          details[i].value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text(14, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// About the company, with three more sections that unfold on tap.
class CompanyOverviewCard extends StatefulWidget {
  const CompanyOverviewCard({super.key, required this.ipo});

  final Ipo ipo;

  @override
  State<CompanyOverviewCard> createState() => _CompanyOverviewCardState();
}

class _CompanyOverviewCardState extends State<CompanyOverviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController.unbounded(
    vsync: this,
  );
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _progress.animateWith(
      springTo(Springs.layout, _progress.value, _expanded ? 1 : 0),
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text(12, weight: FontWeight.w600, color: AppColors.accent),
          ),
          const SizedBox(height: 6),
          Text(body, style: text(13, lineHeight: 20)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ipo = widget.ipo;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PressableScale(
            scaleTo: 0.99,
            haptic: HapticKind.selection,
            onPress: _toggle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'About ${ipo.company}',
                      style: text(15, weight: FontWeight.w700),
                    ),
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) {
                        return Transform.rotate(
                          angle: _progress.value * 3.141592653589793,
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.chip,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.chevronDown,
                              size: 17,
                              color: AppColors.ink,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  ipo.description,
                  style: text(13, color: AppColors.subtle, lineHeight: 20),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _progress,
            builder: (context, child) {
              final p = _progress.value.clamp(0.0, 1.0);
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: p,
                  child: Opacity(opacity: p, child: child),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section('Market Opportunity', ipo.marketOpportunity),
                _section('Financial Highlights', ipo.financialHighlights),
                _section('Growth Metrics', ipo.growthMetrics),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Six metric tiles in two columns.
class FinancialMetricsGrid extends StatelessWidget {
  const FinancialMetricsGrid({
    super.key,
    required this.metrics,
    this.baseDelay = 0,
  });

  final List<IpoMetric> metrics;
  final int baseDelay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < metrics.length; i++)
              SizedBox(
                width: tileWidth,
                child: Enter(
                  delay: Duration(milliseconds: baseDelay + i * 60),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metrics[i].label,
                          style: text(12, color: AppColors.subtle),
                        ),
                        const SizedBox(height: 6),
                        RollingNumber(
                          value: metrics[i].value,
                          fontSize: 21,
                          color: AppColors.ink,
                          keyMode: RollingKeyMode.value,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metrics[i].hint,
                          style: text(
                            11,
                            weight: FontWeight.w500,
                            color: AppColors.cents,
                          ),
                        ),
                      ],
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

const double _timelineCard = 148;
const double _timelineGap = 24;
const double _timelineDot = 12;
const double _segmentLength = _timelineCard + _timelineGap - _timelineDot;

class _Segment extends StatefulWidget {
  const _Segment({required this.delay});

  final int delay;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _grow.forward();
      }
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        width: _segmentLength,
        height: 2,
        child: AnimatedBuilder(
          animation: _grow,
          builder: (context, _) {
            final g = Curves.easeOutCubic.transform(_grow.value);
            return Transform.translate(
              offset: Offset(-(1 - g) * _segmentLength, 0),
              child: const ColoredBox(color: AppColors.outline),
            );
          },
        ),
      ),
    );
  }
}

/// The company's history as a horizontal row of milestone cards.
class CompanyTimeline extends StatelessWidget {
  const CompanyTimeline({super.key, required this.events, this.baseDelay = 0});

  final List<IpoTimelineEvent> events;
  final int baseDelay;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < events.length; i++)
            SizedBox(
              width: i == events.length - 1
                  ? _timelineCard
                  : _timelineCard + _timelineGap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: _timelineDot,
                        height: _timelineDot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == events.length - 1
                              ? AppColors.accent
                              : AppColors.card,
                          border: Border.all(
                            width: 2.5,
                            color: i == events.length - 1
                                ? AppColors.accent
                                : AppColors.accentPurple,
                          ),
                        ),
                      ),
                      if (i < events.length - 1)
                        _Segment(delay: baseDelay + i * 140 + 120),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Enter(
                    delay: Duration(milliseconds: baseDelay + i * 140),
                    child: Container(
                      width: _timelineCard,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            events[i].year,
                            style: text(
                              11,
                              weight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            events[i].title,
                            style: text(14, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            events[i].detail,
                            style: text(
                              11.5,
                              color: AppColors.subtle,
                              lineHeight: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const double _relatedCard = 192;
const double _relatedGap = 12;
const double _relatedSnap = _relatedCard + _relatedGap;

/// Other upcoming offerings, scrolling sideways with the front card slightly
/// enlarged.
class RelatedIpoCarousel extends StatefulWidget {
  const RelatedIpoCarousel({super.key, required this.ipos, this.baseDelay = 0});

  final List<RelatedIpo> ipos;
  final int baseDelay;

  @override
  State<RelatedIpoCarousel> createState() => _RelatedIpoCarouselState();
}

class _RelatedIpoCarouselState extends State<RelatedIpoCarousel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _scaleFor(int index, double scrollX) {
    final before = (index - 1) * _relatedSnap;
    final at = index * _relatedSnap;
    final after = (index + 1) * _relatedSnap;
    if (scrollX <= before) {
      return 1;
    }
    if (scrollX <= at) {
      return 1 - 0.045 * (scrollX - before) / _relatedSnap;
    }
    if (scrollX <= after) {
      return 0.955 - 0.045 * (scrollX - at) / _relatedSnap;
    }
    return 0.91;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: _scroll,
        builder: (context, _) {
          final scrollX = _scroll.hasClients ? _scroll.offset : 0.0;
          return Row(
            children: [
              for (var i = 0; i < widget.ipos.length; i++) ...[
                if (i > 0) const SizedBox(width: _relatedGap),
                Transform.scale(
                  scale: _scaleFor(i, scrollX),
                  child: Enter(
                    delay: Duration(milliseconds: widget.baseDelay + i * 80),
                    child: _RelatedIpoCard(ipo: widget.ipos[i]),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RelatedIpoCard extends StatelessWidget {
  const _RelatedIpoCard({required this.ipo});

  final RelatedIpo ipo;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scaleTo: 0.97,
      child: Container(
        width: _relatedCard,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CompanyLogo(
                  size: 40,
                  gradient: ipo.gradient,
                  monogram: ipo.monogram,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ipo.company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text(14, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ipo.industry,
                        style: text(11, color: AppColors.subtle),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.chip,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.clock,
                        size: 11,
                        color: AppColors.subtle,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${ipo.daysLeft}d left',
                        style: text(11, weight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Raise', style: text(10, color: AppColors.cents)),
                    Text(ipo.raise, style: text(12, weight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
