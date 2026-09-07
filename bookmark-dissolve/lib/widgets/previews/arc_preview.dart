import 'package:flutter/widgets.dart';

import '../../painting/marks.dart';
import '../../theme/index.dart';
import '../spill.dart';

const _sidebarBars = [24.0, 18.0, 21.0, 14.0, 19.0];
const _petals = [
  (9.0, Color(0xFFC4485C)),
  (11.0, Color(0xFFA93248)),
  (8.0, Color(0xFFE2707F)),
  (7.0, Color(0xFF8A2C3B)),
  (8.0, Color(0xFFD05A6A)),
];

/// The pale circle with a violet sparkle in it.
class ArcIcon extends StatelessWidget {
  const ArcIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Color(0xFFEDEDFB), shape: BoxShape.circle),
      child: const Mark.sparkle(size: 8, color: Color(0xFF7A5AF8)),
    );
  }
}

/// A blue landing page: a pull quote, two download buttons and a screenshot of
/// the browser below them.
class ArcBody extends StatelessWidget {
  const ArcBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        color: AppColors.arcBlue,
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Text(
              'Arc makes every\nother browser feel\nlike a relic.',
              textAlign: TextAlign.center,
              style: text(
                size: 17,
                lineHeight: 20,
                weight: FontWeight.w800,
                color: const Color(0xFFFFFFFF),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'WIRED',
                style: text(
                  size: 6,
                  weight: FontWeight.w800,
                  color: const Color(0xFFFFFFFF),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: IntrinsicHeight(
                child: Spill(
                  horizontal: true,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _DownloadButton(
                        background: Color(0xFFFFFFFF),
                        foreground: AppColors.arcBlue,
                        label: ' Download Arc for Mac',
                      ),
                      const SizedBox(width: 4),
                      const _DownloadButton(
                        background: AppColors.arcNavy,
                        foreground: Color(0xFFFFFFFF),
                        label: ' Download Arc for Windows',
                        mark: Mark.window(size: 4.5, color: Color(0xFFFFFFFF)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FractionallySizedBox(
                  widthFactor: 0.86,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    child: Container(
                      color: const Color(0xFFF6D9DC),
                      padding: const EdgeInsets.only(left: 8, top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 32,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Spill(
                                vertical: true,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final width in _sidebarBars)
                                      Container(
                                        width: width,
                                        height: 3,
                                        margin: const EdgeInsets.only(bottom: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE2AEB6),
                                          borderRadius: BorderRadius.circular(1.5),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: _BrowserPane(),
                            ),
                          ),
                        ],
                      ),
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

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.background,
    required this.foreground,
    required this.label,
    this.mark,
  });

  final Color background;
  final Color foreground;
  final String label;
  final Widget? mark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The label carries its own leading space, so the mark sits where
          // the source's glyph does.
          ?mark,
          Text(
            label,
            style: text(size: 6, weight: FontWeight.w700, color: foreground),
          ),
        ],
      ),
    );
  }
}

class _BrowserPane extends StatelessWidget {
  const _BrowserPane();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(6)),
      child: Container(
        color: const Color(0xFFFFFFFF),
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          widthFactor: 0.8,
          heightFactor: 0.7,
          child: Spill(
            vertical: true,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
                  child: Wrap(
                    spacing: 1,
                    runSpacing: 1,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (size, color) in _petals)
                        Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ),
                Container(width: 2, height: 5, color: const Color(0xFF7E9463)),
                Container(
                  width: 20,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDED7CC),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(1),
                      topRight: Radius.circular(1),
                      bottomLeft: Radius.circular(3),
                      bottomRight: Radius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
