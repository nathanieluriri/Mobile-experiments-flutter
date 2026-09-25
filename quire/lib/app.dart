import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'arrival/arrival.dart';
import 'data/library.dart';
import 'painting/signature_painter.dart';
import 'screens/desk/desk_screen.dart';
import 'screens/opening/opening_screen.dart';
import 'screens/reader/reader_host.dart';
import 'screens/reader/reader_route.dart';
import 'screens/sign/sign_screen.dart';
import 'services/document_store.dart';
import 'services/failure_log.dart';
import 'services/incoming_documents.dart';
import 'services/library_catalogue.dart';
import 'theme/colors.dart';
import 'theme/metrics.dart';
import 'theme/typography.dart';
import 'widgets/damaged_surface.dart';
import 'widgets/dissolve/dissolve_scope.dart';
import 'widgets/quire_spinner.dart';

/// Gives a failure somewhere to go, before anything can raise one.
///
/// Two boundaries can be the first to see an error, and left alone both are
/// silent. A widget that throws while building draws Flutter's grey
/// rectangle, sized to whatever slot the broken thing was in, with no text on
/// it in a release build. Everything else reaches the platform: an error on a
/// future nobody awaited, which is how this app saves the desk, printed one
/// line to a device log the owner will never see, having silently not saved.
///
/// Both arrive here instead, so a fault is counted once, and what the reader
/// is shown where the broken thing was is drawn in the app's own hand.
///
/// There is deliberately no [runZonedGuarded]. It is the older way to catch
/// the second kind, and it brings a hazard with it: the binding has to be
/// initialised inside the same zone it runs in, so a guarded `main` and an
/// unguarded `WidgetsFlutterBinding.ensureInitialized` fail against each
/// other at launch, which is the worst moment to learn about a zone.
/// `PlatformDispatcher.onError` is the root zone's own handler and catches
/// the same errors without asking `main` to be arranged around it.
///
/// Called first from `main`, which is the only caller that is not a test.
void installFailureHandlers() {
  FlutterError.onError = (details) {
    failures.record(details.exception, where: 'a build', stack: details.stack);
    // Still said out loud. In a debug run this is the red panel and the
    // console dump, and taking those away would trade one silence for
    // another.
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    failures.record(error, where: 'the platform', stack: stack);
    return true;
  };
  // Recorded already by the handler above, which runs first and always. This
  // only has to decide what stands in the hole.
  ErrorWidget.builder = (details) => const DamagedSurface();
}

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
typedef ReaderHandoff = ({DocumentStore store, bool outside});

/// The whole app: one ground, one type family, one theme and no toggle.
class App extends StatefulWidget {
  const App({
    super.key,
    this.routes = const <String, WidgetBuilder>{},
    this.splashHandedOver = false,
  });

  /// Whether the platform will say what its splash showed and take it away
  /// itself, which Android 12 and later do.
  final bool splashHandedOver;

  /// The screens behind [kDeskRoute], [kReaderRoute] and [kSignRoute].
  ///
  /// A name that is not in here falls back to the app's own ground, except
  /// [kDeskRoute], which falls back to the desk itself.
  final Map<String, WidgetBuilder> routes;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  /// Where the app says a line about itself when neither the desk's pill nor
  /// the reader's band is reachable, which is every moment before one of them
  /// is on screen.
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();

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

  /// Documents handed to quire by another app.
  ///
  /// Null for the same reason [_library] is: a test that brings its own desk
  /// is not being started by a file manager.
  IncomingDocuments? _incoming;

  /// The document the app was started on, while quire is reading it.
  ///
  /// A notifier rather than a plain field, because the desk's route is built
  /// once and a setState out here never reaches inside it: the screen would
  /// go up when the document arrived and then stay up over everything.
  final ValueNotifier<IncomingDocument?> _doorstep =
      ValueNotifier<IncomingDocument?>(null);

  /// Stops the opening screen waiting on a document that is not coming.
  Timer? _doorstepLimit;

  /// True once the screen the arrival opens onto is up: the desk has read
  /// what it holds, and the platform has said whether the app was started on
  /// a document.
  final ValueNotifier<bool> _arrived = ValueNotifier<bool>(false);

  /// Opens the arrival anyway if the desk cannot be read, at the moment the
  /// desk gives up waiting and shows what it has.
  Timer? _arrivalLimit;

  /// True until the platform has said what the app was started on.
  ///
  /// It is the one thing that tells a cold start on a document from a warm
  /// one, because both arrive on the same channel carrying the same thing. A
  /// warm open lands on top of a reading already in progress, and a screen
  /// thrown over that would cover the page somebody was in the middle of.
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    // Registered before the app's own navigator registers, so a page name the
    // platform pushes reaches this first. See [didPushRouteInformation].
    WidgetsBinding.instance.addObserver(this);
    if (widget.routes.containsKey(kDeskRoute)) return;
    final library = LibraryStore(catalogue: LibraryCatalogue());
    _library = library;
    // The desk's first frame is drawn from the manifest alone, so the files
    // are read after it rather than before it. The cards are already on the
    // ground when their real page, row and word counts land on them, and any
    // document opened in an earlier run arrives at the top in the same beat.
    final incoming = IncomingDocuments()..addListener(_onIncoming);
    _incoming = incoming;
    _arrivalLimit = Timer(kDeskWakingLimit, () => _arrived.value = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // The desk before the doorstep. A document handed in at a cold start
      // still goes onto the desk it is opened from, so the desk has to know
      // what it already holds before anything is added to it.
      try {
        await library.boot(parse: false);
        if (mounted) await incoming.boot();
      } finally {
        // The platform has now said what it started the app on, or the desk
        // could not be read and there is nothing more to wait for. Anything
        // that arrives after this came in on top of whatever quire was
        // showing.
        _starting = false;
        _arrivalLimit?.cancel();
        if (mounted) _arrived.value = true;
      }
      // A document handed in at a cold start is opened before the desk's own
      // documents are read, not raced against them.
      await _opening;
      await library.hydrate();
    });
  }

  /// A document has arrived from outside, or been refused.
  void _onIncoming() {
    final incoming = _incoming;
    if (incoming == null || !mounted) return;
    final refused = incoming.refused;
    if (refused != null) {
      incoming.clearRefusal();
      _say(refused.line);
      return;
    }
    final waiting = incoming.take();
    if (waiting == null) return;
    // Only the document the app was started on gets a screen of its own. One
    // handed over later arrives over a desk or a page that is already up, and
    // covering that would take somebody out of what they were doing.
    if (_starting) _raiseOpening(waiting);
    _opening = _openIncoming(waiting);
  }

  /// Names the document quire was opened on, while it is being read.
  ///
  /// The limit is what keeps the naming honest. A file that cannot be reached
  /// or will not parse would otherwise leave somebody looking at its name for
  /// as long as they cared to wait.
  void _raiseOpening(IncomingDocument document) {
    _doorstepLimit?.cancel();
    _doorstepLimit = Timer(kOpeningLimit, _lowerOpening);
    _doorstep.value = document;
  }

  /// Puts the opening screen away, whether the document arrived or not.
  void _lowerOpening() {
    _doorstepLimit?.cancel();
    _doorstepLimit = null;
    if (mounted) _doorstep.value = null;
  }

  /// The incoming document being opened, if one is.
  Future<void>? _opening;

  /// Puts an incoming document on the desk and opens it.
  ///
  /// It is imported rather than read where it lies, because where it lies is a
  /// copy the platform made in a cache directory and will delete when it feels
  /// like it. A document you were handed is a document you have.
  Future<void> _openIncoming(IncomingDocument document) async {
    final library = _library;
    if (library == null) return;
    final Uint8List bytes;
    try {
      bytes = await File(document.path).readAsBytes();
    } on Object {
      // The screen goes before the line is said, so a refusal is not read out
      // from under the name of the document it is refusing.
      _lowerOpening();
      _say(IncomingRefusal.missing.line);
      return;
    }
    final entry = await library.importFile(document.name, bytes);
    if (!mounted) return;
    if (entry == null) {
      _lowerOpening();
      _say(IncomingRefusal.unreadable.line);
      return;
    }
    // The reader the moment the document has been read, with no minimum on
    // the screen that named it. The desk holds its mark for a whole beat
    // because a mark that came and went inside two frames would read as a
    // fault, but what takes this one away is the document itself, and making
    // somebody wait to be told what they are already looking at would be
    // worse than a short screen.
    _open(entry, Rect.zero, outside: true);
    _lowerOpening();
  }

  /// Hands the reader back to whichever app opened the document.
  ///
  /// On Android that is finishing the activity, which returns to the task
  /// underneath it, which is the file manager or the mail client the document
  /// came from. iOS does not let an app send itself away, and puts its own
  /// link back to the other app in the status bar, so there the reader simply
  /// goes back to the desk.
  Future<void> _leaveToCaller() async {
    // The activity may be gone the moment it finishes, so whatever the
    // reading changed is written first.
    await _library?.saveNow();
    await leaveToCaller(
      platform: defaultTargetPlatform,
      // A pop and not a maybePop: the reader's own guard is what called this,
      // and asking it again would only call this again.
      backInApp: () => _navigator.currentState?.pop<void>(),
    );
  }

  /// Writes the desk's state as the app goes to the background, since an app
  /// in the background can be closed without another word.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // An app going into the background may not come back, so a removal
      // still waiting to be undone is settled before the state is written.
      _library?.commitRemoval();
      unawaited(_library?.saveNow());
    }
  }

  /// Says one line over whatever is on screen.
  ///
  /// The desk has a pill of its own for this and the reader has its band, and
  /// neither is reachable from here: this runs before either exists, or over
  /// whichever of them happens to be up. So it is the one place the app talks
  /// to somebody without knowing where they are.
  void _say(String line) {
    final messenger = _messenger.currentState;
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(line, style: AppText.label),
          backgroundColor: AppColors.surfaceHigh,
          behavior: SnackBarBehavior.floating,
          duration: kReaderNotice,
        ),
      );
  }

  /// Refuses every page name the platform tries to push.
  ///
  /// This app is never navigated from outside. A document another app hands
  /// over arrives on the incoming channel, where it can be checked and put on
  /// the desk. A name pushed here instead is a document's address being read
  /// as a place in the app, and there is no such place: honouring it pushes a
  /// blank page the reader then has to press back through.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) =>
      Future<bool>.value(true);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _doorstepLimit?.cancel();
    _arrivalLimit?.cancel();
    _arrived.dispose();
    _doorstep.dispose();
    _incoming
      ?..removeListener(_onIncoming)
      ..dispose();
    _library?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quire',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
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
      // The desk and nothing under it, whatever the platform says the app was
      // started on. Left to the default, a document's content address becomes
      // the starting page and each segment of it becomes a blank page under
      // the reader, which is the one thing back must never uncover.
      onGenerateInitialRoutes: (_) => <Route<void>>[
        _route(const RouteSettings(name: kDeskRoute)),
      ],
      onGenerateRoute: _route,
      onUnknownRoute: _route,
      // The scope sits above the Navigator, so a card can come apart over the
      // whole screen and keep going while the screen under it changes.
      // The loop, not the ground, for the one frame the navigator has yet to
      // hand anything over: an app with nothing on screen is loading, and a
      // bare ground would say it had nothing to show.
      builder: (context, child) {
        final app = _Fitted(
          child: DissolveScope(child: child ?? const QuireLoading()),
        );
        // Outside the design frame, because the splash it takes over from was
        // laid out on the whole screen. A test that brings its own desk is not
        // a launch, and gets no arrival.
        if (_library == null) return app;
        return Arrival(
          ready: _arrived,
          handsOver: widget.splashHandedOver,
          child: app,
        );
      },
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
                ? _reader(handoff.store, outside: handoff.outside)
                : const _Ground(),
      );
    }
    if (settings.name == kSignRoute) {
      final store = settings.arguments;
      return MaterialPageRoute<void>(
        settings: settings,
        builder:
            builder ??
            (context) => store is DocumentStore ? _pad(store) : const _Ground(),
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
  ///
  /// A document another app opened is left the way it was arrived at: back
  /// goes to that app, not to a desk the reader never asked to see.
  Widget _reader(DocumentStore store, {bool outside = false}) => ReaderHost(
    store: store,
    library: _library,
    onLeave: outside ? _leaveToCaller : null,
    placing: identical(store, _signing) ? _mark : null,
    onPlaced: () {
      _mark = null;
      _signing = null;
    },
  );

  /// The pad, and the one thing that happens when a signature leaves it: the
  /// document it was drawn for opens, with the mark in hand.
  ///
  /// The pad offers the signatures used before, and the one placed is put at
  /// the front of them.
  Widget _pad(DocumentStore store) {
    final library = _library;
    if (library == null) {
      return SignScreen(
        onBack: () => _navigator.currentState?.maybePop<void>(),
        onCommit: (mark) => _placeOn(store, mark),
      );
    }
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => SignScreen(
        recent: library.recentSignatures,
        onForget: library.forgetSignature,
        onBack: () => _navigator.currentState?.maybePop<void>(),
        onCommit: (mark) {
          library.useSignature(savedOf(mark));
          _placeOn(store, mark);
        },
      ),
    );
  }

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
      arguments: (store: store, outside: false),
    );
  }

  Widget _desk(BuildContext context) {
    final library = _library;
    if (library == null) return const QuireLoading();
    // The opening screen stands where the desk stands rather than over it, so
    // the document quire was opened on is the only thing in the app while it
    // is being read. A desk laid out behind a screen like this is a desk that
    // can be seen through it and reached with a back gesture, which is an
    // invitation to leave a document that has not arrived yet.
    return ValueListenableBuilder<IncomingDocument?>(
      valueListenable: _doorstep,
      builder: (context, document, _) => AnimatedSwitcher(
        // Behind the arrival's mark the switch is not seen, and a fade still
        // running when the window opens would be.
        duration: _arrived.value ? kDeskWakingFade : Duration.zero,
        child: document == null
            ? KeyedSubtree(
                key: const ValueKey<bool>(true),
                child: DeskScreen(
                  store: library,
                  onOpen: _open,
                  onSign: _sign,
                  holdsItsMark: false,
                ),
              )
            : KeyedSubtree(
                key: const ValueKey<bool>(false),
                child: OpeningScreen(document: document),
              ),
      ),
    );
  }

  /// Takes [entry] to the reader.
  ///
  /// The desk reports where the row was, because it is the desk's business to
  /// know. Nothing here needs it: a document arrives from the edge of the
  /// screen rather than out of the card, the same way the drawer does.
  void _open(LibraryEntry entry, Rect rowRect, {bool outside = false}) {
    final library = _library;
    if (library == null) return;
    final document = library.storeFor(entry)..markOpened();
    _navigator.currentState?.pushNamed(
      kReaderRoute,
      arguments: (store: document, outside: outside),
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

/// Leaves a document another app opened, the way that platform leaves things.
///
/// On Android that is finishing the activity, which returns to the task under
/// it: the file manager or mail client the document came from. iOS does not
/// let an app send itself away, and puts its own link back to the other app in
/// the status bar, so there [backInApp] runs instead.
Future<void> leaveToCaller({
  required TargetPlatform platform,
  required VoidCallback backInApp,
}) async {
  if (platform == TargetPlatform.android) {
    await SystemNavigator.pop();
    return;
  }
  backInApp();
}

/// The bare desk. What is left when a route has nothing behind it, so a wrong
/// name shows the app's own ground rather than an error screen.
class _Ground extends StatelessWidget {
  const _Ground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: AppColors.ground, child: SizedBox.expand());
  }
}

/// How many device points one design point takes on a screen of [size]: as
/// many as let the whole design fit, and no more.
double fittedScale(Size size) =>
    math.min(size.width / kScreenWidth, size.height / kScreenHeight);

/// The phone's own insets, [insets] in device points, as the design frame on a
/// screen of [size] meets them.
///
/// Two rulers differ. The insets are in device points and the frame is in
/// design points, so they are divided by the scale. And they are measured from
/// the screen's edge while the frame is not at the screen's edge: on a phone
/// taller than the design, the frame is centred and starts some way below the
/// top of the glass, part of the way down the status bar. Only the part of the
/// status bar that is over the frame is over anything the app lays out, so a
/// band that reserved the whole of it would leave that much dead ground
/// between the clock and whatever sits under it. The same holds at every edge.
EdgeInsets insetsInFrame(Size size, EdgeInsets insets) {
  final scale = fittedScale(size);
  final across = (size.width - kScreenWidth * scale) / 2;
  final down = (size.height - kScreenHeight * scale) / 2;
  return EdgeInsets.fromLTRB(
    math.max(0.0, insets.left - across) / scale,
    math.max(0.0, insets.top - down) / scale,
    math.max(0.0, insets.right - across) / scale,
    math.max(0.0, insets.bottom - down) / scale,
  );
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
    final scale = fittedScale(size);
    final padding = insetsInFrame(size, query.padding);
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
