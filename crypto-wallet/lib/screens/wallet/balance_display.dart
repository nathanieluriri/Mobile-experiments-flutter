import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../../utils/format.dart';
import 'wallet_refresh_controller.dart';

const double kBalanceHeight = 158;
const double kAmountSize = 54;
const double kLabelSize = 15;
const double kGainSize = 15;
const double kLabelBaseline = 26;
const double kAmountBaseline = 96;
const double kGainBaseline = 136;
const double kBlurMax = 18;
const double kPillGap = 8;
const double kPillPadX = 8;
const double kPillHeight = 24;

/// The total balance block: label, six morphing digits, and the gain pill.
/// Tapping it refreshes.
class BalanceDisplay extends StatelessWidget {
  const BalanceDisplay({super.key, required this.controller});

  final WalletRefreshController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.refresh,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final m = controller.morph;
          Widget canvas = _BalanceCanvas(controller: controller);
          if (m > 0) {
            canvas = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: m * kBlurMax,
                sigmaY: m * kBlurMax,
                tileMode: TileMode.decal,
              ),
              child: canvas,
            );
          }
          return Opacity(
            opacity: 1 - 0.3 * m,
            child: Transform.scale(
              scale: 1 - 0.03 * m,
              child: SizedBox(
                height: kBalanceHeight,
                width: double.infinity,
                child: ClipRect(child: canvas),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Metrics {
  _Metrics(this.style) {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }

  final TextStyle style;
  late final double baseline;

  double width(String value) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}

class _BalanceCanvas extends StatelessWidget {
  const _BalanceCanvas({required this.controller});

  final WalletRefreshController controller;

  static final _Metrics _amount = _Metrics(
    text(kAmountSize, weight: FontWeight.w700, tabular: true),
  );
  static final _Metrics _label = _Metrics(
    text(kLabelSize, weight: FontWeight.w500, color: AppColors.subtle),
  );
  static final _Metrics _gain = _Metrics(
    text(kGainSize, weight: FontWeight.w600, tabular: true),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gain = controller.gain;
        final positive = gain.amount >= 0;
        final gainColor = positive ? AppColors.gain : AppColors.loss;
        final pillColor = positive ? AppColors.gainSoft : AppColors.lossSoft;

        double measure(String char) => _amount.width(char) + 1;
        final cell = measure('0');
        final total =
            measure('\$') + measure(',') + measure('.') + cell * kDigitCount;
        var cursor = (width - total) / 2;
        final amountTop = kAmountBaseline - _amount.baseline;

        final children = <Widget>[];
        void placeChar(String char, Color color) {
          children.add(
            Positioned(
              left: cursor,
              top: amountTop,
              child: Text(char, style: _amount.style.copyWith(color: color)),
            ),
          );
          cursor += measure(char);
        }

        var digitIndex = 0;
        void placeDigits(int count) {
          for (var i = 0; i < count; i++) {
            children.add(
              _MorphDigit(
                index: digitIndex,
                left: cursor,
                top: amountTop,
                style: _amount.style,
                baseColor: digitIndex >= kIntDigits
                    ? AppColors.cents
                    : AppColors.ink,
                controller: controller,
              ),
            );
            digitIndex += 1;
            cursor += cell;
          }
        }

        placeChar('\$', AppColors.ink);
        placeDigits(1);
        placeChar(',', AppColors.ink);
        placeDigits(kIntDigits - 1);
        placeChar('.', AppColors.cents);
        placeDigits(kDigitCount - kIntDigits);

        final gainText = formatSigned(gain.amount);
        final pctText = formatSignedPercent(gain.percent);
        final gainWidth = _gain.width(gainText);
        final pillWidth = _gain.width(pctText) + kPillPadX * 2;
        final gainStart = (width - (gainWidth + kPillGap + pillWidth)) / 2;
        final pillX = gainStart + gainWidth + kPillGap;
        final gainTop = kGainBaseline - _gain.baseline;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: (width - _label.width('Total Balance')) / 2,
              top: kLabelBaseline - _label.baseline,
              child: Text('Total Balance', style: _label.style),
            ),
            ...children,
            Positioned(
              left: gainStart,
              top: gainTop,
              child: Text(
                gainText,
                style: _gain.style.copyWith(color: gainColor),
              ),
            ),
            Positioned(
              left: pillX,
              top: kGainBaseline - kGainSize - (kPillHeight - kGainSize) / 2,
              child: Container(
                width: pillWidth,
                height: kPillHeight,
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(kPillHeight / 2),
                ),
              ),
            ),
            Positioned(
              left: pillX + kPillPadX,
              top: gainTop,
              child: Text(
                pctText,
                style: _gain.style.copyWith(color: gainColor),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MorphDigit extends StatelessWidget {
  const _MorphDigit({
    required this.index,
    required this.left,
    required this.top,
    required this.style,
    required this.baseColor,
    required this.controller,
  });

  final int index;
  final double left;
  final double top;
  final TextStyle style;
  final Color baseColor;
  final WalletRefreshController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final char = RefreshTimeline.digitChar(
      index,
      c.digits,
      c.time,
      c.cycling,
      c.settle,
    );
    final color = RefreshTimeline.digitColor(
      index,
      baseColor,
      c.time,
      c.cycling,
      c.settle,
    );
    final drift = RefreshTimeline.drift(index, c.time, c.morph);
    return Positioned(
      left: left + drift.dx,
      top: top + drift.dy,
      child: Text(char, style: style.copyWith(color: color)),
    );
  }
}
