import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../widgets/screen_title.dart';

/// The Stories title with its two round buttons.
class StoriesHeader extends StatelessWidget {
  const StoriesHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ScreenTitle(title: 'Stories'),
          Row(
            children: [
              _HeaderIconButton(icon: LucideIcons.bell),
              SizedBox(width: 12),
              _HeaderIconButton(icon: LucideIcons.user),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: AppColors.ink),
    );
  }
}
