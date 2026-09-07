import 'package:flutter/widgets.dart';

import '../data/marquee_item.dart';
import '../theme/shadows.dart';
import '../theme/typography.dart';

/// One card: a coloured slab with the name on the left and a picture on the
/// right.
class MarqueeCard extends StatelessWidget {
  const MarqueeCard({super.key, required this.item});

  static const width = 300.0;
  static const height = 92.0;

  final MarqueeItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.only(left: 20, right: 8),
      decoration: BoxDecoration(
        color: item.backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [cardShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.cardTitle.copyWith(color: item.textColor),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              item.imageAsset,
              width: 76,
              height: 76,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }
}
