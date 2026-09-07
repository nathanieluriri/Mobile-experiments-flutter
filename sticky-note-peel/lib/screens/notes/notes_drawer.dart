import 'package:flutter/widgets.dart';

import '../../data/note.dart';
import '../../painting/fold_painter.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// How wide the panel is: most of a narrow phone, capped so it does not swallow
/// a wide one.
double drawerWidth(double screenWidth) =>
    (screenWidth * kDrawerWidthFraction).clamp(0, kDrawerMaxWidth);

/// The panel that slides in from the left, holding one row per list.
///
/// Rows are small sheets of paper with a turned corner, in the colour of the
/// first note carrying that tag, so the menu is made of the same material as
/// the list behind it.
class NotesDrawer extends StatelessWidget {
  const NotesDrawer({
    super.key,
    required this.notes,
    required this.tagCounts,
    required this.selected,
    required this.onSelect,
    required this.topPadding,
    required this.bottomPadding,
  });

  final List<Note> notes;
  final Map<String, int> tagCounts;

  /// The tag being shown, or null for everything.
  final String? selected;

  final ValueChanged<String?> onSelect;
  final double topPadding;
  final double bottomPadding;

  /// The colour of the first note carrying [tag], so a list looks like the
  /// notes inside it.
  Color _colorOf(String tag) {
    for (final note in notes) {
      if (note.tags.contains(tag)) {
        return note.color;
      }
    }
    return AppColors.white;
  }

  @override
  Widget build(BuildContext context) {
    final tags = tagCounts.keys.toList();
    return ColoredBox(
      color: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.only(
          top: topPadding + kDrawerPadding,
          left: kDrawerPadding,
          right: kDrawerPadding,
          bottom: bottomPadding + kDrawerPadding,
        ),
        children: [
          _DrawerRow(
            label: kNotesScreenTitle,
            count: notes.length,
            color: AppColors.ink,
            labelColor: AppColors.white,
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: kDrawerSectionGap),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'Lists',
                style: TextStyle(
                  fontFamily: kFontFamily,
                  fontWeight: FontWeights.semiBold,
                  fontSize: 11,
                  height: kLineHeight,
                  color: AppColors.dockLabel,
                ),
              ),
            ),
            for (final tag in tags) ...[
              _DrawerRow(
                label: tag,
                count: tagCounts[tag]!,
                color: _colorOf(tag),
                labelColor: AppColors.noteText,
                selected: selected == tag,
                onTap: () => onSelect(tag),
              ),
              const SizedBox(height: kDrawerRowGap),
            ],
          ],
        ],
      ),
    );
  }
}

/// One list in the panel: a small sheet with a turned corner, its name, and how
/// many notes are in it.
class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.label,
    required this.count,
    required this.color,
    required this.labelColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final Color labelColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressFade(
      onTap: onTap,
      semanticLabel: '$label, $count notes',
      child: SizedBox(
        height: kDrawerRowHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(kDrawerRowRadius),
                  border: selected
                      ? Border.all(color: AppColors.white, width: 1.5)
                      : null,
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: FoldPainter.atRest(
                  restInset: kDrawerFoldInset,
                  background: AppColors.surface,
                  flapColor: shade(color, kNoteFlapShade),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          fontWeight: FontWeights.semiBold,
                          fontSize: 13,
                          height: kLineHeight,
                          color: labelColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: kDrawerFoldInset + 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: kFontFamily,
                        fontWeight: FontWeights.medium,
                        fontSize: 12,
                        height: kLineHeight,
                        color: labelColor.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
