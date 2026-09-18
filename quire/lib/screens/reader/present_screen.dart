import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../constants/gooey_fab.dart'
    show kGooAlphaThresholdMatrix, kGooBlurSigma;
import '../../model/document.dart';
import '../../painting/present_goo_painter.dart';
import '../../services/document_store.dart';
import '../../services/screen_hold.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/feedback.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import '../desk/desk_sheet.dart';
import 'bodies/deck_body.dart';
import 'bodies/slide_sheet.dart';

/// The cluster's own measurements.
///
/// The pill is exactly as wide as its three controls need to be to answer a
/// thumb: two steps at the pill's own height, and the number between them at
/// [kPresentNumberWidth]. The number is not a label, it is the way into a deck
/// of forty slides, and a target the size of the digit printed on it is a
/// target nobody hits while holding a phone up in front of a room.
const double kPresentPillHeight = 46.0;
const double kPresentNumberWidth = 48.0;
const double kPresentPillWidth = kPresentPillHeight * 2 + kPresentNumberWidth;
const double kPresentLeaveSize = kPresentPillHeight;
const double kPresentLeaveGap = kSpace14;
const double kPresentClusterBottom = kSpace26;

/// Every glyph in the cluster, at one size.
///
/// Three controls sitting on one body have to read as one set. Drawn at three
/// sizes they read as three things that happen to be touching.
const double kPresentGlyph = 20.0;

/// Room left round the goo canvas for the blur, so the body is not cut off at
/// the edge of the box the controls are laid out in.
const double kPresentGooPad = kSpace40;

/// How long the cluster stays after it has been asked for, and how long it
/// takes to come and go.
///
/// Longer than a locked page's chip: the chip says one sentence, and this is
/// three controls a reader may want to use twice.
const Duration kPresentClusterHold = Duration(seconds: 4);
const Duration kPresentClusterMove = Duration(milliseconds: 260);

/// How far out the cluster has to be before its glyphs begin to arrive.
const double kPresentGlyphsIn = 0.55;

/// How long a slide takes to come in from the side when it is stepped to.
const Duration kPresentStep = Duration(milliseconds: 260);

/// What present mode says the first time it takes the screen.
///
/// Once, and briefly. A presentation with a caption over it is a presentation
/// somebody is reading instructions off, and the instruction is one sentence
/// long: the way out is where the controls are.
const String kPresentNotice = 'Tap the slide for the controls.';
const Duration kPresentNoticeHold = Duration(milliseconds: 2600);

/// Whether it has already been said.
///
/// Once in the life of the app, not once per presentation. A presenter who has
/// been told where the controls are does not need telling again, and a line of
/// app copy over the first slide in front of a room is the exact thing this
/// mode exists to keep off the screen.
bool _noticeSaid = false;

/// Forgets that the line has been said, for a test that needs it again.
@visibleForTesting
void resetPresentNotice() => _noticeSaid = false;

/// A deck shown the way it was meant to be shown: one slide, as large as the
/// screen will take it, and nothing else on the glass.
///
/// The way out is the same idea as a locked page's. A presentation that keeps
/// a bar and a close button parked over the slide is a presentation with the
/// app's furniture in the room, so there is no bar at all and the controls are
/// summoned by a tap and go again on their own. What is different from a lock
/// is that this one has somewhere to go as well as a way out, so the cluster
/// carries the step controls too.
class PresentScreen extends StatefulWidget {
  const PresentScreen({
    super.key,
    required this.store,
    required this.slides,
    required this.assets,
    required this.titles,
    this.openAt = 0,
    this.screen,
  });

  final DocumentStore store;
  final List<SlideBlock> slides;
  final Map<String, Uint8List> assets;

  /// Each slide's own title, for the list that jumps between them.
  final List<String> titles;

  final int openAt;

  /// What holds the screen awake, or null for the platform's own.
  final ScreenHold? screen;

  @override
  State<PresentScreen> createState() => _PresentScreenState();
}

class _PresentScreenState extends State<PresentScreen>
    with TickerProviderStateMixin {
  late final PageController _pages = PageController(initialPage: widget.openAt);

  /// The cluster's own arrival, which is what the goo is drawn from.
  late final AnimationController _cluster = AnimationController(
    vsync: this,
    duration: kPresentClusterMove,
  )..addListener(_onCluster);

  /// The clock that takes it away again.
  Timer? _clusterGone;

  /// The one line present mode says, and the clock that takes it back.
  bool _saying = !_noticeSaid;
  Timer? _noticeGone;

  late int _at = widget.openAt;

  late final ScreenHold _screen = widget.screen ?? ScreenHold();

  /// The row the jump list opens on, so a long deck does not offer its list
  /// at slide one while the reader is standing on slide thirty.
  final GlobalKey _standingOn = GlobalKey();

  @override
  void initState() {
    super.initState();
    // The reading goes to the slide being shown straight away, rather than on
    // the first step. A presenter who opens the deck at slide five and leaves
    // without stepping should come back to slide five.
    if (widget.slides.isNotEmpty) widget.store.position = widget.openAt;
    // The screen owns its own room: the system bars go as it opens and come
    // back as it closes, wherever it was opened from and however it is left.
    unawaited(enterPresentation());
    // A presentation is minutes with no touches in it, which is exactly what
    // a phone reads as nobody being there.
    unawaited(_screen.hold());
    if (_saying) {
      _noticeSaid = true;
      _noticeGone = Timer(kPresentNoticeHold, () {
        if (mounted) setState(() => _saying = false);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_screen.release());
    unawaited(leavePresentation());
    _noticeGone?.cancel();
    _clusterGone?.cancel();
    _cluster.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onCluster() {
    if (mounted) setState(() {});
  }

  /// Brings the controls up, and starts the clock that takes them down.
  void _askCluster() {
    _clusterGone?.cancel();
    _cluster.forward();
    _clusterGone = Timer(kPresentClusterHold, () {
      if (mounted) _cluster.reverse();
    });
  }

  void _hideCluster() {
    _clusterGone?.cancel();
    _cluster.reverse();
  }

  /// A tap on the slide: the controls if they are away, and away again if they
  /// are up.
  ///
  /// A tap that only ever summoned them would leave a presenter who brushed
  /// the glass with four seconds of furniture over their slide and no way to
  /// take it off.
  void _onTapSlide() {
    Feel.tap.ring();
    if (_cluster.value > 0.5) {
      _hideCluster();
    } else {
      _askCluster();
    }
  }

  void _goTo(int slide) {
    if (widget.slides.isEmpty) return;
    final wanted = slide.clamp(0, widget.slides.length - 1);
    if (wanted == _at) return;
    _pages.animateToPage(wanted, duration: kPresentStep, curve: easeOutCubic);
  }

  void _onPage(int index) {
    setState(() => _at = index);
    widget.store.position = index;
    // Stepping is a use of the controls, so the clock starts again rather than
    // running out under a presenter's thumb.
    if (_cluster.value > 0) _askCluster();
  }

  /// The list of slides, by their own titles, so a presenter can go straight
  /// to the one somebody in the room asked about.
  Future<void> _jump() async {
    _clusterGone?.cancel();
    final picked = await showDeskSheet<int>(context, (context) {
      // The list opens on the slide being shown. A deck is read in order and
      // asked about out of order, so the row somebody wants is nearly always
      // near the one they are on, and a list that opened at its top would put
      // that row off the bottom of any deck worth having a list for.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _standingOn.currentContext;
        if (row == null) return;
        Scrollable.ensureVisible(row, alignment: 0.4, duration: Duration.zero);
      });
      return DeskSheet(
        title: 'Go to a slide',
        children: <Widget>[
          for (var i = 0; i < widget.slides.length; i++)
            DeskSheetRow(
              key: i == _at ? _standingOn : null,
              label: i < widget.titles.length && widget.titles[i].isNotEmpty
                  ? widget.titles[i]
                  : 'Slide ${i + 1}',
              icon: i == _at ? LucideIcons.squareDot : LucideIcons.square,
              note: i == _at ? 'Slide ${i + 1}, showing now' : 'Slide ${i + 1}',
              // Marked as well as scrolled to. A different glyph on its own is
              // not enough to find at a glance in a list of forty lines that
              // are otherwise identical in weight.
              trailing: i == _at ? const _Standing() : null,
              onTap: () => Navigator.of(context).pop(i),
            ),
        ],
      );
    });
    if (!mounted) return;
    if (picked != null) _goTo(picked);
    _askCluster();
  }

  void _leave() {
    Feel.commit.ring();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      // Back leaves the presentation rather than the document, which is what
      // a presenter reaches for first and what every other app does.
      child: ColoredBox(
        color: AppColors.presentGround,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTapSlide,
                child: PageView.builder(
                  controller: _pages,
                  onPageChanged: _onPage,
                  itemCount: widget.slides.length,
                  itemBuilder: (context, index) => Center(
                    child: _PresentedSlide(
                      slide: widget.slides[index],
                      assets: widget.assets,
                      room: size,
                    ),
                  ),
                ),
              ),
            ),
            if (_saying)
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + kSpace56,
                child: IgnorePointer(
                  child: Center(
                    child: Text(
                      kPresentNotice,
                      style: AppText.docMeta.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ),
              ),
            _Cluster(
              t: _cluster.value,
              label: '${_at + 1}',
              atStart: _at == 0,
              atEnd: _at == widget.slides.length - 1,
              onBack: () => _goTo(_at - 1),
              onOn: () => _goTo(_at + 1),
              onJump: _jump,
              onLeave: _leave,
            ),
          ],
        ),
      ),
    );
  }
}

/// One slide, fitted to the room it is being shown in.
class _PresentedSlide extends StatelessWidget {
  const _PresentedSlide({
    required this.slide,
    required this.assets,
    required this.room,
  });

  final SlideBlock slide;
  final Map<String, Uint8List> assets;
  final Size room;

  @override
  Widget build(BuildContext context) {
    final fitted = slideFitted(slide, room);
    if (fitted.width <= 0) return const SizedBox.shrink();
    return SlideSheet(slide: slide, assets: assets, width: fitted.width);
  }
}

/// The controls: one body that comes out of the middle of the screen's foot,
/// stretches into a pill, and lets a way out off its end.
class _Cluster extends StatelessWidget {
  const _Cluster({
    required this.t,
    required this.label,
    required this.atStart,
    required this.atEnd,
    required this.onBack,
    required this.onOn,
    required this.onJump,
    required this.onLeave,
  });

  final double t;
  final String label;
  final bool atStart;
  final bool atEnd;
  final VoidCallback onBack;
  final VoidCallback onOn;
  final VoidCallback onJump;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final reach =
        kPresentPillWidth / 2 + kPresentLeaveGap + kPresentLeaveSize / 2;
    // The box the cluster is laid out in, centred on the pill, wide enough to
    // hold the way out at full reach on both sides so the pill itself stays on
    // the screen's own centre line.
    final width =
        kPresentPillWidth + 2 * (kPresentLeaveGap + kPresentLeaveSize);
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(context).bottom + kPresentClusterBottom,
      child: Center(
        // The whole cluster keeps the screen's centre line, not the pill
        // alone. At rest it is one blob on the centre; open, it is a pill and
        // a way out whose combined middle is still on it, so nothing appears
        // to drift sideways as it arrives.
        child: Transform.translate(
          offset: Offset(-(kPresentLeaveGap + kPresentLeaveSize) / 2 * t, 0),
          child: SizedBox(
            width: width,
            height: kPresentPillHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                Positioned(
                  left: -kPresentGooPad,
                  right: -kPresentGooPad,
                  top: -kPresentGooPad,
                  bottom: -kPresentGooPad,
                  child: IgnorePointer(
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(
                        kGooAlphaThresholdMatrix,
                      ),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: kGooBlurSigma,
                          sigmaY: kGooBlurSigma,
                          tileMode: TileMode.decal,
                        ),
                        child: CustomPaint(
                          painter: PresentGooPainter(
                            t: t,
                            pillWidth: kPresentPillWidth,
                            pillHeight: kPresentPillHeight,
                            leaveDiameter: kPresentLeaveSize,
                            leaveGap: kPresentLeaveGap,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The pill's own contents, over the goo. They fade in late, so
                // the body is a body before it is a row of buttons.
                Opacity(
                  opacity: _contents,
                  child: SizedBox(
                    width: kPresentPillWidth,
                    height: kPresentPillHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _Step(
                          icon: LucideIcons.chevronLeft,
                          label: 'The slide before',
                          dim: atStart,
                          onTap: onBack,
                        ),
                        PaperPress(
                          onTap: onJump,
                          // The number is the control, so the number is in the
                          // label. Left to itself a screen reader would read
                          // this button out as the word one.
                          semanticLabel: 'Slide $label, go to a slide',
                          feel: Feel.tap,
                          child: SizedBox(
                            width: kPresentNumberWidth,
                            height: kPresentPillHeight,
                            child: Center(
                              child: ExcludeSemantics(
                                child: Text(
                                  label,
                                  style: AppText.actionPill.copyWith(
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _Step(
                          icon: LucideIcons.chevronRight,
                          label: 'The slide after',
                          dim: atEnd,
                          onTap: onOn,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: width / 2 + reach * t - kPresentLeaveSize / 2,
                  child: Opacity(
                    opacity: _contents,
                    child: PaperPress(
                      onTap: onLeave,
                      semanticLabel: 'Leave the presentation',
                      feel: Feel.commit,
                      washRadius: kPresentLeaveSize / 2,
                      child: SizedBox(
                        width: kPresentLeaveSize,
                        height: kPresentLeaveSize,
                        child: Icon(
                          LucideIcons.minimize2,
                          size: kPresentGlyph,
                          color: AppColors.accentBright,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The glyphs arrive once the body has most of its shape, and leave at once.
  ///
  /// [kPresentGlyphsIn] is where they start: late enough that the cluster is a
  /// body before it is a row of buttons, early enough that they are up before
  /// it settles.
  double get _contents =>
      ((t - kPresentGlyphsIn) / (1 - kPresentGlyphsIn)).clamp(0.0, 1.0);
}

/// The mark against the slide the presentation is standing on.
class _Standing extends StatelessWidget {
  const _Standing();

  @override
  Widget build(BuildContext context) => const Icon(
    LucideIcons.check,
    size: kPresentGlyph,
    color: AppColors.accentBright,
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.label,
    required this.dim,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// True at the first slide or the last, where the control has nowhere to go.
  /// It is held back rather than taken away: a pill that changed shape at both
  /// ends of a deck would be a different control each time.
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PaperPress(
    onTap: dim ? null : onTap,
    semanticLabel: label,
    feel: Feel.tap,
    washRadius: kPresentPillHeight / 2,
    child: SizedBox(
      width: kPresentPillHeight,
      height: kPresentPillHeight,
      child: Icon(
        icon,
        size: kPresentGlyph,
        color: dim ? AppColors.inkFaint : AppColors.ink,
      ),
    ),
  );
}

/// The route present mode arrives on: up from the deck, and back down onto it.
///
/// A fade would be the ordinary choice and it is wrong here. The slide the
/// reader tapped is on the bench behind this, and the presentation is that
/// slide lifted off it, so it comes up the way the pad does over a page.
Route<void> presentRoute({
  required DocumentStore store,
  required List<SlideBlock> slides,
  required Map<String, Uint8List> assets,
  required List<String> titles,
  required int openAt,
}) => PageRouteBuilder<void>(
  transitionDuration: kPadArrival,
  reverseTransitionDuration: kPadArrival,
  pageBuilder: (context, animation, secondary) => PresentScreen(
    store: store,
    slides: slides,
    assets: assets,
    titles: titles,
    openAt: openAt,
  ),
  transitionsBuilder: (context, animation, secondary, child) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      // The slide swells off the bench rather than sliding in from an edge,
      // which is the one movement that reads as the same object getting
      // closer instead of a second screen arriving.
      scale: Tween<double>(
        begin: 0.92,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: easeOutCubic)),
      child: child,
    ),
  ),
);

/// Present mode holds the screen awake and takes the system bars off.
///
/// Both are undone on the way out, and both are what separates a presentation
/// from a document that happens to be full screen.
Future<void> enterPresentation() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

Future<void> leavePresentation() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
