import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import 'document_card.dart';

/// How far the colophon's rule sits below the last card, and how far its line
/// of counts sits below the rule.
const kColophonGap = 40.0;
const kColophonRuleGap = 10.0;

/// The counted footer under the last card.
///
/// It is a colophon rather than a watermark: real numbers about the real
/// documents, set small, where a wordmark would have been filling space with
/// its own name.
class DeskColophon extends StatelessWidget {
  const DeskColophon({
    super.key,
    required this.documents,
    required this.words,
    required this.minutes,
    this.topGap = kColophonGap,
  });

  final int documents;

  /// Extracted words, not an estimate from the file size.
  final int words;

  /// [words] at 240 a minute.
  final int minutes;

  /// How much room to leave above the rule. The list already contributes its
  /// own gap, so the desk passes the remainder.
  final double topGap;

  /// The one line of counts, as in `6 DOCUMENTS · 14,200 WORDS · 60 MINUTES`.
  ///
  /// A count nobody has computed yet is left out rather than printed as a
  /// zero, because a colophon claiming no words is worse than a shorter line.
  String get line {
    final parts = <String>[
      '${groupedNumber(documents)} '
          '${documents == 1 ? 'DOCUMENT' : 'DOCUMENTS'}',
      if (words > 0)
        '${groupedNumber(words)} ${words == 1 ? 'WORD' : 'WORDS'}',
      if (minutes > 0)
        '${groupedNumber(minutes)} ${minutes == 1 ? 'MINUTE' : 'MINUTES'}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: topGap),
        const SizedBox(
          width: kColophonRuleWidth,
          height: 1,
          child: ColoredBox(color: AppColors.hairline),
        ),
        const SizedBox(height: kColophonRuleGap),
        Text(
          line,
          textAlign: TextAlign.center,
          style: AppText.micro.copyWith(color: AppColors.inkFaint),
        ),
      ],
    );
  }
}
