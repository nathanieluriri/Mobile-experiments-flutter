import 'package:flutter/widgets.dart';

import '../../painting/marks.dart';
import '../../theme/index.dart';

const _checklistRows = [
  (Color(0xFFDDD9D1), 44.0),
  (Color(0xFFE7E4DE), 58.0),
  (Color(0xFFEDEAE4), 36.0),
];

/// A white square with a hairline border and an N in it.
class NotionIcon extends StatelessWidget {
  const NotionIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE3E1DC)),
      ),
      child: Text(
        'N',
        style: text(size: 13, weight: FontWeight.w700, color: AppColors.ink),
      ),
    );
  }
}

/// A headline, a short paragraph and the top of a document page.
class NotionBody extends StatelessWidget {
  const NotionBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        color: const Color(0xFFFFFEFB),
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Text(
              'Write. Plan. Build.',
              textAlign: TextAlign.center,
              style: text(size: 19, weight: FontWeight.w700, color: AppColors.ink),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 24, right: 24),
              child: Text(
                'One connected workspace for your notes, docs and projects \u2014 '
                'where better, faster work happens together.',
                textAlign: TextAlign.center,
                style: text(size: 6.5, lineHeight: 9, color: AppColors.inkMuted),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FractionallySizedBox(
                  widthFactor: 0.74,
                  child: Container(
                    padding: const EdgeInsets.only(left: 12, right: 12, top: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      border: const Border(
                        top: BorderSide(color: Color(0xFFECEAE5)),
                        left: BorderSide(color: Color(0xFFECEAE5)),
                        right: BorderSide(color: Color(0xFFECEAE5)),
                      ),
                      boxShadow: AppShadows.panel,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Mark.rocket(size: 8),
                        Container(
                          width: 80,
                          height: 4,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7E4DE),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < _checklistRows.length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 5),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    border: Border.all(color: const Color(0xFFD5D1C9)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: _checklistRows[i].$2,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: _checklistRows[i].$1,
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
