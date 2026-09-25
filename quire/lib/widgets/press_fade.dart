import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../constants/gooey_fab.dart' show kGooAlphaThresholdMatrix;
import '../painting/wash_painter.dart';
import '../theme/colors.dart';
import '../theme/easings.dart';
import '../theme/feedback.dart';
import '../theme/metrics.dart';

/// How far a pressed object scales down about its own centre.
const kPressScale = 0.985;

/// How long a press takes to come back up. Slower than it goes down, because a
/// finger lifting is slower than a finger landing.
const kPressRelease = Duration(milliseconds: 120);

/// Every tappable object in the app presses the same way: it scales to
/// [kPressScale] about its own centre, and a wash wells up inside it under the
/// finger, floods it when the finger lifts, and drains away.
///
/// One rule applied to forty unrelated controls is what makes them feel like
/// one manufactured object. The wash is the same material as the goo the
/// menus are made of, drawn small and inside the shape instead of large and
/// outside it, so a press and a menu opening are recognisably one substance.
class PaperPress extends StatefulWidget {
  const PaperPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.semanticLabel,
    this.feel = Feel.tap,
    this.holdFeel = Feel.turn,
    this.wash = true,
    this.washRadius = kWashRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// A disabled object still lays out and still draws; it just does not press.
  final bool enabled;

  final String? semanticLabel;

  /// What a tap feels like. Every control shares [Feel.tap]; the few that
  /// change the desk rather than the view say so by asking for another.
  ///
  /// The ring is on the tap and not on the press, because a finger that lands
  /// on a card and then drags the list has not tapped anything, and a phone
  /// that buzzes every time a scroll begins is a phone nobody wants to hold.
  /// The press itself is answered instantly and silently, by the scale.
  final Feel feel;

  /// What a long press feels like, when there is one.
  final Feel holdFeel;

  /// Whether a press leaves a wash inside this object. Nearly everything
  /// does; the exceptions are objects too small for a blob to read as
  /// anything but a smudge.
  final bool wash;

  /// The corner radius the wash is clipped to, so it fills the object's own
  /// shape rather than a rectangle behind a rounded one.
  final double washRadius;

  @override
  State<PaperPress> createState() => _PaperPressState();
}

class _PaperPressState extends State<PaperPress>
    with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: kPress,
    reverseDuration: kPressRelease,
  );

  /// The blob welling up under a held finger.
  late final AnimationController _well = AnimationController(
    vsync: this,
    duration: kWashRise,
    reverseDuration: kWashSink,
  );

  /// The flood after the finger lifts.
  ///
  /// Its own controller, because it has to run to the end however short the
  /// press was: a tap that lands and leaves in sixty milliseconds still gets
  /// the whole wash, which is what makes a quick tap feel answered rather
  /// than merely registered.
  late final AnimationController _flood = AnimationController(
    vsync: this,
    duration: kWashFlood,
  );

  /// Where the finger landed, in the child's own coordinates.
  Offset? _point;

  /// True from the finger landing until it leaves, however it leaves.
  ///
  /// The flood is keyed to this rather than to how far the well has risen,
  /// because a tap can land and lift inside one frame, before the well has
  /// ticked at all. Keyed to the well, such a tap never floods, and the well
  /// then rises on its own and stays: a wash that never drains.
  bool _pressing = false;

  @override
  void initState() {
    super.initState();
    _flood.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _well.value = 0;
        _flood.value = 0;
      }
    });
  }

  @override
  void dispose() {
    _press.dispose();
    _well.dispose();
    _flood.dispose();
    super.dispose();
  }

  void _down(Offset at) {
    if (!widget.enabled) return;
    _point = at;
    _pressing = true;
    _press.forward();
    if (widget.wash) {
      _flood.value = 0;
      _well.forward();
    }
  }

  /// The finger lifted where it landed: the press is over and the wash
  /// floods.
  void _up() {
    _press.reverse();
    if (widget.wash && _pressing) _flood.forward(from: 0);
    _pressing = false;
  }

  /// The finger went somewhere else, usually into a scroll: the press is over
  /// and the wash sinks back where it was without ever flooding.
  void _cancel() {
    _press.reverse();
    _well.reverse();
    _pressing = false;
  }

  void _tap() {
    widget.feel.ring();
    widget.onTap!();
  }

  void _hold() {
    widget.holdFeel.ring();
    widget.onLongPress!();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _down(details.localPosition),
        onTapUp: (_) => _up(),
        onTapCancel: _cancel,
        onTap: widget.enabled && widget.onTap != null ? _tap : null,
        onLongPress:
            widget.enabled && widget.onLongPress != null ? _hold : null,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            final t = easeOutQuad.transform(_press.value);
            return Transform.scale(
              scale: 1 - (1 - kPressScale) * t,
              child: child,
            );
          },
          child: _washed(widget.child),
        ),
      ),
    );
  }

  /// Puts the wash over [child], inside its shape.
  ///
  /// Over rather than under, because the wash is a light on the surface the
  /// finger is touching, the way ink sits on paper, and under the child it
  /// would only show at the edges. Nothing is built at rest, so a desk full
  /// of pressable things carries no layers until a finger is on one of them.
  Widget _washed(Widget child) {
    if (!widget.wash) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_well, _flood]),
              builder: (context, _) {
                final well = easeOutCubic.transform(_well.value);
                final flood = easeOutCubic.transform(_flood.value);
                final at = _point;
                if ((well <= 0 && flood <= 0) || at == null) {
                  return const SizedBox.shrink();
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(widget.washRadius),
                  child: Opacity(
                    opacity: kWashOpacity * (1 - flood),
                    child: ColorFiltered(
                      colorFilter:
                          const ColorFilter.matrix(kGooAlphaThresholdMatrix),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: kWashBlurSigma,
                          sigmaY: kWashBlurSigma,
                        ),
                        child: CustomPaint(
                          painter: WashPainter(
                            at: at,
                            well: well,
                            flood: flood,
                            colour: AppColors.accentBright,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
