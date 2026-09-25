import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/fixtures.dart';
import '../../data/models.dart';
import '../../painting/glyphs.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/enter.dart';
import '../../widgets/fade_swap_text.dart';
import '../../widgets/flow_header.dart';
import '../../widgets/haptics.dart';
import '../../widgets/pressable_scale.dart';
import '../../widgets/shimmer.dart';

const Duration _load = Duration(milliseconds: 900);
const Duration _copiedReset = Duration(milliseconds: 1100);
const double _qrSize = 204;
const String _infoMessage =
    'Only send supported assets to this address. Sending unsupported assets may permanently result in loss of funds.';

/// Your address as a QR code, per network, with recent incoming transfers.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  Network _network = networks[0];
  bool _sheetOpen = false;
  bool _loading = true;
  Timer? _loadTimer;

  @override
  void initState() {
    super.initState();
    _loadTimer = Timer(_load, () => setState(() => _loading = false));
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
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
                title: 'Receive',
                subtitle: 'Receive crypto instantly',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 8,
                    bottom: padding.bottom + 24,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: const Threshold(0),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, ?current],
                    ),
                    child: _loading
                        ? const ReceiveSkeleton()
                        : Column(
                            key: const ValueKey('content'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Enter(
                                kind: EnterKind.fadeInDown,
                                delay: const Duration(milliseconds: 40),
                                duration: const Duration(milliseconds: 420),
                                child: ReceiveCard(
                                  network: _network,
                                  onNetworkPress: () =>
                                      setState(() => _sheetOpen = true),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Enter(
                                kind: EnterKind.fadeInDown,
                                delay: const Duration(milliseconds: 110),
                                duration: const Duration(milliseconds: 420),
                                child: AddressActions(network: _network),
                              ),
                              const SizedBox(height: 16),
                              Enter(
                                kind: EnterKind.fadeInDown,
                                delay: const Duration(milliseconds: 180),
                                duration: const Duration(milliseconds: 420),
                                child: const InfoCard(message: _infoMessage),
                              ),
                              const SizedBox(height: 24),
                              Enter(
                                kind: EnterKind.fadeInDown,
                                delay: const Duration(milliseconds: 250),
                                duration: const Duration(milliseconds: 420),
                                child: const ReceiveHistory(
                                  transactions: incomingTransactions,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          NetworkSheet(
            open: _sheetOpen,
            onClose: () => setState(() => _sheetOpen = false),
            networks: networks,
            selected: _network,
            onSelect: (network) => setState(() => _network = network),
          ),
        ],
      ),
    );
  }
}

/// The network's brand badge.
class NetworkIcon extends StatelessWidget {
  const NetworkIcon({super.key, required this.id, this.size = 24});

  final NetworkId id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.58;
    final (Color background, Widget glyph) = switch (id) {
      NetworkId.ethereum => (
        const Color(0xFF627EEA),
        EthGlyph(size: iconSize, color: AppColors.white),
      ),
      NetworkId.base => (
        const Color(0xFF0052FF),
        Container(
          width: size * 0.55,
          height: size * 0.55,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.white,
              width: (size * 0.11).clamp(2.0, double.infinity),
            ),
          ),
        ),
      ),
      NetworkId.solana => (
        const Color(0xFF101014),
        SolanaBars(
          barWidth: size * 0.4,
          barHeight: size * 0.08,
          gap: size * 0.08,
        ),
      ),
      NetworkId.polygon => (
        const Color(0xFF8247E5),
        Icon(LucideIcons.hexagon, size: iconSize, color: AppColors.white),
      ),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: glyph,
    );
  }
}

const Duration _sweepDelay = Duration(milliseconds: 650);
const Duration _sweepDuration = Duration(milliseconds: 850);

/// The address as rounded QR modules with a highlight sweeping across once.
class AddressQr extends StatefulWidget {
  const AddressQr({super.key, required this.value, required this.size});

  final String value;
  final double size;

  @override
  State<AddressQr> createState() => _AddressQrState();
}

class _AddressQrState extends State<AddressQr> with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _sweepDuration,
  );
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 0.92,
  )..animateWith(springTo(Springs.pop, 0.92, 1));
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();
  Timer? _delay;
  late QrImage _image = _encode(widget.value);

  static QrImage _encode(String value) {
    final code = QrCode.fromData(
      data: value,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    return QrImage(code);
  }

  @override
  void initState() {
    super.initState();
    _delay = Timer(_sweepDelay, () {
      if (mounted) {
        _sweep.forward(from: 0);
      }
    });
  }

  @override
  void didUpdateWidget(AddressQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _image = _encode(widget.value);
      _delay?.cancel();
      _sweep.value = 0;
      _delay = Timer(_sweepDelay, () {
        if (mounted) {
          _sweep.forward(from: 0);
        }
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _sweep.dispose();
    _scale.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_sweep, _scale, _fade]),
      builder: (context, _) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.scale(
            scale: _scale.value,
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _QrPainter(
                image: _image,
                sweep: -0.6 + Eases.iosInOut.transform(_sweep.value) * 2.2,
                sweeping: _sweep.isAnimating,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter({
    required this.image,
    required this.sweep,
    required this.sweeping,
  });

  final QrImage image;
  final double sweep;
  final bool sweeping;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final cell = size.width / count;
    final inset = cell * 0.08;
    final dot = cell * 0.84;
    final radius = Radius.circular(cell * 0.3);
    final paint = Paint()..color = AppColors.ink;
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (image.isDark(row, col)) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(col * cell + inset, row * cell + inset, dot, dot),
              radius,
            ),
            paint,
          );
        }
      }
    }
    if (!sweeping) {
      return;
    }
    final s = size.width;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(sweep * s, sweep * s - s * 0.4),
          Offset(sweep * s + s * 0.45, sweep * s + s * 0.05),
          const [Color(0x00FFFFFF), Color(0xB3FFFFFF), Color(0x00FFFFFF)],
          const [0, 0.5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.sweep != sweep ||
      oldDelegate.sweeping != sweeping;
}

/// Copies [value] and shows a check for a moment.
class _CopyState extends ChangeNotifier {
  bool copied = false;
  Timer? _timer;

  void copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    Haptics.success();
    copied = true;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(_copiedReset, () {
      copied = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _CopyChip extends StatefulWidget {
  const _CopyChip({required this.address});

  final String address;

  @override
  State<_CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<_CopyChip> {
  final _CopyState _copy = _CopyState();

  @override
  void dispose() {
    _copy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _copy,
      builder: (context, _) {
        return PressableScale(
          scaleTo: 0.9,
          haptic: HapticKind.none,
          onPress: () => _copy.copy(widget.address),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.chip,
              shape: BoxShape.circle,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              reverseDuration: const Duration(milliseconds: 120),
              child: _copy.copied
                  ? const Icon(
                      LucideIcons.check,
                      key: ValueKey('check'),
                      size: 14,
                      color: AppColors.gain,
                    )
                  : const Icon(
                      LucideIcons.copy,
                      key: ValueKey('copy'),
                      size: 14,
                      color: AppColors.ink,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Network chip, QR code, truncated address and caption.
class ReceiveCard extends StatelessWidget {
  const ReceiveCard({
    super.key,
    required this.network,
    required this.onNetworkPress,
  });

  final Network network;
  final VoidCallback onNetworkPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 24, bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          PressableScale(
            scaleTo: 0.95,
            haptic: HapticKind.selection,
            onPress: onNetworkPress,
            child: Container(
              padding: const EdgeInsets.only(
                left: 8,
                right: 12,
                top: 6,
                bottom: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.chip,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    reverseDuration: const Duration(milliseconds: 140),
                    child: NetworkIcon(
                      key: ValueKey(network.id),
                      id: network.id,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FadeSwapText(
                    text: network.name,
                    style: text(13, weight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    LucideIcons.chevronDown,
                    size: 14,
                    color: AppColors.subtle,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AddressQr(
            key: ValueKey(network.address),
            value: network.address,
            size: _qrSize,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeSwapText(
                text: truncateAddress(network.address),
                style: text(15, weight: FontWeight.w600),
              ),
              const SizedBox(width: 10),
              _CopyChip(address: network.address),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Your ${network.name} address',
            style: text(12, color: AppColors.subtle),
          ),
        ],
      ),
    );
  }
}

/// Copy and share buttons under the card.
class AddressActions extends StatefulWidget {
  const AddressActions({super.key, required this.network});

  final Network network;

  @override
  State<AddressActions> createState() => _AddressActionsState();
}

class _AddressActionsState extends State<AddressActions> {
  final _CopyState _copy = _CopyState();

  @override
  void dispose() {
    _copy.dispose();
    super.dispose();
  }

  Widget _button({
    required Widget icon,
    required String label,
    required Color color,
    required VoidCallback onPress,
    HapticKind haptic = HapticKind.tap,
  }) {
    return Expanded(
      child: PressableScale(
        lift: true,
        liftRadius: 20,
        haptic: haptic,
        onPress: onPress,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 8),
              FadeSwapText(
                text: label,
                style: text(15, weight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _copy,
      builder: (context, _) {
        final copied = _copy.copied;
        return Row(
          children: [
            _button(
              icon: Icon(
                copied ? LucideIcons.check : LucideIcons.copy,
                size: 16,
                color: copied ? AppColors.gain : AppColors.ink,
              ),
              label: copied ? 'Copied' : 'Copy Address',
              color: copied ? AppColors.gain : AppColors.ink,
              haptic: HapticKind.none,
              onPress: () => _copy.copy(widget.network.address),
            ),
            const SizedBox(width: 12),
            _button(
              icon: const Icon(
                LucideIcons.share,
                size: 16,
                color: AppColors.ink,
              ),
              label: 'Share QR',
              color: AppColors.ink,
              onPress: () {},
            ),
          ],
        );
      },
    );
  }
}

/// A warning about unsupported assets.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.info,
              size: 16,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: text(13, color: AppColors.subtle, lineHeight: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recent incoming transfers.
class ReceiveHistory extends StatelessWidget {
  const ReceiveHistory({super.key, required this.transactions});

  final List<IncomingTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'RECENT ACTIVITY',
            style: text(
              13,
              weight: FontWeight.w600,
              color: AppColors.subtle,
              tracking: kTrackingWide,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              for (var i = 0; i < transactions.length; i++)
                Enter(
                  kind: EnterKind.fadeInDown,
                  delay: Duration(milliseconds: 120 + i * 80),
                  duration: const Duration(milliseconds: 380),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.gainSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.arrowDownLeft,
                            size: 17,
                            color: AppColors.gain,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                transactions[i].from,
                                style: text(15, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                transactions[i].time,
                                style: text(12, color: AppColors.subtle),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              transactions[i].amount,
                              style: text(
                                15,
                                weight: FontWeight.w700,
                                color: AppColors.gain,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              transactions[i].fiat,
                              style: text(12, color: AppColors.subtle),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shimmer placeholders shaped like the receive layout.
class ReceiveSkeleton extends StatelessWidget {
  const ReceiveSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.sizeOf(context).width - 40;
    final actionWidth = (cardWidth - 12) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: 20,
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(
            children: [
              Shimmer(width: 122, height: 30, radius: 15),
              SizedBox(height: 20),
              Shimmer(width: 204, height: 204, radius: 16),
              SizedBox(height: 20),
              Shimmer(width: 168, height: 16, radius: 7),
              SizedBox(height: 8),
              Shimmer(width: 110, height: 12, radius: 6),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Shimmer(width: actionWidth, height: 52, radius: 20),
            const SizedBox(width: 12),
            Shimmer(width: actionWidth, height: 52, radius: 20),
          ],
        ),
        const SizedBox(height: 16),
        Shimmer(width: cardWidth, height: 64, radius: 22),
        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerLeft,
          child: Shimmer(width: 128, height: 13, radius: 6),
        ),
        const SizedBox(height: 12),
        Shimmer(width: cardWidth, height: 190, radius: 24),
      ],
    );
  }
}

/// Choose which network's address to show.
class NetworkSheet extends StatelessWidget {
  const NetworkSheet({
    super.key,
    required this.open,
    required this.onClose,
    required this.networks,
    required this.selected,
    required this.onSelect,
  });

  final bool open;
  final VoidCallback onClose;
  final List<Network> networks;
  final Network selected;
  final ValueChanged<Network> onSelect;

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      open: open,
      onClose: onClose,
      title: 'Choose network',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, network) in networks.indexed)
            PressableScale(
              key: ValueKey(network.id),
              scaleTo: 0.98,
              haptic: HapticKind.selection,
              onPress: () {
                if (network.id != selected.id) {
                  onSelect(network);
                  Haptics.press();
                }
                onClose();
              },
              child: Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: network.id == selected.id
                        ? AppColors.accentSoft.withValues(alpha: 0.6)
                        : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      NetworkIcon(id: network.id, size: 42),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              network.name,
                              style: text(16, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              truncateAddress(network.address),
                              style: text(13, color: AppColors.subtle),
                            ),
                          ],
                        ),
                      ),
                      if (network.id == selected.id)
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Icon(
                            LucideIcons.circleCheck,
                            size: 18,
                            color: AppColors.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
