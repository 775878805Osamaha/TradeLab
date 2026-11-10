import 'package:flutter/material.dart';

/// Preserved from the existing TradeLab Compose palette.
abstract final class TradeColors {
  static const blue = Color(0xFF2962FF);
  static const blueLight = Color(0xFF5C85FF);
  static const positive = Color(0xFF26A69A);
  static const negative = Color(0xFFEF5350);
  // Short-position drawing palette, measured against PROMPT 01 reference.
  // These are presentation colors and never encode an executed trade.
  static const shortStopFill = Color(0xFFF88F96);
  static const shortTargetFill = Color(0xFF6CA3F5);
  static const shortHandle = Color(0xFF2351E2);
  static const shortLabelBlue = Color(0xFF3374F4);
  static const shortLabelRed = Color(0xFFE9344F);
  // Selected price-range rectangle in PROMPT 02; annotation UI only.
  static const rectangleHandle = Color(0xFF2556E4);
  static const rectangleAxisTag = Color(0xFF2962FF);
  static const rectangleAccentGreen = Color(0xFF5BAD6F);
  static const rectangleAccentOrange = Color(0xFFFFA41D);
  // TradingView-reference chart type picker: isolated white sheet, not the
  // app-wide Material cards or a replacement global light theme.
  static const chartTypeSheet = Color(0xFFFFFFFF);
  static const chartTypeTile = Color(0xFFF2F2F2);
  static const chartTypeSelected = Color(0xFF2E2E2E);
  static const chartTypeInk = Color(0xFF101010);
  static const chartTypeDragHandle = Color(0xFFE3E3E3);
  // PROMPT 04 reference: white drawing catalog, light tiles, amber favorites.
  static const drawingSheet = Color(0xFFFFFFFF);
  static const drawingTile = Color(0xFFF2F2F2);
  static const drawingInk = Color(0xFF101010);
  static const drawingMutedInk = Color(0xFF777777);
  static const drawingHandle = Color(0xFFE3E3E3);
  static const drawingFavorite = Color(0xFFFF9800);
  static const gold = Color(0xFFF5A623);

  static const lightCanvas = Color(0xFFF4F6FA);
  static const lightSurface = Colors.white;
  static const lightElevated = Color(0xFFE8ECF3);
  static const lightBorder = Color(0xFFCBD2DF);
  static const lightText = Color(0xFF192231);
  static const lightSecondary = Color(0xFF526176);

  static const darkCanvas = Color(0xFF131722);
  static const darkSurface = Color(0xFF1E222D);
  static const darkElevated = Color(0xFF242936);
  static const darkBorder = Color(0xFF2A2E39);
  static const darkText = Color(0xFFD1D4DC);
  static const darkSecondary = Color(0xFFACAFB8);
}

abstract final class TradeSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const radius = 14.0;
}

abstract final class TradeTheme {
  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? TradeColors.darkSurface : TradeColors.lightSurface;
    final foreground = dark ? TradeColors.darkText : TradeColors.lightText;
    final outline = dark ? TradeColors.darkBorder : TradeColors.lightBorder;
    final scheme = ColorScheme.fromSeed(
      seedColor: TradeColors.blue,
      brightness: brightness,
      surface: surface,
    ).copyWith(
      primary: TradeColors.blue,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: foreground,
      outline: outline,
      error: TradeColors.negative,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? TradeColors.darkCanvas : TradeColors.lightCanvas,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: outline.withValues(alpha: .7)),
          borderRadius: BorderRadius.circular(TradeSpacing.radius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        height: 72,
        indicatorColor: TradeColors.blue.withValues(alpha: .10),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? TradeColors.blue
              : (dark ? TradeColors.darkSecondary : TradeColors.lightSecondary),
        )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? TradeColors.darkElevated : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? TradeColors.darkElevated : Colors.white,
        selectedColor: TradeColors.blue.withValues(alpha: .12),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        labelStyle: TextStyle(color: foreground, fontSize: 12),
      ),
      dividerColor: outline.withValues(alpha: .65),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
