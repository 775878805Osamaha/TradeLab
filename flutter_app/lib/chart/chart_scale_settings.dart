import 'dart:convert';

/// Price/time axis presentation only. Market candles and replay cursors are
/// deliberately outside this immutable, locally persisted settings model.
enum ChartPriceLabelMode {
  hidden('مخفي'),
  value('قيمة'),
  valueAndLine('قيمة، خط');

  const ChartPriceLabelMode(this.label);
  final String label;
}

enum ChartScaleVisibility {
  always('ظاهر وموجود دائماً'),
  onTap('مرئي عند النقر'),
  hidden('مخفي');

  const ChartScaleVisibility(this.label);
  final String label;
}

/// Display values taken from the two supplied TradingView reference frames.
/// Colors are editable display preferences; they are never OHLC values.
class ChartScaleSettings {
  const ChartScaleSettings({
    this.currencyUnit = ChartScaleVisibility.always,
    this.scaleButtons = ChartScaleVisibility.onTap,
    this.lockPriceToBar = false,
    this.scaleMode = 'تلقائي',
    this.avoidOverlappingLabels = true,
    this.plusButton = true,
    this.countdown = true,
    this.symbolLabel = ChartPriceLabelMode.valueAndLine,
    this.symbolLabelColor = 0xFF22A68F,
    this.symbolNegativeColor = 0xFFF24B60,
    this.symbolLabelPlacement = 'القيمة حسب المقياس',
    this.previousClose = ChartPriceLabelMode.hidden,
    this.previousCloseColor = 0xFFAAAAAA,
    this.indicatorLabels = ChartPriceLabelMode.value,
    this.highLow = ChartPriceLabelMode.hidden,
    this.highColor = 0xFF84CDC4,
    this.lowColor = 0xFFF1A1AC,
    this.bidAsk = ChartPriceLabelMode.hidden,
    this.askColor = 0xFFF49EA8,
    this.bidColor = 0xFF88A3F8,
    this.weekdayOnLabels = true,
  });

  final ChartScaleVisibility currencyUnit;
  final ChartScaleVisibility scaleButtons;
  final bool lockPriceToBar;
  final String scaleMode;
  final bool avoidOverlappingLabels;
  final bool plusButton;
  final bool countdown;
  final ChartPriceLabelMode symbolLabel;
  final int symbolLabelColor;
  final int symbolNegativeColor;
  final String symbolLabelPlacement;
  final ChartPriceLabelMode previousClose;
  final int previousCloseColor;
  final ChartPriceLabelMode indicatorLabels;
  final ChartPriceLabelMode highLow;
  final int highColor;
  final int lowColor;
  final ChartPriceLabelMode bidAsk;
  final int askColor;
  final int bidColor;
  final bool weekdayOnLabels;

  ChartScaleSettings copyWith({
    ChartScaleVisibility? currencyUnit,
    ChartScaleVisibility? scaleButtons,
    bool? lockPriceToBar,
    String? scaleMode,
    bool? avoidOverlappingLabels,
    bool? plusButton,
    bool? countdown,
    ChartPriceLabelMode? symbolLabel,
    int? symbolLabelColor,
    int? symbolNegativeColor,
    String? symbolLabelPlacement,
    ChartPriceLabelMode? previousClose,
    int? previousCloseColor,
    ChartPriceLabelMode? indicatorLabels,
    ChartPriceLabelMode? highLow,
    int? highColor,
    int? lowColor,
    ChartPriceLabelMode? bidAsk,
    int? askColor,
    int? bidColor,
    bool? weekdayOnLabels,
  }) => ChartScaleSettings(
    currencyUnit: currencyUnit ?? this.currencyUnit,
    scaleButtons: scaleButtons ?? this.scaleButtons,
    lockPriceToBar: lockPriceToBar ?? this.lockPriceToBar,
    scaleMode: scaleMode ?? this.scaleMode,
    avoidOverlappingLabels: avoidOverlappingLabels ?? this.avoidOverlappingLabels,
    plusButton: plusButton ?? this.plusButton,
    countdown: countdown ?? this.countdown,
    symbolLabel: symbolLabel ?? this.symbolLabel,
    symbolLabelColor: symbolLabelColor ?? this.symbolLabelColor,
    symbolNegativeColor: symbolNegativeColor ?? this.symbolNegativeColor,
    symbolLabelPlacement: symbolLabelPlacement ?? this.symbolLabelPlacement,
    previousClose: previousClose ?? this.previousClose,
    previousCloseColor: previousCloseColor ?? this.previousCloseColor,
    indicatorLabels: indicatorLabels ?? this.indicatorLabels,
    highLow: highLow ?? this.highLow,
    highColor: highColor ?? this.highColor,
    lowColor: lowColor ?? this.lowColor,
    bidAsk: bidAsk ?? this.bidAsk,
    askColor: askColor ?? this.askColor,
    bidColor: bidColor ?? this.bidColor,
    weekdayOnLabels: weekdayOnLabels ?? this.weekdayOnLabels,
  );

  String encode() => jsonEncode({
    'currencyUnit': currencyUnit.name,
    'scaleButtons': scaleButtons.name,
    'lockPriceToBar': lockPriceToBar,
    'scaleMode': scaleMode,
    'avoidOverlappingLabels': avoidOverlappingLabels,
    'plusButton': plusButton,
    'countdown': countdown,
    'symbolLabel': symbolLabel.name,
    'symbolLabelColor': symbolLabelColor,
    'symbolNegativeColor': symbolNegativeColor,
    'symbolLabelPlacement': symbolLabelPlacement,
    'previousClose': previousClose.name,
    'previousCloseColor': previousCloseColor,
    'indicatorLabels': indicatorLabels.name,
    'highLow': highLow.name,
    'highColor': highColor,
    'lowColor': lowColor,
    'bidAsk': bidAsk.name,
    'askColor': askColor,
    'bidColor': bidColor,
    'weekdayOnLabels': weekdayOnLabels,
  });

  static ChartScaleSettings decode(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    T selected<T extends Enum>(List<T> values, String key, T fallback) {
      for (final value in values) {
        if (value.name == data[key]) return value;
      }
      return fallback;
    }
    int color(String key, int fallback) =>
        data[key] is int ? data[key] as int : fallback;
    bool flag(String key, bool fallback) =>
        data[key] is bool ? data[key] as bool : fallback;
    const defaults = ChartScaleSettings();
    return ChartScaleSettings(
      currencyUnit: selected(ChartScaleVisibility.values, 'currencyUnit', defaults.currencyUnit),
      scaleButtons: selected(ChartScaleVisibility.values, 'scaleButtons', defaults.scaleButtons),
      lockPriceToBar: flag('lockPriceToBar', defaults.lockPriceToBar),
      scaleMode: data['scaleMode'] is String ? data['scaleMode'] as String : defaults.scaleMode,
      avoidOverlappingLabels: flag('avoidOverlappingLabels', defaults.avoidOverlappingLabels),
      plusButton: flag('plusButton', defaults.plusButton),
      countdown: flag('countdown', defaults.countdown),
      symbolLabel: selected(ChartPriceLabelMode.values, 'symbolLabel', defaults.symbolLabel),
      symbolLabelColor: color('symbolLabelColor', defaults.symbolLabelColor),
      symbolNegativeColor: color('symbolNegativeColor', defaults.symbolNegativeColor),
      symbolLabelPlacement: data['symbolLabelPlacement'] is String
          ? data['symbolLabelPlacement'] as String : defaults.symbolLabelPlacement,
      previousClose: selected(ChartPriceLabelMode.values, 'previousClose', defaults.previousClose),
      previousCloseColor: color('previousCloseColor', defaults.previousCloseColor),
      indicatorLabels: selected(ChartPriceLabelMode.values, 'indicatorLabels', defaults.indicatorLabels),
      highLow: selected(ChartPriceLabelMode.values, 'highLow', defaults.highLow),
      highColor: color('highColor', defaults.highColor),
      lowColor: color('lowColor', defaults.lowColor),
      bidAsk: selected(ChartPriceLabelMode.values, 'bidAsk', defaults.bidAsk),
      askColor: color('askColor', defaults.askColor),
      bidColor: color('bidColor', defaults.bidColor),
      weekdayOnLabels: flag('weekdayOnLabels', defaults.weekdayOnLabels),
    );
  }

  static const weekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
    'الجمعة', 'السبت', 'الأحد'];

  /// The reference's weekday switch uses the phone's local trading-time axis.
  static String localWeekday(DateTime timestamp) =>
      weekdays[timestamp.toLocal().weekday - 1];
}
