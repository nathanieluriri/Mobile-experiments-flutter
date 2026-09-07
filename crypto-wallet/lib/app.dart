import 'package:flutter/material.dart';

import 'screens/wallet/wallet_screen.dart';
import 'theme/theme.dart';

/// Route names.
abstract final class Routes {
  static const wallet = '/';
  static const send = '/send';
  static const receive = '/receive';
  static const swap = '/swap';
  static const ipo = '/ipo';
}

class App extends StatelessWidget {
  const App({super.key, this.initialRoute = Routes.wallet});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crypto Wallet',
      debugShowCheckedModeBanner: false,
      color: AppColors.band,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: kFontFamily,
        scaffoldBackgroundColor: AppColors.screen,
        splashFactory: NoSplash.splashFactory,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          surface: AppColors.screen,
          onSurface: AppColors.ink,
        ),
      ),
      initialRoute: initialRoute,
      onGenerateRoute: generateRoute,
    );
  }
}

/// Builds every named route. Flows slide up over the wallet, which scales
/// back, rounds its corners and dims behind them.
Route<void> generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case Routes.send:
      return FlowRoute(settings: settings, builder: (_) => const _Placeholder('Send'));
    case Routes.receive:
      return FlowRoute(settings: settings, builder: (_) => const _Placeholder('Receive'));
    case Routes.swap:
      return FlowRoute(settings: settings, builder: (_) => const _Placeholder('Swap'));
    case Routes.ipo:
      return FlowRoute(settings: settings, builder: (_) => const _Placeholder('IPO'));
    case Routes.wallet:
    default:
      return WalletRoute(settings: settings, builder: (_) => const WalletScreen());
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(title)));
  }
}

final SpringCurve _screenCurve = SpringCurve(Springs.screen);

/// A flow screen that slides up from the bottom on the screen spring.
class FlowRoute<T> extends PageRoute<T> {
  FlowRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => false;

  @override
  Duration get transitionDuration => _screenCurve.duration;

  @override
  Duration get reverseTransitionDuration => _screenCurve.duration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final height = MediaQuery.sizeOf(context).height;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final p = _screenCurve.transform(animation.value);
        return Transform.translate(offset: Offset(0, (1 - p) * height), child: child);
      },
    );
  }
}

/// The wallet route: recedes, rounds and dims while a flow is on top.
class WalletRoute<T> extends PageRoute<T> {
  WalletRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: secondaryAnimation,
      child: child,
      builder: (context, child) {
        final q = _screenCurve.transform(secondaryAnimation.value);
        return ColoredBox(
          color: AppColors.band,
          child: Transform.scale(
            scale: 1 - q * 0.06,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(q * 28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child!,
                  IgnorePointer(
                    child: ColoredBox(color: Colors.black.withValues(alpha: q * 0.3)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
