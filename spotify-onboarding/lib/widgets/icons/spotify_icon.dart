import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/colors.dart';

const _logo =
    'M83.996.277C37.747.277.253 37.77.253 84.019'
    'c0 46.251 37.494 83.741 83.743 83.741 46.254 0 83.744-37.49 83.744-83.741 0-46.246-37.49-83.738-83.745-83.738'
    'l.001-.004zm38.404 120.78a5.217 5.217 0 01-7.18 1.73'
    'c-19.662-12.01-44.414-14.73-73.564-8.07'
    'a5.222 5.222 0 01-6.249-3.93 5.213 5.213 0 013.926-6.25'
    'c31.9-7.291 59.263-4.15 81.337 9.34 2.46 1.51 3.24 4.72 1.73 7.18'
    'zm10.25-22.805'
    'c-1.89 3.075-5.91 4.045-8.98 2.155-22.51-13.839-56.823-17.846-83.448-9.764-3.453 1.043-7.1-.903-8.148-4.35'
    'a6.538 6.538 0 014.354-8.143'
    'c30.413-9.228 68.222-4.758 94.072 11.127 3.07 1.89 4.04 5.91 2.15 8.976'
    'v-.001zm.88-23.744'
    'c-26.99-16.031-71.52-17.505-97.289-9.684-4.138 1.255-8.514-1.081-9.768-5.219'
    'a7.835 7.835 0 015.221-9.771'
    'c29.581-8.98 78.756-7.245 109.83 11.202'
    'a7.823 7.823 0 012.74 10.733c-2.2 3.722-7.02 4.949-10.73 2.739'
    'z';

const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 168 168">'
    '<path d="$_logo" fill="#000" fill-rule="evenodd"/></svg>';

/// Spotify wordless logo. With a [discColor] the waves sit on a filled circle,
/// otherwise they stand alone.
class SpotifyIcon extends StatelessWidget {
  const SpotifyIcon({
    super.key,
    required this.size,
    this.color = AppColors.spotify,
    this.discColor,
  });

  final double size;
  final Color color;
  final Color? discColor;

  @override
  Widget build(BuildContext context) {
    final waves = SvgPicture.string(
      _svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
    if (discColor == null) {
      return waves;
    }
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: discColor, shape: BoxShape.circle),
        child: waves,
      ),
    );
  }
}
