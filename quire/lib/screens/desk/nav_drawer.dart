import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import 'shell_model.dart';

/// How far a row is held off the panel's own edges, so a selected row reads as
/// a pill inside the drawer rather than as a band across it.
const kDrawerMargin = 12.0;

/// The room above the first row and below the last.
///
/// There is no header over the rows. The app does not need to say its own name
/// to somebody already inside it. The rows start under the top bar's own
/// height because the menu button stays above the panel, and the first row
/// must not slide under the arrow it turned into.
const kDrawerHeadTop = 8.0;
const kDrawerHeadBottom = 20.0;

/// Above and below the divider between the two groups.
const kDrawerDividerGap = 8.0;

/// The navigation drawer, over a scrim, over the shell.
///
/// It is chrome and not a document: no fold, no grain, no corner to turn. The
/// one thing it borrows from the paper is that it is opaque, because a panel
/// you can read the library through would be a panel you cannot read.
class NavDrawer extends StatelessWidget {
  const NavDrawer({
    super.key,
    required this.progress,
    required this.selected,
    required this.onSelect,
    required this.onDismiss,
    required this.onDrag,
    required this.onDragEnd,
  });

  /// 0 shut, 1 fully in. The panel's offset and the hamburger's turn are both
  /// read off this one number.
  final double progress;

  final DrawerDestination selected;
  final ValueChanged<DrawerDestination> onSelect;
  final VoidCallback onDismiss;

  /// A finger on the panel, in logical points since the drag began.
  final ValueChanged<double> onDrag;

  /// The finger leaving, with the velocity it left at.
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final width = drawerWidth(MediaQuery.sizeOf(context).width);
    return IgnorePointer(
      ignoring: p <= 0,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: Opacity(
                opacity: p,
                child: const ColoredBox(color: AppColors.scrim),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: width,
            child: Transform.translate(
              offset: Offset(-width * (1 - p), 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // The panel follows the finger from the moment it lands, rather
              // than from the moment the drag is recognised, so the first
              // eighteen points of the pull are not thrown away.
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragUpdate: (details) =>
                    onDrag(details.primaryDelta ?? 0),
                onHorizontalDragEnd: (details) =>
                    onDragEnd(details.velocity.pixelsPerSecond.dx),
                child: _Panel(selected: selected, onSelect: onSelect),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.selected, required this.onSelect});

  final DrawerDestination selected;
  final ValueChanged<DrawerDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: AppColors.surface,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: top + kTopBarHeight + kDrawerHeadTop,
          bottom: MediaQuery.paddingOf(context).bottom + kDrawerHeadBottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final destination in DrawerDestination.values) ...[
              _Row(
                destination: destination,
                selected: destination == selected,
                onSelect: onSelect,
              ),
              if (destination == kDrawerLastOfGroup) _divider(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          kDrawerDividerInset,
          kDrawerDividerGap,
          kDrawerDividerInset,
          kDrawerDividerGap,
        ),
        child: SizedBox(
          height: hairline(context),
          child: const ColoredBox(color: AppColors.hairline),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.destination,
    required this.selected,
    required this.onSelect,
  });

  final DrawerDestination destination;
  final bool selected;
  final ValueChanged<DrawerDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kDrawerMargin),
      child: PaperPress(
        onTap: () => onSelect(destination),
        semanticLabel: destination.label,
        child: Container(
          height: kDrawerRowHeight,
          padding:
              const EdgeInsets.symmetric(horizontal: kDrawerRowPaddingX),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentMuted : null,
            borderRadius: BorderRadius.circular(kDrawerRowRadius),
          ),
          child: Row(
            children: [
              Icon(
                destination.icon,
                size: kDrawerRowGlyph,
                color: AppColors.ink,
              ),
              const SizedBox(width: kDrawerRowGap),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (selected
                          ? AppText.drawerRowSelected
                          : AppText.drawerRow)
                      .copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
