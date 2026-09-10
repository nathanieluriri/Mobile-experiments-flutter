import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data/library.dart';
import 'painting/signature_painter.dart';
import 'screens/desk/desk_screen.dart';
import 'screens/reader/reader_host.dart';
import 'screens/reader/reader_route.dart';
import 'screens/sign/sign_screen.dart';
import 'services/document_store.dart';
import 'services/library_catalogue.dart';
import 'theme/colors.dart';
import 'theme/metrics.dart';
import 'theme/typography.dart';
import 'widgets/dissolve/dissolve_scope.dart';
import 'widgets/quire_spinner.dart';

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
typedef ReaderHandoff = ({DocumentStore store});

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
    final library = LibraryStore(catalogue: LibraryCatalogue());
    _library = library;
    // The desk's first frame is drawn from the manifest alone, so the files
    // are read after it rather than before it. The cards are already on the
    // ground when their real page, row and word counts land on them, and any
    // document opened in an earlier run arrives at the top in the same beat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) library.boot();
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
      // The loop, not the ground, for the one frame the navigator has yet to
      // hand anything over: an app with nothing on screen is loading, and a
      // bare ground would say it had nothing to show.
      builder: (context, child) => _Fitted(
        child: DissolveScope(child: child ?? const QuireLoading()),
      ),
    );
  }

  Route<void> _route(RouteSettings settings) {
    final builder = widget.routes[settings.name];
    if (settings.name == kReaderRoute) {
      final handoff = settings.arguments;
      return ReaderRoute<void>(
        settings: settings,
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
    library: _library,
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
      arguments: (store: store),
    );
  }

  Widget _desk(BuildContext context) {
    final library = _library;
    if (library == null) return const QuireLoading();
    return DeskScreen(store: library, onOpen: _open, onSign: _sign);
  }

  /// Takes [entry] to the reader.
  ///
  /// The desk reports where the row was, because it is the desk's business to
  /// know. Nothing here needs it: a document arrives from the edge of the
  /// screen rather than out of the card, the same way the drawer does.
  void _open(LibraryEntry entry, Rect rowRect) {
    final library = _library;
    if (library == null) return;
    final document = library.storeFor(entry)..markOpened();
    _navigator.currentState?.pushNamed(
      kReaderRoute,
      arguments: (store: document),
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

/// Maps the design's fixed [kScreenWidth] by [kScreenHeight] space onto
/// whatever screen the app is actually running on.
///
/// Every metric in this app is a constant in a 402 by 874 space, which is what
/// lets the fore edge, the folio chip and the sheet be laid out as constants
/// rather than measured. A phone narrower than 402 would otherwise push the
/// sheet's right edge, and with it the corner you turn a page by, off the
/// screen entirely.
///
/// The scale is uniform, so a sheet keeps the proportions it was drawn with.
/// Whatever the shorter axis leaves over becomes ground coloured margin, which
/// reads as the desk the page is lying on rather than as a bar.
class _Fitted extends StatelessWidget {
  const _Fitted({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final query = MediaQuery.of(context);
    final size = query.size;
    if (size.isEmpty) return child;
    final scale = math.min(
      size.width / kScreenWidth,
      size.height / kScreenHeight,
    );
    // The device's own insets are in device points, so they have to be taken
    // back into design points before anything laid out in design space reads
    // them, or a notch would be measured against the wrong ruler.
    final padding = EdgeInsets.fromLTRB(
      query.padding.left / scale,
      query.padding.top / scale,
      query.padding.right / scale,
      query.padding.bottom / scale,
    );
    return ColoredBox(
      color: AppColors.ground,
      child: Center(
        child: SizedBox(
          width: kScreenWidth * scale,
          height: kScreenHeight * scale,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: kScreenWidth,
              height: kScreenHeight,
              child: MediaQuery(
                // The ratio is multiplied rather than left alone so a snapshot
                // the dissolve takes is rasterised at the pixels it will
                // actually occupy, not the smaller count design space implies.
                data: query.copyWith(
                  size: const Size(kScreenWidth, kScreenHeight),
                  padding: padding,
                  viewPadding: padding,
                  devicePixelRatio: query.devicePixelRatio * scale,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
