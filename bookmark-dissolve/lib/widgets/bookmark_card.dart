import 'package:flutter/widgets.dart';

import '../theme/index.dart';
import 'close_button.dart';

const kCardRadius = 22.0;
const kCardHeaderHeight = 40.0;

/// One bookmark: a title bar with the site's mark and a close button, and a
/// preview of the page below it.
///
/// [cardKey] is attached to the repaint boundary the dissolve snapshots, which
/// is the rounded, clipped box inside the shadow.
class BookmarkCard extends StatelessWidget {
  const BookmarkCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onClose,
    required this.child,
    this.cardKey,
  });

  final String title;
  final Widget icon;
  final VoidCallback onClose;
  final Widget child;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(kCardRadius),
        boxShadow: AppShadows.card,
      ),
      child: RepaintBoundary(
        key: cardKey,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kCardRadius),
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Column(
              children: [
                SizedBox(
                  height: kCardHeaderHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      icon,
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text(size: 14, weight: FontWeight.w500, color: AppColors.ink),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CardCloseButton(onPressed: onClose),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
