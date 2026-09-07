import 'package:flutter/widgets.dart';

import '../../data/albums.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/tab_bar_controller.dart';

/// Every album as a two column grid of covers.
class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key, required this.tabBar});

  final TabBarController tabBar;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final topInset = MediaQuery.paddingOf(context).top;
    final tileSize = (width - 20 * 2 - 16) / 2;

    return ColoredBox(
      color: AppColors.background,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            tabBar.handleScroll(
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
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Browse',
                  style: AppText.heading,
                ),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final album in albums)
                    SizedBox(
                      width: tileSize,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Tile(asset: album.imageAsset, size: tileSize),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              album.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.tileTitle,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              album.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.tileArtist,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.asset, required this.size});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(10));
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: AppColors.coverBorder, width: hairlineWidth(context)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover),
      ),
    );
  }
}
