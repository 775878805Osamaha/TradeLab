import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_history_prefetch_policy.dart';

void main() {
  bool prefetch(double scroll, {
    int count = 4000, double width = 320, double barWidth = 10,
  }) => ChartHistoryPrefetchPolicy.shouldPrefetch(
    scrollBars: scroll,
    loadedBars: count,
    plotWidth: width,
    barWidth: barWidth,
  );

  test('time candles request older source two screens before the left edge',
      () {
    // At 320px / 10px: 32 displayed, 64 verified-source bars ahead.
    // Previous one-size 25-bar lead would still be false at 3910.
    expect(prefetch(3800), isFalse);
    expect(prefetch(3904), isFalse);
    expect(prefetch(3905), isTrue);
    expect(prefetch(3940), isTrue);
  });

  test('deep 3px zoom fetches history earlier without fabricating any bars',
      () {
    // At 320px / 3px: ~106.7 visible bars and 213.3-bar lead.
    expect(prefetch(3600, barWidth: 3), isFalse);
    expect(prefetch(3680, barWidth: 3), isFalse);
    expect(prefetch(3681, barWidth: 3), isTrue);
    expect(prefetch(3740, barWidth: 3), isTrue);
  });

  test('highly zoomed 60px candles keep a minimum bounded early lead',
      () {
    // 320/60=5.33 bars, two screens only 10.66, so use 25 bars.
    expect(prefetch(3969, barWidth: 60), isFalse);
    expect(prefetch(3970, barWidth: 60), isTrue);
  });

  test('missing small chart history triggers only after user actually pans',
      () {
    expect(prefetch(0, count: 40), isFalse,
        reason: 'No background fetch solely because chart opened');
    expect(prefetch(1, count: 40), isTrue);
    expect(prefetch(0, count: 0), isFalse);
    expect(prefetch(-5, count: 40), isFalse);
  });

  test('bounded 256-bar lead stops extreme zoom from eager network work',
      () {
    // Wide 3200px plot at narrow 3px bar has >1000 bars on screen;
    // avoid starting thousands of bars in advance.
    expect(prefetch(3500, count: 5000, width: 3200, barWidth: 3),
        isFalse);
    expect(prefetch(3680, count: 5000, width: 3200, barWidth: 3),
        isTrue);
  });

  test('invalid gesture geometry is ignored before touching the source',
      () {
    for (final bad in <double>[
      double.nan, double.infinity, double.negativeInfinity,
    ]) {
      expect(prefetch(bad), isFalse);
      expect(prefetch(4000, width: bad), isFalse);
      expect(prefetch(4000, barWidth: bad), isFalse);
    }
    expect(prefetch(100, width: 0), isFalse);
    expect(prefetch(100, barWidth: 0), isFalse);
  });
}
