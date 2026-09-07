import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';

const double _avatarSize = 48;

/// Avatar, handle and address with the QR and search actions.
class WalletHeader extends StatelessWidget {
  const WalletHeader({super.key, required this.profile});

  final WalletProfile profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: _avatarSize,
                height: _avatarSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const RadialGradient(
                    center: Alignment(0.42 * 2 - 1, 0.62 * 2 - 1),
                    radius: 0.85,
                    colors: [
                      Color(0xFF3D0A54),
                      Color(0xFFB01BD6),
                      Color(0xFFE44BE0),
                      Color(0xFFF26BD8),
                    ],
                    stops: [0, 0.45, 0.8, 1],
                  ),
                ),
              ),
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${profile.username}',
                  style: text(16, weight: FontWeight.w700, lineHeight: 24),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.address,
                  style: text(14, color: AppColors.subtle, lineHeight: 20),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.qrCode, size: 22, color: AppColors.ink),
          const SizedBox(width: 20),
          const Icon(LucideIcons.search, size: 22, color: AppColors.ink),
        ],
      ),
    );
  }
}
