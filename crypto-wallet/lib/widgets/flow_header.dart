import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';
import 'pressable_scale.dart';

/// Back button, centred title and subtitle at the top of a flow.
class FlowHeader extends StatelessWidget {
  const FlowHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 4),
      child: Row(
        children: [
          PressableScale(
            scaleTo: 0.92,
            onPress: onBack,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.chevronLeft, size: 22, color: AppColors.ink),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(title, style: text(17, weight: FontWeight.w700)),
                Text(subtitle, style: text(12, color: AppColors.subtle)),
              ],
            ),
          ),
          const SizedBox(width: 44, height: 44),
        ],
      ),
    );
  }
}
