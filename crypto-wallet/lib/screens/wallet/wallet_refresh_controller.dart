import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../utils/random.dart';

const int kIntDigits = 4;
const int kCentDigits = 2;
const int kDigitCount = kIntDigits + kCentDigits;

/// The six digits of [value] in cents, clamped to the four-digit range.
String toDigitString(double value) {
  final clamped = value.clamp(1000.0, 9999.99);
  return (clamped * 100).round().toString().padLeft(kDigitCount, '0');
}

/// Drifts the balance by up to 4 percent either way.
double nextBalance(double previous, math.Random random) {
  final drift = 0.96 + random.nextDouble() * 0.08;
  return (previous * drift).clamp(1200.0, 9500.0);
}

Gain gainFrom(double previous, double next) {
  final amount = next - previous;
  return Gain(amount: amount, percent: amount / previous * 100);
}

/// Every value of the refresh sequence as a function of the milliseconds
/// since the refresh was triggered.
abstract final class RefreshTimeline {
  static const double morphDelayMs = 180;
  static const double morphInMs = 450;
  static const double fetchMs = 2000;
  static const double settleMs = 340;
  static const double morphOutDelayMs = 140;
  static const double morphOutMs = 520;
  static const double spinnerInMs = 280;
  static const double spinnerOutDelayMs = 220;
  static const double spinnerOutMs = 320;
  static const double shiftInMs = 420;
  static const double shiftOutDelayMs = 220;
  static const double shiftOutMs = 460;

  /// When the blur has cleared and a new refresh may start.
  static const double finishMs = fetchMs + morphOutDelayMs + morphOutMs;

  /// When the last value (the header shift) is back at rest.
  static const double endMs = fetchMs + shiftOutDelayMs + shiftOutMs;

  static double _ramp(double t, double duration) =>
      (t / duration).clamp(0.0, 1.0);

  static double spinner(double t) {
    if (t < fetchMs + spinnerOutDelayMs) {
      return Eases.iosOut.transform(_ramp(t, spinnerInMs));
    }
    return 1 -
        Eases.ios.transform(
          _ramp(t - fetchMs - spinnerOutDelayMs, spinnerOutMs),
        );
  }

  static double shift(double t) {
    if (t < fetchMs + shiftOutDelayMs) {
      return Eases.ios.transform(_ramp(t, shiftInMs));
    }
    return 1 -
        Eases.ios.transform(_ramp(t - fetchMs - shiftOutDelayMs, shiftOutMs));
  }

  static double cycling(double t) => t >= morphDelayMs && t < finishMs ? 1 : 0;

  static double morph(double t) {
    if (t < morphDelayMs) {
      return 0;
    }
    if (t < fetchMs + morphOutDelayMs) {
      return Eases.ios.transform(_ramp(t - morphDelayMs, morphInMs));
    }
    return 1 -
        Eases.ios.transform(_ramp(t - fetchMs - morphOutDelayMs, morphOutMs));
  }

  static double settle(double t) =>
      t < fetchMs ? 0 : _ramp(t - fetchMs, settleMs);

  /// The settle progress at which digit [index] stops cycling.
  static double lockAt(int index) => (index + 1) / (kDigitCount + 1);

  static bool locked(int index, double cycling, double settle) =>
      cycling < 0.5 || settle >= lockAt(index);

  /// The character digit [index] shows at [time] ms into the refresh.
  static String digitChar(
    int index,
    String target,
    double time,
    double cycling,
    double settle,
  ) {
    if (locked(index, cycling, settle)) {
      return target[index];
    }
    final tick = (time / (72 + index * 12)).floor();
    return (seededRandom(tick * 12.9898 + index * 78.233) * 10)
        .floor()
        .toString();
  }

  /// The colour digit [index] shows at [time] ms into the refresh.
  static Color digitColor(
    int index,
    Color base,
    double time,
    double cycling,
    double settle,
  ) {
    if (locked(index, cycling, settle)) {
      return base;
    }
    final tick = (time / (110 + index * 9)).floor();
    final r = seededRandom(tick * 7.31 + index * 31.7 + 5.0);
    if (r < 0.08) {
      return AppColors.accentPurple;
    }
    if (r < 0.16) {
      return AppColors.accentPink;
    }
    if (r < 0.28) {
      return AppColors.accentGrey;
    }
    return base;
  }

  /// How far digit [index] wanders while morphing.
  static Offset drift(int index, double time, double morph) {
    return Offset(
      math.sin(time / 68 + index * 2.6) * 2.5 * morph,
      math.sin(time / 92 + index * 1.9) * 6 * morph,
    );
  }
}

/// Drives the balance refresh: a single ticker supplies the elapsed time and
/// every animated value is read from [RefreshTimeline].
class WalletRefreshController extends ChangeNotifier {
  WalletRefreshController({
    required TickerProvider vsync,
    required double initialBalance,
    required Gain initialGain,
    required this.random,
  }) : balance = initialBalance,
       gain = initialGain,
       digits = toDigitString(initialBalance) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;

  /// Source of the simulated balance drift.
  final math.Random random;

  double balance;
  Gain gain;
  String digits;

  double _elapsed = 0;
  bool _busy = false;
  bool _fetched = false;

  /// True from the trigger until the blur has cleared.
  bool refreshing = false;

  bool get _active => _ticker.isActive;

  /// Milliseconds since the refresh was triggered, 0 at rest.
  double get time => _elapsed;
  double get spinner => _active ? RefreshTimeline.spinner(_elapsed) : 0;
  double get shift => _active ? RefreshTimeline.shift(_elapsed) : 0;
  double get cycling => _active ? RefreshTimeline.cycling(_elapsed) : 0;
  double get morph => _active ? RefreshTimeline.morph(_elapsed) : 0;
  double get settle => _active ? RefreshTimeline.settle(_elapsed) : 1;

  /// Starts a refresh unless one is already running.
  void refresh() {
    if (_busy) {
      return;
    }
    _busy = true;
    refreshing = true;
    _fetched = false;
    _elapsed = 0;
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _ticker.start();
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed.inMicroseconds / 1000;
    if (!_fetched && _elapsed >= RefreshTimeline.fetchMs) {
      _fetched = true;
      final next = nextBalance(balance, random);
      gain = gainFrom(balance, next);
      balance = next;
      digits = toDigitString(next);
    }
    if (_busy && _elapsed >= RefreshTimeline.finishMs) {
      _busy = false;
      refreshing = false;
    }
    if (_elapsed >= RefreshTimeline.endMs) {
      _ticker.stop();
      _elapsed = 0;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
