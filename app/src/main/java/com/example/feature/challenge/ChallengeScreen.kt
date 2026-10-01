package com.example.feature.challenge

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import com.example.core.challenge.FtmoChallengeEvaluator
import com.example.core.model.ChallengeConfig
import com.example.core.model.ChallengeStatus
import com.example.feature.account.AccountViewModel
import com.example.ui.components.StatTile
import com.example.ui.theme.*
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChallengeScreen(
    viewModel: AccountViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val account = uiState.selectedAccount
    val status = uiState.challengeStatus

    Scaffold(
        modifier = modifier.testTag("challenge_screen"),
        topBar = {
            TopAppBar(
                title = { Text("قواعد التحدي ومؤشر الانضباط", fontSize = 17.sp, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = TradingBackground)
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            contentPadding = PaddingValues(bottom = 24.dp)
        ) {
            // Discipline Score Hero Card
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Column(
                        modifier = Modifier.padding(20.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Default.MilitaryTech, contentDescription = null, tint = TradingGold, modifier = Modifier.size(48.dp))
                        Spacer(modifier = Modifier.height(6.dp))
                        Text(text = "مؤشر الانضباط التداولي", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.height(4.dp))
                        val score = status?.disciplineScore ?: 100
                        Text(
                            text = "$score / 100",
                            fontSize = 32.sp,
                            fontWeight = FontWeight.ExtraBold,
                            color = if (score >= 80) TradingPositive else if (score >= 50) TradingGold else TradingNegative
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        val progress = score / 100f
                        LinearProgressIndicator(
                            progress = { progress },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(8.dp)
                                .clip(RoundedCornerShape(4.dp)),
                            color = if (score >= 80) TradingPositive else if (score >= 50) TradingGold else TradingNegative,
                            trackColor = TradingElevated
                        )
                    }
                }
            }

            // Challenge Rules Evaluation Grid
            item {
                Text(text = "مراقبة حدود الحساب (Challenge Limits)", style = MaterialTheme.typography.titleSmall, color = TradingTextSecondary)
            }

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    val remDaily = status?.remainingDailyLoss ?: 0.0
                    StatTile(
                        label = "المتبقي من الخسارة اليومية",
                        value = String.format(Locale.US, "$%.2f", remDaily),
                        isPositive = remDaily > 0,
                        modifier = Modifier.weight(1f)
                    )
                    val remMax = status?.remainingMaxLoss ?: 0.0
                    StatTile(
                        label = "المتبقي من أقصى تراجع كلي",
                        value = String.format(Locale.US, "$%.2f", remMax),
                        isPositive = remMax > 0,
                        modifier = Modifier.weight(1f)
                    )
                }
            }

            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    val targetProg = status?.profitTargetProgressPct ?: 0.0
                    StatTile(
                        label = "التقدم نحو الهدف الربحي",
                        value = String.format(Locale.US, "%.1f%%", targetProg),
                        isPositive = targetProg >= 50.0,
                        modifier = Modifier.weight(1f)
                    )
                    StatTile(
                        label = "أيام التداول المسجلة",
                        value = "${status?.tradingDaysCount ?: 0} يوم",
                        modifier = Modifier.weight(1f)
                    )
                }
            }

            // Violations or Good Standing
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Column(modifier = Modifier.padding(14.dp)) {
                        Text(text = "سجل مخالفات القواعد", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        Spacer(modifier = Modifier.height(8.dp))
                        if (status?.ruleViolations.isNullOrEmpty()) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.CheckCircle, contentDescription = null, tint = TradingPositive, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = "الحساب ملتزم تماماً بجميع قواعد إدارة المخاطر، لا توجد مخالفات مسجلة.",
                                    fontSize = 12.sp,
                                    color = TradingTextSecondary
                                )
                            }
                        } else {
                            status?.ruleViolations?.forEach { v ->
                                Row(
                                    modifier = Modifier.padding(vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(Icons.Default.Warning, contentDescription = null, tint = TradingNegative, modifier = Modifier.size(16.dp))
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text(text = v, fontSize = 12.sp, color = TradingNegative)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
