package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ui.components.ChartDisplayStyle

/** Visual order is right-to-left, matching TradingView's Arabic type picker. */
internal data class ChartTypeOption(
    val key: String,
    val title: String,
    val icon: ImageVector,
    val style: ChartDisplayStyle?
)

internal object ChartTypeCatalog {
    val options = listOf(
        ChartTypeOption("bars", "أعمدة", Icons.Default.BarChart, ChartDisplayStyle.BARS),
        ChartTypeOption("candles", "شموع", Icons.Default.CandlestickChart, ChartDisplayStyle.CANDLES),
        ChartTypeOption("hollow", "الشموع المجوفة", Icons.Default.CandlestickChart, ChartDisplayStyle.HOLLOW_CANDLES),
        ChartTypeOption("volume_candles", "شموع الحجم", Icons.Default.CandlestickChart, ChartDisplayStyle.VOLUME_CANDLES),
        ChartTypeOption("line", "خط", Icons.Default.ShowChart, ChartDisplayStyle.LINE),
        ChartTypeOption("line_markers", "خط بعلامات", Icons.Default.Timeline, ChartDisplayStyle.LINE_MARKERS),
        ChartTypeOption("step", "خط متدرج", Icons.Default.Stairs, ChartDisplayStyle.STEP_LINE),
        ChartTypeOption("area", "مساحة", Icons.Default.AreaChart, ChartDisplayStyle.AREA),
        ChartTypeOption("hlc_area", "منطقة HLC", Icons.Default.StackedLineChart, ChartDisplayStyle.HLC_AREA),
        ChartTypeOption("baseline", "خط الأساس", Icons.Default.ShowChart, ChartDisplayStyle.BASELINE),
        ChartTypeOption("columns", "الأعمدة", Icons.Default.BarChart, ChartDisplayStyle.COLUMNS),
        ChartTypeOption("high_low", "أعلى-أدنى", Icons.Default.ViewWeek, ChartDisplayStyle.HIGH_LOW),
        ChartTypeOption("footprint", "بصمة الحجم", Icons.Default.ViewList, null),
        ChartTypeOption("time_price", "فرصة السعر الزمني", Icons.Default.TableChart, null),
        ChartTypeOption("session_volume", "بروفايل أحجام التداول للجلسة", Icons.Default.StackedBarChart, null),
        ChartTypeOption("heikin", "هايكين آشي", Icons.Default.CandlestickChart, ChartDisplayStyle.HEIKIN_ASHI),
        ChartTypeOption("renko", "رينكو", Icons.Default.GridView, null),
        ChartTypeOption("line_break", "كسر الخط", Icons.Default.ViewColumn, null),
        ChartTypeOption("kagi", "كاجي", Icons.Default.ShowChart, null),
        ChartTypeOption("point_figure", "النقطة والرقم", Icons.Default.Grain, null),
        ChartTypeOption("range", "مدى", Icons.Default.MultilineChart, null)
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ChartTypeSheet(
    current: ChartDisplayStyle,
    onSelect: (ChartDisplayStyle) -> Unit,
    onUnavailable: (String) -> Unit,
    onDismiss: () -> Unit
) {
    val background = Color.White
    val tile = Color(0xFFF2F2F2)
    val selected = Color(0xFF303030)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = background,
        contentColor = Color.Black,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
        dragHandle = {
            Box(
                Modifier.padding(top = 16.dp, bottom = 10.dp)
                    .size(34.dp, 4.dp)
                    .background(Color(0xFFE1E1E1), RoundedCornerShape(8.dp))
                    .testTag("chart_type_drag_handle")
            )
        }
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().fillMaxHeight(0.97f)
                .background(background).testTag("chart_type_sheet")
        ) {
            Text(
                text = "نوع الرسم البياني",
                color = Color(0xFF101010), fontSize = 26.sp,
                fontWeight = FontWeight.Bold, textAlign = TextAlign.Right,
                modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 18.dp, top = 20.dp, bottom = 26.dp)
                    .testTag("chart_type_sheet_title")
            )
            androidx.compose.runtime.CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 32.dp),
                    modifier = Modifier.fillMaxWidth().weight(1f).testTag("chart_type_grid")
                ) {
                    items(ChartTypeCatalog.options, key = { it.key }) { option ->
                        val active = option.style == current && option.style != null
                        Column(
                            modifier = Modifier.fillMaxWidth().height(79.dp)
                                .background(if (active) selected else tile, RoundedCornerShape(13.dp))
                                .clickable {
                                    if (option.style != null) onSelect(option.style)
                                    else onUnavailable(option.title)
                                }
                                .testTag("chart_type_${option.key}"),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Icon(
                                option.icon, contentDescription = null,
                                tint = if (active) Color.White else Color(0xFF101010),
                                modifier = Modifier.size(25.dp)
                            )
                            Spacer(Modifier.height(8.dp))
                            Text(
                                option.title, color = if (active) Color.White else Color(0xFF111111),
                                fontSize = if (option.title.length > 23) 12.sp else 14.sp,
                                lineHeight = 16.sp, fontWeight = FontWeight.Medium,
                                textAlign = TextAlign.Center, maxLines = 2,
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 3.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}
