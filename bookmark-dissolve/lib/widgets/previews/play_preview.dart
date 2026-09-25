import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/index.dart';
import '../spill.dart';

/// The black rounded square with a purple play triangle in it.
class PlayIcon extends StatelessWidget {
  const PlayIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.only(left: 2),
        child: CustomPaint(
          size: Size(8.5, 10),
          painter: _Triangle(AppColors.playPurple, _Point.right),
        ),
      ),
    );
  }
}

/// A dark product page with a headline, a paragraph, a call to action and a
/// wireframe of the editor below it.
class PlayBody extends StatelessWidget {
  const PlayBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ColoredBox(
        color: const Color(0xFF050506),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: kStep * 3,
                  right: kStep * 3,
                  top: kStep * 3.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Design interfaces that\nfeel alive, on your phone.',
                      textAlign: TextAlign.center,
                      style: text(
                        size: 12,
                        lineHeight: 15,
                        weight: FontWeight.w700,
                        color: AppColors.playPurple,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        top: kStep * 2,
                        left: kStep * 2,
                        right: kStep * 2,
                      ),
                      child: Text(
                        'Sketch, prototype and ship native interactions directly from '
                        'your pocket \u2014 with all the craft and fidelity of a full '
                        'design studio.',
                        textAlign: TextAlign.center,
                        style: text(
                          size: 6.5,
                          lineHeight: 9,
                          color: AppColors.playGray,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: kStep * 2.5),
                      child: Text(
                        'Start Creating Today  →',
                        textAlign: TextAlign.center,
                        style: text(
                          size: 7,
                          weight: FontWeight.w600,
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: kStep * 3.5),
                        child: _EditorWireframe(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: kStep * 1.5,
              right: kStep * 4,
              child: Transform.rotate(
                angle: -38 * math.pi / 180,
                child: const CustomPaint(
                  size: Size(10, 13),
                  painter: _Triangle(Color(0xFFFFFFFF), _Point.up),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorWireframe extends StatelessWidget {
  const _EditorWireframe();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: kStep * 7,
          decoration: const BoxDecoration(
            color: Color(0xFF151517),
            borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
          ),
        ),
        const SizedBox(width: kStep * 1.5),
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(
              left: kStep * 2,
              right: kStep * 2,
              top: kStep * 2,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF131315),
              borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Spill(
              vertical: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(kStep * 10, const Color(0xFF2A2A2E)),
                  const SizedBox(height: kStep * 1.5),
                  _bar(kStep * 14, const Color(0xFF232327)),
                  const SizedBox(height: kStep * 2.5),
                  Container(
                    width: kStep * 11,
                    height: kStep * 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D1D20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Chip(Color(0xFF4A4A50), 1.5),
                        SizedBox(width: 3),
                        _Chip(Color(0xFF3A3A40), 2.5),
                        SizedBox(width: 3),
                        _Chip(Color(0xFF333338), 1.5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bar(double width, Color color) => Container(
    width: width,
    height: 3,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(1.5),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

enum _Point { right, up }

class _Triangle extends CustomPainter {
  const _Triangle(this.color, this.point);

  final Color color;
  final _Point point;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (point == _Point.right) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Triangle old) => old.color != color || old.point != point;
}
