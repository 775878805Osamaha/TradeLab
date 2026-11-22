import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_axis_contrast.dart';

void main() {
  test('dark TradingView-like chart uses readable price/time labels', () {
    const darkCanvas = Color(0xFF000D16);
    final foreground = ChartAxisContrast.readableAxisLabel(
      background: darkCanvas, configuredArgb: 0xFF000000);
    expect(foreground, const Color(0xFFCBD5E1));
    final bg = darkCanvas.computeLuminance();
    final fg = foreground.computeLuminance();
    expect((fg + .05) / (bg + .05), greaterThan(4.5),
      reason: 'Real broker prices cannot be invisible on dark canvas');
  });

  test('light canvas and explicit appearance preferences are preserved', () {
    const light = Color(0xFFFFFFFF);
    expect(ChartAxisContrast.readableAxisLabel(
      background: light, configuredArgb: 0xFF000000),
      const Color(0xFF000000));
    const chosenBlue = 0xFF688AD2;
    expect(ChartAxisContrast.readableAxisLabel(
      background: const Color(0xFF000D16),
      configuredArgb: chosenBlue), const Color(chosenBlue));
    expect(ChartAxisContrast.readableAxisLabel(
      background: const Color(0xFF777777),
      configuredArgb: 0xFF000000), const Color(0xFF000000));
  });

  test('medium-dark backgrounds adapt instead of using unreadable black', () {
    const surface = Color(0xFF555555);
    final chosen = ChartAxisContrast.readableAxisLabel(
        background: surface, configuredArgb: 0xFF000000);
    expect(chosen, isNot(const Color(0xFF000000)));
    final contrast = (chosen.computeLuminance() + .05) /
        (surface.computeLuminance() + .05);
    expect(contrast, greaterThanOrEqualTo(4.5));
  });
}
