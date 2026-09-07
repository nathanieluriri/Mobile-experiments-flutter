import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/index.dart';

const _taglineLines = ['A quiet home', 'for everything', 'you save.'];
const _lineFadeStep = 0.18;

/// The rounded orange square with the mymind mark in it.
class MymindIcon extends StatelessWidget {
  const MymindIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.mymindOrange,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SizedBox(
        width: 11,
        height: 10,
        child: Stack(
          children: [
            const Positioned(left: 0, top: 0, child: _Lobe()),
            const Positioned(right: 0, top: 0, child: _Lobe()),
            Positioned(
              left: 2.25,
              top: 2.5,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(width: 6.5, height: 6.5, color: const Color(0xFFFFFFFF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lobe extends StatelessWidget {
  const _Lobe();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6.5,
      height: 6.5,
      decoration: const BoxDecoration(color: Color(0xFFFFFFFF), shape: BoxShape.circle),
    );
  }
}

/// A tagline that fades line by line, with a saved product card tucked into the
/// bottom right corner.
class MymindBody extends StatelessWidget {
  const MymindBody({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _taglineLines.length; i++)
                          Opacity(
                            opacity: 1 - i * _lineFadeStep,
                            child: Text(
                              _taglineLines[i],
                              textAlign: TextAlign.center,
                              style: text(size: 22, lineHeight: 26, color: AppColors.mymindText),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: -4,
                  right: 10,
                  width: constraints.maxWidth * 0.68,
                  height: constraints.maxHeight * 0.52,
                  child: const _SavedCard(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.floating,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'SHOP · Soap',
                  style: text(size: 5, color: const Color(0xFFA9A49D), letterSpacing: 0.5),
                ),
                Container(
                  width: 13,
                  height: 13,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFC8C2B8), width: 0.8),
                  ),
                  child: Container(
                    width: 4.5,
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      border: Border.all(color: const Color(0xFFC8C2B8), width: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFF4EDE4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3D0B7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Opacity(
                          opacity: 0.7,
                          child: Container(
                            width: 40,
                            height: 7,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9DFD0),
                              borderRadius: BorderRadius.circular(3.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 16,
                    child: Center(
                      child: Transform.rotate(
                        angle: math.pi / 2,
                        child: OverflowBox(
                          maxWidth: double.infinity,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 40,
                            child: Text(
                              'BINU BINU',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: text(
                                size: 4.5,
                                color: const Color(0xFF9A948B),
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
