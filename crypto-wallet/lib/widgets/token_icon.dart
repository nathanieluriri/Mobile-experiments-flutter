import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../painting/glyphs.dart';

/// A round token badge in the token's brand colour.
class TokenIcon extends StatelessWidget {
  const TokenIcon({super.key, required this.id, this.size = 44});

  final TokenId id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.52;
    final (Color background, Widget glyph) = switch (id) {
      TokenId.eth => (
          const Color(0xFF627EEA),
          EthGlyph(size: iconSize, color: Colors.white),
        ),
      TokenId.usdc => (
          const Color(0xFF2775CA),
          DollarGlyph(size: iconSize * 0.8, color: Colors.white),
        ),
      TokenId.btc => (
          const Color(0xFFF7931A),
          Icon(LucideIcons.bitcoin, size: iconSize * 1.15, color: Colors.white),
        ),
      TokenId.sol => (
          const Color(0xFF101014),
          SolanaBars(barWidth: size * 0.36, barHeight: size * 0.07, gap: size * 0.07),
        ),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: glyph,
    );
  }
}
