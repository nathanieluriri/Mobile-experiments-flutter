import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import '../desk/desk_sheet.dart';

const double kSwatchSize = 40.0;

/// A number the sheet can step, such as a size or a thickness.
class SheetStep {
  const SheetStep({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
    this.less = 'Less',
    this.more = 'More',
  });

  final String label;

  /// What the two buttons are called to a screen reader.
  final String less;
  final String more;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final ValueChanged<double> onChanged;
}

/// Colours to pick from and, when the thing has one, a number to step,
/// changed as they are touched so the page behind shows each choice.
class SwatchSheet extends StatefulWidget {
  const SwatchSheet({
    super.key,
    required this.title,
    required this.colours,
    required this.colour,
    required this.onColour,
    this.step,
    this.more = const <SheetStep>[],
  });

  final String title;
  final List<(int, String)> colours;
  final int colour;
  final ValueChanged<int> onColour;
  final SheetStep? step;

  /// Further settings stepped the same way, such as opacity.
  final List<SheetStep> more;

  List<SheetStep> get steps => <SheetStep>[?step, ...more];

  @override
  State<SwatchSheet> createState() => _SwatchSheetState();
}

class _SwatchSheetState extends State<SwatchSheet> {
  late int _colour = widget.colour;
  late final List<double> _values = <double>[for (final step in widget.steps) step.value];

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    return DeskSheet(
      title: widget.title,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX, vertical: 8),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: <Widget>[
              for (final (argb, name) in widget.colours)
                PaperPress(
                  onTap: () {
                    setState(() => _colour = argb);
                    widget.onColour(argb);
                  },
                  semanticLabel: name,
                  child: Container(
                    width: kSwatchSize,
                    height: kSwatchSize,
                    decoration: BoxDecoration(
                      color: Color(argb),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: argb == _colour ? AppColors.accentBright : AppColors.hairline,
                        width: argb == _colour ? 3 : 1,
                      ),
                    ),
                    child: argb == _colour
                        ? Icon(
                            LucideIcons.check,
                            size: 18,
                            color: Color(argb).computeLuminance() > 0.5
                                ? AppColors.pageInk
                                : AppColors.page,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(kDeskSheetPadX, 8, kDeskSheetPadX, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(steps[i].label, style: AppText.menuRow.copyWith(color: AppColors.ink)),
                ),
                _StepButton(
                  icon: LucideIcons.minus,
                  label: steps[i].less,
                  enabled: _values[i] - steps[i].step >= steps[i].min - 0.001,
                  onTap: () => _stepBy(i, -steps[i].step),
                ),
                SizedBox(
                  width: 72,
                  child: Center(
                    child: Text(
                      '${_values[i].toStringAsFixed(_values[i] % 1 == 0 ? 0 : 1)} ${steps[i].unit}',
                      style: AppText.menuRow.copyWith(color: AppColors.ink),
                    ),
                  ),
                ),
                _StepButton(
                  icon: LucideIcons.plus,
                  label: steps[i].more,
                  enabled: _values[i] + steps[i].step <= steps[i].max + 0.001,
                  onTap: () => _stepBy(i, steps[i].step),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _stepBy(int index, double by) {
    final step = widget.steps[index];
    final next = (_values[index] + by).clamp(step.min, step.max).toDouble();
    setState(() => _values[index] = next);
    step.onChanged(next);
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: PaperPress(
        onTap: onTap,
        enabled: enabled,
        semanticLabel: label,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AppColors.surfaceHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: AppColors.ink),
        ),
      ),
    );
  }
}
