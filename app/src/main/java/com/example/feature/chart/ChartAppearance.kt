package com.example.feature.chart

import android.content.SharedPreferences
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.example.R
import com.example.ui.theme.AppearanceSettings

internal data class ChartAppearance(
    val up: Int = 0xFF00B7AA.toInt(), val down: Int = 0xFFFF3D48.toInt(),
    val grid: Boolean = true, val wicks: Boolean = true, val hollow: Boolean = false,
    val background: Int? = null,
    val line: Int = 0xFF5C85FF.toInt(), val gridColor: Int? = null,
    val lastPrice: Boolean = true, val sourceTime: Boolean = true,
    val axisScale: Float = 1f
) {
    fun save(prefs: SharedPreferences) {
        prefs.edit().putInt("up", up).putInt("down", down).putBoolean("grid", grid)
            .putBoolean("wicks", wicks).putBoolean("hollow", hollow)
            .putInt("line", line).putBoolean("last_price", lastPrice).putBoolean("source_time", sourceTime)
            .putFloat("axis_scale", axisScale.takeIf { it.isFinite() }?.coerceIn(.8f, 1.4f) ?: 1f).apply {
                if (gridColor == null) remove("grid_color") else putInt("grid_color", gridColor)
                if (background == null) remove("background") else putInt("background", background)
            }.apply()
    }
    companion object {
        fun load(p: SharedPreferences) = ChartAppearance(p.getInt("up", 0xFF00B7AA.toInt()),
            p.getInt("down", 0xFFFF3D48.toInt()), p.getBoolean("grid", true),
            p.getBoolean("wicks", true), p.getBoolean("hollow", false),
            if(p.contains("background")) p.getInt("background", 0) else null,
            p.getInt("line", 0xFF5C85FF.toInt()),
            if(p.contains("grid_color")) p.getInt("grid_color", 0) else null,
            p.getBoolean("last_price", true), p.getBoolean("source_time", true),
            p.getFloat("axis_scale", 1f).takeIf { it.isFinite() }?.coerceIn(.8f,1.4f) ?: 1f)
    }
}

@Composable
internal fun ChartAppearanceDialog(value: ChartAppearance, onSave: (ChartAppearance) -> Unit, onDismiss: () -> Unit) {
    var draft by remember { mutableStateOf(value) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.chart_appearance)) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            AppearanceSettings()
            ChartColorChoices(stringResource(R.string.candle_up), draft.up) { draft = draft.copy(up = it) }
            ChartColorChoices(stringResource(R.string.candle_down), draft.down) { draft = draft.copy(down = it) }
            ChartColorChoices(stringResource(R.string.chart_background), draft.background) { draft = draft.copy(background = it) }
            TextButton(onClick = { draft = draft.copy(background = null) }) { Text(stringResource(R.string.follow_app_theme)) }
            ChartColorChoices(stringResource(R.string.chart_line_color), draft.line) { draft = draft.copy(line = it) }
            ChartColorChoices(stringResource(R.string.chart_grid_color), draft.gridColor) { draft = draft.copy(gridColor = it) }
            TextButton(onClick = { draft = draft.copy(gridColor = null) }) { Text(stringResource(R.string.chart_grid_auto)) }
            AppearanceToggle(R.string.chart_last_price, draft.lastPrice) { draft = draft.copy(lastPrice = it) }
            AppearanceToggle(R.string.chart_source_time, draft.sourceTime) { draft = draft.copy(sourceTime = it) }
            Text(stringResource(R.string.chart_axis_size))
            Slider(draft.axisScale, { draft = draft.copy(axisScale = it) }, valueRange = .8f..1.4f, steps = 5)
            AppearanceToggle(R.string.chart_grid, draft.grid) { draft = draft.copy(grid = it) }
            AppearanceToggle(R.string.candle_wicks, draft.wicks) { draft = draft.copy(wicks = it) }
            AppearanceToggle(R.string.candle_hollow, draft.hollow) { draft = draft.copy(hollow = it) }
            TextButton(onClick = { draft = ChartAppearance() }) { Text(stringResource(R.string.appearance_reset)) }
        }
    }, confirmButton = { TextButton(onClick = { onSave(draft); onDismiss() }) { Text(stringResource(R.string.appearance_save)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.appearance_cancel)) } })
}

@Composable
private fun AppearanceToggle(label: Int, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(stringResource(label), Modifier.weight(1f)); Switch(checked, onChange)
    }
}

@Composable
internal fun ChartColorChoices(label: String, selected: Int?, onChange: (Int) -> Unit) {
    var custom by remember(selected) { mutableStateOf(selected?.let { "%06X".format(it and 0xFFFFFF) } ?: "") }
    val parsed = custom.removePrefix("#").takeIf { it.matches(Regex("[0-9a-fA-F]{6}")) }?.toLongOrNull(16)
    Text(label)
    OutlinedTextField(custom, { custom = it.take(7) }, singleLine = true,
        label = { Text(stringResource(R.string.custom_color_hex)) },
        isError = custom.isNotEmpty() && parsed == null,
        trailingIcon = { TextButton(enabled = parsed != null, onClick = { parsed?.let { onChange((0xFF000000L or it).toInt()) } }) { Text(stringResource(R.string.appearance_apply)) } })
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(0xFF00B7AA, 0xFFFF3D48, 0xFF2962FF, 0xFFF5A623, 0xFF9C27B0, 0xFF131722, 0xFFFFFFFF, 0xFF000D16).forEach { raw ->
            val color = raw.toInt()
            Surface(Modifier.size(44.dp).clickable(onClickLabel = "$label #${raw.toString(16).takeLast(6)}") { onChange(color) },
                color = Color(color), border = androidx.compose.foundation.BorderStroke(if(selected == color) 3.dp else 1.dp, MaterialTheme.colorScheme.outline)) {
                if(selected == color) Box(contentAlignment = androidx.compose.ui.Alignment.Center) { Text("✓", color = if(color == -1) Color.Black else Color.White) }
            }
        }
    }
}
