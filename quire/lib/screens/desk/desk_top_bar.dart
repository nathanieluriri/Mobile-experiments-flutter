import 'package:flutter/widgets.dart';

import '../../painting/hamburger_painter.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import 'search_pill.dart';

/// Between the hamburger, the pill and the avatar.
const kTopBarGap = 8.0;

/// Where the menu button sits, which both the bar and the shell need to know:
/// the bar so it can leave the room, the shell so it can put the button there.
const kMenuButtonTop = (kTopBarHeight - kBurgerTarget) / 2;

/// The top bar: the way into the library, and the person holding the phone.
///
/// Two objects and no title. The app's name is not on it, because a bar that
/// spends its width saying `quire` to somebody already inside quire has spent
/// it badly.
///
/// The menu button is missing from the row on purpose. It is the drawer's own
/// handle, so it is drawn above the drawer instead of under it, and the bar
/// leaves exactly its room. A glyph that turned into an arrow behind an opaque
/// panel would be a morph nobody ever sees.
class DeskTopBar extends StatelessWidget {
  const DeskTopBar({super.key, required this.search});

  final SearchPill search;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kTopBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kTopBarPaddingX),
        child: Row(
          children: [
            const SizedBox(width: kBurgerTarget),
            const SizedBox(width: kTopBarGap),
            Expanded(child: search),
            const SizedBox(width: kTopBarGap),
            const _Avatar(letter: 'N'),
          ],
        ),
      ),
    );
  }
}

/// The menu button: three lines that are already part way into being an arrow,
/// wherever the drawer has got to.
class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.progress,
    required this.onTap,
  });

  /// Where the drawer is, 0 shut and 1 fully in. The glyph reads this and
  /// nothing else, so it can never be out of step with the panel.
  final double progress;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      semanticLabel: 'Menu',
      child: HamburgerGlyph(progress: progress),
    );
  }
}

/// The three lines, at whatever point of their turn the drawer has reached.
class HamburgerGlyph extends StatelessWidget {
  const HamburgerGlyph({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kBurgerTarget,
      height: kBurgerTarget,
      child: CustomPaint(
        painter: HamburgerPainter(
          progress: progress,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// One letter on a green disc. The only thing on the screen that stands for a
/// person rather than for a document.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kAvatarSize,
      height: kAvatarSize,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.avatar,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: AppText.avatar.copyWith(color: AppColors.onAccent),
      ),
    );
  }
}
