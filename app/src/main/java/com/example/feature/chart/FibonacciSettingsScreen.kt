package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.text.input.KeyboardType
import com.example.core.model.Candle
import com.example.feature.chart.model.*
import java.util.Locale

private val fibInk = Color(0xFF171717)
private val fibBorder = Color(0xFFDDDDDD)

/** Full-page Fibonacci editor, kept inside ChartScreen so the app's real bottom navigation remains visible. */
@Composable
internal fun FibonacciSettingsScreen(
    drawing: ChartDrawing,
    candles: List<Candle>,
    onCancel: () -> Unit,
    onSave: (ChartDrawing) -> Unit,
    onDelete: () -> Unit,
    onCopy: ((ChartDrawing) -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val focusManager = LocalFocusManager.current
    var tab by remember(drawing.id) { mutableIntStateOf(0) }
    LaunchedEffect(tab) { focusManager.clearFocus(force = true) }
    var settings by remember(drawing.id) { mutableStateOf(drawing.fibonacci) }
    var levelsRaw by remember(drawing.id) { mutableStateOf(drawing.fibonacci.levels.map { fibNumber(it.value) }) }
    var ruleInputs by remember(drawing.id) { mutableStateOf(drawing.fibonacci.timeRules.associate { rule ->
        rule.unit to (rule.from.toString() to rule.to.toString())
    }) }
    var firstPrice by remember(drawing.id) { mutableStateOf(fibNumber(drawing.startPrice)) }
    var secondPrice by remember(drawing.id) { mutableStateOf(fibNumber(drawing.endPrice ?: drawing.startPrice)) }
    val firstIndex = remember(drawing.startTime, candles) { candles.indexOfLast { it.openTime <= drawing.startTime }.takeIf { it >= 0 }?.plus(1) }
    val secondIndex = remember(drawing.endTime, candles) { candles.indexOfLast { it.openTime <= (drawing.endTime ?: drawing.startTime) }.takeIf { it >= 0 }?.plus(1) }
    var firstBar by remember(drawing.id, firstIndex) { mutableStateOf(firstIndex?.toString() ?: "") }
    var secondBar by remember(drawing.id, secondIndex) { mutableStateOf(secondIndex?.toString() ?: "") }
    var lineColor by remember(drawing.id) { mutableStateOf(drawing.color) }
    val lineStyle = drawing.lineStyle
    var lineWidth by remember(drawing.id) { mutableFloatStateOf(drawing.strokeWidth) }
    var title by remember(drawing.id) { mutableStateOf(drawing.text.takeUnless { it == "تعليق" } ?: "تصحيح فيبوناتشي") }
    var renaming by remember { mutableStateOf(false) }
    var showMore by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var colorTarget by remember { mutableIntStateOf(-1) }
    val pricesValid = firstPrice.toDoubleOrNull()?.let { it.isFinite() && it > 0.0 } == true &&
        secondPrice.toDoubleOrNull()?.let { it.isFinite() && it > 0.0 } == true
    val levelsValid = levelsRaw.all { it.toDoubleOrNull()?.let { n -> n.isFinite() && n in -100.0..100.0 } == true }
    val rulesValid = settings.timeRules.all { rule ->
        val inputs = ruleInputs[rule.unit] ?: return@all false
        val from = inputs.first.toIntOrNull(); val to = inputs.second.toIntOrNull()
        from != null && to != null && from in 1..rule.unit.upperBound && to in from..rule.unit.upperBound
    }
    val barValid = candles.isEmpty() || listOf(firstBar, secondBar).all {
        it.toIntOrNull()?.let { index -> index in 1..candles.size } == true
    }
    val canSave = pricesValid && levelsValid && rulesValid && barValid

    Column(modifier.fillMaxSize().background(Color.White).testTag("fib_settings_screen")) {
        Row(Modifier.fillMaxWidth().height(80.dp).padding(start = 13.dp, end = 20.dp),
            horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onCancel, modifier = Modifier.testTag("fib_close")) {
                Icon(Icons.Outlined.Close, contentDescription = "إغلاق", modifier = Modifier.size(27.dp), tint = fibInk)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { renaming = true }, modifier = Modifier.testTag("fib_rename")) {
                    Icon(Icons.Outlined.Edit, contentDescription = "تعديل اسم الرسم", tint = fibInk)
                }
                Text(title, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.Black,
                    maxLines = 1, modifier = Modifier.widthIn(max = 250.dp).testTag("fib_title"))
            }
        }
        Row(Modifier.fillMaxWidth().height(45.dp).padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
            listOf("الظهور", "إحداثيات", "نمط").forEachIndexed { i, label ->
                val selected = tab == 2 - i
                Column(Modifier.width(80.dp).fillMaxHeight().clickable {
                    focusManager.clearFocus(force = true)
                    tab = 2 - i
                }
                    .testTag("fib_tab_${2 - i}"), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Bottom) {
                    Text(label, fontSize = 17.sp, fontWeight = FontWeight.Medium, color = fibInk)
                    Spacer(Modifier.height(7.dp))
                    Box(Modifier.width(48.dp).height(4.dp)
                        .background(if (selected) Color(0xFF252525) else Color.Transparent, RoundedCornerShape(6.dp)))
                }
            }
        }
        HorizontalDivider(thickness = 2.dp, color = Color(0xFFF3F3F3))
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when (tab) {
                0 -> FibonacciStyleTab(settings, levelsRaw, lineColor, lineStyle, lineWidth,
                    onSettings = { settings = it }, onRawLevel = { index, next ->
                        levelsRaw = levelsRaw.toMutableList().also { it[index] = next }
                    }, onColor = { colorTarget = it },
                    onLineWidth = { lineWidth = it })
                1 -> FibonacciCoordinatesTab(firstPrice, secondPrice, firstBar, secondBar, candles.isNotEmpty(),
                    onFirstPrice = { firstPrice = it }, onSecondPrice = { secondPrice = it },
                    onFirstBar = { firstBar = it }, onSecondBar = { secondBar = it })
                else -> FibonacciVisibilityTab(settings, ruleInputs,
                    onSettings = { settings = it }, onRawInput = { unit, isStart, value ->
                        val old = ruleInputs[unit] ?: ("1" to unit.upperBound.toString())
                        val updated = if (isStart) value to old.second else old.first to value
                        ruleInputs = ruleInputs + (unit to updated)
                        val from = updated.first.toIntOrNull(); val to = updated.second.toIntOrNull()
                        if (from != null && to != null && from in 1..unit.upperBound && to in from..unit.upperBound) {
                            settings = settings.updateRule(FibTimeRule(unit,
                                settings.timeRules.first { it.unit == unit }.enabled, from, to))
                        }
                    })
            }
        }
        HorizontalDivider(thickness = 1.dp, color = Color(0xFFE8E8E8))
        Row(Modifier.fillMaxWidth().height(69.dp).padding(horizontal = 20.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = {
                if (!canSave) return@Button
                val p1 = firstPrice.toDouble(); val p2 = secondPrice.toDouble()
                val updated = settings.copy(levels = settings.levels.mapIndexed { i, level ->
                    level.copy(value = levelsRaw[i].toDouble())
                })
                val time1 = firstBar.toIntOrNull()?.let { candles.getOrNull(it - 1)?.openTime } ?: drawing.startTime
                val time2 = secondBar.toIntOrNull()?.let { candles.getOrNull(it - 1)?.openTime } ?: drawing.endTime
                val anchors = if (drawing.anchors.isNotEmpty()) drawing.anchors.mapIndexed { i, anchor ->
                    when (i) { 0 -> DrawingAnchor(time1, p1); 1 -> DrawingAnchor(time2 ?: anchor.time, p2); else -> anchor }
                } else emptyList()
                onSave(drawing.copy(startPrice = p1, endPrice = p2,
                    startTime = time1, endTime = time2, text = title, anchors = anchors,
                    color = lineColor, lineStyle = lineStyle, strokeWidth = lineWidth, fibonacci = updated))
            }, enabled = canSave, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF222222)),
                shape = RoundedCornerShape(9.dp), modifier = Modifier.height(40.dp).testTag("fib_confirm")) {
                Text("موافق", fontSize = 17.sp, color = Color.White)
            }
            Spacer(Modifier.width(12.dp))
            OutlinedButton(onClick = onCancel, shape = RoundedCornerShape(9.dp),
                border = androidx.compose.foundation.BorderStroke(1.3.dp, fibInk),
                modifier = Modifier.height(40.dp).testTag("fib_cancel")) {
                Text("إلغاء", fontSize = 17.sp, color = fibInk)
            }
            Spacer(Modifier.weight(1f))
            Box {
                OutlinedButton(onClick = { showMore = true }, shape = RoundedCornerShape(10.dp),
                    border = androidx.compose.foundation.BorderStroke(1.dp, fibBorder),
                    modifier = Modifier.height(40.dp).width(63.dp).testTag("fib_more"),
                    contentPadding = PaddingValues(0.dp)) {
                    Icon(Icons.Outlined.MoreHoriz, contentDescription = "المزيد", tint = fibInk)
                }
                DropdownMenu(expanded = showMore, onDismissRequest = { showMore = false }) {
                    DropdownMenuItem(text = { Text("إضافة مستوى") }, onClick = {
                        if (settings.levels.size < 64) {
                            settings = settings.copy(levels = settings.levels +
                                FibonacciLevel(0.0, Color(0xFF4CAF50)))
                            levelsRaw = levelsRaw + "0"
                        }
                        showMore = false
                    })
                    DropdownMenuItem(text = { Text("إعادة تعيين الإعدادات") }, onClick = {
                        settings = FibonacciSettings(); levelsRaw = settings.levels.map { fibNumber(it.value) }
                        ruleInputs = settings.timeRules.associate { it.unit to (it.from.toString() to it.to.toString()) }
                        showMore = false
                    })
                    if (onCopy != null) DropdownMenuItem(text = { Text("نسخ الرسم") }, onClick = {
                        onCopy(drawing); showMore = false
                    })
                    DropdownMenuItem(text = { Text("حذف الرسم", color = Color(0xFFC62828)) },
                        onClick = { showMore = false; confirmingDelete = true })
                }
            }
        }
    }
    if (renaming) {
        AlertDialog(onDismissRequest = { renaming = false }, title = { Text("اسم الرسم") },
            text = { OutlinedTextField(title, { title = it.take(60) }, singleLine = true) },
            confirmButton = { TextButton(onClick = { renaming = false }, enabled = title.isNotBlank()) { Text("موافق") } },
            dismissButton = { TextButton(onClick = { renaming = false }) { Text("إلغاء") } })
    }
    if (confirmingDelete) {
        AlertDialog(onDismissRequest = { confirmingDelete = false }, title = { Text("حذف فيبوناتشي؟") },
            text = { Text("سيُحذف هذا الرسم فقط من الشارت الحالي.") },
            confirmButton = { TextButton(onClick = { confirmingDelete = false; onDelete() }) { Text("حذف") } },
            dismissButton = { TextButton(onClick = { confirmingDelete = false }) { Text("إلغاء") } })
    }
    if (colorTarget != -1) {
        val colors = listOf(Color(0xFFF53649), Color.White, Color(0xFFFFF37D), Color(0xFF4CAF50),
            Color(0xFF00A18F), Color(0xFF8CA8F8), Color(0xFFEA8EA2), Color(0xFFC38DCE),
            Color(0xFFFFA000), Color(0xFF737373), Color.Black, Color(0xFF40B9CF))
        AlertDialog(onDismissRequest = { colorTarget = -1 },
            title = { Text(if (colorTarget == -3) "لون خط الاتجاه" else "لون المستوى") },
            text = {
                Column {
                    colors.chunked(6).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                            row.forEach { c ->
                                Box(Modifier.size(34.dp).border(1.dp, fibBorder, RoundedCornerShape(6.dp))
                                    .background(c, RoundedCornerShape(6.dp))
                                    .clickable {
                                        when (colorTarget) {
                                            -2 -> lineColor = c
                                            -3 -> settings = settings.copy(trendLineColor = c)
                                            else -> settings = settings.copy(levels = settings.levels.toMutableList().also {
                                                it[colorTarget] = it[colorTarget].copy(color = c)
                                            })
                                        }
                                        colorTarget = -1
                                    }.testTag("fib_color_${c.value}"))
                            }
                        }
                        Spacer(Modifier.height(10.dp))
                    }
                }
            }, confirmButton = { TextButton(onClick = { colorTarget = -1 }) { Text("إغلاق") } })
    }
}

private fun fibNumber(value: Double): String = String.format(Locale.US, "%.6f", value)
    .trimEnd('0').trimEnd('.')

@Composable
private fun FibChecked(checked: Boolean, onChange: (Boolean) -> Unit, tag: String) {
    Checkbox(checked = checked, onCheckedChange = onChange,
        colors = CheckboxDefaults.colors(checkedColor = Color(0xFF242424),
            uncheckedColor = Color(0xFF242424), checkmarkColor = Color.White),
        modifier = Modifier.size(42.dp).testTag(tag))
}

@Composable
private fun FibonacciStyleTab(
    settings: FibonacciSettings,
    levelsRaw: List<String>,
    lineColor: Color,
    lineStyle: DrawingLineStyle,
    lineWidth: Float,
    onSettings: (FibonacciSettings) -> Unit,
    onRawLevel: (Int, String) -> Unit,
    onColor: (Int) -> Unit,
    onLineWidth: (Float) -> Unit
) {
    var extensionExpanded by remember { mutableStateOf(false) }
    val compact = LocalConfiguration.current.screenWidthDp < 380
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
        .padding(top = 10.dp, bottom = 14.dp).testTag("fib_style_content")) {
        FibSettingsRow("خط الاتجاه", settings.trendLine,
            { onSettings(settings.copy(trendLine = it)) }, "fib_trend_line") {
            Spacer(Modifier.width(if (compact) 40.dp else 90.dp))
            FibLinePreview(settings.trendLineColor ?: lineColor,
                settings.trendLineStyle ?: lineStyle, lineWidth, { onColor(-3) },
                { onSettings(settings.copy(trendLineStyle = it)) }, onLineWidth)
        }
        FibSettingsRow("خط المستويات", true, {}, "fib_level_line", withCheck = false) {
            Spacer(Modifier.width(if (compact) 25.dp else 45.dp))
            FibLevelLinePreview(settings.levelLineStyle ?: lineStyle,
                settings.levelLineWidth ?: lineWidth,
                { onSettings(settings.copy(levelLineStyle = it)) },
                { onSettings(settings.copy(levelLineWidth = it)) })
        }
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Box {
                OutlinedButton(onClick = { extensionExpanded = true },
                    modifier = Modifier.width(165.dp).height(42.dp).testTag("fib_extension"),
                    shape = RoundedCornerShape(7.dp), contentPadding = PaddingValues(horizontal = 6.dp)) {
                    Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null,
                        tint = Color(0xFF666666), modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(when (settings.extension) {
                        FibExtension.NONE -> "لا تقم بالتمديد"; FibExtension.LEFT -> "لليسار"
                        FibExtension.RIGHT -> "لليمين"; FibExtension.BOTH -> "في الاتجاهين"
                    }, color = fibInk, fontSize = 13.sp)
                }
                DropdownMenu(expanded = extensionExpanded, onDismissRequest = { extensionExpanded = false }) {
                    FibExtension.entries.forEach { option -> DropdownMenuItem(text = { Text(when(option) {
                        FibExtension.NONE -> "لا تقم بالتمديد"; FibExtension.LEFT -> "لليسار"
                        FibExtension.RIGHT -> "لليمين"; FibExtension.BOTH -> "في الاتجاهين"
                    }) }, onClick = { onSettings(settings.copy(extension = option)); extensionExpanded = false }) }
                }
            }
            Text("تمديد", fontSize = 14.sp, color = fibInk)
        }
        settings.levels.forEachIndexed { index, level ->
            Row(Modifier.fillMaxWidth().height(45.dp).padding(start = 18.dp, end = 15.dp),
                horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(34.dp).background(level.color, RoundedCornerShape(6.dp))
                    .border(1.dp, fibBorder, RoundedCornerShape(6.dp))
                    .clickable { onColor(index) }.testTag("fib_level_color_$index"))
                Spacer(Modifier.width(9.dp))
                FibNumberField(levelsRaw.getOrElse(index) { fibNumber(level.value) },
                    { onRawLevel(index, it) }, Modifier.width(105.dp)
                        .testTag("fib_level_value_$index"), enabled = level.enabled)
                Spacer(Modifier.width(6.dp))
                FibChecked(level.enabled, { enabled ->
                    onSettings(settings.copy(levels = settings.levels.toMutableList().also {
                        it[index] = it[index].copy(enabled = enabled)
                    }))
                }, "fib_level_enabled_$index")
            }
            Spacer(Modifier.height(4.dp))
        }
        FibSettingsRow("استخدم لون واحد", settings.singleColor,
            { onSettings(settings.copy(singleColor = it)) }, "fib_single_color", withCheck = false) {
            Box(Modifier.size(36.dp).border(1.dp, fibBorder, RoundedCornerShape(8.dp))
                .clickable { onColor(-2) }.padding(5.dp).clip(RoundedCornerShape(4.dp))) {
                Canvas(Modifier.fillMaxSize()) {
                    drawRect(if (settings.singleColor) lineColor else Color(0xFF1DA18E))
                    if (!settings.singleColor) drawPath(Path().apply {
                        moveTo(size.width, 0f)
                        lineTo(size.width, size.height)
                        lineTo(0f, size.height)
                        close()
                    }, Color(0xFFF44866))
                }
            }
        }
        FibSettingsRow("الخلفية", settings.background,
            { onSettings(settings.copy(background = it)) }, "fib_background") {
            Slider(value = settings.backgroundOpacity, onValueChange = {
                onSettings(settings.copy(backgroundOpacity = it))
            }, colors = SliderDefaults.colors(
                activeTrackColor = Color(0xFF8CA8F8),
                inactiveTrackColor = Color(0xFF8CA8F8)),
                thumb = {
                    Box(Modifier.size(17.dp)
                        .background(Color.White, CircleShape)
                        .border(2.dp, Color(0xFF7B7B7B), CircleShape))
                }, modifier = Modifier.width(155.dp).testTag("fib_background_opacity"))
        }
        FibSettingsRow("انعكاس", settings.reverse, { onSettings(settings.copy(reverse = it)) }, "fib_reverse")
        FibSettingsRow("أسعار", settings.showPrices, { onSettings(settings.copy(showPrices = it)) }, "fib_prices")
        FibSettingsRow("مستويات", settings.showLevels, { onSettings(settings.copy(showLevels = it)) }, "fib_levels") {
            Spacer(Modifier.width(if (compact) 30.dp else 60.dp))
            FibChoice(settings.labelsAsPercents, listOf(false, true),
                { if (it) "النسب %" else "القيم" },
                { onSettings(settings.copy(labelsAsPercents = it)) }, "fib_level_label_format")
        }
        FibSettingsRow("عناوين", true, {}, "fib_titles", withCheck = false) {
            Spacer(Modifier.width(if (compact) 30.dp else 60.dp))
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                FibChoice(settings.labelPosition, FibLabelPosition.entries,
                    { when (it) {
                        FibLabelPosition.LEFT -> "يسار"; FibLabelPosition.CENTER -> "وسط"
                        FibLabelPosition.RIGHT -> "يمين"
                    } }, { onSettings(settings.copy(labelPosition = it)) }, "fib_title_position")
                FibChoice(settings.labelVerticalPosition, FibVerticalPosition.entries,
                    { fibVerticalLabel(it) },
                    { onSettings(settings.copy(labelVerticalPosition = it)) }, "fib_title_vertical")
            }
        }
        FibSettingsRow("النص", settings.showText, { onSettings(settings.copy(showText = it)) }, "fib_text") {
            Spacer(Modifier.width(if (compact) 30.dp else 60.dp))
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                FibChoice(settings.textAlignment, FibTextAlignment.entries,
                    { when (it) {
                        FibTextAlignment.LEFT -> "يسار"; FibTextAlignment.CENTER -> "مركز"
                        FibTextAlignment.RIGHT -> "يمين"
                    } }, { onSettings(settings.copy(textAlignment = it)) }, "fib_text_alignment")
                FibChoice(settings.textVerticalPosition, FibVerticalPosition.entries,
                    { fibVerticalLabel(it) },
                    { onSettings(settings.copy(textVerticalPosition = it)) }, "fib_text_vertical")
            }
        }
        FibSettingsRow("حجم الخط", true, {}, "fib_text_size", withCheck = false) {
            Spacer(Modifier.width(if (compact) 30.dp else 60.dp))
            FibChoice(settings.textSize, listOf(10, 12, 14, 16, 18, 20, 24),
                { it.toString() }, { onSettings(settings.copy(textSize = it)) }, "fib_font_size")
        }
        FibSettingsRow("مستويات فيبوناتشي استناداً على المقياس اللوغاريتمي", settings.logarithmic,
            { onSettings(settings.copy(logarithmic = it)) }, "fib_log_scale")
    }
}

private fun fibVerticalLabel(position: FibVerticalPosition): String = when (position) {
    FibVerticalPosition.TOP -> "أعلى"
    FibVerticalPosition.CENTER -> "وسط"
    FibVerticalPosition.BOTTOM -> "أسفل"
}

@Composable
private fun <T : Any> FibChoice(
    selected: T,
    options: List<T>,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    tag: String
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { expanded = true },
            modifier = Modifier.width(108.dp).height(39.dp).testTag(tag),
            shape = RoundedCornerShape(8.dp),
            border = androidx.compose.foundation.BorderStroke(1.dp, fibBorder),
            contentPadding = PaddingValues(horizontal = 7.dp)) {
            Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null,
                modifier = Modifier.size(17.dp), tint = Color(0xFF777777))
            Spacer(Modifier.weight(1f))
            Text(label(selected), color = fibInk, fontSize = 14.sp, maxLines = 1)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(label(option)) }, onClick = {
                    onSelect(option); expanded = false
                })
            }
        }
    }
}

@Composable
private fun FibLinePreview(color: Color, style: DrawingLineStyle, width: Float,
                           onColor: () -> Unit, onStyle: (DrawingLineStyle) -> Unit,
                           onWidth: (Float) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box {
            OutlinedButton(onClick = { expanded = true }, shape = RoundedCornerShape(7.dp),
                border = androidx.compose.foundation.BorderStroke(1.dp, fibBorder),
                modifier = Modifier.height(35.dp).width(78.dp).testTag("fib_trend_line_style"),
                contentPadding = PaddingValues(horizontal = 8.dp)) {
                Text(when (style) {
                    DrawingLineStyle.SOLID -> "━━━━"; DrawingLineStyle.DASHED -> "━ ━ ━"
                    DrawingLineStyle.DOTTED -> "••••••"
                }, color = fibInk, fontSize = 12.sp)
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DrawingLineStyle.entries.forEach { option ->
                    DropdownMenuItem(text = { Text(when (option) {
                        DrawingLineStyle.SOLID -> "خط متصل"; DrawingLineStyle.DASHED -> "خط متقطع"
                        DrawingLineStyle.DOTTED -> "خط منقط"
                    }) }, onClick = { onStyle(option); expanded = false })
                }
                HorizontalDivider()
                listOf(1f, 2f, 3f, 4f, 5f).forEach { size ->
                    DropdownMenuItem(text = { Text("سُمك ${size.toInt()} px") }, onClick = {
                        onWidth(size); expanded = false
                    })
                }
            }
        }
        Spacer(Modifier.width(7.dp))
        Box(Modifier.size(32.dp).background(color, RoundedCornerShape(4.dp))
            .border(1.dp, fibBorder, RoundedCornerShape(4.dp)).clickable(onClick = onColor)
            .testTag("fib_trend_line_color"))
    }
}

/** TradingView-style independent width and stroke controls for the Fibonacci levels. */
@Composable
private fun FibLevelLinePreview(style: DrawingLineStyle, width: Float,
                                onStyle: (DrawingLineStyle) -> Unit,
                                onWidth: (Float) -> Unit) {
    var widthExpanded by remember { mutableStateOf(false) }
    var styleExpanded by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        Box {
            OutlinedButton(onClick = { widthExpanded = true },
                modifier = Modifier.width(35.dp).height(35.dp).testTag("fib_level_line_width"),
                shape = RoundedCornerShape(7.dp),
                border = androidx.compose.foundation.BorderStroke(1.dp, fibBorder),
                contentPadding = PaddingValues(0.dp)) {
                Text(if (width <= 2f) "−" else "${width.toInt()}",
                    color = fibInk, fontSize = 17.sp)
            }
            DropdownMenu(expanded = widthExpanded, onDismissRequest = { widthExpanded = false }) {
                listOf(1f, 1.5f, 2f, 3f, 4f, 5f).forEach { value ->
                    DropdownMenuItem(text = { Text("${value}px") }, onClick = {
                        onWidth(value); widthExpanded = false
                    })
                }
            }
        }
        Box {
            OutlinedButton(onClick = { styleExpanded = true },
                modifier = Modifier.width(88.dp).height(35.dp).testTag("fib_level_line_style"),
                shape = RoundedCornerShape(7.dp),
                border = androidx.compose.foundation.BorderStroke(1.dp, fibBorder),
                contentPadding = PaddingValues(horizontal = 8.dp)) {
                Text(when (style) {
                    DrawingLineStyle.SOLID -> "━━━━"
                    DrawingLineStyle.DASHED -> "━ ━ ━"
                    DrawingLineStyle.DOTTED -> "••••••"
                }, fontSize = 14.sp, color = fibInk)
            }
            DropdownMenu(expanded = styleExpanded, onDismissRequest = { styleExpanded = false }) {
                DrawingLineStyle.entries.forEach { value ->
                    DropdownMenuItem(text = { Text(when (value) {
                        DrawingLineStyle.SOLID -> "خط متصل"
                        DrawingLineStyle.DASHED -> "خط متقطع"
                        DrawingLineStyle.DOTTED -> "خط منقط"
                    }) }, onClick = { onStyle(value); styleExpanded = false })
                }
            }
        }
    }
}

@Composable
private fun FibSettingsRow(label: String, checked: Boolean, onChecked: (Boolean) -> Unit,
                           tag: String, withCheck: Boolean = true,
                           leftContent: @Composable () -> Unit = {}) {
    val appearanceRows = setOf("fib_single_color", "fib_background", "fib_reverse", "fib_prices",
        "fib_levels", "fib_titles", "fib_text", "fib_text_size", "fib_log_scale")
    val stacked = tag == "fib_titles" || tag == "fib_text"
    val rowModifier = Modifier.fillMaxWidth().heightIn(min = if (tag in appearanceRows) 60.dp else 46.dp)
        .then(if (tag == "fib_single_color") Modifier.clickable { onChecked(!checked) }
            else Modifier)
        .padding(horizontal = 16.dp)
    Row(rowModifier,
        verticalAlignment = if (stacked) Alignment.Top else Alignment.CenterVertically) {
        leftContent()
        Spacer(Modifier.weight(1f))
        Text(label, textAlign = TextAlign.Right, fontSize = 14.sp, color = fibInk,
            modifier = if (stacked) Modifier.padding(top = 9.dp) else Modifier)
        Spacer(Modifier.width(5.dp))
        if (withCheck) FibChecked(checked, onChecked, tag)
        else Spacer(Modifier.width(42.dp))
    }
}

@Composable
private fun FibonacciCoordinatesTab(
    p1: String, p2: String, bar1: String, bar2: String, hasCandles: Boolean,
    onFirstPrice: (String) -> Unit, onSecondPrice: (String) -> Unit,
    onFirstBar: (String) -> Unit, onSecondBar: (String) -> Unit
) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
        .padding(start = 20.dp, end = 18.dp, top = 24.dp).testTag("fib_coordinates_content")) {
        listOf(Triple("#1' (سعر، عمود)", p1, bar1), Triple("#2' (سعر، عمود)", p2, bar2))
            .forEachIndexed { index, row ->
                Row(Modifier.fillMaxWidth().height(51.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween) {
                    FibNumberField(row.third, if (index == 0) onFirstBar else onSecondBar,
                        Modifier.weight(0.95f).testTag("fib_bar_$index"), enabled = hasCandles)
                    Spacer(Modifier.width(9.dp))
                    FibNumberField(row.second, if (index == 0) onFirstPrice else onSecondPrice,
                        Modifier.weight(0.95f).testTag("fib_price_$index"))
                    Spacer(Modifier.width(17.dp))
                    Text(row.first, fontSize = 16.sp, color = fibInk, textAlign = TextAlign.Right,
                        modifier = Modifier.weight(1f))
                }
                Spacer(Modifier.height(5.dp))
            }
        if (!hasCandles) Text("تعديل رقم العمود يتطلب تحميل شموع الشارت أولاً.",
            color = Color(0xFF999999), fontSize = 12.sp, textAlign = TextAlign.Right,
            modifier = Modifier.fillMaxWidth())
    }
}

@Composable
private fun FibNumberField(value: String, onChange: (String) -> Unit, modifier: Modifier,
                           enabled: Boolean = true) {
    BasicTextField(value = value, onValueChange = onChange,
        modifier = modifier.height(38.dp)
            .background(if (enabled) Color.White else Color(0xFFF2F2F2), RoundedCornerShape(9.dp))
            .border(1.dp, fibBorder, RoundedCornerShape(9.dp))
            .padding(horizontal = 9.dp, vertical = 8.dp),
        singleLine = true, enabled = enabled, textStyle = TextStyle(fontSize = 15.sp,
            textAlign = TextAlign.End, textDirection = TextDirection.Ltr,
            color = if (enabled) fibInk else Color(0xFFAAAAAA)),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
}

@Composable
private fun FibonacciVisibilityTab(settings: FibonacciSettings,
                                   inputs: Map<FibTimeUnit, Pair<String, String>>,
                                   onSettings: (FibonacciSettings) -> Unit,
                                   onRawInput: (FibTimeUnit, Boolean, String) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
        .padding(top = 11.dp, bottom = 14.dp).testTag("fib_visibility_content")) {
        settings.timeRules.forEach { rule ->
            Row(Modifier.fillMaxWidth().height(if (rule.unit == FibTimeUnit.TICKS || rule.unit == FibTimeUnit.RANGES) 52.dp else 109.dp)
                .padding(horizontal = 18.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                if (rule.unit != FibTimeUnit.TICKS && rule.unit != FibTimeUnit.RANGES) {
                    Text("−", fontSize = 20.sp, color = fibInk)
                    Spacer(Modifier.width(9.dp))
                    Column(Modifier.width(106.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        FibNumberField(inputs[rule.unit]?.first ?: rule.from.toString(),
                            { onRawInput(rule.unit, true, it) },
                            Modifier.fillMaxWidth().testTag("fib_from_${rule.unit.name}"))
                        FibNumberField(inputs[rule.unit]?.second ?: rule.to.toString(),
                            { onRawInput(rule.unit, false, it) },
                            Modifier.fillMaxWidth().testTag("fib_to_${rule.unit.name}"))
                    }
                }
                Spacer(Modifier.weight(1f))
                Text(rule.unit.label, fontSize = 15.sp, color = fibInk)
                Spacer(Modifier.width(7.dp))
                FibChecked(rule.enabled, { enabled -> onSettings(settings.updateRule(rule.copy(enabled = enabled))) },
                    "fib_visible_${rule.unit.name}")
            }
            if (rule.unit != FibTimeUnit.TICKS && rule.unit != FibTimeUnit.RANGES) Spacer(Modifier.height(6.dp))
        }
    }
}

private fun FibonacciSettings.updateRule(next: FibTimeRule): FibonacciSettings =
    copy(timeRules = timeRules.map { if (it.unit == next.unit) next else it })
