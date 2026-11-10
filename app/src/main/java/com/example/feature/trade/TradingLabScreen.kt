package com.example.feature.trade

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoGraph
import androidx.compose.material.icons.filled.CandlestickChart
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Science
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.ui.theme.TradingAccent
import com.example.ui.theme.TradingBackground
import com.example.ui.theme.TradingCard
import com.example.ui.theme.TradingTextPrimary
import com.example.ui.theme.TradingTextSecondary

/** A visible entry point for the two distinct training modes. */
@Composable
fun TradingLabScreen(
    onOpenSimulator: () -> Unit,
    onOpenStrategies: () -> Unit,
    onOpenBacktest: () -> Unit,
    onOpenDataSettings: () -> Unit,
    sourceStatus: String,
    modifier: Modifier = Modifier
) {
    Scaffold(
        modifier = modifier.testTag("lab_screen"),
        containerColor = TradingBackground,
        topBar = {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(Icons.Default.Science, contentDescription = null, tint = TradingAccent)
                Text("مختبر التداول", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold,
                    color = TradingTextPrimary)
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding)
                .verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text("اختر طريقة التدريب. لا تُنشأ شموع أو صفقات وهمية عندما يفشل مصدر الأسعار.",
                style = MaterialTheme.typography.bodyMedium, color = TradingTextSecondary)

            LabActionCard(
                title = "محاكي التداول اليدوي",
                description = "افتح Replay على نفس الشارت، اختر تاريخًا، ثم نفّذ شراء أو بيع تجريبيًا وشاهد نتائجه.",
                icon = { Icon(Icons.Default.CandlestickChart, contentDescription = null, tint = TradingAccent) },
                button = "فتح محاكي التداول",
                tag = "lab_start_simulator",
                onClick = onOpenSimulator
            )
            LabActionCard(
                title = "اختبار الاستراتيجيات",
                description = "حدّد الاستراتيجية والرمز والفاصل الزمني ورأس المال، ثم شغّل اختبارًا تاريخيًا مع سجل الصفقات والإحصاءات.",
                icon = { Icon(Icons.Default.AutoGraph, contentDescription = null, tint = TradingAccent) },
                button = "بدء إعداد الاختبار",
                tag = "lab_start_backtest",
                onClick = onOpenBacktest
            )
            LabActionCard(
                title = "مكتبة الاستراتيجيات",
                description = "استعرض الاستراتيجيات المتاحة، عدّل معاملاتها، واختر استراتيجية للاختبار.",
                icon = { Icon(Icons.Default.LibraryBooks, contentDescription = null, tint = TradingAccent) },
                button = "تصفح الاستراتيجيات",
                tag = "lab_open_strategies",
                onClick = onOpenStrategies
            )

            HorizontalDivider()
            Text("حالة مصدر البيانات", style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold, color = TradingTextPrimary)
            Text(sourceStatus.ifBlank { "لم يتم التحقق من اتصال cTrader" },
                style = MaterialTheme.typography.bodyMedium, color = TradingTextSecondary,
                modifier = Modifier.testTag("lab_source_status"))
            OutlinedButton(
                onClick = onOpenDataSettings,
                modifier = Modifier.fillMaxWidth().testTag("lab_source_settings")
            ) {
                Icon(Icons.Default.Settings, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("إعدادات cTrader")
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun LabActionCard(
    title: String,
    description: String,
    icon: @Composable () -> Unit,
    button: String,
    tag: String,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = TradingCard)
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                icon()
                Text(title, style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold, color = TradingTextPrimary)
            }
            Text(description, style = MaterialTheme.typography.bodyMedium, color = TradingTextSecondary)
            OutlinedButton(
                onClick = onClick,
                modifier = Modifier.fillMaxWidth().testTag(tag),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 7.dp)
            ) {
                Text(button)
                Spacer(Modifier.width(6.dp))
                Icon(Icons.Default.ChevronLeft, contentDescription = null)
            }
        }
    }
}
