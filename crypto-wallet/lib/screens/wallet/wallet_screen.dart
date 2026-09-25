import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/fixtures.dart';
import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/random.dart';
import '../../widgets/apple_spinner.dart';
import 'asset_list.dart';
import 'balance_display.dart';
import 'wallet_action_bar.dart';
import 'wallet_header.dart';
import 'wallet_refresh_controller.dart';

const double kInitialBalance = 2378.12;
const Gain kInitialGain = Gain(amount: 52.36, percent: 1.74);
const Duration kAutoRefreshDelay = Duration(milliseconds: 1200);

const double kPullTrigger = 44;
const double kPullMax = 92;
const double kPullDamping = 0.45;
const double kHeaderShift = 52;

/// The home screen: balance card, action band and holdings. Pull down or tap
/// the balance to refresh.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with TickerProviderStateMixin {
  late final WalletRefreshController _controller = WalletRefreshController(
    vsync: this,
    initialBalance: kInitialBalance,
    initialGain: kInitialGain,
    random: appRandom,
  );
  late final AnimationController _pull = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _autoRefresh;
  double _dragTotal = 0;

  @override
  void initState() {
    super.initState();
    _autoRefresh = Timer(kAutoRefreshDelay, _controller.refresh);
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _pull.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _pull.stop();
    _dragTotal = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragTotal += details.delta.dy;
    final drag = math.max(0.0, _dragTotal) * kPullDamping;
    _pull.value = math.min(kPullMax, drag);
  }

  void _onDragEnd([DragEndDetails? details]) {
    if (_pull.value >= kPullTrigger) {
      _controller.refresh();
    }
    _pull.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Eases.ios,
    );
  }

  void _open(String route) => Navigator.of(context).pushNamed(route);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: AppColors.band,
        child: GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          onVerticalDragCancel: _onDragEnd,
          child: Column(
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([_controller, _pull]),
                builder: (context, _) {
                  final spacer = _pull.value + _controller.shift * kHeaderShift;
                  final visibility = math.max(
                    _controller.spinner,
                    math.min(1.0, _pull.value / kPullTrigger),
                  );
                  return ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(36),
                    ),
                    child: ColoredBox(
                      color: AppColors.white,
                      child: Stack(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: top, bottom: 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(height: spacer),
                                const SizedBox(height: 16),
                                const WalletHeader(profile: walletProfile),
                                const SizedBox(height: 24),
                                BalanceDisplay(controller: _controller),
                              ],
                            ),
                          ),
                          Positioned(
                            top: top + 4,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: AppleSpinner(visibility: visibility),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              WalletActionBar(
                onReceive: () => _open('/receive'),
                onSend: () => _open('/send'),
                onSwap: () => _open('/swap'),
                onIpo: () => _open('/ipo'),
              ),
              const Expanded(child: AssetList(assets: walletAssets)),
            ],
          ),
        ),
      ),
    );
  }
}
