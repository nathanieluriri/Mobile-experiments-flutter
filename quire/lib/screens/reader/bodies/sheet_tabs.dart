import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../constants/gooey_fab.dart'
    show kGooAlphaThresholdMatrix, kGooBlurSigma;
import '../../../painting/tab_goo_painter.dart';
import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/press_fade.dart';

/// The air between one sheet's name and the next.
const kSheetTabGap = 8.0;

/// How far through the journey the chip's own fill takes over from the goo.
const kSheetTabHandover = 0.15;

/// The sheets of a workbook, along the foot of the reader.
///
/// The foot rather than the head, because that is where a thumb is and
/// because the reader's own band lives at the top: two rows of chrome over
/// one document is one row too many.
///
/// The sheet you are on is a filled pill, and the fill travels: it gathers
/// out of the old pill, crosses the row on a thread, and opens into the new
/// one. Nothing here switches, because a workbook is one document and moving
/// between its sheets is moving through it.
class SheetTabs extends StatefulWidget {
  const SheetTabs({
    super.key,
    required this.names,
    required this.active,
    this.onSelect,
    this.onAll,
  });

  final List<String> names;
  final int active;
  final void Function(int index)? onSelect;

  /// Opens the list of every sheet, for a workbook with more of them than the
  /// foot of a phone can show.
  final VoidCallback? onAll;

  @override
  State<SheetTabs> createState() => _SheetTabsState();
}

class _SheetTabsState extends State<SheetTabs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: kTabTravel,
    value: 1,
  );

  final GlobalKey _content = GlobalKey();
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};

  /// The sheet the fill is leaving, or null when it has arrived.
  int? _from;

  GlobalKey _keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  @override
  void didUpdateWidget(SheetTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _from = oldWidget.active;
      _travel.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  /// Where a sheet's pill sits, in the strip's own coordinates.
  Rect? _rectOf(int index) {
    final box = _keys[index]?.currentContext?.findRenderObject();
    final content = _content.currentContext?.findRenderObject();
    if (box is! RenderBox || content is! RenderBox || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: content) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kSheetTabHeight,
      decoration: const BoxDecoration(
        color: AppColors.ground,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: <Widget>[
          if (widget.onAll != null)
            PaperPress(
              onTap: widget.onAll,
              semanticLabel: 'Every sheet in this workbook',
              child: const SizedBox(
                width: kSheetTabHeight,
                height: kSheetTabHeight,
                child: Icon(
                  LucideIcons.list,
                  size: kSheetTabGlyph,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: kSheetTabGap),
              child: AnimatedBuilder(
                animation: _travel,
                builder: (context, _) {
                  final settled = _travel.value >= 1 - kSheetTabHandover;
                  return Stack(
                    key: _content,
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      _row(filled: settled, faces: true),
                      Positioned.fill(
                        child: IgnorePointer(child: _travelling()),
                      ),
                      _row(filled: settled, faces: false),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One pass of the row: the pills, or the names over them.
  Widget _row({required bool filled, required bool faces}) => Row(
    children: <Widget>[
      for (var i = 0; i < widget.names.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(width: kSheetTabGap),
        _Tab(
          key: faces ? _keyFor(i) : null,
          name: widget.names[i],
          chosen: i == widget.active,
          filled: i == widget.active && filled,
          face: faces,
          onTap: widget.onSelect == null ? null : () => widget.onSelect!(i),
        ),
      ],
    ],
  );

  /// The fill on its way between sheets, or nothing once it is home.
  Widget _travelling() {
    final from = _from;
    if (from == null || _travel.value >= 1) return const SizedBox.shrink();
    final a = _rectOf(from);
    final b = _rectOf(widget.active);
    if (a == null || b == null) return const SizedBox.shrink();
    final fade = ui.lerpDouble(
      1,
      0,
      ((_travel.value - (1 - kSheetTabHandover)) / kSheetTabHandover).clamp(
        0.0,
        1.0,
      ),
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
              t: _travel.value,
              colour: AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// One sheet's name, as a pill.
class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.name,
    required this.chosen,
    required this.filled,
    required this.face,
    this.onTap,
  });

  final String name;

  /// True for the sheet showing, which sets the name's colour at once even
  /// while the fill is still on its way.
  final bool chosen;

  /// True once the fill has arrived, which is when the pill wears it.
  final bool filled;

  /// True for the pill behind the name. The pass over it carries the press.
  final bool face;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: kSheetTabPill,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: kSheetTabPadX),
      decoration: BoxDecoration(
        color: face && filled ? AppColors.accent : null,
        borderRadius: BorderRadius.circular(kSheetTabPill / 2),
      ),
      child: Text(
        name,
        maxLines: 1,
        style: AppText.label.copyWith(
          color: face
              ? const Color(0x00000000)
              : chosen
              ? AppColors.onAccent
              : AppColors.inkSoft,
        ),
      ),
    );
    if (face) return pill;
    return PaperPress(
      onTap: onTap,
      semanticLabel: name,
      washRadius: kSheetTabPill / 2,
      child: pill,
    );
  }
}
