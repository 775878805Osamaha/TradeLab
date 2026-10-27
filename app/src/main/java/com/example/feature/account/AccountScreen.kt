package com.example.feature.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.model.VirtualAccount
import com.example.ui.components.StatTile
import com.example.ui.components.VirtualDisclaimerBanner
import com.example.ui.theme.*
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(
    viewModel: AccountViewModel,
    onNavigateToTrade: () -> Unit,
    onNavigateToReplay: () -> Unit,
    onNavigateToBacktest: () -> Unit,
    onNavigateToHistory: () -> Unit,
    onNavigateToRules: () -> Unit,
    onNavigateToCalendar: () -> Unit,
    onNavigateToSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val account = uiState.selectedAccount

    var showCreateDialog by remember { mutableStateOf(false) }
    var showResetDialog by remember { mutableStateOf(false) }
    var showDeleteConfirmDialog by remember { mutableStateOf<VirtualAccount?>(null) }
    var newAccountName by remember { mutableStateOf("") }
    var newAccountBalance by remember { mutableStateOf("50") }
    var newAccountLeverage by remember { mutableStateOf("100") }
    var resetBalanceOption by remember { mutableStateOf("50") }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(uiState.message) {
        uiState.message?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearMessage()
        }
    }

    Scaffold(
        modifier = modifier.testTag("account_screen"),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "الحساب",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold
                    )
                },
                actions = {
                    TextButton(onClick = viewModel::toggleReportSource) { Text(if(uiState.isReplayReport) "Replay" else "تداول ورقي") }

                    IconButton(
                        onClick = onNavigateToCalendar,
                        modifier = Modifier.testTag("nav_calendar_btn")
                    ) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = "التقويم")
                    }
                    IconButton(
                        onClick = onNavigateToSettings,
                        modifier = Modifier.testTag("nav_settings_btn")
                    ) {
                        Icon(Icons.Default.Settings, contentDescription = "الإعدادات")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = TradingBackground)
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(bottom = 24.dp)
        ) {
            item {
                VirtualDisclaimerBanner()
            }

            // Margin Warning Banner if free margin is critical
            if (uiState.isMarginWarning) {
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth().testTag("margin_warning_banner"),
                        shape = RoundedCornerShape(8.dp),
                        colors = CardDefaults.cardColors(containerColor = Color(0x33EF4444)),
                        border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingNegative))
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Warning, contentDescription = null, tint = TradingNegative)
                            Spacer(modifier = Modifier.width(10.dp))
                            Text(
                                text = "تحذير: مستوى الهامش المتاح منخفض جداً! يُرجى توخي الحذر قبل فتح مراكز إضافية لتفادي توقف الصفقات.",
                                fontSize = 12.sp,
                                color = TradingTextPrimary,
                                lineHeight = 17.sp
                            )
                        }
                    }
                }
            }

            if (account != null) {
                // Section: Main Financial Dashboard Card
                item {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("account_summary_card"),
                        shape = RoundedCornerShape(8.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingCard),
                        border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column {
                                    Text(
                                        text = account.name,
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = TradingTextPrimary
                                    )
                                    Text(
                                        text = "الرافعة: 1:${account.leverage.toInt()} • الرصيد المبدئي: $${account.initialBalance.toInt()}",
                                        fontSize = 12.sp,
                                        color = TradingTextSecondary
                                    )
                                }
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(TradingAccent.copy(alpha = 0.2f))
                                        .padding(horizontal = 8.dp, vertical = 4.dp)
                                ) {
                                    Text(
                                        text = "VIRTUAL DEMO",
                                        color = TradingAccentLight,
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                            }

                            Spacer(modifier = Modifier.height(10.dp))

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Column {
                                    Text(text = "رصيد الحساب (Balance)", fontSize = 12.sp, color = TradingTextSecondary)
                                    Text(
                                        text = String.format(Locale.US, "$%.2f", account.balance),
                                        style = TextStyle(textDirection = TextDirection.Ltr),
                                        maxLines = 1,
                                        fontSize = 21.sp,
                                        fontWeight = FontWeight.ExtraBold,
                                        color = TradingTextPrimary
                                    )
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(text = "حقوق الملكية (Equity)", fontSize = 12.sp, color = TradingTextSecondary)
                                    val isProfit = account.equity >= account.initialBalance
                                    Text(
                                        text = String.format(Locale.US, "$%.2f", account.equity),
                                        style = TextStyle(textDirection = TextDirection.Ltr),
                                        maxLines = 1,
                                        fontSize = 21.sp,
                                        fontWeight = FontWeight.ExtraBold,
                                        color = if (isProfit) TradingPositive else TradingNegative
                                    )
                                }
                            }

                            Spacer(modifier = Modifier.height(14.dp))
                            HorizontalDivider(color = TradingBorder)
                            Spacer(modifier = Modifier.height(12.dp))

                            // Margin Metrics Grid
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Column {
                                    Text(text = "الهامش المستخدم", fontSize = 11.sp, color = TradingTextSecondary)
                                    Text(
                                        text = String.format(Locale.US, "$%.2f", account.margin),
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = TradingTextPrimary
                                    )
                                }
                                Column {
                                    Text(text = "الهامش المتاح", fontSize = 11.sp, color = TradingTextSecondary)
                                    Text(
                                        text = String.format(Locale.US, "$%.2f", account.freeMargin),
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = TradingCyan
                                    )
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(text = "مستوى الهامش", fontSize = 11.sp, color = TradingTextSecondary)
                                    val levelText = if (account.margin > 0) String.format(Locale.US, "%.1f%%", account.marginLevel) else "∞"
                                    Text(
                                        text = levelText,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = if (account.marginLevel < 120.0 && account.margin > 0) TradingNegative else TradingTextPrimary
                                    )
                                }
                            }

                            Spacer(modifier = Modifier.height(14.dp))

                            // Quick Action Buttons (TRADE, REPLAY, BACKTEST, HISTORY)
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Button(
                                    onClick = onNavigateToTrade,
                                    modifier = Modifier.weight(1f).height(40.dp).testTag("dash_action_trade"),
                                    shape = RoundedCornerShape(8.dp),
                                    colors = ButtonDefaults.buttonColors(containerColor = TradingPositive)
                                ) {
                                    Text("تداول", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }
                                Button(
                                    onClick = onNavigateToReplay,
                                    modifier = Modifier.weight(1f).height(40.dp).testTag("dash_action_replay"),
                                    shape = RoundedCornerShape(8.dp),
                                    colors = ButtonDefaults.buttonColors(containerColor = TradingAccent)
                                ) {
                                    Text("Replay", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                }
                                Button(
                                    onClick = onNavigateToBacktest,
                                    modifier = Modifier.weight(1f).height(40.dp).testTag("dash_action_backtest"),
                                    shape = RoundedCornerShape(8.dp),
                                    colors = ButtonDefaults.buttonColors(containerColor = TradingElevated)
                                ) {
                                    Text("اختبار", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TradingCyan)
                                }
                                Button(
                                    onClick = onNavigateToHistory,
                                    modifier = Modifier.weight(1f).height(40.dp).testTag("dash_action_history"),
                                    shape = RoundedCornerShape(8.dp),
                                    colors = ButtonDefaults.buttonColors(containerColor = TradingElevated)
                                ) {
                                    Text("السجل", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TradingTextPrimary)
                                }
                            }
                        }
                    }
                }

                // Section: Performance Snapshot Tiles
                item {
                    Text(
                        text = "مؤشرات الأداء اللحظية (Performance Snapshot)",
                        style = MaterialTheme.typography.titleSmall,
                        color = TradingTextSecondary
                    )
                }

                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        StatTile(
                            label = "أرباح عائمة (Unrealized P/L)",
                            value = String.format(Locale.US, "%s$%.2f", if (uiState.unrealizedProfitLoss >= 0) "+" else "", uiState.unrealizedProfitLoss),
                            isPositive = uiState.unrealizedProfitLoss >= 0,
                            modifier = Modifier.weight(1f)
                        )
                        StatTile(
                            label = "أرباح محققة (Realized P/L)",
                            value = String.format(Locale.US, "%s$%.2f", if (uiState.realizedProfitLoss >= 0) "+" else "", uiState.realizedProfitLoss),
                            isPositive = uiState.realizedProfitLoss >= 0,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        StatTile(
                            label = "المراكز المفتوحة",
                            value = "${uiState.openPositionsCount} صفقات",
                            modifier = Modifier.weight(1f)
                        )
                        StatTile(
                            label = "الأوامر المعلقة",
                            value = "${uiState.pendingOrdersCount} أوامر",
                            modifier = Modifier.weight(1f)
                        )
                        StatTile(
                            label = "معدل الفوز (Win Rate)",
                            value = String.format(Locale.US, "%.1f%%", uiState.winRatePct),
                            isPositive = uiState.winRatePct >= 50.0,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }

                // FTMO Challenge Summary Card
                item {
                    val challenge = uiState.challengeStatus
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onNavigateToRules() }
                            .testTag("discipline_card"),
                        shape = RoundedCornerShape(8.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingCard),
                        border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                    ) {
                        Column(modifier = Modifier.padding(14.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Default.MilitaryTech, contentDescription = null, tint = TradingGold)
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text(
                                        text = "مؤشر الانضباط وقواعد التحدي (FTMO Rules)",
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 13.sp
                                    )
                                }
                                Text(
                                    text = "التفاصيل ›",
                                    color = TradingCyan,
                                    fontSize = 12.sp
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(text = "درجة الانضباط (0-100):", fontSize = 12.sp, color = TradingTextSecondary)
                                Text(
                                    text = "${challenge?.disciplineScore ?: 100} / 100",
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = TradingGold
                                )
                            }
                            Spacer(modifier = Modifier.height(6.dp))
                            val progress = (challenge?.disciplineScore ?: 100) / 100f
                            LinearProgressIndicator(
                                progress = { progress },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(6.dp)
                                    .clip(RoundedCornerShape(3.dp)),
                                color = if (progress >= 0.7f) TradingPositive else TradingGold,
                                trackColor = TradingElevated
                            )
                        }
                    }
                }
            }

            // Virtual Accounts Management
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "المحافظ الافتراضية (${uiState.allAccounts.size})",
                        style = MaterialTheme.typography.titleSmall,
                        color = TradingTextSecondary
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { showResetDialog = true }) {
                            Text("إعادة التعيين", fontSize = 12.sp, color = TradingNegative)
                        }
                        Button(
                            onClick = { showCreateDialog = true },
                            colors = ButtonDefaults.buttonColors(containerColor = TradingAccent),
                            contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("حساب جديد", fontSize = 12.sp)
                        }
                    }
                }
            }

            items(uiState.allAccounts.size) { index ->
                val acc = uiState.allAccounts[index]
                val isSelected = acc.id == account?.id
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.selectAccount(acc.id) }
                        .testTag("account_item_${acc.id}"),
                    shape = RoundedCornerShape(8.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = if (isSelected) TradingElevated else TradingCard
                    ),
                    border = if (isSelected) {
                        CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingAccent))
                    } else CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(10.dp)
                                    .clip(CircleShape)
                                    .background(if (isSelected) TradingAccent else TradingBorder)
                            )
                            Spacer(modifier = Modifier.width(10.dp))
                            Column {
                                Text(
                                    text = acc.name,
                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                                    fontSize = 14.sp
                                )
                                Text(
                                    text = "الرافعة 1:${acc.leverage.toInt()} • البداية $${acc.initialBalance.toInt()}",
                                    fontSize = 11.sp,
                                    color = TradingTextMuted
                                )
                            }
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                text = String.format(Locale.US, "$%.2f", acc.balance),
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                                color = TradingTextPrimary
                            )
                            if (uiState.allAccounts.size > 1 && !isSelected) {
                                Text(
                                    text = "حذف",
                                    fontSize = 11.sp,
                                    color = TradingNegative,
                                    modifier = Modifier.clickable { showDeleteConfirmDialog = acc }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Dialogs: Create Account
    if (showCreateDialog) {
        AlertDialog(
            onDismissRequest = { showCreateDialog = false },
            title = { Text("إنشاء محفظة افتراضية جديدة", fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(
                        value = newAccountName,
                        onValueChange = { newAccountName = it },
                        label = { Text("اسم الحساب (مثال: محفظة السكالبينج)") },
                        modifier = Modifier.fillMaxWidth().testTag("new_account_name_input")
                    )
                    OutlinedTextField(
                        value = newAccountBalance,
                        onValueChange = { newAccountBalance = it },
                        label = { Text("الرصيد المبدئي الافتراضي ($)") },
                        modifier = Modifier.fillMaxWidth().testTag("new_account_balance_input")
                    )
                    OutlinedTextField(
                        value = newAccountLeverage,
                        onValueChange = { newAccountLeverage = it },
                        label = { Text("الرافعة المالية (مثال: 100)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val name = newAccountName.ifBlank { "محفظة تداول افتراضية" }
                        val bal = newAccountBalance.toDoubleOrNull() ?: 50.0
                        val lev = newAccountLeverage.toDoubleOrNull() ?: 100.0
                        viewModel.createAccount(name, bal, lev)
                        showCreateDialog = false
                        newAccountName = ""
                        newAccountBalance = "50"
                    },
                    modifier = Modifier.testTag("confirm_create_account_btn")
                ) {
                    Text("إنشاء الحساب")
                }
            },
            dismissButton = {
                TextButton(onClick = { showCreateDialog = false }) {
                    Text("إلغاء")
                }
            }
        )
    }

    // Dialogs: Reset Account with Options
    if (showResetDialog) {
        AlertDialog(
            onDismissRequest = { showResetDialog = false },
            title = { Text("إعادة تعيين المحفظة الافتراضية", fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = "تحذير: سيتم حذف جميع الصفقات المفتوحة والسابقة والأوامر المعلقة للحساب الحالي نهائياً.\nاختر الرصيد الجديد للبدء من جديد:",
                        fontSize = 13.sp,
                        color = TradingTextSecondary
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        listOf("50", "100", "500", "1000").forEach { opt ->
                            val isSel = resetBalanceOption == opt
                            OutlinedButton(
                                onClick = { resetBalanceOption = opt },
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.outlinedButtonColors(
                                    containerColor = if (isSel) TradingAccent.copy(alpha = 0.2f) else Color.Transparent
                                )
                            ) {
                                Text("$$opt", fontSize = 11.sp, fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val bal = resetBalanceOption.toDoubleOrNull() ?: 50.0
                        viewModel.resetAccount(bal)
                        showResetDialog = false
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = TradingNegative),
                    modifier = Modifier.testTag("confirm_reset_account_btn")
                ) {
                    Text("تأكيد إعادة التعيين")
                }
            },
            dismissButton = {
                TextButton(onClick = { showResetDialog = false }) {
                    Text("إلغاء")
                }
            }
        )
    }

    // Dialog: Delete Account Confirmation
    showDeleteConfirmDialog?.let { accToDelete ->
        AlertDialog(
            onDismissRequest = { showDeleteConfirmDialog = null },
            title = { Text("حذف الحساب الافتراضي", fontWeight = FontWeight.Bold) },
            text = { Text("هل أنت متأكد من حذف الحساب '${accToDelete.name}' وجميع سجلاته الافتراضية؟ لا يمكن التراجع عن هذا الإجراء.") },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.deleteAccount(accToDelete.id)
                        showDeleteConfirmDialog = null
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = TradingNegative)
                ) {
                    Text("نعم، حذف الحساب")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmDialog = null }) {
                    Text("إلغاء")
                }
            }
        )
    }
}
