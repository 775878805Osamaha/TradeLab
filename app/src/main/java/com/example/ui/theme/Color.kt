package com.example.ui.theme

import androidx.compose.ui.graphics.Color

// Shared semantic colors observed by Compose and Canvas when appearance changes.
val TradingChartBackground get() = if (AppPalette.light) Color.White else Color(0xFF000D16)
val TradingBackground get() = if (AppPalette.light) Color(0xFFF4F6FA) else Color(0xFF131722)
val TradingCard get() = if (AppPalette.light) Color(0xFFFFFFFF) else Color(0xFF1E222D)
val TradingElevated get() = if (AppPalette.light) Color(0xFFE8ECF3) else Color(0xFF242936)
val TradingBorder get() = if (AppPalette.light) Color(0xFFCBD2DF) else Color(0xFF2A2E39)

val TradingPositive = Color(0xFF26A69A)
val TradingPositiveBg = Color(0x1F26A69A)
val TradingNegative = Color(0xFFEF5350)
val TradingNegativeBg = Color(0x1FEF5350)

val TradingAccent = Color(0xFF2962FF)
val TradingAccentLight = Color(0xFF5C85FF)
val TradingCyan = TradingPositive
val TradingGold = Color(0xFFF5A623)

val TradingTextPrimary get() = if (AppPalette.light) Color(0xFF192231) else Color(0xFFD1D4DC)
val TradingTextSecondary get() = if (AppPalette.light) Color(0xFF526176) else Color(0xFF9598A1)
val TradingTextMuted get() = if (AppPalette.light) Color(0xFF637086) else Color(0xFF737783)
