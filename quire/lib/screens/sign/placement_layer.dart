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
    this.onPlace,
  });

  /// The signature drawn on the pad.
  final SignatureMark mark;

  /// The page it is being put on, which is where the baselines come from.
  final PageDisplayList page;

  /// Which page that is, zero based.
  final int pageIndex;

  /// The leaf the page is drawn on.
  final Rect sheet;

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
  late Offset _centre = widget.sheet.center;
  double _scale = 1;
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

  late final List<double> _baselines = <double>[
    for (final y in pageBaselines(widget.page))
      baselineOnScreen(y, _pageRect, widget.page),
  ];

  Rect get _pageRect => pageRectIn(widget.sheet, widget.page);

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

  /// The 24 point corner that scales the mark.
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
  /// A signature half off the leaf is not a signature on the document, and
  /// there is nowhere else on this screen for it to be.
  void _clampToSheet() {
    final size = _stampSize;
    final left = widget.sheet.left + size.width / 2;
    final right = widget.sheet.right - size.width / 2;
    final top = widget.sheet.top + size.height / 2;
    final bottom = widget.sheet.bottom - size.height / 2;
    _centre = Offset(
      left <= right ? _centre.dx.clamp(left, right) : widget.sheet.center.dx,
      top <= bottom ? _centre.dy.clamp(top, bottom) : widget.sheet.center.dy,
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
