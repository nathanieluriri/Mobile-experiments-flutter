import 'package:flutter/material.dart';

import 'data/library.dart';
import 'screens/desk/desk_screen.dart';
import 'screens/reader/reader_route.dart';
import 'services/document_store.dart';
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

/// What the desk hands the reader: the open document, and the rect of the card
/// it came out of.
///
/// A record rather than a class because the screens on either side of it need
/// nothing beyond these two values: the reader reads its document from the
/// store, and the route grows the sheet from the rect.
typedef ReaderHandoff = ({DocumentStore store, Rect from});

/// The whole app: one ground, one type family, no dark mode and no toggle.
class App extends StatefulWidget {
  const App({super.key, this.routes = const <String, WidgetBuilder>{}});

  /// The screens behind [kDeskRoute], [kReaderRoute] and [kSignRoute].
  ///
  /// A name that is not in here falls back to the app's own ground, except
  /// [kDeskRoute], which falls back to the desk itself.
  final Map<String, WidgetBuilder> routes;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  /// Every document on the desk, made once and kept for as long as the app
  /// runs, so a document remembers its place, its dog ears and its search
  /// index between visits.
  ///
  /// It is null when something else has been given [kDeskRoute], which is what
  /// a test that brings its own library does.
  LibraryStore? _library;

  @override
  void initState() {
    super.initState();
    if (widget.routes.containsKey(kDeskRoute)) return;
    final library = LibraryStore();
    _library = library;
    // The desk's first frame is drawn from the manifest alone, so the six
    // files are read after it rather than before it. The cards are already on
    // the ground when their real page, row and word counts land on them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) library.hydrate();
    });
  }

  @override
  void dispose() {
    _library?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'quire',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
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
    final builder = widget.routes[settings.name];
    if (settings.name == kReaderRoute) {
      final handoff = settings.arguments;
      return ReaderRoute<void>(
        settings: settings,
        from: handoff is ReaderHandoff ? handoff.from : null,
        builder: builder ?? (context) => const _Ground(),
      );
    }
    return MaterialPageRoute<void>(
      settings: settings,
      builder: builder ??
          (settings.name == kDeskRoute ? _desk : (context) => const _Ground()),
    );
  }

  Widget _desk(BuildContext context) {
    final library = _library;
    if (library == null) return const _Ground();
    return DeskScreen(store: library, onOpen: _open, onSign: _sign);
  }

  /// Takes [entry] to the reader, growing the sheet out of its card.
  ///
  /// Nothing happens while no reader has been registered, because a route with
  /// no screen behind it would put the app's bare ground over a working desk
  /// and mark a document read that nobody has read.
  void _open(LibraryEntry entry, Rect cardRect) {
    final library = _library;
    if (library == null || !widget.routes.containsKey(kReaderRoute)) return;
    final document = library.storeFor(entry)..markOpened();
    _navigator.currentState?.pushNamed(
      kReaderRoute,
      arguments: (store: document, from: cardRect),
    );
  }

  /// Takes [entry] to the signature pad.
  void _sign(LibraryEntry entry) {
    final library = _library;
    if (library == null || !widget.routes.containsKey(kSignRoute)) return;
    _navigator.currentState?.pushNamed(
      kSignRoute,
      arguments: library.storeFor(entry),
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
