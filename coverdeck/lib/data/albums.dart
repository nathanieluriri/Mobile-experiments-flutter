import 'package:flutter/painting.dart';

/// One record in the deck.
///
/// [tint] is the cover's dominant colour and [wash] its pastel blend, which the
/// deck backdrop fades through as the focused cover changes.
class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationSec,
    required this.tint,
    required this.wash,
  });

  final String id;
  final String title;
  final String artist;
  final int durationSec;
  final Color tint;
  final Color wash;

  /// Bundled cover art for this album.
  String get imageAsset => 'assets/images/$id.jpg';
}

const albums = <Album>[
  Album(
    id: 'midnight-static',
    title: 'Midnight Static',
    artist: 'Neon Harbor',
    durationSec: 214,
    tint: Color(0xFF250252),
    wash: Color(0xFFD9D1E4),
  ),
  Album(
    id: 'crowd-theory',
    title: 'Crowd Theory',
    artist: 'The Velvet Antennas',
    durationSec: 187,
    tint: Color(0xFF6F312E),
    wash: Color(0xFFEAD9D8),
  ),
  Album(
    id: 'open-mic-elegy',
    title: 'Open Mic Elegy',
    artist: 'June Casette',
    durationSec: 243,
    tint: Color(0xFFFBDFCD),
    wash: Color(0xFFFFF1E8),
  ),
  Album(
    id: 'violet-hours',
    title: 'Violet Hours',
    artist: 'Prism Motel',
    durationSec: 201,
    tint: Color(0xFF534037),
    wash: Color(0xFFE3DEDB),
  ),
  Album(
    id: 'encore-weather',
    title: 'Encore Weather',
    artist: 'Fjord Radio',
    durationSec: 229,
    tint: Color(0xFFC19020),
    wash: Color(0xFFFCEFD2),
  ),
  Album(
    id: 'signs-of-life',
    title: 'Signs of Life',
    artist: 'Marquee Ghosts',
    durationSec: 195,
    tint: Color(0xFF472922),
    wash: Color(0xFFE2D9D7),
  ),
  Album(
    id: 'b-side-weather',
    title: 'B-Side Weather',
    artist: 'Analog Meadow',
    durationSec: 252,
    tint: Color(0xFFD05C29),
    wash: Color(0xFFFCE2D7),
  ),
  Album(
    id: 'last-set',
    title: 'Last Set',
    artist: 'Copper Choir',
    durationSec: 218,
    tint: Color(0xFF4B3C31),
    wash: Color(0xFFE2DDDA),
  ),
  Album(
    id: 'festival-physics',
    title: 'Festival Physics',
    artist: 'Slow Comet',
    durationSec: 206,
    tint: Color(0xFF202020),
    wash: Color(0xFFD9D9D9),
  ),
  Album(
    id: 'tape-hiss-hotel',
    title: 'Tape Hiss Hotel',
    artist: 'The Reverb Society',
    durationSec: 234,
    tint: Color(0xFF74548E),
    wash: Color(0xFFE8E0EF),
  ),
  Album(
    id: 'chorus-of-wires',
    title: 'Chorus of Wires',
    artist: 'Little Amplitude',
    durationSec: 191,
    tint: Color(0xFFFF91B2),
    wash: Color(0xFFFFE8EE),
  ),
  Album(
    id: 'afterglow-index',
    title: 'Afterglow Index',
    artist: 'Paper Sirens',
    durationSec: 226,
    tint: Color(0xFF1E224F),
    wash: Color(0xFFD6D7E4),
  ),
];
