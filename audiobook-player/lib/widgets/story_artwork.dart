import 'package:flutter/widgets.dart';

import '../theme/colors.dart';

/// A square picture with rounded corners, fading in once it has decoded.
class StoryArtwork extends StatelessWidget {
  const StoryArtwork({
    super.key,
    required this.asset,
    required this.size,
    required this.borderRadius,
    this.placeholder = AppColors.artworkBackdrop,
  });

  final String asset;
  final double size;
  final double borderRadius;
  final Color placeholder;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: placeholder,
        child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover),
      ),
    );
  }
}
