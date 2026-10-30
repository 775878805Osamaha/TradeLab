package com.example.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.*
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color

private fun darkScheme() = darkColorScheme(
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
    val context = LocalContext.current
    val prefs = remember(context) { context.getSharedPreferences("appearance", 0) }
    var mode by remember { mutableStateOf(prefs.getString("mode", "dark")) }
    DisposableEffect(prefs) {
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "mode") mode = prefs.getString("mode", "dark")
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    val light = mode == "light" || (mode == "system" && !isSystemInDarkTheme())
    val view = LocalView.current
    SideEffect {
        AppPalette.light = light
        var host = view.context
        while(host is android.content.ContextWrapper && host !is android.app.Activity) host = host.baseContext
        (host as? android.app.Activity)?.window?.let { window ->
            androidx.core.view.WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = light
                isAppearanceLightNavigationBars = light
            }
        }
    }
    val scheme = if (light) lightColorScheme(
        primary = TradingAccent, onPrimary = Color.White,
        background = Color(0xFFF4F6FA), onBackground = Color(0xFF192231),
        surface = Color.White, onSurface = Color(0xFF192231),
        surfaceVariant = Color(0xFFE8ECF3), onSurfaceVariant = Color(0xFF526176),
        outline = Color(0xFFCBD2DF), error = Color(0xFFB3261E)
    ) else darkScheme()
    MaterialTheme(
        colorScheme = scheme,
        typography = Typography,
        content = content
    )
}
