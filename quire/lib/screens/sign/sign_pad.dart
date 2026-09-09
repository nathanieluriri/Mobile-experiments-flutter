import 'package:flutter/widgets.dart';

import '../../painting/signature_painter.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../widgets/paper_sheet.dart';

/// How far in from the pad's edges the signing rule runs.
///
/// It stops short of the paper on both sides so the line reads as something
/// printed on the sheet rather than as the sheet's own edge.
const kPadRuleInset = 28.0;

/// The size of the cross that sits on the rule, and how far in it sits.
const kPadCross = 8.0;
const kPadCrossInset = 20.0;

/// Where the signing rule sits inside [pad].
double padBaseline(Rect pad) => pad.top + pad.height * kPadBaselineFraction;

/// The ink on the pad: the strokes drawn so far, how wet the newest one is,
/// and the two ways to take a stroke back.
///
/// It is a [ChangeNotifier] because the pad draws the ink while the screen
/// around it decides whether the commit pill is alive, and the two must never
/// disagree about whether anything has been signed.
class SignPadController extends ChangeNotifier {
  final List<InkStroke> _strokes = <InkStroke>[];
  final List<Offset> _points = <Offset>[];
  final List<Duration> _times = <Duration>[];
  double _dry = 1;

  /// Every stroke, oldest first. The last one is the one that is drying.
  List<InkStroke> get strokes => List<InkStroke>.unmodifiable(_strokes);

  bool get isEmpty => _strokes.isEmpty;

  /// 0 the moment the newest stroke ended, 1 once it has set.
  double get dry => _dry;

  /// The pad's drying controller drives this. Nothing else writes it.
  set dry(double value) {
    if (value == _dry) return;
    _dry = value;
    notifyListeners();
  }

  /// The signature the pad currently holds, ready to be placed on a page.
  SignatureMark get mark => SignatureMark.of(_strokes);

  /// Starts a stroke at [at].
  void down(Offset at, Duration time) {
    _points
      ..clear()
      ..add(at);
    _times
      ..clear()
      ..add(time);
    _strokes.add(InkStroke.fromSamples(_points, _times));
    _dry = 0;
    notifyListeners();
  }

  /// Extends the stroke in progress.
  void move(Offset at, Duration time) {
    if (_points.isEmpty) return;
    _points.add(at);
    _times.add(time);
    _strokes[_strokes.length - 1] = InkStroke.fromSamples(_points, _times);
    notifyListeners();
  }

  /// Ends the stroke in progress. The pad starts drying it.
  void up() {
    _points.clear();
    _times.clear();
    notifyListeners();
  }

  /// Takes the last stroke back. Repeated far enough it is [clear], which is
  /// why the pad carries no separate way to start again.
  void undo() {
    if (_strokes.isEmpty) return;
    _strokes.removeLast();
    _dry = 1;
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    _dry = 1;
    notifyListeners();
  }
}

/// The 362 x 240 sheet a signature is drawn on.
///
/// It is paper like everything else in the app, which is why it carries a
/// resting fold and a hairline edge rather than reading as an input field.
class SignPad extends StatefulWidget {
  const SignPad({super.key, required this.controller});

  final SignPadController controller;

  @override
  State<SignPad> createState() => _SignPadState();
}

class _SignPadState extends State<SignPad> with SingleTickerProviderStateMixin {
  late final AnimationController _drying;

  @override
  void initState() {
    super.initState();
    // Built here rather than lazily: a pad nobody drew on still has to have a
    // controller to dispose, and building one during unmount looks up an
    // ancestor that has already gone.
    _drying = AnimationController(vsync: this, duration: kInkDry, value: 1)
      ..addListener(_pushDryness);
  }

  void _pushDryness() {
    widget.controller.dry = easeOutCubic.transform(_drying.value);
  }

  @override
  void dispose() {
    _drying
      ..removeListener(_pushDryness)
      ..dispose();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    _drying.stop();
    widget.controller.down(event.localPosition, event.timeStamp);
  }

  void _move(PointerMoveEvent event) {
    widget.controller.move(event.localPosition, event.timeStamp);
  }

  void _up(PointerEvent event) {
    widget.controller.up();
    _drying.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: PaperSheet(
        width: kPadWidth,
        height: kPadHeight,
        foldInset: kFoldRestInset,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => CustomPaint(
            painter: const _PadRulePainter(),
            foregroundPainter: SignaturePainter(
              strokes: widget.controller.strokes,
              dry: widget.controller.dry,
            ),
            size: const Size(kPadWidth, kPadHeight),
          ),
        ),
      ),
    );
  }
}

/// The rule you sign above, and the cross that says which end to start at.
class _PadRulePainter extends CustomPainter {
  const _PadRulePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * kPadBaselineFraction;
    canvas.drawLine(
      Offset(kPadRuleInset, y),
      Offset(size.width - kPadRuleInset, y),
      Paint()
        ..color = AppColors.rule
        ..strokeWidth = 1,
    );
    final arm = kPadCross / 2;
    final cross = Paint()
      ..color = AppColors.inkFaint
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(kPadCrossInset - arm, y - arm),
      Offset(kPadCrossInset + arm, y + arm),
      cross,
    );
    canvas.drawLine(
      Offset(kPadCrossInset - arm, y + arm),
      Offset(kPadCrossInset + arm, y - arm),
      cross,
    );
  }

  @override
  bool shouldRepaint(_PadRulePainter old) => false;
}
