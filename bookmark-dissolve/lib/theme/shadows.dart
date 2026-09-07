import 'package:flutter/painting.dart';

/// The three drop shadows the cards and their inner panels use.
abstract final class AppShadows {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x1A40372E), blurRadius: 18, offset: Offset(0, 10)),
  ];

  static const floating = <BoxShadow>[
    BoxShadow(color: Color(0x2440372E), blurRadius: 12, offset: Offset(0, 6)),
  ];

  static const panel = <BoxShadow>[
    BoxShadow(color: Color(0x1440372E), blurRadius: 10, offset: Offset(0, 4)),
  ];
}
