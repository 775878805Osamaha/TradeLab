package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.feature.chart.model.ChartDrawing
import com.example.feature.chart.model.DrawingLineStyle
import com.example.feature.chart.model.DrawingTool
import com.example.feature.chart.model.isTextTool

/** TradingView-like quick actions on the chart, without opening a modal on selection. */
@Composable
internal fun DrawingContextToolbar(
    drawing: ChartDrawing,
    onUpdate: (ChartDrawing) -> Unit,
    onDelete: () -> Unit,
    onCopy: () -> Unit,
    onProperties: () -> Unit,
    onDismiss: () -> Unit
) {
    var styleMenu by remember(drawing.id) { mutableStateOf(false) }
    var widthMenu by remember(drawing.id) { mutableStateOf(false) }
    var colorMenu by remember(drawing.id) { mutableStateOf(false) }
    var stopColorMenu by remember(drawing.id) { mutableStateOf(false) }
    var showTextEditor by remember(drawing.id) { mutableStateOf(false) }
    var labelText by remember(drawing.id) { mutableStateOf(if (drawing.text == "تعليق") "" else drawing.text) }
    val ink = Color(0xFFF2F3F7)
    val dark = Color(0xFF202229)
    val blue = Color(0xFF3479FF)
    Surface(
        // Leave breathing room around the selection like TradingView's
        // floating editing palette. Secondary actions remain horizontally
        // scrollable on a narrow mobile display.
        modifier = Modifier.fillMaxWidth(0.86f).testTag("drawing_context_toolbar"),
        color = dark,
        shape = RoundedCornerShape(13.dp),
        shadowElevation = 12.dp
    ) {
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 4.dp, vertical = 3.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(1.dp)
        ) {
            IconButton(onClick = onProperties, modifier = Modifier.testTag("drawing_edit_more")) {
                Icon(Icons.Default.MoreHoriz, contentDescription = "المزيد من إعدادات الرسم", tint = ink)
            }
            IconButton(onClick = onDelete, modifier = Modifier.testTag("drawing_edit_delete")) {
                Icon(Icons.Default.DeleteOutline, contentDescription = "حذف الرسم المحدد", tint = ink)
            }
            Box {
                IconButton(onClick = { styleMenu = true }, modifier = Modifier.testTag("drawing_edit_style")) {
                    Icon(Icons.Default.Tune, contentDescription = "نمط الخط", tint = ink)
                }
                DropdownMenu(expanded = styleMenu, onDismissRequest = { styleMenu = false }) {
                    DrawingLineStyle.entries.forEach { style ->
                        DropdownMenuItem(
                            text = { Text(when (style) {
                                DrawingLineStyle.SOLID -> "خط متصل ━━━"
                                DrawingLineStyle.DASHED -> "خط متقطع ┄┄┄"
                                DrawingLineStyle.DOTTED -> "خط منقط ·····"
                            }) },
                            onClick = { onUpdate(drawing.copy(lineStyle = style)); styleMenu = false },
                            leadingIcon = {
                                if (drawing.lineStyle == style) Icon(Icons.Default.Check, contentDescription = null)
                            }
                        )
                    }
                }
            }
            Box {
                TextButton(onClick = { widthMenu = true }, modifier = Modifier.testTag("drawing_edit_width")) {
                    Text("${drawing.strokeWidth.toInt()}px", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = ink)
                }
                DropdownMenu(expanded = widthMenu, onDismissRequest = { widthMenu = false }) {
                    listOf(1f, 2f, 3f, 4f, 5f, 6f).forEach { width ->
                        DropdownMenuItem(text = { Text("${width.toInt()}px") },
                            onClick = { onUpdate(drawing.copy(strokeWidth = width)); widthMenu = false },
                            leadingIcon = { if (drawing.strokeWidth == width) Icon(Icons.Default.Check, null) })
                    }
                }
            }
            Box {
                IconButton(onClick = { colorMenu = true }, modifier = Modifier.testTag("drawing_edit_color")) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.FormatColorFill, contentDescription = "لون الرسم", tint = ink, modifier = Modifier.size(21.dp))
                        Box(Modifier.size(26.dp, 4.dp).clip(RoundedCornerShape(4.dp)).background(drawing.color))
                    }
                }
                DropdownMenu(expanded = colorMenu, onDismissRequest = { colorMenu = false }) {
                    listOf(
                        "أزرق" to Color(0xFF2962FF),
                        "أخضر" to Color(0xFF4CAF50),
                        "تركوازي" to Color(0xFF00B7AA),
                        "أحمر" to Color(0xFFFF3D48),
                        "أصفر" to Color(0xFFFFD54F),
                        "أبيض" to Color.White
                    ).forEach { (name, swatch) ->
                        DropdownMenuItem(
                            text = { Text(name) },
                            leadingIcon = { Box(Modifier.size(20.dp).clip(CircleShape).background(swatch)) },
                            onClick = { onUpdate(drawing.copy(color = swatch)); colorMenu = false }
                        )
                    }
                }
            }
            if (drawing.tool == DrawingTool.LONG_POSITION || drawing.tool == DrawingTool.SHORT_POSITION) {
                Box {
                    IconButton(onClick = { stopColorMenu = true }, modifier = Modifier.testTag("drawing_edit_stop_color")) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Default.FormatColorFill, contentDescription = "لون وقف الخسارة", tint = ink, modifier = Modifier.size(21.dp))
                            Box(Modifier.size(26.dp, 4.dp).clip(RoundedCornerShape(4.dp)).background(drawing.secondaryColor))
                        }
                    }
                    DropdownMenu(expanded = stopColorMenu, onDismissRequest = { stopColorMenu = false }) {
                        listOf("أحمر" to Color(0xFFFF3D48), "برتقالي" to Color(0xFFFF9800),
                            "أزرق" to Color(0xFF2962FF), "أخضر" to Color(0xFF4CAF50)).forEach { (name, swatch) ->
                            DropdownMenuItem(text = { Text(name) }, leadingIcon = {
                                Box(Modifier.size(20.dp).clip(CircleShape).background(swatch))
                            }, onClick = { onUpdate(drawing.copy(secondaryColor = swatch)); stopColorMenu = false })
                        }
                    }
                }
            }
            if (drawing.tool.isTextTool || drawing.tool in setOf(DrawingTool.HORIZONTAL_LINE, DrawingTool.TRENDLINE)) {
                IconButton(onClick = { showTextEditor = true }, modifier = Modifier.testTag("drawing_edit_text")) {
                    Icon(Icons.Default.TextFields, contentDescription = "تعديل نص الرسم", tint = ink)
                }
            }
            IconButton(onClick = onCopy, modifier = Modifier.testTag("drawing_edit_copy")) {
                Icon(Icons.Default.ContentCopy, contentDescription = "نسخ الرسم", tint = ink)
            }
            IconButton(onClick = onProperties, modifier = Modifier.testTag("drawing_edit_properties")) {
                Icon(Icons.Default.Settings, contentDescription = "خصائص الرسم", tint = blue)
            }
            IconButton(onClick = onDismiss, modifier = Modifier.testTag("drawing_edit_close")) {
                Icon(Icons.Default.Close, contentDescription = "إلغاء تحديد الرسم", tint = ink)
            }
        }
    }
    if (showTextEditor) {
        AlertDialog(
            onDismissRequest = { showTextEditor = false },
            title = { Text("تعديل النص") },
            text = { OutlinedTextField(value = labelText, onValueChange = { labelText = it },
                label = { Text("نص الرسم") }, modifier = Modifier.testTag("drawing_edit_text_input")) },
            confirmButton = { TextButton(onClick = {
                onUpdate(drawing.copy(text = labelText.ifBlank { "تعليق" }))
                showTextEditor = false
            }) { Text("حفظ") } },
            dismissButton = { TextButton(onClick = { showTextEditor = false }) { Text("إلغاء") } }
        )
    }
}
