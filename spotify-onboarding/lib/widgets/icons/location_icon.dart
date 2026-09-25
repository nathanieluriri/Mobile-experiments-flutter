import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/colors.dart';

const _pin =
    'M12 4.8c-2.98 0-5.4 2.42-5.4 5.4 0 4.05 5.4 10 5.4 10s5.4-5.95 5.4-10'
    'c0-2.98-2.42-5.4-5.4-5.4zm0 7.33a1.93 1.93 0 110-3.86 1.93 1.93 0 010 3.86z';

String _svg({required bool inset}) {
  final transform = inset ? ' transform="translate(2.4 2.4) scale(0.8)"' : '';
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<path d="$_pin" fill="#000"$transform/></svg>';
}

/// Map pin. With a [discColor] the pin is inset inside a filled circle,
/// otherwise it stands alone.
class LocationIcon extends StatelessWidget {
  const LocationIcon({
    super.key,
    required this.size,
    this.color = AppColors.white,
    this.discColor,
  });

  final double size;
  final Color color;
  final Color? discColor;

  @override
  Widget build(BuildContext context) {
    final pin = SvgPicture.string(
      _svg(inset: discColor != null),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
    if (discColor == null) {
      return pin;
    }
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: discColor, shape: BoxShape.circle),
        child: pin,
      ),
    );
  }
}
