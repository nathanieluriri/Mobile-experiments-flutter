import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/metrics.dart';
import '../../widgets/goo_menu.dart';

/// Everything that can be done to a document from inside it.
///
/// The desk's menu is about a file: open it, star it, throw it away. This one
/// is about the thing on the screen, so it holds only what needs the document
/// to be open in front of you.
enum ReaderAction {
  sign(label: 'Sign this page', icon: LucideIcons.penLine),
  shareSigned(label: 'Share the signed copy', icon: LucideIcons.share2),
  dogEar(label: 'Dog ear this page', icon: LucideIcons.bookmark),
  undogEar(label: 'Remove the dog ear', icon: LucideIcons.bookmark),
  dogEars(label: 'Dog ears', icon: LucideIcons.bookMarked),
  comments(label: 'Comments', icon: LucideIcons.messageSquare),
  present(label: 'Present this deck', icon: LucideIcons.play),
  find(label: 'Find in document', icon: LucideIcons.search),
  view(label: 'View', icon: LucideIcons.scanEye),
  lock(label: 'Lock the reading', icon: LucideIcons.lockKeyhole);

  const ReaderAction({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Where the reader's three dots sit, which is where its menu comes out of.
///
/// Worked out rather than measured, because the band is laid out from the
/// phone's own top inset and these two numbers: asking the screen where the
/// button ended up would be asking it a question the layout already answers.
Rect readerMenuAnchor(EdgeInsets safeArea) => Rect.fromLTWH(
      kScreenWidth - kScreenPadding - kHeaderButtonSize,
      safeArea.top + (kHeadBandHeight - kHeaderButtonSize) / 2,
      kHeaderButtonSize,
      kHeaderButtonSize,
    );

/// The room the reader's pills may occupy.
Rect readerMenuBounds(EdgeInsets safeArea, double height) => Rect.fromLTRB(
      0,
      safeArea.top,
      kScreenWidth,
      height - safeArea.bottom,
    );

/// [ReaderAction] as the shared goo menu states an item.
GooMenuItem gooItemOf(ReaderAction action) =>
    GooMenuItem(label: action.label, icon: action.icon);
