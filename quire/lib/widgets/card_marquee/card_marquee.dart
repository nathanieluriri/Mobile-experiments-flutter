import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import 'marquee_arc_item.dart';
import 'marquee_bottom_fade.dart';
import 'marquee_constants.dart';
import 'marquee_snap_physics.dart';

/// How many times an endless list is repeated before the slot it opens on.
/// Scrolling up runs out of items only after this many loops, which no one
/// reaches, so the loop has no seam in either direction.
const _copiesBeforeStart = 250;

/// Where an endless marquee of [count] items opens, in pixels.
double marqueeOrigin(int count) =>
    _copiesBeforeStart * count * kMarqueeItemHeight;

/// How far a finite marquee is padded before its first slot.
double finiteLeadingPadding(double viewportHeight) =>
    kFinitePaddingViewports * viewportHeight;

/// Where a finite marquee sits when item [index] is in the centre.
///
/// The list itself is hung one slot above the marquee so the item just out of
/// sight still paints, which is the extra slot height in this sum.
double finiteOrigin(int index, double viewportHeight) =>
    finiteLeadingPadding(viewportHeight) +
    index * kMarqueeItemHeight -
    kMarqueeItemHeight / 2 -
    viewportHeight / 2;

/// A column of cards wrapped around an arc that comes to rest on a card
/// boundary: a cylinder you spin with a thumb and it lands on one.
///
/// In [finite] mode the list has a real first and last item, as a document
/// does, and carries [kFinitePaddingViewports] viewports of padding at each end
/// so item one and item n can still reach the centre.
class CardMarquee extends StatefulWidget {
  const CardMarquee({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.finite = false,
    this.initialIndex = 0,
    this.viewportHeight,
    this.tilts,
    this.ground = AppColors.deskDeep,
    this.onItemTap,
  }) : assert(
          !finite || controller != null || viewportHeight != null,
          'a finite marquee needs its viewport height to know where to open',
        );

  final int itemCount;

  /// Builds the content of one slot, by item index.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Supply one to open the marquee somewhere other than its own origin.
  final ScrollController? controller;

  /// Whether the list ends, or wraps forever.
  final bool finite;

  /// Which item is in the centre when a finite marquee opens.
  final int initialIndex;

  /// The marquee's own height. Required for a finite marquee with no supplied
  /// controller, because the opening offset depends on it.
  final double? viewportHeight;

  /// Per item lean in degrees. Defaults to [marqueeTilts], which is seeded, so
  /// the stack is hand stacked and byte identical every run.
  final List<double>? tilts;

  final Color ground;

  /// Called when a slot is tapped, with its item index.
  final void Function(int index)? onItemTap;

  @override
  State<CardMarquee> createState() => _CardMarqueeState();
}

class _CardMarqueeState extends State<CardMarquee> {
  ScrollController? _owned;
  late List<double> _tilts = widget.tilts ?? marqueeTilts(widget.itemCount);

  ScrollController get _controller =>
      widget.controller ?? (_owned ??= ScrollController(
            initialScrollOffset: widget.finite
                ? finiteOrigin(widget.initialIndex, widget.viewportHeight!)
                : marqueeOrigin(widget.itemCount),
          ));

  @override
  void didUpdateWidget(CardMarquee old) {
    super.didUpdateWidget(old);
    if (widget.tilts != old.tilts || widget.itemCount != old.itemCount) {
      _tilts = widget.tilts ?? marqueeTilts(widget.itemCount);
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  double _tiltFor(int index) =>
      _tilts.isEmpty ? 0 : _tilts[index % _tilts.length];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = widget.viewportHeight ?? constraints.maxHeight;
        final padding =
            widget.finite ? finiteLeadingPadding(viewportHeight) : 0.0;
        return ClipRect(
          child: Stack(
            children: [
              // The list reaches one slot beyond the marquee at each end, so
              // the item just out of sight still paints the corner its lean
              // pushes back into view. The surrounding clip hides the rest.
              Positioned(
                left: 0,
                right: 0,
                top: -kMarqueeItemHeight,
                height: viewportHeight + kMarqueeItemHeight * 2,
                child: ListView.builder(
                  controller: _controller,
                  // Without this a list picks up the screen's safe area as
                  // content padding, which would push every slot down.
                  padding: widget.finite
                      ? EdgeInsets.symmetric(vertical: padding)
                      : EdgeInsets.zero,
                  physics: MarqueeSnapPhysics(
                    origin:
                        widget.finite ? finiteOrigin(0, viewportHeight) : 0,
                    parent: const BouncingScrollPhysics(),
                  ),
                  itemExtent: kMarqueeItemHeight,
                  itemCount: widget.finite ? widget.itemCount : null,
                  itemBuilder: (context, index) {
                    // An endless list is shifted one slot, so the item above
                    // the viewport is still built.
                    final slot = widget.finite ? index : index - 1;
                    final item = widget.finite
                        ? index
                        : slot % widget.itemCount;
                    return MarqueeArcItem(
                      slot: slot,
                      controller: _controller,
                      viewportHeight: viewportHeight,
                      itemTilt: _tiltFor(item),
                      leadingPadding: widget.finite
                          ? padding - kMarqueeItemHeight
                          : 0,
                      child: widget.onItemTap == null
                          ? widget.itemBuilder(context, item)
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onItemTap!(item),
                              child: widget.itemBuilder(context, item),
                            ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: kTopFadeHeight,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          widget.ground,
                          widget.ground.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MarqueeBottomFade(ground: widget.ground),
              ),
            ],
          ),
        );
      },
    );
  }
}
