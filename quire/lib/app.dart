import 'package:flutter/material.dart';

import 'theme/colors.dart';
import 'theme/typography.dart';
import 'widgets/dissolve/dissolve_scope.dart';

/// The desk, where every document lives.
const kDeskRoute = '/';

/// The reader, pushed over the desk on a route that is not opaque, so the desk
/// stays mounted underneath and a back drag can reveal it.
const kReaderRoute = '/read';

/// The signature pad.
const kSignRoute = '/sign';

/// The whole app: one ground, one type family, no dark mode and no toggle.
class App extends StatelessWidget {
  const App({super.key, this.routes = const <String, WidgetBuilder>{}});

  /// The screens behind [kDeskRoute], [kReaderRoute] and [kSignRoute].
  final Map<String, WidgetBuilder> routes;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'quire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: kFontFamily,
        scaffoldBackgroundColor: AppColors.deskGround,
        canvasColor: AppColors.deskGround,
        // Every tappable object in this app presses through PaperPress, so the
        // Material ink would be a second, contradictory answer to a finger.
        splashFactory: NoSplash.splashFactory,
        highlightColor: const Color(0x00000000),
        colorScheme: const ColorScheme.light(
          surface: AppColors.leaf,
          primary: AppColors.ink,
        ),
      ),
      initialRoute: kDeskRoute,
      onGenerateRoute: _route,
      onUnknownRoute: _route,
      // The scope sits above the Navigator, so a card can come apart over the
      // whole screen and keep going while the screen under it changes.
      builder: (context, child) =>
          DissolveScope(child: child ?? const _Ground()),
    );
  }

  Route<void> _route(RouteSettings settings) {
    final builder = routes[settings.name];
    return MaterialPageRoute<void>(
      settings: settings,
      builder: builder ?? (context) => const _Ground(),
    );
  }
}

/// The bare desk. What is left when a route has nothing behind it, so a wrong
/// name shows the app's own ground rather than an error screen.
class _Ground extends StatelessWidget {
  const _Ground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.deskGround,
      child: SizedBox.expand(),
    );
  }
}
