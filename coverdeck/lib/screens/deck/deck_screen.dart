import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/albums.dart';
import '../../theme/typography.dart';
import '../../widgets/coverflow/coverflow.dart';
import '../../widgets/coverflow/coverflow_controller.dart';
import 'progress_bar.dart';
import 'transport_controls.dart';

/// Now playing: the deck, the focused album's name, and the player controls.
///
/// The backdrop is every album's wash colour laid end to end and sampled at the
/// deck's position, so it slides between two records mid drag.
class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key, this.controller});

  /// Deck position, supplied by tests that need to place it precisely.
  final CoverflowController? controller;

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> with SingleTickerProviderStateMixin {
  late final CoverflowController _deck =
      widget.controller ?? CoverflowController(vsync: this, count: albums.length);
  late int _index = _deck.index;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _deck.onIndexChanged = _handleIndexChange;
  }

  @override
  void dispose() {
    _deck.onIndexChanged = null;
    if (widget.controller == null) {
      _deck.dispose();
    }
    super.dispose();
  }

  void _handleIndexChange(int next) {
    HapticFeedback.selectionClick();
    setState(() => _index = next);
  }

  void _skip(int direction) {
    _deck.scrollTo(clampDouble((_index + direction).toDouble(), 0, albums.length - 1).round());
  }

  @override
  Widget build(BuildContext context) {
    final album = albums[_index];
    final topInset = MediaQuery.paddingOf(context).top;

    return AnimatedBuilder(
      animation: _deck,
      builder: (context, child) => ColoredBox(color: deckWash(_deck.scrollX), child: child),
      child: Padding(
        padding: EdgeInsets.only(top: topInset + 12),
        child: Column(
          children: [
            const SizedBox(
              width: double.infinity,
              child: Text(
                'NOW PLAYING',
                semanticsLabel: 'Now Playing',
                textAlign: TextAlign.center,
                style: AppText.eyebrow,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  Coverflow(albums: albums, controller: _deck),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      children: [
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.nowPlayingTitle,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            album.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.nowPlayingArtist,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32, right: 32, bottom: 148),
              child: Column(
                spacing: 18,
                children: [
                  ProgressBar(
                    playing: _playing,
                    durationSec: album.durationSec,
                    resetKey: album.id,
                  ),
                  TransportControls(
                    playing: _playing,
                    onTogglePlay: () => setState(() => _playing = !_playing),
                    onSkip: _skip,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The album wash colours laid end to end and sampled at [scrollX], so the
/// backdrop slides between two records while the deck is mid drag.
Color deckWash(double scrollX) {
  final x = clampDouble(scrollX, 0, albums.length - 1);
  final lower = x.floor().clamp(0, albums.length - 2);
  return Color.lerp(albums[lower].wash, albums[lower + 1].wash, x - lower)!;
}
