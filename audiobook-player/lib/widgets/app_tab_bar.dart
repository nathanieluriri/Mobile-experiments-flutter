import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/colors.dart';
import '../theme/layout.dart';

/// One destination in the tab bar.
class TabBarItem {
  const TabBarItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The four tabs, in the order the navigator declares them.
const tabBarItems = <TabBarItem>[
  TabBarItem(LucideIcons.bookOpen, 'Stories'),
  TabBarItem(LucideIcons.search, 'Search'),
  TabBarItem(LucideIcons.heart, 'Collection'),
  TabBarItem(LucideIcons.listMusic, 'Playlist'),
];

/// The bar along the bottom. It slides out of the way as the sheet opens, and
/// is gone by the time the sheet is 40 percent open.
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.sheetProgress,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Animation<double> sheetProgress;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final travel = Layout.tabBarHeight + bottomInset + 12;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedBuilder(
        animation: sheetProgress,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            0,
            (sheetProgress.value / 0.4).clamp(0.0, 1.0) * travel,
          ),
          child: child,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(
              top: BorderSide(color: AppColors.hairline, width: 1),
            ),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SizedBox(
            height: Layout.tabBarHeight,
            child: Row(
              children: [
                for (var i = 0; i < tabBarItems.length; i++)
                  Expanded(
                    child: _Tab(
                      item: tabBarItems[i],
                      focused: i == currentIndex,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.focused, required this.onTap});

  final TabBarItem item;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = focused ? AppColors.ink : AppColors.faint;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(item.label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}
