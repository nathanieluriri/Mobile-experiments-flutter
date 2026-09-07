import 'package:flutter/widgets.dart';

import '../painting/glyphs.dart';
import '../painting/outer_shadow.dart';
import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/springs.dart';
import '../theme/typography.dart';
import 'glyph_icon.dart';
import 'spring_size.dart';
import 'tab_bar_controller.dart';

const _items = <({TabGlyph glyph, String label})>[
  (glyph: TabGlyph.deck, label: 'Deck'),
  (glyph: TabGlyph.browse, label: 'Browse'),
  (glyph: TabGlyph.library, label: 'Library'),
];

/// Corner radius of the pill.
const _pillRadius = BorderRadius.all(Radius.circular(30));

/// Corner radius of a selected tab's chip.
const _itemRadius = BorderRadius.all(Radius.circular(22));

/// The floating tab pill.
///
/// Its contents change shape at once when the dock collapses, while the pill
/// itself springs across the whole difference and clips whatever is still
/// hanging over the edge.
class BottomDock extends StatefulWidget {
  const BottomDock({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.controller,
  });

  final int selected;
  final ValueChanged<int> onSelect;
  final TabBarController controller;

  @override
  State<BottomDock> createState() => _BottomDockState();
}

class _BottomDockState extends State<BottomDock> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleShapeChange);
  }

  @override
  void didUpdateWidget(BottomDock old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_handleShapeChange);
      widget.controller.addListener(_handleShapeChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleShapeChange);
    super.dispose();
  }

  void _handleShapeChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final compact = widget.controller.compact;
    final shape = RoundedSuperellipseBorder(
      borderRadius: _pillRadius,
      side: BorderSide(
        color: const Color(0xFF000000).withValues(alpha: 0.06),
        width: hairlineWidth(context),
      ),
    );

    // The pill swallows taps that land on its padding; only the strip around
    // it lets them through.
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: OuterShadowPainter(
          shape: shape,
          color: const Color(0xFF000000).withValues(alpha: 0.12),
          sigma: 9,
          offset: const Offset(0, 6),
        ),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.82),
            shape: shape,
          ),
          child: ClipRSuperellipse(
            borderRadius: _pillRadius,
            child: SpringSize(
              vsync: this,
              spring: dockLayoutSpring,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: compact ? 5 : 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, item) in _items.indexed)
                      _DockItem(
                        glyph: item.glyph,
                        label: item.label,
                        active: index == widget.selected,
                        compact: compact,
                        onTap: () {
                          widget.controller.expand();
                          widget.onSelect(index);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.glyph,
    required this.label,
    required this.active,
    required this.compact,
    required this.onTap,
  });

  final TabGlyph glyph;
  final String label;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.secondaryLabel;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: 6,
            horizontal: compact ? 16 : 22,
          ),
          decoration: active
              ? ShapeDecoration(
                  color: const Color(0xFF000000).withValues(alpha: 0.05),
                  shape: const RoundedSuperellipseBorder(
                    borderRadius: _itemRadius,
                  ),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabGlyphIcon(glyph: glyph, color: color),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    label,
                    style: AppText.dockLabel.copyWith(color: color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
