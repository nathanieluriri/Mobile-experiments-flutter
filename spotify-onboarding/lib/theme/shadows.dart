import 'package:flutter/painting.dart';

/// Shadow cast by every marquee card.
///
/// The design calls for a shadow blurred with a standard deviation of 14, and
/// [BoxShadow] turns its radius into a sigma with `radius * 0.57735 + 0.5`.
const cardShadow = BoxShadow(
  color: Color(0x2E000000),
  blurRadius: 23.4,
  offset: Offset(0, 10),
);
