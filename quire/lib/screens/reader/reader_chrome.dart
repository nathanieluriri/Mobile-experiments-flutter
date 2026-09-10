import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../painting/overflow_dots_painter.dart';
import '../desk/desk_top_bar.dart' show HamburgerGlyph, kMenuButtonTop;
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// Floating chrome is an opaque control fill with a hairline round it.
///
/// The app draws no blur and casts no shadow, so a button that let the page
/// under it show through would have nothing left saying which surface is in
/// front. An opaque fill and one rule is how a printed page marks off a panel
/// from the text it lies on.
///
/// The fill is [AppColors.surfaceHigh] and not [AppColors.surface], because
/// chrome has to stand above every surface it can land on: a reading sheet is
/// [AppColors.surface] and the back of one is [AppColors.leafBack], so a
/// button in either of those values reads as a hole punched through the page
/// rather than as a control resting on it.

/// Where the head band goes when it leaves: far enough up that the whole band,
/// the part behind the status bar included, is off the screen.
const kHeadBandHidden = -kHeadBandHeight;

/// The size of the glyph inside a 38.5 header button.
const kChromeIcon = 20.0;

/// How wide the title is allowed to run before it ellipses, which is what
/// keeps it clear of the buttons at both ends.
const kReaderTitleWidth = 170.0;

/// How wide a line the band is saying may run.
///
/// Wider than the title, because a notice is a sentence and a title is a
/// name, and narrower than the band: the two buttons at the right end and the
/// one at the left are still there, and a line that ran under them would be a
/// line half of which cannot be read.
const kBandLabelWidth =
    kScreenWidth -
    (kScreenPadding + kHeaderButtonSize) * 2 -
    kHeaderButtonSize -
    kChromeButtonGap -
    kSpace12 * 2;

/// The head band: the way back, the document's name, and what can be done to
/// it, on an opaque band floating over the top of the page.
///
/// The band is opaque and covers the status bar, because the sheet underneath
/// it is the whole screen now: a title in the app's ink over a white page
/// would be unreadable, and a page that stopped short of the top to make room
/// would be the chrome taking a tenth of the screen for the whole reading.
///
/// It leaves entirely when the reader scrolls down and comes back the moment
/// they scroll up, which is the bargain that lets it cover anything at all.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.title,
    this.hidden = 0,
    this.showingBack = false,
    this.onBack,
    this.onFind,
    this.onMenu,
    this.placing = false,
    this.onConfirm,
    this.onCancel,
    this.menuOpen = 0,
    this.notice,
    this.locked = false,
    this.backMorph = 1,
  });

  /// The document's title, as the desk prints it.
  final String title;

  /// 0 with the chrome fully in, 1 with it gone.
  final double hidden;

  /// True once the sheet has been turned over, which adds the suffix that
  /// tells a reader which side they are on.
  final bool showingBack;

  final VoidCallback? onBack;
  final VoidCallback? onFind;
  final VoidCallback? onMenu;

  /// True while a signature is loose over the page, which is the one state
  /// where the band answers a question instead of naming a document.
  final bool placing;

  /// Sets the loose signature into the page.
  final VoidCallback? onConfirm;

  /// Takes it away again.
  final VoidCallback? onCancel;

  /// 0 with the menu shut, 1 with it open, which is what draws the three dots
  /// together into the one dot the goo comes out of.
  final double menuOpen;

  /// How far the way back has turned from the menu it came out of: 0 the
  /// desk's three lines, 1 the arrow.
  ///
  /// The document arrives over the desk, and the button in the corner is the
  /// same button the desk had. So it turns rather than being swapped, which is
  /// what the drawer's own button does when the drawer comes over the desk.
  final double backMorph;

  /// True when the way out is fastened, which turns the arrow into the
  /// padlock that undoes it.
  ///
  /// The same button, because it is the same question: this is the corner you
  /// go to when you want to be somewhere else, and while the reading is
  /// locked, what it does first is unlock it.
  final bool locked;

  /// A line the band says instead of the document's name, for as long as it
  /// has something to say.
  ///
  /// The reader has one place for words about itself and this is it. A dialog
  /// would stop the reading to say something the reading does not depend on,
  /// and a second floating pill would be a second answer to a question the
  /// band already answers.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    // A band that could leave while a signature is loose would take the only
    // way of setting it down with it.
    final gone = placing || notice != null ? 0.0 : hidden;
    // Where the phone says its own chrome ends, rather than where the design
    // guessed it would.
    final safeTop = MediaQuery.paddingOf(context).top;
    final bandHeight = safeTop + kHeadBandHeight;
    final rowTop = safeTop + (kHeadBandHeight - kHeaderButtonSize) / 2;
    final shift = -bandHeight * gone;
    final fade = 1 - gone;
    return SizedBox(
      width: kScreenWidth,
      height: kScreenHeight,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: shift,
            height: bandHeight,
            child: Opacity(
              opacity: fade,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.ground,
                  border: Border(
                    bottom: BorderSide(color: AppColors.hairline, width: 1),
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
          // The corner button sits exactly where the desk's own does, at the
          // desk's own size, because it is the desk's own button: it arrives
          // as the three lines the desk had and turns into the arrow in place.
          // A button eight points to the side of the one it is continuing is
          // two buttons, and the turn reads as one of them appearing over the
          // other rather than as either of them becoming anything.
          Positioned(
            left: kTopBarPaddingX,
            top: safeTop + kMenuButtonTop + shift,
            child: Opacity(
              opacity: fade,
              child: _HeaderButton(
                size: kBurgerTarget,
                icon: switch ((placing, locked)) {
                  (true, _) => LucideIcons.x,
                  (_, true) => LucideIcons.lockKeyhole,
                  _ => null,
                },
                accent: locked && !placing,
                onTap: placing ? onCancel : onBack,
                semanticLabel: switch ((placing, locked)) {
                  (true, _) => 'Put the signature away',
                  (_, true) => 'Unlock the reading',
                  _ => 'Back to the desk',
                },
                // Not a glyph but the desk's own, part way through its turn.
                child: placing || locked
                    ? null
                    : HamburgerGlyph(progress: backMorph),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: safeTop + shift,
            height: kHeadBandHeight,
            child: Opacity(
              opacity: fade,
              child: IgnorePointer(
                child: switch ((placing, notice)) {
                  (true, _) => const _BandLabel('Place your signature'),
                  (_, final String said) => _BandLabel(said),
                  _ => _Title(title, back: showingBack),
                },
              ),
            ),
          ),
          if (placing)
            Positioned(
              left: kScreenWidth - kScreenPadding - kHeaderButtonSize,
              top: rowTop,
              child: _HeaderButton(
                icon: LucideIcons.check,
                accent: true,
                onTap: onConfirm,
                semanticLabel: 'Set the signature into the page',
              ),
            )
          else ...[
            Positioned(
              left: kScreenWidth -
                  kScreenPadding -
                  kHeaderButtonSize * 2 -
                  kChromeButtonGap,
              top: rowTop + shift,
              child: Opacity(
                opacity: fade,
                child: _HeaderButton(
                  icon: LucideIcons.search,
                  onTap: gone >= 1 ? null : onFind,
                  semanticLabel: 'Find in document',
                ),
              ),
            ),
            Positioned(
              left: kScreenWidth - kScreenPadding - kHeaderButtonSize,
              top: rowTop + shift,
              child: Opacity(
                opacity: fade,
                child: _HeaderButton(
                  onTap: gone >= 1 ? null : onMenu,
                  semanticLabel: 'What can be done with this document',
                  // The dots are drawn rather than set, because they are not
                  // a glyph here: they draw together into the one dot the
                  // menu's goo is pulled out of, the way the desk's do.
                  child: CustomPaint(
                    painter: OverflowDotsPainter(
                      t: menuOpen,
                      colour: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The air between the two buttons at the right end of the band.
const kChromeButtonGap = 10.0;

/// One 38.5 point floating button: the only shape a control takes in the
/// reader.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    this.icon,
    this.child,
    this.onTap,
    this.semanticLabel,
    this.accent = false,
    this.size = kHeaderButtonSize,
  }) : assert(icon != null || child != null, 'a button needs a face');

  /// How big the button is. The corner one is the desk's size rather than the
  /// band's, so it can be the same object the desk was showing.
  final double size;

  final IconData? icon;

  /// What the button holds when a glyph is not enough, which is the one
  /// button whose face is an animation.
  final Widget? child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// True for the one button that finishes something rather than opening it.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      semanticLabel: semanticLabel,
      washRadius: kHeaderButtonRadius,
      // At rest a button in the band is the band: no plate, no rule, just the
      // glyph on the same ground the title is on. The plate a button used to
      // wear all the time was three light shapes on a dark band competing with
      // the document for the eye, and the only moment it is worth having is
      // the moment the finger is on it. That moment is what the wash is.
      //
      // The one exception is a button that finishes something rather than
      // opening it, which stays in the accent so it cannot be missed.
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: accent ? AppColors.accent : null,
          borderRadius: BorderRadius.circular(kHeaderButtonRadius),
        ),
        child: child ??
            Center(
              child: Icon(
                icon,
                size: kChromeIcon,
                color: accent ? AppColors.onAccent : AppColors.ink,
              ),
            ),
      ),
    );
  }
}

/// What the band says while it is asking rather than naming.
///
/// It gets two lines and no more. A notice is the app talking about itself in
/// the middle of somebody's reading, and anything it cannot say in two lines
/// of a phone's width it should not be saying here at all.
class _BandLabel extends StatelessWidget {
  const _BandLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kBandLabelWidth),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.label.copyWith(color: AppColors.ink),
      ),
    ),
  );
}

/// The title, centred in the band, with the suffix that names the side of the
/// sheet you are reading.
class _Title extends StatelessWidget {
  const _Title(this.title, {required this.back});

  final String title;
  final bool back;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kReaderTitleWidth),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: AppColors.ink),
              ),
            ),
            if (back)
              Padding(
                padding: const EdgeInsets.only(left: kSpace8),
                child: Text(
                  '· BACK',
                  style: AppText.micro.copyWith(color: AppColors.accentBright),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
