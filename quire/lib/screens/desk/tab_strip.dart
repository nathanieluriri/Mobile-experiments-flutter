import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../constants/gooey_fab.dart'
    show kGooAlphaThresholdMatrix, kGooBlurSigma;
import '../../painting/tab_goo_painter.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/digit_roll.dart';
import '../../widgets/press_fade.dart';
import 'shell_model.dart';

/// The share of the journey over which the travelling fill hands over to the
/// chip's own fill at the end, so the arrival is a hardening and not a cut.
const kTabGooHandover = 0.15;

/// The five format tabs, each carrying how much it holds.
///
/// The count is part of the tab rather than a badge on it, because the number
/// is what you are choosing between: DOCS with a 1 beside it tells you not to
/// bother before you have tapped it. It rolls rather than cuts, so a document
/// leaving the library moves one digit instead of repainting the row.
///
/// The selection travels. When the selected tab changes, its fill gathers
/// into a blob, crosses the row trailing a thread, and arrives at the new
/// chip, so the strip reads as one thing that moved and not as two things
/// that changed.
///
/// The strip is drawn in three layers so the fill can cross: the chips'
/// faces at the bottom, the goo above them, and the chips' labels on top.
/// Drawn under the chips the fill vanished behind every chip it passed and
/// seemed to come from the neighbour; drawn over them it would have hidden
/// the label of the chip it was arriving at. The two chip layers are the
/// same widgets with one half painted transparent, so they cannot disagree
/// about where anything is.
class TabStrip extends StatefulWidget {
  const TabStrip({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final DeskTab selected;

  /// How many documents each tab holds, before the search is applied.
  final Map<DeskTab, int> counts;

  final ValueChanged<DeskTab> onSelect;

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: kTabTravel,
    value: 1,
  );

  /// One key per tab, on the label layer, so a chip can be measured where it
  /// actually is.
  final Map<DeskTab, GlobalKey> _keys = <DeskTab, GlobalKey>{
    for (final tab in DeskTab.values) tab: GlobalKey(),
  };

  /// The strip's scrolling content, which is what chips are measured against
  /// so the goo scrolls with them.
  final GlobalKey _content = GlobalKey();

  /// The chip the fill is leaving, for as long as it is on its way.
  DeskTab? _from;

  @override
  void didUpdateWidget(TabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _from = oldWidget.selected;
      _travel.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  /// Where [tab]'s chip is, in the content's coordinates, or null before it
  /// has been laid out.
  Rect? _rectOf(DeskTab tab) {
    final content = _content.currentContext?.findRenderObject();
    final box = _keys[tab]?.currentContext?.findRenderObject();
    if (content is! RenderBox || box is! RenderBox || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: content) & box.size;
  }

  Widget _row(_TabLayer layer, bool settled) {
    return Row(
      children: [
        for (final tab in DeskTab.values) ...[
          if (tab != DeskTab.values.first) const SizedBox(width: kTabGap),
          _Tab(
            key: layer == _TabLayer.label ? _keys[tab] : null,
            layer: layer,
            tab: tab,
            selected: tab == widget.selected,
            filled: tab == widget.selected && settled,
            count: widget.counts[tab] ?? 0,
            onSelect: widget.onSelect,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kTabStripHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kTabStripPaddingX),
        child: AnimatedBuilder(
          animation: _travel,
          builder: (context, _) {
            // The chip's own fill takes over at the end of the journey.
            final settled = _travel.value >= 1 - kTabGooHandover;
            return Stack(
              key: _content,
              clipBehavior: Clip.none,
              children: [
                _row(_TabLayer.face, settled),
                Positioned.fill(child: IgnorePointer(child: _travelling())),
                _row(_TabLayer.label, settled),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The fill on its way between chips, or nothing when it has arrived.
  Widget _travelling() {
    final from = _from;
    if (from == null || _travel.value >= 1) return const SizedBox.shrink();
    final a = _rectOf(from);
    final b = _rectOf(widget.selected);
    if (a == null || b == null) return const SizedBox.shrink();
    final t = _travel.value;
    // Fades over the handover so the chip's fill appears under it rather
    // than beside it: the threshold leaves the goo's edge a pixel outside
    // the chip's, and a pixel of rim round a settled chip reads as a fault.
    final fade = ui.lerpDouble(
      1,
      0,
      ((t - (1 - kTabGooHandover)) / kTabGooHandover).clamp(0.0, 1.0),
    )!;
    return Opacity(
      opacity: fade,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(kGooAlphaThresholdMatrix),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: kGooBlurSigma,
            sigmaY: kGooBlurSigma,
            tileMode: TileMode.decal,
          ),
          child: CustomPaint(
            painter: TabGooPainter(
              from: a,
              to: b,
              t: t,
              colour: AppColors.accentMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Which half of a chip a [_Tab] paints.
enum _TabLayer {
  /// The pill behind the words. Not tappable: the label layer over it is.
  face,

  /// The words, over a transparent pill. Carries the press and the wash.
  label,
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.layer,
    required this.tab,
    required this.selected,
    required this.filled,
    required this.count,
    required this.onSelect,
  });

  final _TabLayer layer;
  final DeskTab tab;

  /// Whether this is the chosen tab, which sets the label's colour at once.
  final bool selected;

  /// Whether the face draws its fill, which it does not while the fill is
  /// still on its way to it.
  final bool filled;

  final int count;
  final ValueChanged<DeskTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final face = layer == _TabLayer.face;
    // Transparent rather than absent, so both layers lay out the same words
    // at the same size and the label lands exactly over the face.
    const clear = Color(0x00000000);
    final chip = Container(
      height: kTabPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: kTabPillPaddingX),
      decoration: BoxDecoration(
        color: !face
            ? clear
            : filled
                ? AppColors.accentMuted
                : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(kTabPillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tab.label,
            style: AppText.label.copyWith(
              color: face
                  ? clear
                  : selected
                      ? AppColors.ink
                      : AppColors.inkSoft,
            ),
          ),
          const SizedBox(width: kTabCountGap),
          DigitRoll(
            '$count',
            style: AppText.cell,
            color: face ? clear : AppColors.inkFaint,
          ),
        ],
      ),
    );
    if (face) return chip;
    return PaperPress(
      onTap: () => onSelect(tab),
      semanticLabel: '${tab.label} $count',
      washRadius: kTabPillRadius,
      child: chip,
    );
  }
}
