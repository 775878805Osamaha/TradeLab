import 'dart:convert';

/// Chart-only presentation preferences. Neither OHLC history nor Replay state
/// is owned or changed by this model.
enum ChartButtonVisibility {
  onTap('مرئي عند النقر'),
  always('مرئي دائمًا'),
  hidden('مخفي');

  const ChartButtonVisibility(this.label);
  final String label;
}

enum ChartGridStroke {
  solid('متصل'),
  dashed('متقطع');

  const ChartGridStroke(this.label);
  final String label;
}

enum ChartWatermarkMode {
  replay('وضع إعادة التشغيل'),
  hidden('إخفاء');

  const ChartWatermarkMode(this.label);
  final String label;
}

class ChartPanelSettings {
  const ChartPanelSettings({
    this.axisTextSize = 12,
    this.axisTextColor = 0xFF000000,
    this.scaleLineColor = 0x00000000,
    this.navigationButtons = ChartButtonVisibility.onTap,
    this.paneButtons = ChartButtonVisibility.onTap,
    this.topMarginPercent = 10,
    this.bottomMarginPercent = 8,
    this.rightMarginBars = 10,
    this.verticalGridVisible = false,
    this.horizontalGridVisible = false,
    this.backgroundColor = 0xFFFFFFFF,
    this.verticalGridColor = 0xFFEEEEEE,
    this.horizontalGridColor = 0xFFEEEEEE,
    this.verticalGridStroke = ChartGridStroke.solid,
    this.horizontalGridStroke = ChartGridStroke.solid,
    this.crosshairColor = 0xFF9E9E9E,
    this.crosshairStroke = ChartGridStroke.dashed,
    this.watermarkMode = ChartWatermarkMode.replay,
    this.watermarkColor = 0x26000000,
  });

  final int axisTextSize;
  final int axisTextColor;
  final int scaleLineColor;
  final ChartButtonVisibility navigationButtons;
  final ChartButtonVisibility paneButtons;
  final int topMarginPercent;
  final int bottomMarginPercent;
  final int rightMarginBars;
  final bool verticalGridVisible;
  final bool horizontalGridVisible;
  final int backgroundColor;
  final int verticalGridColor;
  final int horizontalGridColor;
  final ChartGridStroke verticalGridStroke;
  final ChartGridStroke horizontalGridStroke;
  final int crosshairColor;
  final ChartGridStroke crosshairStroke;
  final ChartWatermarkMode watermarkMode;
  final int watermarkColor;

  static bool marginsValid(int top, int bottom, int right) =>
      top >= 0 && bottom >= 0 && top + bottom <= 80 &&
      right >= 0 && right <= 100;

  ChartPanelSettings copyWith({
    int? axisTextSize,
    int? axisTextColor,
    int? scaleLineColor,
    ChartButtonVisibility? navigationButtons,
    ChartButtonVisibility? paneButtons,
    int? topMarginPercent,
    int? bottomMarginPercent,
    int? rightMarginBars,
    bool? verticalGridVisible,
    bool? horizontalGridVisible,
    int? backgroundColor,
    int? verticalGridColor,
    int? horizontalGridColor,
    ChartGridStroke? verticalGridStroke,
    ChartGridStroke? horizontalGridStroke,
    int? crosshairColor,
    ChartGridStroke? crosshairStroke,
    ChartWatermarkMode? watermarkMode,
    int? watermarkColor,
  }) => ChartPanelSettings(
    axisTextSize: axisTextSize ?? this.axisTextSize,
    axisTextColor: axisTextColor ?? this.axisTextColor,
    scaleLineColor: scaleLineColor ?? this.scaleLineColor,
    navigationButtons: navigationButtons ?? this.navigationButtons,
    paneButtons: paneButtons ?? this.paneButtons,
    topMarginPercent: topMarginPercent ?? this.topMarginPercent,
    bottomMarginPercent: bottomMarginPercent ?? this.bottomMarginPercent,
    rightMarginBars: rightMarginBars ?? this.rightMarginBars,
    verticalGridVisible: verticalGridVisible ?? this.verticalGridVisible,
    horizontalGridVisible: horizontalGridVisible ?? this.horizontalGridVisible,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    verticalGridColor: verticalGridColor ?? this.verticalGridColor,
    horizontalGridColor: horizontalGridColor ?? this.horizontalGridColor,
    verticalGridStroke: verticalGridStroke ?? this.verticalGridStroke,
    horizontalGridStroke: horizontalGridStroke ?? this.horizontalGridStroke,
    crosshairColor: crosshairColor ?? this.crosshairColor,
    crosshairStroke: crosshairStroke ?? this.crosshairStroke,
    watermarkMode: watermarkMode ?? this.watermarkMode,
    watermarkColor: watermarkColor ?? this.watermarkColor,
  );

  Map<String, Object> toJson() => {
    'axisTextSize': axisTextSize,
    'axisTextColor': axisTextColor,
    'scaleLineColor': scaleLineColor,
    'navigationButtons': navigationButtons.name,
    'paneButtons': paneButtons.name,
    'topMarginPercent': topMarginPercent,
    'bottomMarginPercent': bottomMarginPercent,
    'rightMarginBars': rightMarginBars,
    'verticalGridVisible': verticalGridVisible,
    'horizontalGridVisible': horizontalGridVisible,
    'backgroundColor': backgroundColor,
    'verticalGridColor': verticalGridColor,
    'horizontalGridColor': horizontalGridColor,
    'verticalGridStroke': verticalGridStroke.name,
    'horizontalGridStroke': horizontalGridStroke.name,
    'crosshairColor': crosshairColor,
    'crosshairStroke': crosshairStroke.name,
    'watermarkMode': watermarkMode.name,
    'watermarkColor': watermarkColor,
  };

  String encode() => jsonEncode(toJson());

  static ChartPanelSettings decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const ChartPanelSettings();
    const defaults = ChartPanelSettings();
    int number(String key, int fallback) {
      final n = decoded[key];
      return n is int ? n : fallback;
    }
    ChartButtonVisibility visibility(String key) =>
      ChartButtonVisibility.values.firstWhere(
        (v) => v.name == decoded[key],
        orElse: () => ChartButtonVisibility.onTap);
    ChartGridStroke stroke(String key, ChartGridStroke fallback) =>
      ChartGridStroke.values.firstWhere(
        (v) => v.name == decoded[key], orElse: () => fallback);
    ChartWatermarkMode watermark() =>
      ChartWatermarkMode.values.firstWhere(
        (v) => v.name == decoded['watermarkMode'],
        orElse: () => ChartWatermarkMode.replay);
    final top = number('topMarginPercent', defaults.topMarginPercent);
    final bottom = number('bottomMarginPercent', defaults.bottomMarginPercent);
    final right = number('rightMarginBars', defaults.rightMarginBars);
    return ChartPanelSettings(
      axisTextSize: number('axisTextSize', defaults.axisTextSize).clamp(8, 24),
      axisTextColor: number('axisTextColor', defaults.axisTextColor),
      scaleLineColor: number('scaleLineColor', defaults.scaleLineColor),
      navigationButtons: visibility('navigationButtons'),
      paneButtons: visibility('paneButtons'),
      topMarginPercent: marginsValid(top, bottom, right)
          ? top : defaults.topMarginPercent,
      bottomMarginPercent: marginsValid(top, bottom, right)
          ? bottom : defaults.bottomMarginPercent,
      rightMarginBars: marginsValid(top, bottom, right)
          ? right : defaults.rightMarginBars,
      verticalGridVisible: decoded['verticalGridVisible'] == true,
      horizontalGridVisible: decoded['horizontalGridVisible'] == true,
      backgroundColor: number('backgroundColor', defaults.backgroundColor),
      verticalGridColor: number('verticalGridColor', defaults.verticalGridColor),
      horizontalGridColor: number('horizontalGridColor', defaults.horizontalGridColor),
      verticalGridStroke: stroke('verticalGridStroke', defaults.verticalGridStroke),
      horizontalGridStroke: stroke('horizontalGridStroke', defaults.horizontalGridStroke),
      crosshairColor: number('crosshairColor', defaults.crosshairColor),
      crosshairStroke: stroke('crosshairStroke', defaults.crosshairStroke),
      watermarkMode: watermark(),
      watermarkColor: number('watermarkColor', defaults.watermarkColor),
    );
  }
}
