package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

internal data class AnalysisHubItem(
    val id: String,
    val label: String,
    val icon: ImageVector? = null,
    val enabled: Boolean = true,
    val chartGlyph: Boolean = false
)

/** RTL order, matching the phone-size Arabic TradingView Analysis Hub reference. */
internal object AnalysisHubCatalog {
    val toolsWide = listOf(
        AnalysisHubItem("indicators", "مؤشرات", Icons.Default.InsertChartOutlined),
        AnalysisHubItem("compare", "قارن", Icons.Default.AddCircleOutline),
        AnalysisHubItem("alerts", "تنبيهات", Icons.Default.Alarm),
        AnalysisHubItem("bar_replay", "إعادة تشغيل الأعمدة", Icons.Default.FastRewind)
    )
    val toolsCompact = listOf(
        AnalysisHubItem("indicator_templates", "قوالب المؤشر", Icons.Default.GridView),
        AnalysisHubItem("chart_type", "نوع الرسم البياني", chartGlyph = true),
        AnalysisHubItem("object_tree", "شجرة الكائنات", Icons.Default.Layers)
    )
    val information = listOf(
        AnalysisHubItem("symbol_info", "معلومات الرمز", Icons.Default.Info),
        AnalysisHubItem("financial_data", "البيانات المالية", Icons.Default.BarChart, enabled = false),
        AnalysisHubItem("forecasts", "التوقعات", Icons.Default.TrendingUp, enabled = false),
        AnalysisHubItem("technical_analysis", "تحليلات فنية", Icons.Default.Speed)
    )
    val more = listOf(
        AnalysisHubItem("publish", "نشر التحليل", Icons.Default.Lightbulb),
        AnalysisHubItem("pine_editor", "Pine Editor", Icons.Default.Code)
    )
}

@Composable
private fun AnalysisHubTile(item: AnalysisHubItem, modifier: Modifier = Modifier, onAction: (String) -> Unit) {
    val viewportWidthDp = LocalConfiguration.current.screenWidthDp
    val color = if (item.enabled) Color(0xFF121212) else Color(0xFFA4A4A4)
    val background = if (item.enabled) Color(0xFFF2F2F2) else Color(0xFFFAFAFA)
    Column(
        modifier = modifier.height((viewportWidthDp * 0.20f).dp)
            .background(background, RoundedCornerShape((viewportWidthDp * 0.035f).dp))
            .clickable(enabled = item.enabled) { onAction(item.id) }
            .testTag("analysis_hub_${item.id}"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        if (item.chartGlyph) ChartTypeGlyph("candles", color)
        else Icon(item.icon ?: Icons.Default.Info, contentDescription = null, tint = color, modifier = Modifier.size(23.dp))
        Spacer(Modifier.height(8.dp))
        Text(
            item.label, color = color, fontSize = if (item.label.length > 17) 13.sp else 15.sp,
            lineHeight = 17.sp, fontWeight = FontWeight.Medium, maxLines = 2,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 3.dp)
        )
    }
}

@Composable
private fun AnalysisHubRow(items: List<AnalysisHubItem>, onAction: (String) -> Unit) {
    val viewportWidthDp = LocalConfiguration.current.screenWidthDp
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Row(Modifier.fillMaxWidth().padding(horizontal = (viewportWidthDp * 0.044f).dp),
            horizontalArrangement = Arrangement.spacedBy((viewportWidthDp * 0.023f).dp)) {
            items.forEach { item -> AnalysisHubTile(item, Modifier.weight(1f), onAction) }
        }
    }
}

@Composable
private fun AnalysisHubSectionTitle(title: String, topPadding: androidx.compose.ui.unit.Dp) {
    Text(
        title, color = Color(0xFF777777), fontSize = 16.sp, fontWeight = FontWeight.Medium,
        textAlign = TextAlign.Right,
        modifier = Modifier.fillMaxWidth().padding(top = topPadding, bottom = 8.dp, end = 28.dp)
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AnalysisHubSheet(onDismiss: () -> Unit, onAction: (String) -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Color.White,
        contentColor = Color(0xFF131313),
        shape = androidx.compose.ui.graphics.RectangleShape,
        dragHandle = {
            Box(
                Modifier.padding(top = 16.dp, bottom = 10.dp)
                    .size(34.dp, 4.dp)
                    .background(Color(0xFFE1E1E1), RoundedCornerShape(5.dp))
                    .testTag("analysis_hub_drag_handle")
            )
        }
    ) {
        Column(
            Modifier.fillMaxWidth().fillMaxHeight(0.965f)
                .background(Color.White)
                .verticalScroll(rememberScrollState())
                .testTag("analysis_hub_sheet")
        ) {
            Text(
                "محور التحليل", color = Color.Black, fontSize = 26.sp,
                fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Right,
                modifier = Modifier.fillMaxWidth().padding(end = 17.dp, top = 22.dp, bottom = 9.dp)
                    .testTag("analysis_hub_title")
            )
            HorizontalDivider(thickness = 1.dp, color = Color(0xFFF0F0F0))
            AnalysisHubSectionTitle("أدوات", 0.dp)
            AnalysisHubRow(AnalysisHubCatalog.toolsWide.take(2), onAction)
            Spacer(Modifier.height(8.dp))
            AnalysisHubRow(AnalysisHubCatalog.toolsWide.drop(2), onAction)
            Spacer(Modifier.height(8.dp))
            AnalysisHubRow(AnalysisHubCatalog.toolsCompact, onAction)
            AnalysisHubSectionTitle("معلومات", 11.dp)
            AnalysisHubRow(AnalysisHubCatalog.information.take(2), onAction)
            Spacer(Modifier.height(8.dp))
            AnalysisHubRow(AnalysisHubCatalog.information.drop(2), onAction)
            AnalysisHubSectionTitle("المزيد", 11.dp)
            AnalysisHubRow(AnalysisHubCatalog.more, onAction)
            Spacer(Modifier.height(25.dp))
            HorizontalDivider(thickness = 1.dp, color = Color(0xFFF0F0F0))
            Spacer(Modifier.height(20.dp))
            Row(
                Modifier.fillMaxWidth().height(48.dp)
                    .clickable { onAction("help") }
                    .testTag("analysis_hub_help"),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("مركز المساعدة", fontSize = 19.sp, fontWeight = FontWeight.SemiBold, color = Color.Black)
                Spacer(Modifier.width(12.dp))
                Icon(Icons.Default.HelpOutline, contentDescription = null, tint = Color.Black, modifier = Modifier.size(23.dp))
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}
