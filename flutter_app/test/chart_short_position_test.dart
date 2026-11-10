import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_short_position.dart';

void main() {
  const sell = ChartShortPosition(
    startIndex: 50,
    endIndex: 62,
    entry: 4057.56,
    stop: 4066.93,
    target: 4043.91,
  );

  test('sell geometry derives points and R/R without monetary P/L', () {
    expect(sell.risk, closeTo(9.37, 1e-8));
    expect(sell.reward, closeTo(13.65, 1e-8));
    expect(sell.rewardRisk, closeTo(13.65 / 9.37, 1e-8));
    expect(sell.riskPercent, closeTo(9.37 / 4057.56 * 100, 1e-8));
    expect(sell.rewardPercent, closeTo(13.65 / 4057.56 * 100, 1e-8));
  });

  test('editing stop/entry/target keeps a valid sell setup', () {
    expect(sell.edited(stop: 4055), isNull);
    expect(sell.edited(target: 4060), isNull);
    expect(sell.edited(entry: 4070), isNull);
    expect(sell.edited(endIndex: 49), isNull);
    expect(sell.edited(stop: 4070)!.stop, 4070);
    expect(sell.edited(target: 4041)!.target, 4041);
  });

  test('historical pagination keeps exact source prices and anchors', () {
    final shifted = sell.shifted(10000);
    expect(shifted.startIndex, 10050);
    expect(shifted.endIndex, 10062);
    expect(shifted.entry, sell.entry);
    expect(shifted.stop, sell.stop);
    expect(shifted.target, sell.target);
    expect(shifted.visibleAt(10062), isFalse);
    expect(shifted.visibleAt(10063), isTrue);
  });

  test('dragging a sell object moves both time and price, not risk', () {
    final moved = sell.moved(4, 10);
    expect(moved.startIndex, 54);
    expect(moved.endIndex, 66);
    expect(moved.entry, 4067.56);
    expect(moved.risk, closeTo(sell.risk, 1e-8));
    expect(moved.reward, closeTo(sell.reward, 1e-8));
  });

  test('range rebasing preserves prices even when bar indices change', () {
    final rebased = sell.reanchored(103, 121);
    expect(rebased.startIndex, 103);
    expect(rebased.endIndex, 121);
    expect(rebased.entry, sell.entry);
    expect(rebased.target, sell.target);
  });
}
