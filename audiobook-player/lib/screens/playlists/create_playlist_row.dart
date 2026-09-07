import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../painting/dashed_border.dart';
import '../../theme/colors.dart';
import '../../widgets/pressable.dart';

/// How thick the dashed outline is. It takes up room of its own, so the row
/// stands 4 taller than a tinted one and its contents sit 2 further in.
const _borderWidth = 2.0;

/// The dashed row that would start a new playlist.
class CreatePlaylistRow extends StatelessWidget {
  const CreatePlaylistRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      heldOpacity: 0.7,
      child: CustomPaint(
        painter: const DashedBorderPainter(
          color: AppColors.faint,
          strokeWidth: _borderWidth,
          radius: 22,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10 + _borderWidth),
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
      ),
    );
  }
}
