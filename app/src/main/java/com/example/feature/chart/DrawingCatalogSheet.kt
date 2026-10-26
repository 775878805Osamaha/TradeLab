package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
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
    DrawingGroup("نماذج", listOf(DrawingTool.XABCD, DrawingTool.CYPHER, DrawingTool.HEAD_SHOULDERS, DrawingTool.ABCD, DrawingTool.TRIANGLE_PATTERN, DrawingTool.THREE_DRIVES, DrawingTool.ELLIOTT_IMPULSE, DrawingTool.ELLIOTT_CORRECTION, DrawingTool.ELLIOTT_TRIANGLE, DrawingTool.ELLIOTT_DOUBLE, DrawingTool.ELLIOTT_TRIPLE, DrawingTool.CYCLES)),
    DrawingGroup("التنبؤ والقياس", listOf(DrawingTool.LONG_POSITION, DrawingTool.SHORT_POSITION, DrawingTool.FORECAST, DrawingTool.BARS_PATTERN, DrawingTool.GHOST_FEED, DrawingTool.PROJECTION, DrawingTool.ANCHORED_VWAP, DrawingTool.VOLUME_PROFILE_FIXED, DrawingTool.VOLUME_PROFILE_SESSION, DrawingTool.PRICE_RANGE, DrawingTool.DATE_RANGE, DrawingTool.DATE_PRICE_RANGE, DrawingTool.MEASUREMENT)),
    DrawingGroup("الأشكال الهندسية", listOf(DrawingTool.BRUSH, DrawingTool.HIGHLIGHTER, DrawingTool.ARROW_MARKER, DrawingTool.ARROW, DrawingTool.ARROW_UP, DrawingTool.ARROW_DOWN, DrawingTool.RECTANGLE, DrawingTool.ROTATED_RECTANGLE, DrawingTool.PATH, DrawingTool.CIRCLE, DrawingTool.ELLIPSE, DrawingTool.POLYLINE, DrawingTool.TRIANGLE, DrawingTool.ARC, DrawingTool.CURVE, DrawingTool.DOUBLE_CURVE)),
    DrawingGroup("ملاحظة", listOf(DrawingTool.TEXT, DrawingTool.ANCHORED_TEXT, DrawingTool.NOTE, DrawingTool.PRICE_LABEL, DrawingTool.PIN, DrawingTool.TABLE, DrawingTool.CALLOUT, DrawingTool.ANNOTATION, DrawingTool.PRICE_NOTE, DrawingTool.SIGNPOST, DrawingTool.FLAG, DrawingTool.IMAGE))
)

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun DrawingCatalogSheet(
    active: DrawingTool,
    favorites: Set<String>, showFavorites: Boolean,
    onFavorite: (DrawingTool) -> Unit, onShowFavorites: (Boolean) -> Unit,
    canUndo: Boolean, onUndo: () -> Unit, onClear: () -> Unit,
    onSelect: (DrawingTool) -> Unit, onIndicators: () -> Unit, onDismiss: () -> Unit
) {
    val keyboard=androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    var query by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf("المفضلة") }
    var confirmClear by remember { mutableStateOf(false) }
    val categories = listOf("المفضلة", "أدوات") + drawingGroups.map { it.title } + "المرئيات"
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var heightFraction by rememberSaveable { mutableFloatStateOf(.667f) }
    val density=androidx.compose.ui.platform.LocalDensity.current
    val screenHeightDp=androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp
    val windowHeight=with(density) { screenHeightDp.dp.toPx() }
    var dragBelowMinimum by remember { mutableFloatStateOf(0f) }
    fun settleHeight() {
        if(dragBelowMinimum > with(density){140.dp.toPx()}) onDismiss()
        else heightFraction=listOf(.667f,.875f,.96f).minBy { kotlin.math.abs(it-heightFraction) }
    }
    val ink = Color(0xFF171717)
    val muted = Color(0xFF808080)
    val tile = Color(0xFFF2F2F2)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState,
        containerColor = Color.White, contentColor = ink,
        shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp),
        dragHandle = {
            Box(Modifier.fillMaxWidth().testTag("drawing_sheet_handle").pointerInput(windowHeight) {
                detectVerticalDragGestures(onDragStart={dragBelowMinimum=0f},onDragEnd={settleHeight()},onDragCancel={settleHeight()}) { change,dy ->
                    change.consume()
                    if(heightFraction<=.668f && dy>0)dragBelowMinimum+=dy
                    heightFraction=(heightFraction-dy/windowHeight).coerceIn(.667f,.96f)
                }
            }.padding(top=18.dp,bottom=8.dp),contentAlignment=Alignment.Center) {
                Box(Modifier.size(36.dp,4.dp).background(Color(0xFFE7E7E7),RoundedCornerShape(3.dp)))
            }
        }) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(heightFraction).testTag("drawing_catalog_sheet")) {
            Text("رسومات", fontWeight = FontWeight.Bold, fontSize = 24.sp, lineHeight = 24.sp,
                modifier = Modifier.align(Alignment.Start).padding(horizontal = 18.dp).padding(top=24.dp,bottom=13.dp))
            androidx.compose.foundation.text.BasicTextField(
                value=query,onValueChange={query=it},singleLine=true,
                textStyle=androidx.compose.ui.text.TextStyle(color=ink,fontSize=16.sp),
                modifier=Modifier.fillMaxWidth().padding(horizontal=18.dp).testTag("drawing_catalog_search"),
                decorationBox={ field -> Row(Modifier.fillMaxWidth().height(48.dp).background(tile,RoundedCornerShape(14.dp)).padding(horizontal=14.dp),verticalAlignment=Alignment.CenterVertically) {
                    Icon(Icons.Default.Search,"بحث",tint=ink,modifier=Modifier.size(26.dp));Spacer(Modifier.width(10.dp))
                    Box(Modifier.weight(1f)) { if(query.isBlank())Text("بحث",color=muted,fontSize=17.sp,fontWeight=FontWeight.Bold);field() }
                    if(query.isNotEmpty())IconButton(onClick={query=""},modifier=Modifier.size(28.dp)){Icon(Icons.Default.Close,"مسح البحث",tint=ink)}
                } }
            )
            Row(Modifier.fillMaxWidth().testTag("drawing_catalog_categories").padding(vertical = 14.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                categories.forEach { name ->
                    Text(name, color = if (category == name) ink else muted, fontSize = 17.sp, lineHeight = 20.sp,
                        fontWeight = if (category == name) FontWeight.Bold else FontWeight.Medium,
                        modifier = Modifier.background(if (category == name) tile else Color.Transparent, RoundedCornerShape(10.dp))
                            .clickable { category = name }.padding(horizontal = 14.dp, vertical = 8.dp).testTag("drawing_category_$name"))
                }
            }
            val groups = if(category=="المرئيات" && query.isBlank()) listOf(DrawingGroup("المرئيات",listOf(DrawingTool.IMAGE,DrawingTool.SIGNPOST,DrawingTool.FLAG,DrawingTool.ARROW_UP,DrawingTool.ARROW_DOWN))) else drawingGroups
            val matching = groups.map { group -> group.copy(tools = group.tools.filter { tool ->
                val search = query.isBlank() || tool.displayNameAr.contains(query, true) || tool.name.contains(query, true)
                search && (query.isNotBlank() || when(category) { "المفضلة" -> tool.name in favorites; "أدوات" -> true; else -> group.title == category })
            }.let { tools ->
                if(category=="المفضلة" && group.title=="التنبؤ والقياس") tools.sortedBy { when(it) { DrawingTool.SHORT_POSITION->0;DrawingTool.LONG_POSITION->1;else->2 } } else tools
            }) }.filter { it.tools.isNotEmpty() }
            LazyColumn(Modifier.weight(1f).fillMaxWidth().testTag("drawing_catalog_grid"),
                contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                if (category == "أدوات" && query.isBlank()) item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        TextButton(onClick = onUndo, enabled = canUndo) { Icon(Icons.Default.Undo, null); Text("تراجع") }
                        TextButton(onClick = { confirmClear = true }, enabled = canUndo) { Icon(Icons.Default.DeleteOutline, null); Text("مسح") }
                        TextButton(onClick = onIndicators) { Icon(Icons.Default.ShowChart, null); Text("المؤشرات") }
                    }
                }
                matching.forEach { group ->
                    if(category in listOf("المفضلة","أدوات") || query.isNotBlank()) item(key = group.title) {
                        Text(group.title,color=muted,fontSize=14.sp,lineHeight=20.sp,fontWeight=FontWeight.SemiBold,modifier=Modifier.padding(vertical=5.dp))
                    }
                    group.tools.chunked(3).forEach { row -> item(key = row.first().name) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                            row.forEach { tool ->
                                Box(Modifier.weight(1f).height(82.dp).background(if (active == tool) Color(0xFFE7EEFF) else tile, RoundedCornerShape(14.dp))
                                    .combinedClickable(onClick={keyboard?.hide();onSelect(tool)},onLongClick={onFavorite(tool)},onLongClickLabel="تبديل المفضلة").testTag("drawing_tool_${tool.name}")) {
                                    Column(Modifier.fillMaxSize().padding(horizontal = 3.dp, vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.SpaceBetween) {
                                        DrawingToolGlyph(tool, ink, Modifier.size(40.dp))
                                        Text(tool.catalogLabel(), color = ink, fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                    IconButton(onClick = { onFavorite(tool) }, modifier = Modifier.align(Alignment.TopEnd).size(28.dp).testTag("drawing_favorite_${tool.name}")) {
                                        Icon(if (tool.name in favorites) Icons.Default.Star else Icons.Default.StarBorder,
                                            if (tool.name in favorites) "إزالة من المفضلة" else "إضافة للمفضلة", tint = if (tool.name in favorites) Color(0xFFF59B00) else Color.Transparent, modifier = Modifier.size(19.dp))
                                    }
                                }
                            }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    } }
                }
                if (matching.isEmpty()) item { Text(if (query.isBlank()) "أضف أدوات للمفضلة باستخدام النجمة" else "لا توجد أدوات مطابقة", color = muted, modifier = Modifier.padding(18.dp)) }
            }
            if(category == "المفضلة") {
            HorizontalDivider(color = Color(0xFFEEEEEE))
            Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                Box(Modifier.size(28.dp)) { Icon(Icons.Default.Edit,null,tint=ink);Icon(Icons.Default.StarBorder,null,tint=ink,modifier=Modifier.size(12.dp).align(Alignment.BottomEnd)) }
                Text("إظهار المفضلة على الرسم البياني",color=ink,fontSize=17.5.sp,fontWeight=FontWeight.Bold,maxLines=1,overflow=TextOverflow.Ellipsis,modifier=Modifier.weight(1f).padding(horizontal=8.dp))
                Box(Modifier.size(54.dp,28.dp).background(ink,RoundedCornerShape(50)).toggleable(showFavorites,role=Role.Switch,onValueChange=onShowFavorites).testTag("drawing_favorites_switch").padding(3.dp)) {
                    Box(Modifier.size(22.dp).align(if(showFavorites) androidx.compose.ui.AbsoluteAlignment.CenterRight else androidx.compose.ui.AbsoluteAlignment.CenterLeft).background(Color.White,RoundedCornerShape(50)))
                }
            }
            }
        }
    }
    if (confirmClear) AlertDialog(onDismissRequest = { confirmClear = false }, title = { Text("مسح الرسومات؟") },
        text = { Text("ستُمسح رسومات الزوج والإطار الحالي فقط.") }, confirmButton = { TextButton(onClick = { onClear(); confirmClear = false }) { Text("مسح") } },
        dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("إلغاء") } })
}

internal fun DrawingTool.catalogLabel(): String = when(this) {
    DrawingTool.TRENDLINE -> "خط الاتجاه"; DrawingTool.HORIZONTAL_LINE -> "خط أفقي"; DrawingTool.VERTICAL_LINE -> "خط رأسي"
    DrawingTool.RECTANGLE -> "مستطيل"; DrawingTool.ELLIPSE -> "بيضاوي"; DrawingTool.FIBONACCI -> "تصحيح فيبوناتشي"
    DrawingTool.MEASUREMENT -> "أداة القياس"; else -> displayNameAr
}
