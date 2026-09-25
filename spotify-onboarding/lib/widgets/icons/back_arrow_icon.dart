import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/colors.dart';

const _arrow =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">'
    '<path d="M19 12H5m0 0l6-6m-6 6l6 6" stroke="#000" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round"/></svg>';

/// Left pointing arrow in the onboarding header.
class BackArrowIcon extends StatelessWidget {
  const BackArrowIcon({super.key, this.size = 22, this.color = AppColors.ink});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _arrow,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
