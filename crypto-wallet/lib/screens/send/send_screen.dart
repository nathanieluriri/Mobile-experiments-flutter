import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/fixtures.dart';
import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/blinking_cursor.dart';
import '../../widgets/enter.dart';
import '../../widgets/fade_swap_text.dart';
import '../../widgets/flow_header.dart';
import '../../widgets/gradient_avatar.dart';
import '../../widgets/haptics.dart';
import '../../widgets/numeric_keyboard.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rolling_number.dart';
import '../../widgets/shimmer.dart';
import '../../widgets/token_icon.dart';
import '../../widgets/token_select_sheet.dart';

const Duration _resolve = Duration(milliseconds: 900);
const Duration _feeRefresh = Duration(milliseconds: 520);

/// Pick a recipient, type an amount and choose the asset to send.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  Token _token = tokens[0];
  bool _sheetOpen = false;
  String _amount = '';
  Recipient? _recipient;
  bool _resolving = false;
  Timer? _resolveTimer;

  bool get _canContinue => _recipient != null && parseAmount(_amount) > 0;

  void _onKey(String key) {
    setState(() {
      _amount = key == kDeleteKey ? deleteAmountKey(_amount) : appendAmountKey(_amount, key);
    });
  }

  void _clear() {
    Haptics.press();
    setState(() => _amount = '');
  }

  void _resolvePasted() {
    _resolveTimer?.cancel();
    setState(() => _resolving = true);
    _resolveTimer = Timer(_resolve, () {
      setState(() {
        _recipient = pastedRecipient;
        _resolving = false;
      });
      Haptics.success();
    });
  }

  void _selectRecipient(Recipient recipient) {
    _resolveTimer?.cancel();
    setState(() {
      _resolving = false;
      _recipient = recipient;
    });
  }

  void _clearRecipient() {
    _resolveTimer?.cancel();
    setState(() {
      _resolving = false;
      _recipient = null;
    });
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: AppColors.screen,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              SizedBox(height: padding.top),
              FlowHeader(
                title: 'Send',
                subtitle: 'Send crypto securely',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight - 12),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 20, right: 20, top: 8),
                                child: Enter(
                                  kind: EnterKind.fadeInDown,
                                  delay: const Duration(milliseconds: 40),
                                  duration: const Duration(milliseconds: 420),
                                  child: RecipientCard(
                                    recipient: _recipient,
                                    resolving: _resolving,
                                    onPastePress: _resolvePasted,
                                    onScanPress: _resolvePasted,
                                    onClear: _clearRecipient,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: Enter(
                                  kind: EnterKind.fadeInDown,
                                  delay: const Duration(milliseconds: 110),
                                  duration: const Duration(milliseconds: 420),
                                  child: RecentRecipients(
                                    recipients: recentRecipients,
                                    onSelect: _selectRecipient,
                                  ),
                                ),
                              ),
                              // Like the source's flex 1 with a zero basis: this
                              // block takes whatever height is left and lets its
                              // glyphs overdraw when there is not enough.
                              Expanded(
                                child: _ZeroIntrinsicHeight(
                                  child: OverflowBox(
                                    alignment: Alignment.center,
                                    minHeight: 0,
                                    maxHeight: double.infinity,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 20),
                                      child: Enter(
                                        kind: EnterKind.fadeInDown,
                                        delay: const Duration(milliseconds: 180),
                                        duration: const Duration(milliseconds: 420),
                                        child: AmountDisplay(value: _amount, token: _token),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Enter(
                                  kind: EnterKind.fadeInDown,
                                  delay: const Duration(milliseconds: 250),
                                  duration: const Duration(milliseconds: 420),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      TokenPicker(
                                        selected: _token,
                                        onPress: () => setState(() => _sheetOpen = true),
                                      ),
                                      const SizedBox(height: 12),
                                      NetworkFeeCard(token: _token),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 12, bottom: padding.bottom + 6),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 12),
                      child: PrimaryButton(enabled: _canContinue, onPress: Haptics.success),
                    ),
                    NumericKeyboard(onKey: _onKey, onClearAll: _clear),
                  ],
                ),
              ),
            ],
          ),
          TokenSelectSheet(
            open: _sheetOpen,
            onClose: () => setState(() => _sheetOpen = false),
            tokens: tokens,
            selectedId: _token.id,
            onSelect: (token) => setState(() => _token = token),
          ),
        ],
      ),
    );
  }
}

/// The amount block's vertical padding, which is also the smallest height a
/// flex item with a zero basis keeps in the original layout engine.
const double _amountBlockFloor = 40;

/// Lays out its child normally but reports only the padding floor as its
/// intrinsic height, so a flexible parent measures it the way a flex basis of
/// 0 behaves and the content overdraws when space is short.
class _ZeroIntrinsicHeight extends SingleChildRenderObjectWidget {
  const _ZeroIntrinsicHeight({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderZeroIntrinsicHeight();
}

class _RenderZeroIntrinsicHeight extends RenderProxyBox {
  @override
  double computeMinIntrinsicHeight(double width) => _amountBlockFloor;

  @override
  double computeMaxIntrinsicHeight(double width) => _amountBlockFloor;
}

const double _amountFontSize = 58;
const int _maxChars = 8;

/// The typed dollar amount with its token equivalent underneath.
class AmountDisplay extends StatefulWidget {
  const AmountDisplay({super.key, required this.value, required this.token});

  final String value;
  final Token token;

  @override
  State<AmountDisplay> createState() => _AmountDisplayState();
}

class _AmountDisplayState extends State<AmountDisplay> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);

  String get _display => '\$${widget.value.isEmpty ? '0' : groupThousands(widget.value)}';

  @override
  void didUpdateWidget(AmountDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = math.min(1.0, _maxChars / _display.length);
    if (target != _scale.value) {
      _scale.animateWith(springTo(Springs.layout, _scale.value, target));
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.value.isEmpty;
    final usd = parseAmount(widget.value);
    final equivalent = formatTokenAmount(usd, widget.token.priceUsd, widget.token.displayDecimals);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _scale,
          builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RollingNumber(
                value: _display,
                fontSize: _amountFontSize,
                color: empty ? AppColors.cents : AppColors.ink,
                fontWeight: FontWeight.w800,
              ),
              const BlinkingCursor(height: _amountFontSize * 0.76),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RollingNumber(
              value: equivalent,
              fontSize: 15,
              color: AppColors.subtle,
              fontWeight: FontWeight.w600,
              keyMode: RollingKeyMode.value,
            ),
            FadeSwapText(
              text: ' ${widget.token.symbol}',
              style: text(15, weight: FontWeight.w600, color: AppColors.subtle),
            ),
          ],
        ),
      ],
    );
  }
}

/// Fee, network and arrival time for the chosen token.
class NetworkFeeCard extends StatefulWidget {
  const NetworkFeeCard({super.key, required this.token});

  final Token token;

  @override
  State<NetworkFeeCard> createState() => _NetworkFeeCardState();
}

class _NetworkFeeCardState extends State<NetworkFeeCard> {
  bool _pending = false;
  Timer? _timer;

  @override
  void didUpdateWidget(NetworkFeeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token.id != widget.token.id) {
      setState(() => _pending = true);
      _timer?.cancel();
      _timer = Timer(_feeRefresh, () => setState(() => _pending = false));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _slot(String label, String value, CrossAxisAlignment align) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label.toUpperCase(),
          style: text(11, weight: FontWeight.w600, color: AppColors.subtle, tracking: kTrackingWide),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 20,
          child: Align(
            alignment: switch (align) {
              CrossAxisAlignment.center => Alignment.center,
              CrossAxisAlignment.end => Alignment.centerRight,
              _ => Alignment.centerLeft,
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _pending
                  ? const Shimmer(key: ValueKey('shimmer'), width: 54, height: 13, radius: 6)
                  : FadeSwapText(key: const ValueKey('value'), text: value, style: text(14, weight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.token;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _slot('Est. fee', '\$${token.feeUsd.toStringAsFixed(2)}', CrossAxisAlignment.start),
          _slot('Network', token.network, CrossAxisAlignment.center),
          _slot('Arrival', token.eta, CrossAxisAlignment.end),
        ],
      ),
    );
  }
}

/// Horizontal row of recent recipients.
class RecentRecipients extends StatelessWidget {
  const RecentRecipients({super.key, required this.recipients, required this.onSelect});

  final List<Recipient> recipients;
  final ValueChanged<Recipient> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 10),
          child: Text(
            'RECENTS',
            style: text(13, weight: FontWeight.w600, color: AppColors.subtle, tracking: kTrackingWide),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              for (var i = 0; i < recipients.length; i++) ...[
                if (i > 0) const SizedBox(width: 20),
                PressableScale(
                  scaleTo: 0.88,
                  haptic: HapticKind.selection,
                  onPress: () => onSelect(recipients[i]),
                  child: Column(
                    children: [
                      GradientAvatar(
                        size: 50,
                        gradient: recipients[i].gradient,
                        label: recipients[i].name,
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 64),
                        child: Text(
                          recipients[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: text(12, weight: FontWeight.w500, color: AppColors.subtle),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Where the money goes: empty, resolving a pasted address, or filled.
class RecipientCard extends StatelessWidget {
  const RecipientCard({
    super.key,
    required this.recipient,
    required this.resolving,
    required this.onPastePress,
    required this.onScanPress,
    required this.onClear,
  });

  final Recipient? recipient;
  final bool resolving;
  final VoidCallback onPastePress;
  final VoidCallback onScanPress;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final empty = recipient == null && !resolving;
    final Widget state;
    if (resolving) {
      state = const _ResolvingState(key: ValueKey('resolving'));
    } else if (recipient != null) {
      state = _FilledState(key: const ValueKey('filled'), recipient: recipient!, onClear: onClear);
    } else {
      state = _EmptyState(key: const ValueKey('empty'), onScanPress: onScanPress);
    }
    return PressableScale(
      scaleTo: 0.98,
      lift: true,
      enabled: empty,
      onPress: onPastePress,
      child: Container(
        height: 78,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          reverseDuration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -25 * (1 - animation.value)),
                  child: child,
                ),
              ),
            );
          },
          child: state,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.onScanPress});

  final VoidCallback onScanPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          CustomPaint(
            painter: _DashedCirclePainter(),
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(child: Icon(LucideIcons.user, size: 18, color: AppColors.subtle)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Paste or scan wallet address',
              style: text(15, weight: FontWeight.w500, color: AppColors.subtle),
            ),
          ),
          PressableScale(
            scaleTo: 0.92,
            onPress: onScanPress,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.chip, shape: BoxShape.circle),
              child: const Icon(LucideIcons.scanQrCode, size: 18, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.cents;
    final radius = size.width / 2 - 0.5;
    const dashes = 14;
    for (var i = 0; i < dashes; i++) {
      final start = i / dashes * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
        start,
        math.pi * 2 / dashes * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) => false;
}

class _ResolvingState extends StatelessWidget {
  const _ResolvingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Shimmer(width: 44, height: 44, radius: 22),
          SizedBox(width: 14),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Shimmer(width: 124, height: 15, radius: 6),
              SizedBox(height: 8),
              Shimmer(width: 88, height: 12, radius: 6),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilledState extends StatelessWidget {
  const _FilledState({super.key, required this.recipient, required this.onClear});

  final Recipient recipient;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Enter(
            kind: EnterKind.fadeIn,
            duration: const Duration(milliseconds: 340),
            child: GradientAvatar(size: 44, gradient: recipient.gradient, label: recipient.name),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(recipient.name, style: text(16, weight: FontWeight.w700)),
                    if (recipient.verified)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Enter(
                          kind: EnterKind.zoomIn,
                          delay: const Duration(milliseconds: 180),
                          springDamping: 14,
                          child: const Icon(LucideIcons.badgeCheck, size: 16, color: AppColors.accent),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Enter(
                  kind: EnterKind.fadeIn,
                  delay: const Duration(milliseconds: 90),
                  child: Text(truncateAddress(recipient.address), style: text(13, color: AppColors.subtle)),
                ),
              ],
            ),
          ),
          PressableScale(
            scaleTo: 0.92,
            onPress: onClear,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.chip, shape: BoxShape.circle),
              child: const Icon(LucideIcons.x, size: 16, color: AppColors.subtle),
            ),
          ),
        ],
      ),
    );
  }
}

/// The asset being sent, opening the token sheet.
class TokenPicker extends StatelessWidget {
  const TokenPicker({super.key, required this.selected, required this.onPress});

  final Token selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scaleTo: 0.98,
      lift: true,
      onPress: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              reverseDuration: const Duration(milliseconds: 140),
              child: TokenIcon(key: ValueKey(selected.id), id: selected.id, size: 42),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PAY WITH',
                    style: text(11, weight: FontWeight.w600, color: AppColors.subtle, tracking: kTrackingWide),
                  ),
                  const SizedBox(height: 2),
                  FadeSwapText(text: selected.name, style: text(16, weight: FontWeight.w700)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FadeSwapText(
                    text: '${formatNumber(selected.balance)} ${selected.symbol}',
                    style: text(14, weight: FontWeight.w600),
                    alignment: Alignment.centerRight,
                  ),
                  const SizedBox(height: 2),
                  FadeSwapText(
                    text: '\$${formatFiat(selected.balance * selected.priceUsd)}',
                    style: text(13, color: AppColors.subtle),
                    alignment: Alignment.centerRight,
                  ),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.chip, shape: BoxShape.circle),
              child: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.subtle),
            ),
          ],
        ),
      ),
    );
  }
}
