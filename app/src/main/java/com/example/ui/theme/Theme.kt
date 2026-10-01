package com.example.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = TradingAccent,
    onPrimary = Color.White,
    primaryContainer = TradingElevated,
    onPrimaryContainer = TradingAccentLight,
    secondary = TradingCyan,
    onSecondary = Color.Black,
    secondaryContainer = TradingElevated,
    onSecondaryContainer = TradingCyan,
    tertiary = TradingGold,
    onTertiary = Color.Black,
    background = TradingBackground,
    onBackground = TradingTextPrimary,
    surface = TradingCard,
    onSurface = TradingTextPrimary,
    surfaceVariant = TradingElevated,
    onSurfaceVariant = TradingTextSecondary,
    outline = TradingBorder,
    error = TradingNegative,
    onError = Color.White
)

@Composable
fun TradeLabTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = Typography,
        content = content
    )
}
