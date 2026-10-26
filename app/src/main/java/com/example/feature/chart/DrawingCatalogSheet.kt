package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.feature.chart.model.DrawingTool

internal data class DrawingGroup(val title: String, val tools: List<DrawingTool>)
internal val drawingGroups = listOf(
    DrawingGroup("خطوط اتجاه", listOf(DrawingTool.INFO_LINE, DrawingTool.HORIZONTAL_LINE, DrawingTool.TRENDLINE, DrawingTool.HORIZONTAL_RAY, DrawingTool.EXTENDED_LINE, DrawingTool.RAY, DrawingTool.VERTICAL_LINE, DrawingTool.PARALLEL_CHANNEL)),
    DrawingGroup("جان وفيبوناتشي", listOf(DrawingTool.FIBONACCI, DrawingTool.FIB_FAN)),
    DrawingGroup("نماذج", listOf(DrawingTool.XABCD, DrawingTool.HEAD_SHOULDERS, DrawingTool.ABCD, DrawingTool.ELLIOTT_IMPULSE, DrawingTool.ELLIOTT_CORRECTION)),
    DrawingGroup("التنبؤ والقياس", listOf(DrawingTool.LONG_POSITION, DrawingTool.SHORT_POSITION, DrawingTool.ANCHORED_VWAP, DrawingTool.PRICE_RANGE, DrawingTool.DATE_RANGE, DrawingTool.DATE_PRICE_RANGE, DrawingTool.MEASUREMENT)),
    DrawingGroup("الأشكال الهندسية", listOf(DrawingTool.BRUSH, DrawingTool.HIGHLIGHTER, DrawingTool.ARROW, DrawingTool.ARROW_UP, DrawingTool.ARROW_DOWN, DrawingTool.PATH, DrawingTool.ROTATED_RECTANGLE, DrawingTool.RECTANGLE, DrawingTool.POLYLINE, DrawingTool.ELLIPSE, DrawingTool.CURVE, DrawingTool.ARC, DrawingTool.TRIANGLE)),
    DrawingGroup("ملاحظة", listOf(DrawingTool.TEXT, DrawingTool.ANCHORED_TEXT, DrawingTool.NOTE, DrawingTool.PRICE_LABEL, DrawingTool.PIN, DrawingTool.CALLOUT, DrawingTool.ANNOTATION, DrawingTool.FLAG))
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DrawingCatalogSheet(
    active: DrawingTool,
    favorites: Set<String>, showFavorites: Boolean,
    onFavorite: (DrawingTool) -> Unit, onShowFavorites: (Boolean) -> Unit,
    canUndo: Boolean, onUndo: () -> Unit, onClear: () -> Unit,
    onSelect: (DrawingTool) -> Unit, onIndicators: () -> Unit, onDismiss: () -> Unit
) {
    var query by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf("المفضلة") }
    var confirmClear by remember { mutableStateOf(false) }
    val categories = listOf("المفضلة", "أدوات") + drawingGroups.map { it.title }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val ink = Color(0xFF171717)
    val muted = Color(0xFF808080)
    val tile = Color(0xFFF2F2F2)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState,
        containerColor = Color.White, contentColor = ink,
        shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp),
        dragHandle = { Box(Modifier.testTag("drawing_sheet_handle").padding(top = 14.dp, bottom = 12.dp).size(36.dp, 4.dp).background(Color(0xFFE7E7E7), RoundedCornerShape(3.dp))) }) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(.93f).testTag("drawing_catalog_sheet")) {
            Text("رسومات", fontWeight = FontWeight.Bold, fontSize = 23.sp,
                modifier = Modifier.align(Alignment.Start).padding(horizontal = 18.dp, vertical = 14.dp))
            TextField(query, { query = it }, singleLine = true,
                placeholder = { Text("بحث", color = muted) },
                leadingIcon = { Icon(Icons.Default.Search, "بحث", tint = ink) },
                trailingIcon = { if (query.isNotEmpty()) IconButton(onClick = { query = "" }) { Icon(Icons.Default.Close, "مسح البحث", tint = ink) } },
                shape = RoundedCornerShape(14.dp),
                colors = TextFieldDefaults.colors(focusedContainerColor = tile, unfocusedContainerColor = tile,
                    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
                    focusedTextColor = ink, unfocusedTextColor = ink, cursorColor = ink),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp).testTag("drawing_catalog_search"))
            Row(Modifier.fillMaxWidth().padding(vertical = 14.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                categories.forEach { name ->
                    Text(name, color = if (category == name) ink else muted, fontSize = 16.sp,
                        fontWeight = if (category == name) FontWeight.Bold else FontWeight.Medium,
                        modifier = Modifier.background(if (category == name) tile else Color.Transparent, RoundedCornerShape(10.dp))
                            .clickable { category = name }.padding(horizontal = 14.dp, vertical = 10.dp).testTag("drawing_category_$name"))
                }
            }
            val matching = drawingGroups.map { group -> group.copy(tools = group.tools.filter { tool ->
                val search = query.isBlank() || tool.displayNameAr.contains(query, true) || tool.name.contains(query, true)
                search && (query.isNotBlank() || when(category) { "المفضلة" -> tool.name in favorites; "أدوات" -> true; else -> group.title == category })
            }) }.filter { it.tools.isNotEmpty() }
            LazyColumn(Modifier.weight(1f).fillMaxWidth().testTag("drawing_catalog_grid"),
                contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                if (category == "أدوات" && query.isBlank()) item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        TextButton(onClick = onUndo, enabled = canUndo) { Icon(Icons.Default.Undo, null); Text("تراجع") }
                        TextButton(onClick = { confirmClear = true }, enabled = canUndo) { Icon(Icons.Default.DeleteOutline, null); Text("مسح") }
                        TextButton(onClick = onIndicators) { Icon(Icons.Default.ShowChart, null); Text("المؤشرات") }
                    }
                }
                matching.forEach { group ->
                    item(key = group.title) { Text(group.title, color = muted, fontSize = 14.sp, modifier = Modifier.padding(top = 9.dp, bottom = 7.dp)) }
                    group.tools.chunked(3).forEach { row -> item(key = row.first().name) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                            row.forEach { tool ->
                                Box(Modifier.weight(1f).height(82.dp).background(if (active == tool) Color(0xFFE7EEFF) else tile, RoundedCornerShape(14.dp))
                                    .clickable { onSelect(tool) }.testTag("drawing_tool_${tool.name}")) {
                                    Column(Modifier.fillMaxSize().padding(horizontal = 3.dp, vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.SpaceBetween) {
                                        DrawingToolGlyph(tool, ink, Modifier.size(32.dp))
                                        Text(tool.catalogLabel(), color = ink, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                    IconButton(onClick = { onFavorite(tool) }, modifier = Modifier.align(Alignment.TopEnd).size(28.dp).testTag("drawing_favorite_${tool.name}")) {
                                        Icon(if (tool.name in favorites) Icons.Default.Star else Icons.Default.StarBorder,
                                            if (tool.name in favorites) "إزالة من المفضلة" else "إضافة للمفضلة", tint = if (tool.name in favorites) Color(0xFFF59B00) else Color(0xFFBBBBBB), modifier = Modifier.size(19.dp))
                                    }
                                }
                            }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    } }
                }
                if (matching.isEmpty()) item { Text(if (query.isBlank()) "أضف أدوات للمفضلة باستخدام النجمة" else "لا توجد أدوات مطابقة", color = muted, modifier = Modifier.padding(18.dp)) }
            }
            HorizontalDivider(color = Color(0xFFEEEEEE))
            Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                Icon(Icons.Default.Edit, null, tint = ink)
                Text("إظهار المفضلة على الرسم البياني", color = ink, fontSize = 14.sp, modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
                Switch(showFavorites, onShowFavorites, modifier = Modifier.testTag("drawing_favorites_switch"), colors = SwitchDefaults.colors(checkedTrackColor = ink, checkedThumbColor = Color.White))
            }
        }
    }
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text("مسح الرسومات؟") },
        text = { Text("ستُمسح رسومات الزوج والإطار الحالي فقط.") }, confirmButton = { TextButton(onClick = { onClear(); confirmClear = false }) { Text("مسح") } },
        dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("إلغاء") } })
}

internal fun DrawingTool.catalogLabel(): String = when(this) {
    DrawingTool.TRENDLINE -> "خط الاتجاه"; DrawingTool.HORIZONTAL_LINE -> "خط أفقي"; DrawingTool.VERTICAL_LINE -> "خط رأسي"
    DrawingTool.RECTANGLE -> "مستطيل"; DrawingTool.ELLIPSE -> "دائرة"; DrawingTool.FIBONACCI -> "تصحيح فيبوناتشي"
    DrawingTool.MEASUREMENT -> "أداة القياس"; else -> displayNameAr
}
