import 'package:flutter/widgets.dart';

import '../../data/albums.dart';
import '../../painting/glyphs.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/glyph_icon.dart';
import '../../widgets/tab_bar_controller.dart';

/// One saved playlist and the cover that stands in for it.
typedef Playlist = ({String name, int count, int coverIndex});

const playlists = <Playlist>[
  (name: 'Heavy Rotation', count: 34, coverIndex: 0),
  (name: 'Late Night Static', count: 21, coverIndex: 3),
  (name: 'Front Row', count: 18, coverIndex: 4),
  (name: 'Tape Deck Gold', count: 47, coverIndex: 6),
  (name: 'Slow Mornings', count: 26, coverIndex: 9),
  (name: 'Encore Material', count: 15, coverIndex: 7),
  (name: 'Wires & Choirs', count: 31, coverIndex: 10),
  (name: 'Afterglow', count: 22, coverIndex: 11),
];

/// The saved playlists, one row each.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.tabBar});

  final TabBarController tabBar;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: AppColors.background,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            tabBar.handleScroll(
              'library',
              notification.metrics.pixels,
              notification.metrics.maxScrollExtent,
            );
          }
          return false;
        },
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: topInset + 16, left: 20, right: 20, bottom: 150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Library',
                  style: AppText.heading,
                ),
              ),
              for (final playlist in playlists) _PlaylistRow(playlist: playlist),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(8));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        spacing: 14,
        children: [
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: radius,
                side: BorderSide(color: AppColors.coverBorder, width: hairlineWidth(context)),
              ),
            ),
            child: ClipRSuperellipse(
              borderRadius: radius,
              child: Image.asset(
                albums[playlist.coverIndex].imageAsset,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${playlist.count} songs',
                    style: AppText.rowSubtitle,
                  ),
                ),
              ],
            ),
          ),
          const GlyphIcon(
            glyph: Glyph.chevronRight,
            size: 14,
            color: AppColors.tertiaryLabel,
          ),
        ],
      ),
    );
  }
}
