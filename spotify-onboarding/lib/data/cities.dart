import 'dart:ui';

import 'marquee_item.dart';

/// Cities shown on the Find Concerts step. The order is load bearing: the
/// marquee loops through this list.
const cities = <MarqueeItem>[
  MarqueeItem(
    id: 'newyork',
    name: 'New\nYork',
    backgroundColor: Color(0xFF274690),
    textColor: Color(0xFF9DB9F0),
    tilt: -5,
  ),
  MarqueeItem(
    id: 'london',
    name: 'London',
    backgroundColor: Color(0xFFB0413E),
    textColor: Color(0xFFF1C6C4),
    tilt: 6,
  ),
  MarqueeItem(
    id: 'berlin',
    name: 'Berlin',
    backgroundColor: Color(0xFF17181A),
    textColor: Color(0xFFFFD447),
    tilt: -6,
  ),
  MarqueeItem(
    id: 'tokyo',
    name: 'Tokyo',
    backgroundColor: Color(0xFFE9E4DA),
    textColor: Color(0xFF96938A),
    tilt: 5,
  ),
  MarqueeItem(
    id: 'paris',
    name: 'Paris',
    backgroundColor: Color(0xFFC78B4E),
    textColor: Color(0xFF2C2014),
    tilt: -7,
  ),
  MarqueeItem(
    id: 'amsterdam',
    name: 'Amster-\ndam',
    backgroundColor: Color(0xFF66743F),
    textColor: Color(0xFF3F4C22),
    tilt: 4,
  ),
  MarqueeItem(
    id: 'losangeles',
    name: 'Los\nAngeles',
    backgroundColor: Color(0xFF7B97DE),
    textColor: Color(0xFFF5BFD3),
    tilt: -5,
  ),
  MarqueeItem(
    id: 'barcelona',
    name: 'Barce-\nlona',
    backgroundColor: Color(0xFF6C3126),
    textColor: Color(0xFFE8A33A),
    tilt: 7,
  ),
];
