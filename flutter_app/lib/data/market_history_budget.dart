import 'market_api.dart';

/// Bounded Android on-screen TIME candle memory, not the broker's entire
/// archived history. All chart read/merge/prepend/paint paths share one limit.
abstract final class MarketHistoryBudget {
  static const maxVisibleTimeCandles = 200000;

  static void requireCapacity(int count) {
    if (count < 0 || count > maxVisibleTimeCandles) {
      throw const MarketDataException(
        'تجاوزت الشموع الزمنية حد ذاكرة الشارت (200 ألف). '
        'بقيت بيانات المصدر على القرص دون تعديل؛ '
        'يلزم إظهار نافذة تاريخ أصغر.',
      );
    }
  }
}
