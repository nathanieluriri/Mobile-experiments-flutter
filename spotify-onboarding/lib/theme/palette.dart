import 'package:flutter/material.dart';

import 'colors.dart';

/// The surfaces of the flow, in the two grounds it can be drawn on.
///
/// The two are a swap rather than a recolour: what the flow is written in
/// becomes what it is drawn on. The call to action swaps too, so the button is
/// a near black slab carrying a coloured label on white, and a slab of that
/// same colour carrying a near black label on black.
@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.ink,
    required this.pill,
    required this.pillLabel,
    required this.invertCta,
  });

  /// What the flow is drawn on.
  final Color background;

  /// What the flow is written in.
  final Color ink;

  /// Background and label of the Skip pill.
  final Color pill;
  final Color pillLabel;

  /// Whether the call to action takes the step's accent as its own colour
  /// instead of carrying it as a label.
  final bool invertCta;

  static const light = AppPalette(
    background: AppColors.white,
    ink: AppColors.ink,
    pill: Color(0xFFF1F1F1),
    pillLabel: Color(0xFF6F6F73),
    invertCta: false,
  );

  static const dark = AppPalette(
    background: AppColors.pitch,
    ink: AppColors.paper,
    pill: Color(0xFF1E1E20),
    pillLabel: Color(0xFFA3A3A8),
    invertCta: true,
  );

  /// Secondary text reads on both grounds, so it is the same either way.
  Color get muted => AppColors.muted;

  /// The call to action's slab, given the step's [accent].
  Color ctaSurface(Color accent) => invertCta ? accent : AppColors.ink;

  /// The mark and label on that slab.
  Color ctaContent(Color accent) => invertCta ? AppColors.ink : accent;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
