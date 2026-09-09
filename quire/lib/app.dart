import 'package:flutter/material.dart';

import 'data/library.dart';
import 'painting/signature_painter.dart';
import 'screens/desk/desk_screen.dart';
import 'screens/reader/reader_host.dart';
import 'screens/reader/reader_route.dart';
import 'screens/reader/sheet_surface.dart';
import 'screens/sign/sign_screen.dart';
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

/// The whole app: one ground, one type family, one theme and no toggle.
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

  /// The signature the pad has just finished, and the document it was drawn
  /// for. It is held here for the one push between the pad and the reader,
  /// because a mark that has been made and not yet placed belongs to neither
  /// screen.
  SignatureMark? _mark;
  DocumentStore? _signing;

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
        brightness: Brightness.dark,
        fontFamily: kFontFamily,
        scaffoldBackgroundColor: AppColors.ground,
        canvasColor: AppColors.ground,
        dividerColor: AppColors.hairline,
        // Every tappable object in this app presses through PaperPress, so the
        // Material ink would be a second, contradictory answer to a finger.
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.ink),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AppColors.accentBright,
          selectionColor: AppColors.foundWash,
          selectionHandleColor: AppColors.accentBright,
        ),
        // Every role is stated, including the ones nothing in the app asks
        // for, so a widget that reaches past the palette for a colour cannot
        // land on a Material default and put a stray blue or a stray white
        // into a dark screen.
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          onPrimary: AppColors.onAccent,
          primaryContainer: AppColors.accentMuted,
          onPrimaryContainer: AppColors.ink,
          secondary: AppColors.accentBright,
          onSecondary: AppColors.onAccentBright,
          secondaryContainer: AppColors.accentMuted,
          onSecondaryContainer: AppColors.ink,
          tertiary: AppColors.accentPale,
          onTertiary: AppColors.onAccentBright,
          tertiaryContainer: AppColors.surfaceHigh,
          onTertiaryContainer: AppColors.ink,
          error: AppColors.damage,
          onError: AppColors.onAccentBright,
          errorContainer: AppColors.surfaceHigh,
          onErrorContainer: AppColors.damage,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
          surfaceContainerLowest: AppColors.ground,
          surfaceContainerLow: AppColors.surface,
          surfaceContainer: AppColors.surface,
          surfaceContainerHigh: AppColors.surfaceHigh,
          surfaceContainerHighest: AppColors.surfaceHigh,
          onSurfaceVariant: AppColors.inkSoft,
          outline: AppColors.hairline,
          outlineVariant: AppColors.hairlineFaint,
          inverseSurface: AppColors.ink,
          onInverseSurface: AppColors.ground,
          inversePrimary: AppColors.accentBright,
          scrim: AppColors.scrim,
          // Nothing in this app casts one, and stating it here means nothing
          // can quietly start.
          shadow: Colors.transparent,
          surfaceTint: Colors.transparent,
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
        builder:
            builder ??
            (context) => handoff is ReaderHandoff
                ? _reader(handoff.store)
                : const _Ground(),
      );
    }
    if (settings.name == kSignRoute) {
      final store = settings.arguments;
      return MaterialPageRoute<void>(
        settings: settings,
        builder:
            builder ??
            (context) =>
                store is DocumentStore ? _pad(store) : const _Ground(),
      );
    }
    return MaterialPageRoute<void>(
      settings: settings,
      builder:
          builder ??
          (settings.name == kDeskRoute ? _desk : (context) => const _Ground()),
    );
  }

  /// The reader, holding [store] and whatever is waiting to be set into it.
  Widget _reader(DocumentStore store) => ReaderHost(
    store: store,
    placing: identical(store, _signing) ? _mark : null,
    onPlaced: () {
      _mark = null;
      _signing = null;
    },
  );

  /// The pad, and the one thing that happens when a signature leaves it: the
  /// document it was drawn for opens, with the mark in hand.
  Widget _pad(DocumentStore store) => SignScreen(
    onBack: () => _navigator.currentState?.maybePop<void>(),
    onCommit: (mark) => _placeOn(store, mark),
  );

  /// Carries [mark] from the pad to the page.
  ///
  /// The pad is left rather than stacked under the reader: the mark exists
  /// now, and the only thing left to decide is where on the page it goes.
  void _placeOn(DocumentStore store, SignatureMark mark) {
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    _mark = mark;
    _signing = store;
    store.markOpened();
    navigator.pop();
    navigator.pushNamed(
      kReaderRoute,
      arguments: (store: store, from: kSheetRect),
    );
  }

  Widget _desk(BuildContext context) {
    final library = _library;
    if (library == null) return const _Ground();
    return DeskScreen(store: library, onOpen: _open, onSign: _sign);
  }

  /// Takes [entry] to the reader, growing the sheet out of its card.
  void _open(LibraryEntry entry, Rect cardRect) {
    final library = _library;
    if (library == null) return;
    final document = library.storeFor(entry)..markOpened();
    _navigator.currentState?.pushNamed(
      kReaderRoute,
      arguments: (store: document, from: cardRect),
    );
  }

  /// Takes [entry] to the signature pad.
  void _sign(LibraryEntry entry) {
    final library = _library;
    if (library == null) return;
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
      color: AppColors.ground,
      child: SizedBox.expand(),
    );
  }
}
