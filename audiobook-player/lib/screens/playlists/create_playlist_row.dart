import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../painting/dashed_border.dart';

/// The dashed row that would start a new playlist.
class CreatePlaylistRow extends StatelessWidget {
  const CreatePlaylistRow({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const DashedBorderPainter(
        color: AppColors.faint,
        strokeWidth: 2,
        radius: 22,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                LucideIcons.plus,
                size: 22,
                color: AppColors.sub,
              ),
            ),
            const SizedBox(width: 14),
            const Text(
              'New playlist',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
