import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models.dart';
import '../../painting/glyphs.dart';
import '../../theme/theme.dart';
import '../../utils/format.dart';

/// The white sheet of holdings below the action bar.
class AssetList extends StatelessWidget {
  const AssetList({super.key, required this.assets});

  final List<Asset> assets;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [for (final asset in assets) _AssetRow(asset: asset)],
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final changeColor = asset.change >= 0 ? AppColors.gain : AppColors.loss;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          AssetIcon(id: asset.id),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asset.name, style: text(16, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  formatQuantity(asset.quantity, asset.symbol),
                  style: text(14, color: AppColors.subtle, lineHeight: 20),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatUsd(asset.value), style: text(16, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                formatSigned(asset.change),
                style: text(14, weight: FontWeight.w500, color: changeColor, lineHeight: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 44 px badge in front of each holding.
class AssetIcon extends StatelessWidget {
  const AssetIcon({super.key, required this.id});

  final TokenId id;

  @override
  Widget build(BuildContext context) {
    final (Color background, Widget? glyph) = switch (id) {
      TokenId.eth => (
          AppColors.chip,
          const EthGlyph(size: 24, color: Color(0xFF454A54)),
        ),
      TokenId.usdc => (
          const Color(0xFF2775CA),
          const Icon(LucideIcons.dollarSign, size: 18, color: AppColors.white),
        ),
      TokenId.sol => (
          const Color(0xFF101014),
          const SolanaBars(barWidth: 16, barHeight: 3, gap: 3),
        ),
      TokenId.btc => (AppColors.chip, null),
    };
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: glyph,
    );
  }
}
