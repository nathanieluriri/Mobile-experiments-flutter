import 'package:flutter/widgets.dart';

import '../theme/colors.dart';

/// The large title every tab opens with.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
          color: AppColors.ink,
        ),
      ),
    );
  }
}
