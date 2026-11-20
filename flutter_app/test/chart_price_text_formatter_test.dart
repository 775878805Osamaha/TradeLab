import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_price_text_formatter.dart';

/// Exact formatter previously executed in _CandleChartPainter on every
/// price label. Keep it independent as a reference for visual parity.
String _previousPaintText(double value, int digits) {
  final parts = value.toStringAsFixed(digits).split('.');
  final integer = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return digits == 0 ? integer : '$' + 'integer.' + '${parts.last}';
}

void main() {
  test('gold, USDJPY, US30, BTC and microprice labels stay byte-identical',
      () {
    const cases = <(double, int)>[
      (3987, 2), (3987.12345, 5), (0.00123456, 8),
      (1.072100012, 9), (1.072100000025, 12), (145.123456, 6),
      (52534, 0), (52635.125, 3), (50000.01, 2),
      (1000000, 0), (1000000000.5, 2), (0, 2),
      (-3987.21, 2), (-1234567.89, 2), (-0.0000002, 8),
      (999999999.999, 3), (0.000000000001, 12),
    ];
    for (final (value, digits) in cases) {
      final expected = _previousPaintText(value, digits);
      expect(ChartPriceTextFormatter.price(value, digits), expected,
          reason: 'Price-axis and SL/TP drawing characters must not change');
    }
    expect(ChartPriceTextFormatter.price(3987.2, 2), '3,987.20');
    expect(ChartPriceTextFormatter.price(52534, 0), '52,534');
    expect(ChartPriceTextFormatter.price(-1234567.89, 2),
        '-1,234,567.89');
    expect(ChartPriceTextFormatter.price(1.072100012, 9),
        '1.072100012');
  });

  test('hundreds of changing chart labels preserve old formatting exactly',
      () {
    for (var i = 0; i < 500; i++) {
      final price = i.isEven
          ? 3850.123456789 + i * .1875
          : -1000000.0 + i * 1234.56789;
      for (final digits in [0, 2, 3, 5, 7, 9, 12]) {
        expect(ChartPriceTextFormatter.price(price, digits),
            _previousPaintText(price, digits));
      }
    }
  });

  test('invalid formatting precision retains original argument behavior',
      () {
    expect(() => ChartPriceTextFormatter.price(1.2, -1),
        throwsRangeError);
    expect(() => ChartPriceTextFormatter.price(1.2, 21),
        throwsRangeError);
  });
}
