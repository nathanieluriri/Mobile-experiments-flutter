import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/blinking_cursor.dart';
import '../../widgets/enter.dart';
import '../../widgets/fade_swap_text.dart';
import '../../widgets/haptics.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/refreshable_value.dart';
import '../../widgets/rolling_number.dart';
import '../../widgets/token_icon.dart';

const double _swapFeeRate = 0.0025;
const double _slippage = 0.005;

SwapQuote computeSwapQuote(Token from, Token to, double amount) {
  final rate = from.priceUsd / to.priceUsd;
  final toAmount = amount * rate;
  final usdValue = amount * from.priceUsd;
  return SwapQuote(
    toAmount: toAmount,
    rate: rate,
    feeUsd: usdValue * _swapFeeRate,
    priceImpact: math.min(0.04 + usdValue / 250000, 3.2),
    networkFeeUsd: from.feeUsd,
    minReceived: toAmount * (1 - _slippage),
  );
}

SwapVenue resolveSwapVenue(Token from, Token to) {
  return from.id == TokenId.sol || to.id == TokenId.sol
      ? SwapVenue.jupiter
      : SwapVenue.uniswap;
}

/// A token icon that nods when the token changes.
class _NoddingIcon extends StatefulWidget {
  const _NoddingIcon({required this.token, required this.size});

  final Token token;
  final double size;

  @override
  State<_NoddingIcon> createState() => _NoddingIconState();
}

class _NoddingIconState extends State<_NoddingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void didUpdateWidget(_NoddingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token.id != widget.token.id) {
      _nod();
    }
  }

  void _nod() {
    _rotation
        .animateTo(-0.16, duration: const Duration(milliseconds: 110))
        .whenComplete(() {
          if (mounted) {
            _rotation.animateWith(springTo(Springs.pop, _rotation.value, 0));
          }
        });
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotation,
      builder: (context, _) {
        return Transform.rotate(
          angle: _rotation.value,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            reverseDuration: const Duration(milliseconds: 140),
            child: TokenIcon(
              key: ValueKey(widget.token.id),
              id: widget.token.id,
              size: widget.size,
            ),
          ),
        );
      },
    );
  }
}

/// A token icon that only cross-fades when the token changes.
class _FadingIcon extends StatelessWidget {
  const _FadingIcon({required this.token, required this.size});

  final Token token;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 140),
      child: TokenIcon(key: ValueKey(token.id), id: token.id, size: size),
    );
  }
}

/// A grey pill with the token icon and symbol.
class TokenChip extends StatelessWidget {
  const TokenChip({super.key, required this.token, required this.onPress});

  final Token token;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scaleTo: 0.94,
      haptic: HapticKind.selection,
      onPress: onPress,
      child: Container(
        padding: const EdgeInsets.only(left: 6, right: 12, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: AppColors.chip,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NoddingIcon(token: token, size: 34),
            const SizedBox(width: 8),
            FadeSwapText(
              text: token.symbol,
              style: text(16, weight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const Icon(
              LucideIcons.chevronDown,
              size: 15,
              color: AppColors.subtle,
            ),
          ],
        ),
      ),
    );
  }
}

const double _amountSize = 32;
const double _orbitX = 18;

/// From and to rows with the flip button between them. The chips arc past each
/// other when the direction flips.
class SwapCard extends StatefulWidget {
  const SwapCard({
    super.key,
    required this.tokenA,
    required this.tokenB,
    required this.flipped,
    required this.fromToken,
    required this.amount,
    required this.toAmountText,
    required this.rateText,
    required this.refreshing,
    required this.onFlip,
    required this.onPressChipA,
    required this.onPressChipB,
    required this.onMax,
  });

  final Token tokenA;
  final Token tokenB;
  final bool flipped;
  final Token fromToken;
  final String amount;
  final String toAmountText;
  final String rateText;
  final bool refreshing;
  final VoidCallback onFlip;
  final VoidCallback onPressChipA;
  final VoidCallback onPressChipB;
  final VoidCallback onMax;

  @override
  State<SwapCard> createState() => _SwapCardState();
}

class _SwapCardState extends State<SwapCard> with TickerProviderStateMixin {
  late final AnimationController _phase = AnimationController.unbounded(
    vsync: this,
    value: widget.flipped ? 1 : 0,
  );
  late final AnimationController _rotation = AnimationController.unbounded(
    vsync: this,
  );
  final GlobalKey _rowA = GlobalKey();
  final GlobalKey _rowB = GlobalKey();

  double get _travel {
    final a = _rowA.currentContext?.findRenderObject() as RenderBox?;
    final b = _rowB.currentContext?.findRenderObject() as RenderBox?;
    if (a == null || b == null || !a.hasSize || !b.hasSize) {
      return 140;
    }
    return b.localToGlobal(Offset.zero).dy - a.localToGlobal(Offset.zero).dy;
  }

  @override
  void didUpdateWidget(SwapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flipped != widget.flipped) {
      _phase.animateWith(
        springTo(Springs.sheet, _phase.value, widget.flipped ? 1 : 0),
      );
    }
  }

  void _flip() {
    _rotation.animateWith(
      springTo(Springs.pop, _rotation.value, _rotation.value + math.pi),
    );
    widget.onFlip();
  }

  @override
  void dispose() {
    _phase.dispose();
    _rotation.dispose();
    super.dispose();
  }

  Widget _arcChip({required Widget child, required bool a}) {
    return AnimatedBuilder(
      animation: _phase,
      child: child,
      builder: (context, child) {
        final p = _phase.value;
        final arc = math.sin(p * math.pi);
        final sign = a ? 1.0 : -1.0;
        return Transform.translate(
          offset: Offset(sign * arc * _orbitX, sign * p * _travel),
          child: Transform.scale(scale: 1 + arc * 0.06, child: child),
        );
      },
    );
  }

  Widget _eyebrow(String label) {
    return Text(
      label.toUpperCase(),
      style: text(
        11,
        weight: FontWeight.w600,
        color: AppColors.subtle,
        tracking: kTrackingWide,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.amount.isEmpty;
    final display = empty ? '0' : groupThousands(widget.amount);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _eyebrow('From'),
              Row(
                children: [
                  FadeSwapText(
                    text:
                        'Balance ${formatNumber(widget.fromToken.balance)} ${widget.fromToken.symbol}',
                    style: text(12, color: AppColors.subtle),
                  ),
                  const SizedBox(width: 8),
                  PressableScale(
                    scaleTo: 0.9,
                    haptic: HapticKind.selection,
                    onPress: widget.onMax,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'MAX',
                        style: text(
                          11,
                          weight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            key: _rowA,
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _arcChip(
                  a: true,
                  child: TokenChip(
                    token: widget.tokenA,
                    onPress: widget.onPressChipA,
                  ),
                ),
                Row(
                  children: [
                    RollingNumber(
                      value: display,
                      fontSize: _amountSize,
                      color: empty ? AppColors.cents : AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                    const BlinkingCursor(height: _amountSize * 0.72),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned(
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(color: AppColors.outline),
                  ),
                ),
                PressableScale(
                  scaleTo: 0.9,
                  haptic: HapticKind.press,
                  onPress: _flip,
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.outline),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: AnimatedBuilder(
                      animation: _rotation,
                      builder: (context, _) => Transform.rotate(
                        angle: _rotation.value,
                        child: const Icon(
                          LucideIcons.arrowUpDown,
                          size: 22,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _eyebrow('To'),
              FadeSwapText(
                text: widget.rateText,
                style: text(12, color: AppColors.subtle),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            key: _rowB,
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _arcChip(
                  a: false,
                  child: TokenChip(
                    token: widget.tokenB,
                    onPress: widget.onPressChipB,
                  ),
                ),
                RefreshableValue(
                  refreshing: widget.refreshing,
                  shimmerWidth: 96,
                  shimmerHeight: 22,
                  child: RollingNumber(
                    value: widget.toAmountText,
                    fontSize: _amountSize,
                    color: empty ? AppColors.cents : AppColors.ink,
                    fontWeight: FontWeight.w800,
                    keyMode: RollingKeyMode.value,
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

/// Rate, fees, impact and minimum received.
class SwapDetailsCard extends StatelessWidget {
  const SwapDetailsCard({
    super.key,
    required this.quote,
    required this.fromToken,
    required this.toToken,
    required this.refreshing,
  });

  final SwapQuote quote;
  final Token fromToken;
  final Token toToken;
  final bool refreshing;

  Widget _row(String label, int index, Widget child) {
    return Enter(
      kind: EnterKind.fadeInDown,
      delay: Duration(milliseconds: 80 + index * 55),
      duration: const Duration(milliseconds: 360),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: text(13, color: AppColors.subtle)),
            RefreshableValue(
              refreshing: refreshing,
              shimmerWidth: 64,
              shimmerHeight: 14,
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bold = text(13, weight: FontWeight.w700);
    final impactColor = quote.priceImpact < 1 ? AppColors.gain : AppColors.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            'Exchange rate',
            0,
            FadeSwapText(
              text:
                  '1 ${fromToken.symbol} = ${formatRate(quote.rate)} ${toToken.symbol}',
              style: bold,
            ),
          ),
          _row(
            'Estimated fee',
            1,
            RollingNumber(
              value: '\$${quote.feeUsd.toStringAsFixed(2)}',
              fontSize: 13,
              color: AppColors.ink,
              keyMode: RollingKeyMode.value,
            ),
          ),
          _row(
            'Price impact',
            2,
            FadeSwapText(
              text: '${quote.priceImpact.toStringAsFixed(2)}%',
              style: bold.copyWith(color: impactColor),
            ),
          ),
          _row(
            'Network fee',
            3,
            RollingNumber(
              value: '\$${quote.networkFeeUsd.toStringAsFixed(2)}',
              fontSize: 13,
              color: AppColors.ink,
              keyMode: RollingKeyMode.value,
            ),
          ),
          _row(
            'Minimum received',
            4,
            Row(
              children: [
                RollingNumber(
                  value: quote.minReceived.toStringAsFixed(
                    math.min(toToken.displayDecimals, 4),
                  ),
                  fontSize: 13,
                  color: AppColors.ink,
                  keyMode: RollingKeyMode.value,
                ),
                const SizedBox(width: 4),
                FadeSwapText(text: toToken.symbol, style: bold),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const double _routeTrack = 24;
const Duration _routeCycle = Duration(milliseconds: 1700);
const List<double> _routePhases = [0, 0.38, 0.72];

/// The two tokens joined by a hairline with accent particles travelling along it.
class RouteCard extends StatefulWidget {
  const RouteCard({super.key, required this.fromToken, required this.toToken});

  final Token fromToken;
  final Token toToken;

  @override
  State<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<RouteCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _routeCycle,
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final venue = resolveSwapVenue(widget.fromToken, widget.toToken);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _FadingIcon(token: widget.fromToken, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: _routeTrack,
              child: AnimatedBuilder(
                animation: _clock,
                builder: (context, _) =>
                    CustomPaint(painter: _RoutePainter(t: _clock.value)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _FadingIcon(token: widget.toToken, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'VIA',
                style: text(
                  10,
                  weight: FontWeight.w600,
                  color: AppColors.subtle,
                  tracking: kTrackingWide,
                ),
              ),
              FadeSwapText(
                text: venue.label,
                style: text(13, weight: FontWeight.w700),
                alignment: Alignment.centerRight,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, _routeTrack / 2 - 0.5, size.width, 1),
      Paint()..color = AppColors.outline,
    );
    for (final phase in _routePhases) {
      final u = (t + phase) % 1;
      final cx = u * size.width;
      final fade = math.sin(math.pi * u);
      canvas.drawCircle(
        Offset(cx, _routeTrack / 2),
        5.5,
        Paint()
          ..color = AppColors.accent.withValues(
            alpha: (fade * 0.22).clamp(0.0, 1.0),
          ),
      );
      canvas.drawCircle(
        Offset(cx, _routeTrack / 2),
        2.2,
        Paint()
          ..color = AppColors.accent.withValues(
            alpha: (fade * 0.95).clamp(0.0, 1.0),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) => oldDelegate.t != t;
}
