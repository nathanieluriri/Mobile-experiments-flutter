import 'package:flutter/widgets.dart';

import '../../data/marquee_item.dart';
import '../../theme/palette.dart';
import 'marquee_arc_item.dart';
import 'marquee_bottom_fade.dart';
import 'marquee_constants.dart';
import 'marquee_snap_physics.dart';

/// How many times the list is repeated before the slot the marquee opens on.
/// Scrolling up runs out of cards only after this many loops, which no one
/// reaches, so the loop has no seam in either direction.
const _copiesBeforeStart = 250;

/// Where the marquee opens, in pixels, for a list of [count] cards.
double marqueeOrigin(int count) =>
    _copiesBeforeStart * count * kMarqueeItemHeight;

/// An endless column of cards, wrapped around an arc, that comes to rest on a
/// card boundary.
class CardMarquee extends StatefulWidget {
  const CardMarquee({super.key, required this.items, this.controller});

  final List<MarqueeItem> items;

  /// Supply one to open the marquee somewhere other than [marqueeOrigin].
  final ScrollController? controller;

  @override
  State<CardMarquee> createState() => _CardMarqueeState();
}

class _CardMarqueeState extends State<CardMarquee> {
  ScrollController? _owned;

  ScrollController get _controller =>
      widget.controller ??
      (_owned ??= ScrollController(
        initialScrollOffset: marqueeOrigin(widget.items.length),
      ));

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
        final ground = AppPalette.of(context).background;
        return ClipRect(
          child: Stack(
            children: [
              // The list reaches one slot beyond the marquee at each end, so
              // the card just out of sight still paints the corner its lean
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
                  padding: EdgeInsets.zero,
                  physics: const MarqueeSnapPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  itemExtent: kMarqueeItemHeight,
                  itemBuilder: (context, index) {
                    final slot = index - 1;
                    return MarqueeArcItem(
                      item: widget.items[slot % widget.items.length],
                      slot: slot,
                      controller: _controller,
                      viewportHeight: viewportHeight,
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
                        colors: [ground, ground.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MarqueeBottomFade(),
              ),
            ],
          ),
        );
      },
    );
  }
}
