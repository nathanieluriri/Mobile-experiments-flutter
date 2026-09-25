import 'dart:ui';

import 'marquee_item.dart';

/// Artists shown on the Connect Spotify step. The order is load bearing: the
/// marquee loops through this list.
const artists = <MarqueeItem>[
  MarqueeItem(
    id: 'tyler',
    name: 'Tyler the\nCreator',
    backgroundColor: Color(0xFF66743F),
    textColor: Color(0xFF3F4C22),
    tilt: -5,
  ),
  MarqueeItem(
    id: 'jake',
    name: 'Jake\nIsaac',
    backgroundColor: Color(0xFFE9E4DA),
    textColor: Color(0xFF96938A),
    tilt: 6,
  ),
  MarqueeItem(
    id: 'altj',
    name: 'ALT-J',
    backgroundColor: Color(0xFF161616),
    textColor: Color(0xFFFF4D9D),
    tilt: -6,
  ),
  MarqueeItem(
    id: 'cas',
    name: 'Cigarettes\nAfter Sex',
    backgroundColor: Color(0xFF101010),
    textColor: Color(0xFFF4F4F4),
    tilt: 5,
  ),
  MarqueeItem(
    id: 'sigur',
    name: 'Sigur\nR\u00f3s',
    backgroundColor: Color(0xFFC78B4E),
    textColor: Color(0xFF2C2014),
    tilt: -7,
  ),
  MarqueeItem(
    id: 'tame',
    name: 'Tame\nImpala',
    backgroundColor: Color(0xFF7B97DE),
    textColor: Color(0xFFF5BFD3),
    tilt: 4,
  ),
  MarqueeItem(
    id: 'sampha',
    name: 'Sampha',
    backgroundColor: Color(0xFF6C3126),
    textColor: Color(0xFFE8A33A),
    tilt: -5,
  ),
  MarqueeItem(
    id: 'bon',
    name: 'Bon\nIver',
    backgroundColor: Color(0xFFE08A35),
    textColor: Color(0xFF4A2E10),
    tilt: 7,
  ),
];
