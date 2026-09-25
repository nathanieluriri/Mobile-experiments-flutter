import 'package:flutter/widgets.dart';

import '../../painting/signature_painter.dart';
import '../../pdf/display_list.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../widgets/dissolve/dissolve_scope.dart';
import '../reader/sheet_surface.dart';
import 'signature_stamp.dart';

/// Where a page of [list] is drawn inside [sheet]: the full width of the leaf,
/// aligned to its top, at one scale in both directions.
///
/// The placement layer has to agree with the body about this to the point, or
/// a mark would land somewhere the reader did not put it.
Rect pageRectIn(Rect sheet, PageDisplayList list) {
  final scale = list.widthPts <= 0 ? 1.0 : sheet.width / list.widthPts;
  return Rect.fromLTWH(
    sheet.left,
    sheet.top,
    sheet.width,
    list.heightPts * scale,
  );
}

/// Every baseline the page itself carries, in top left page points, sorted,
/// each stated once however many runs sit on it.
///
/// These are the page's own lines of type, not a grid laid over it, which is
/// why a signature that snaps to one lands like set type rather than like
/// something dropped on a guide.
List<double> pageBaselines(PageDisplayList list) {
  final seen = <double>{for (final run in list.texts) run.y};
  return seen.toList()..sort();
}

/// The baseline within [within] of [y], or null when there is none.
double? snapBaseline(
  double y,
  List<double> baselines, {
  double within = kBaselineSnapDistance,
}) {
  double? best;
  var closest = within;
  for (final baseline in baselines) {
    final gap = (baseline - y).abs();
    if (gap <= closest) {
      closest = gap;
      best = baseline;
    }
  }
  return best;
}

/// A page baseline in screen points.
double baselineOnScreen(double pageY, Rect pageRect, PageDisplayList list) =>
    pageRect.top + pageY * _scaleOf(pageRect, list);

/// The same journey back, for turning a placed mark into page coordinates.
double baselineInPage(double screenY, Rect pageRect, PageDisplayList list) =>
    (screenY - pageRect.top) / _scaleOf(pageRect, list);

double _scaleOf(Rect pageRect, PageDisplayList list) =>
    list.widthPts <= 0 ? 1.0 : pageRect.width / list.widthPts;

/// The reader in placement mode: the page held back, one mark loose over it,
/// and the guide that appears when the mark finds a line of the page's own.
class PlacementLayer extends StatefulWidget {
  const PlacementLayer({
    super.key,
    required this.mark,
    required this.page,
    required this.pageIndex,
    this.sheet = kSheetRect,
    this.paper,
    this.onPlace,
  });

  /// The signature drawn on the pad.
  final SignatureMark mark;

  /// The page it is being put on, which is where the baselines come from.
  final PageDisplayList page;

  /// Which page that is, zero based.
  final int pageIndex;

  /// The leaf the page is drawn on, which is what the mark is dimmed and
  /// clamped against.
  final Rect sheet;

  /// Where that page has actually been drawn, when something knows.
  ///
  /// The body scrolls its pages, so the page the reader is signing is almost
  /// never at the top of the sheet. Working the paper out from the sheet is
  /// only right at the very top of the very first page, and everywhere else
  /// it is out by however far the reader has scrolled: the mark was recorded
  /// that far down the page from where the finger let it go, and once that ran
  /// past the last line of the page it was recorded off the paper altogether
  /// and drawn nowhere at all.
  final Rect? paper;

  /// Called once the mark has finished sinking in, with the mark stated in the
  /// page's own coordinates. The host drops this layer when it fires.
  final ValueChanged<PlacedSignature>? onPlace;

  @override
  State<PlacementLayer> createState() => PlacementLayerState();
}

/// The placement's state, exposed so a test can read where the mark is and
/// commit it without pretending to be a finger for the parts that are not the
/// point of the test.
class PlacementLayerState extends State<PlacementLayer>
    with TickerProviderStateMixin {
  /// Where the finger has put the mark, before any snap.
  Offset _centre = Offset.zero;
  double _scale = 1;

  /// The scale a two finger gesture started from, so a pinch is measured
  /// against the size the mark was rather than compounding every frame.
  double _scaleAtPinch = 1;
  double? _snappedTo;
  bool _committed = false;

  final GlobalKey _inkKey = GlobalKey();

  /// The guide holds and then leaves, so one controller covers both.
  late final AnimationController _guide = AnimationController(
    vsync: this,
    duration: kSnapGuideHold + kSnapGuideFade,
  );

  /// The chrome coming off a mark that has landed. It runs for the longer of
  /// the two relaxations and each one reads its own share of it.
  late final AnimationController _settling = AnimationController(
    vsync: this,
    duration: kStampSettle,
  );

  List<double> _baselines = const <double>[];

  @override
  void initState() {
    super.initState();
    _measure();
    _centre = _paper.center;
  }

  @override
  void didUpdateWidget(PlacementLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page == widget.page &&
        oldWidget.sheet == widget.sheet &&
        oldWidget.paper == widget.paper) {
      return;
    }
    // The paper moved under the mark, so the mark goes with it: what the
    // finger is holding is a place on the page, not a place on the glass.
    final was = _pageRect;
    _measure();
    _centre += _pageRect.topLeft - was.topLeft;
    _clampToSheet();
    _resnap();
  }

  void _measure() {
    _baselines = <double>[
      for (final y in pageBaselines(widget.page))
        baselineOnScreen(y, _pageRect, widget.page),
    ];
  }

  Rect get _pageRect => widget.paper ?? pageRectIn(widget.sheet, widget.page);

  /// The paper a mark may actually be set into: the page, as far as it is on
  /// screen.
  ///
  /// A page is not the screen. At full width a letter page is shorter than
  /// the room the reader has, so there is screen below the paper, and a mark
  /// let go down there was being recorded at a place on the page that is past
  /// its bottom edge. It dissolved into nothing, because nothing is what is
  /// there. A signature belongs on the paper or nowhere.
  Rect get _paper {
    final paper = _pageRect.intersect(widget.sheet);
    return paper.isEmpty ? widget.sheet : paper;
  }

  /// How wide and tall the mark is at the current scale.
  Size get _stampSize {
    final width = kStampInitialWidth * _scale;
    return Size(width, width * widget.mark.aspect);
  }

  /// Where the mark sits on screen, snapped if it has found a line.
  Rect get stampRect {
    final size = _stampSize;
    final free = Rect.fromCenter(
      center: _centre,
      width: size.width,
      height: size.height,
    );
    final landed = _snappedTo;
    if (landed == null) return free;
    return free.translate(0, landed - free.bottom);
  }

  /// The corner target that scales the mark, hung on the mark's bottom right.
  ///
  /// This is the one statement of where the handle is. The widget is laid out
  /// at exactly this rect, so the target a finger finds and the target a test
  /// reads cannot drift apart.
  Rect get handleRect => Rect.fromLTWH(
    stampRect.right - kStampHandle,
    stampRect.bottom - kStampHandle,
    kStampHandle,
    kStampHandle,
  );

  /// True while the mark is sitting on one of the page's own baselines.
  bool get snapped => _snappedTo != null;

  @override
  void dispose() {
    _guide.dispose();
    _settling.dispose();
    super.dispose();
  }

  void _drag(Offset delta) {
    setState(() {
      _centre += delta;
      _clampToSheet();
      _resnap();
    });
  }

  /// Keeps the whole mark on the paper.
  ///
  /// A signature half off the leaf is not a signature on the document, and a
  /// signature below the leaf is not anywhere at all.
  void _clampToSheet() {
    final size = _stampSize;
    final paper = _paper;
    final left = paper.left + size.width / 2;
    final right = paper.right - size.width / 2;
    final top = paper.top + size.height / 2;
    final bottom = paper.bottom - size.height / 2;
    _centre = Offset(
      left <= right ? _centre.dx.clamp(left, right) : paper.center.dx,
      top <= bottom ? _centre.dy.clamp(top, bottom) : paper.center.dy,
    );
  }

  /// The handle grows the mark from its own centre outward, so the corner
  /// under the finger is the one that moves.
  void _scaleBy(Offset delta) {
    setState(() {
      final width = (_stampSize.width + delta.dx * 2).clamp(
        kStampInitialWidth * kStampScaleMin,
        kStampInitialWidth * kStampScaleMax,
      );
      _scale = width / kStampInitialWidth;
      _clampToSheet();
      _resnap();
    });
  }

  /// Takes the size the mark is now as the one a pinch will be measured from.
  void _pinchStart() => _scaleAtPinch = _scale;

  /// Sets the size to [factor] of what it was when the pinch began.
  void _pinchTo(double factor) {
    setState(() {
      _scale = (_scaleAtPinch * factor).clamp(
        kStampScaleMin,
        kStampScaleMax,
      );
      _clampToSheet();
      _resnap();
    });
  }

  /// Looks for a line under the mark's own baseline, and starts the guide when
  /// it finds a different one from the one it was on.
  void _resnap() {
    final size = _stampSize;
    final bottom = _centre.dy + size.height / 2;
    final found = snapBaseline(bottom, _baselines);
    if (found == _snappedTo) return;
    _snappedTo = found;
    if (found != null) _guide.forward(from: 0);
  }

  /// Sets the mark into the page: the grains take it, the chrome comes off,
  /// and when the dust has settled the page owns it.
  void commit() {
    if (_committed || widget.mark.isEmpty) return;
    final landed = stampRect;
    _settling.forward(from: 0);
    DissolveScope.of(context).absorb(
      _inkKey,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
      onCaptured: () => setState(() => _committed = true),
      onDone: () => widget.onPlace?.call(_signatureAt(landed)),
    );
  }

  /// The mark stated the way the page states everything else about itself.
  PlacedSignature _signatureAt(Rect landed) {
    final page = _pageRect;
    final scale = widget.page.widthPts <= 0
        ? 1.0
        : widget.page.widthPts / page.width;
    return PlacedSignature(
      pageIndex: widget.pageIndex,
      rect: Rect.fromLTWH(
        (landed.left - page.left) * scale,
        (landed.top - page.top) * scale,
        landed.width * scale,
        landed.height * scale,
      ),
      strokes: widget.mark.outlines,
      encoded: widget.mark.encoded,
      picture: widget.mark.picture,
    );
  }

  /// The guide is full while it holds and then goes, which is the one line in
  /// the app that arrives and leaves on its own.
  double get _guideOpacity {
    final hold = kSnapGuideHold.inMilliseconds;
    final fade = kSnapGuideFade.inMilliseconds;
    final ms = _guide.value * (hold + fade);
    if (ms <= hold) return 1;
    return 1 - easeOutQuad.transform(((ms - hold) / fade).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_guide, _settling]),
      builder: (context, _) {
        final settled = easeOutQuad.transform(_settling.value);
        final outlineGone = easeOutQuad.transform(
          (_settling.value *
                  kStampSettle.inMilliseconds /
                  kStampOutlineFade.inMilliseconds)
              .clamp(0.0, 1.0),
        );
        final rect = stampRect;
        return Stack(
          children: <Widget>[
            Positioned.fromRect(
              key: const ValueKey<String>('dim'),
              rect: widget.sheet,
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: kPeelableCorner,
                  child: ColoredBox(
                    color: AppColors.ground.withValues(
                      alpha: (1 - kPlacementDim) * (1 - settled),
                    ),
                  ),
                ),
              ),
            ),
            if (snapped && _guideOpacity > 0 && !_committed)
              Positioned(
                key: const ValueKey<String>('guide'),
                left: widget.sheet.left,
                top: _snappedTo! - 0.5,
                width: widget.sheet.width,
                height: 1,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: AppColors.accent.withValues(alpha: _guideOpacity),
                  ),
                ),
              ),
            // Keyed, every one of them. A guide that appears halfway through a
            // drag changes the length of this list, and without keys the
            // stamp would be rebuilt from the guide's element, which cancels
            // the very gesture that summoned the guide.
            Positioned.fromRect(
              key: const ValueKey<String>('stamp'),
              rect: rect,
              // A mark that has been given to the page is no longer something
              // to take hold of, and it must not stand between a finger and
              // the document for the length of the absorb.
              child: IgnorePointer(
                ignoring: _committed,
                child: SignatureStamp(
                  mark: widget.mark,
                  inkKey: _inkKey,
                  ink: _committed ? 0 : 1,
                  outline: _committed ? 1 - outlineGone : 1,
                  onDrag: _drag,
                  onPinchStart: _pinchStart,
                  onPinch: _pinchTo,
                ),
              ),
            ),
            // After the stamp, so that where the two overlap the corner wins
            // the touch, and outside the stamp so that a mark smaller than the
            // target still has a whole target.
            if (!_committed || outlineGone < 1)
              Positioned.fromRect(
                key: const ValueKey<String>('handle'),
                rect: handleRect,
                child: IgnorePointer(
                  ignoring: _committed,
                  child: StampHandle(
                    opacity: _committed ? 1 - outlineGone : 1,
                    onScale: _scaleBy,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
