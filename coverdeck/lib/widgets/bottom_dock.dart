import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../painting/glyphs.dart';
import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/springs.dart';
import '../theme/typography.dart';
import 'glyph_icon.dart';
import 'tab_bar_controller.dart';

const _items = <({TabGlyph glyph, String label})>[
  (glyph: TabGlyph.deck, label: 'Deck'),
  (glyph: TabGlyph.browse, label: 'Browse'),
  (glyph: TabGlyph.library, label: 'Library'),
];

/// The floating tab pill.
///
/// Its padding springs between the labelled and compact shapes while the
/// labels themselves appear and disappear at once.
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

class _BottomDockState extends State<BottomDock> with SingleTickerProviderStateMixin {
  late final AnimationController _shape = AnimationController.unbounded(
    vsync: this,
    value: widget.controller.compact ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleShapeChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleShapeChange);
    _shape.dispose();
    super.dispose();
  }

  void _handleShapeChange() {
    _shape.animateWith(
      SpringSimulation(
        dockLayoutSpring,
        _shape.value,
        widget.controller.compact ? 1 : 0,
        _shape.velocity,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.controller.compact;
    return AnimatedBuilder(
      animation: _shape,
      builder: (context, _) {
        final t = _shape.value;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: 6,
            vertical: lerpDouble(8, 5, t)!,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.82),
            borderRadius: const BorderRadius.all(Radius.circular(30)),
            border: Border.all(
              color: const Color(0xFF000000).withValues(alpha: 0.06),
              width: hairlineWidth(context),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
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
                  horizontalPadding: lerpDouble(22, 16, t)!,
                  onTap: () {
                    widget.controller.expand();
                    widget.onSelect(index);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.glyph,
    required this.label,
    required this.active,
    required this.compact,
    required this.horizontalPadding,
    required this.onTap,
  });

  final TabGlyph glyph;
  final String label;
  final bool active;
  final bool compact;
  final double horizontalPadding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.secondaryLabel;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: horizontalPadding),
        decoration: active
            ? BoxDecoration(
                color: const Color(0xFF000000).withValues(alpha: 0.05),
                borderRadius: const BorderRadius.all(Radius.circular(22)),
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
    );
  }
}
