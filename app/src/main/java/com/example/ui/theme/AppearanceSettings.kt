package com.example.ui.theme

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.R

internal object AppPalette {
    var light by mutableStateOf(false)
}

@Composable
fun AppearanceSettings() {
    val context = LocalContext.current
    val prefs = remember(context) { context.getSharedPreferences("appearance", 0) }
    var mode by remember { mutableStateOf(prefs.getString("mode", "dark") ?: "dark") }
    DisposableEffect(prefs) {
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if(key == "mode") mode = prefs.getString("mode", "dark") ?: "dark"
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        onDispose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.appearance_title), style = MaterialTheme.typography.titleMedium)
        listOf("dark" to R.string.appearance_dark, "light" to R.string.appearance_light, "system" to R.string.appearance_system).forEach { (value, label) ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                RadioButton(selected = mode == value, onClick = { mode = value; prefs.edit().putString("mode", value).apply() })
                TextButton(onClick = { mode = value; prefs.edit().putString("mode", value).apply() }) { Text(stringResource(label)) }
            }
        }
    }
}
