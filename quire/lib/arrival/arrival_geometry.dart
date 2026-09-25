import 'dart:ui';

import 'quire_mark.dart';

/// Where the splash put the mark and the name, in the view's logical pixels.
class ArrivalGeometry {
  const ArrivalGeometry({required this.markBox, required this.nameBox});

  /// Where every launch screen puts them on a view of [size]: the mark's box
  /// centred on the whole screen, the name's slot [kNameBottom] off its foot.
  factory ArrivalGeometry.standard(Size size) => ArrivalGeometry(
    markBox: Rect.fromCenter(
      center: size.center(Offset.zero),
      width: kMarkBox,
      height: kMarkBox,
    ),
    nameBox: Rect.fromLTWH(
      (size.width - kNameBox.width) / 2,
      size.height - kNameBottom - kNameBox.height,
      kNameBox.width,
      kNameBox.height,
    ),
  );

  /// From what the platform measured on its own splash: the rect its mark's
  /// ink covers, and its name's slot. Either may be missing, and the standard
  /// place stands in for it.
  factory ArrivalGeometry.measured(Size size, {Rect? markInk, Rect? nameBox}) {
    final standard = ArrivalGeometry.standard(size);
    return ArrivalGeometry(
      markBox: markInk == null || markInk.isEmpty
          ? standard.markBox
          : _boxAround(markInk),
      nameBox: nameBox == null || nameBox.isEmpty ? standard.nameBox : nameBox,
    );
  }

  /// The mark's whole viewport, in logical pixels.
  final Rect markBox;

  /// The name's slot, in logical pixels.
  final Rect nameBox;

  /// Logical pixels per unit of the mark's viewport.
  double get unit => markBox.width / kMarkViewport;

  /// Where a point of the mark's viewport lands on the screen.
  Offset place(Offset unitPoint) => markBox.topLeft + unitPoint * unit;

  static Rect _boxAround(Rect markInk) {
    final ink = QuireMark.ink;
    final unit = (markInk.width / ink.width + markInk.height / ink.height) / 2;
    final origin = markInk.center - ink.center * unit;
    return origin & Size.square(kMarkViewport * unit);
  }

  @override
  bool operator ==(Object other) =>
      other is ArrivalGeometry &&
      other.markBox == markBox &&
      other.nameBox == nameBox;

  @override
  int get hashCode => Object.hash(markBox, nameBox);
}
