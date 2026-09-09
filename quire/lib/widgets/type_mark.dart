import 'package:flutter/widgets.dart';

import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/typography.dart';

/// The format mark: a filled rounded square carrying the file's extension.
///
/// The five hues live here and on the fore edge and nowhere else, so a colour
/// in this app always means a format and can never be mistaken for the accent
/// or for a match. The letters are set in [AppColors.onAccent] on every one of
/// them, because the mark has to read the same at 20 as it does at 30 and a
/// per hue ink would be five different answers to the same question.
class TypeMark extends StatelessWidget {
  const TypeMark({
    super.key,
    required this.letters,
    required this.chroma,
    this.size = kTypeMarkSize,
  });

  /// The extension, written uppercase in the source so a golden reads what the
  /// source says.
  final String letters;

  /// The format's own hue.
  final Color chroma;

  /// The mark's side. A list row uses [kTypeMarkSize], a grid card's header
  /// [kTypeMarkGridSize]. Everything inside scales with it.
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: chroma,
          borderRadius: BorderRadius.circular(typeMarkRadius(size)),
        ),
        child: Center(
          child: Text(
            letters,
            textAlign: TextAlign.center,
            style: typeMarkStyle(size),
          ),
        ),
      ),
    );
  }
}

/// The corner of a mark of [size], scaled from [kTypeMarkRadius] so a 20 mark
/// is the same shape as a 30 one rather than a rounder square.
double typeMarkRadius(double size) => kTypeMarkRadius * size / kTypeMarkSize;

/// The letters on a mark of [size], in [AppColors.onAccent].
///
/// Free of the widget so a painter redrawing a card's face through a fold sets
/// the same letters the same way, instead of guessing at them.
TextStyle typeMarkStyle(double size) => AppText.typeMark.copyWith(
  color: AppColors.onAccent,
  fontSize: AppText.typeMark.fontSize! * size / kTypeMarkSize,
);
