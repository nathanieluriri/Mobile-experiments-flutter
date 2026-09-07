import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/fixtures.dart';
import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/enter.dart';
import '../../widgets/flow_header.dart';
import '../../widgets/haptics.dart';
import '../../widgets/loading_ring.dart';
import '../../widgets/numeric_keyboard.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/token_icon.dart';
import '../../widgets/token_select_sheet.dart';
import 'swap_widgets.dart';

const Duration _quoteDelay = Duration(milliseconds: 380);

/// Exchange one token for another.
class SwapScreen extends StatefulWidget {
  const SwapScreen({super.key});

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  Token _tokenA = tokens[0];
  Token _tokenB = tokens[1];
  bool _flipped = false;
  SwapSlot? _sheetSlot;
  bool _confirming = false;
  String _amount = '';
  late SwapQuote _quote = computeSwapQuote(_fromToken, _toToken, 0);
  bool _refreshing = false;
  Timer? _quoteTimer;

  Token get _fromToken => _flipped ? _tokenB : _tokenA;
  Token get _toToken => _flipped ? _tokenA : _tokenB;
  double get _amountNum => parseAmount(_amount);

  void _requote() {
    setState(() => _refreshing = true);
    _quoteTimer?.cancel();
    _quoteTimer = Timer(_quoteDelay, () {
      setState(() {
        _quote = computeSwapQuote(_fromToken, _toToken, _amountNum);
        _refreshing = false;
      });
    });
  }

  void _setAmount(String amount) {
    if (amount == _amount) {
      return;
    }
    setState(() => _amount = amount);
    _requote();
  }

  void _onKey(String key) {
    _setAmount(
      key == kDeleteKey
          ? deleteAmountKey(_amount)
          : appendAmountKey(_amount, key, maxDecimals: _fromToken.displayDecimals),
    );
  }

  void _clear() {
    Haptics.press();
    _setAmount('');
  }

  void _flip() {
    setState(() => _flipped = !_flipped);
    _requote();
  }

  void _select(Token token) {
    final slot = _sheetSlot;
    if (slot == null) {
      return;
    }
    final other = slot == SwapSlot.a ? _tokenB : _tokenA;
    if (token.id == other.id) {
      _flip();
      return;
    }
    setState(() {
      if (slot == SwapSlot.a) {
        _tokenA = token;
      } else {
        _tokenB = token;
      }
    });
    _requote();
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final from = _fromToken;
    final to = _toToken;
    final toAmountText = _quote.toAmount.toStringAsFixed(math.min(to.displayDecimals, 4));
    final rateText = '1 ${from.symbol} = ${formatRate(_quote.rate)} ${to.symbol}';
    final summary = '${formatNumber(_amountNum)} ${from.symbol} → $toAmountText ${to.symbol}';
    final insufficient = _amountNum > from.balance;
    final canSwap = _amountNum > 0 && !insufficient && !_refreshing;

    return Scaffold(
      backgroundColor: AppColors.screen,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              SizedBox(height: padding.top),
              FlowHeader(
                title: 'Swap',
                subtitle: 'Exchange assets instantly',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Enter(
                          kind: EnterKind.fadeInDown,
                          delay: const Duration(milliseconds: 40),
                          duration: const Duration(milliseconds: 420),
                          child: SwapCard(
                            tokenA: _tokenA,
                            tokenB: _tokenB,
                            flipped: _flipped,
                            fromToken: from,
                            amount: _amount,
                            toAmountText: toAmountText,
                            rateText: rateText,
                            refreshing: _refreshing,
                            onFlip: _flip,
                            onPressChipA: () => setState(() => _sheetSlot = SwapSlot.a),
                            onPressChipB: () => setState(() => _sheetSlot = SwapSlot.b),
                            onMax: () => _setAmount(formatNumber(from.balance)),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12, left: 20, right: 20),
                        child: Enter(
                          kind: EnterKind.fadeInDown,
                          delay: const Duration(milliseconds: 130),
                          duration: const Duration(milliseconds: 420),
                          child: SwapDetailsCard(
                            quote: _quote,
                            fromToken: from,
                            toToken: to,
                            refreshing: _refreshing,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12, left: 20, right: 20),
                        child: Enter(
                          kind: EnterKind.fadeInDown,
                          delay: const Duration(milliseconds: 210),
                          duration: const Duration(milliseconds: 420),
                          child: RouteCard(fromToken: from, toToken: to),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 12, bottom: padding.bottom + 6),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 12),
                      child: PrimaryButton(
                        enabled: canSwap,
                        onPress: () => setState(() => _confirming = true),
                        label: insufficient ? 'Insufficient ${from.symbol}' : 'Swap',
                      ),
                    ),
                    NumericKeyboard(onKey: _onKey, onClearAll: _clear),
                  ],
                ),
              ),
            ],
          ),
          TokenSelectSheet(
            open: _sheetSlot != null,
            onClose: () => setState(() => _sheetSlot = null),
            tokens: tokens,
            selectedId: (_sheetSlot == SwapSlot.b ? _tokenB : _tokenA).id,
            onSelect: _select,
            searchable: true,
          ),
          if (_confirming)
            SwapConfirmation(
              fromToken: from,
              toToken: to,
              summary: summary,
              onDone: () {
                setState(() {
                  _confirming = false;
                  _amount = '';
                });
                _requote();
              },
            ),
        ],
      ),
    );
  }
}

const Duration _processing = Duration(milliseconds: 1900);
const double _ring = 136;
const double _iconApart = 46;
const double _iconClose = 20;

/// Processing then success, in a centred card over a blurred screen.
class SwapConfirmation extends StatefulWidget {
  const SwapConfirmation({
    super.key,
    required this.fromToken,
    required this.toToken,
    required this.summary,
    required this.onDone,
  });

  final Token fromToken;
  final Token toToken;
  final String summary;
  final VoidCallback onDone;

  @override
  State<SwapConfirmation> createState() => _SwapConfirmationState();
}

class _SwapConfirmationState extends State<SwapConfirmation> with TickerProviderStateMixin {
  bool _success = false;
  Timer? _timer;
  late final AnimationController _approach = AnimationController.unbounded(vsync: this)
    ..animateWith(springTo(Springs.sheet, 0, 1));
  late final AnimationController _cardScale = AnimationController.unbounded(vsync: this, value: 0.92)
    ..animateWith(springTo(Springs.pop, 0.92, 1));
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();

  @override
  void initState() {
    super.initState();
    _timer = Timer(_processing, () {
      if (!mounted) {
        return;
      }
      setState(() => _success = true);
      Haptics.success();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _approach.dispose();
    _cardScale.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: _fade,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: const ColoredBox(color: Color(0x40000000)),
            ),
          ),
        ),
        Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_cardScale, _fade]),
            builder: (context, child) {
              return Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _cardScale.value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - _fade.value)),
                    child: child,
                  ),
                ),
              );
            },
            child: Container(
              width: width * 0.8,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                reverseDuration: const Duration(milliseconds: 180),
                child: _success ? _successStage() : _processingStage(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _processingStage() {
    return Column(
      key: const ValueKey('processing'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _ring,
          height: _ring,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const LoadingRing(size: _ring),
              AnimatedBuilder(
                animation: _approach,
                builder: (context, _) {
                  final a = _approach.value;
                  final shift = _iconApart - a * (_iconApart - _iconClose);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(-shift, 0),
                        child: TokenIcon(id: widget.fromToken.id, size: 40),
                      ),
                      Transform.translate(
                        offset: Offset(shift, 0),
                        child: TokenIcon(id: widget.toToken.id, size: 40),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Swapping', style: text(16, weight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(widget.summary, style: text(13, color: AppColors.subtle)),
      ],
    );
  }

  Widget _successStage() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Enter(
            kind: EnterKind.zoomIn,
            delay: const Duration(milliseconds: 80),
            springDamping: 13,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.gainSoft, shape: BoxShape.circle),
              child: const Icon(LucideIcons.check, size: 28, color: AppColors.gain),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Swap Complete', textAlign: TextAlign.center, style: text(18, weight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(widget.summary, textAlign: TextAlign.center, style: text(13, color: AppColors.subtle)),
        const SizedBox(height: 24),
        PressableScale(
          haptic: HapticKind.press,
          onPress: widget.onDone,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text('Done', style: text(15, weight: FontWeight.w700, color: AppColors.white)),
          ),
        ),
      ],
    );
  }
}
