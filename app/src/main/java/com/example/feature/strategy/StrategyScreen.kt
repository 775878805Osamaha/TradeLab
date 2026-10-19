package com.example.feature.strategy

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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
import com.example.core.strategy.*
import com.example.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StrategyScreen(
    onNavigateToBacktest: (String) -> Unit,
    onNavigateToReplay: (String) -> Unit = {},
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var searchQuery by remember { mutableStateOf("") }
    var selectedCategory by remember { mutableStateOf<StrategyCategory?>(null) }
    var expandedStrategyId by remember { mutableStateOf<String?>(null) }
    var userParameters by remember { mutableStateOf(mutableMapOf<String, MutableMap<String, Any>>()) }
    var validationErrors by remember { mutableStateOf(mapOf<String, List<ValidationError>>()) }
    val snackbarHostState = remember { SnackbarHostState() }
    var statusMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(statusMessage) {
        statusMessage?.let {
            snackbarHostState.showSnackbar(it)
            statusMessage = null
        }
    }

    val allStrategies = remember { StrategyRegistry.getAllStrategies() }
    val filteredStrategies = remember(searchQuery, selectedCategory) {
        allStrategies.filter { strat ->
            val matchesQuery = searchQuery.isBlank() ||
                strat.name.contains(searchQuery, ignoreCase = true) ||
                strat.description.contains(searchQuery, ignoreCase = true) ||
                strat.id.contains(searchQuery, ignoreCase = true)
            val matchesCategory = selectedCategory == null || strat.category == selectedCategory
            matchesQuery && matchesCategory
        }
    }

    Scaffold(
        modifier = modifier.testTag("strategy_screen"),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("مكتبة الاستراتيجيات الخوارزمية", fontSize = 17.sp, fontWeight = FontWeight.Bold) },
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
            contentPadding = PaddingValues(bottom = 32.dp)
        ) {
            // Search Bar
            item {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    placeholder = { Text("ابحث عن استراتيجية بالاسم أو المعامل...") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = "بحث") },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Default.Clear, contentDescription = "مسح")
                            }
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("search_strategy_input"),
                    shape = RoundedCornerShape(10.dp),
                    singleLine = true
                )
            }

            // Category Filter Chips
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    item {
                        FilterChip(
                            selected = selectedCategory == null,
                            onClick = { selectedCategory = null },
                            label = { Text("الكل (${allStrategies.size})") }
                        )
                    }
                    items(StrategyCategory.values()) { cat ->
                        FilterChip(
                            selected = selectedCategory == cat,
                            onClick = { selectedCategory = if (selectedCategory == cat) null else cat },
                            label = { Text(cat.displayNameAr) }
                        )
                    }
                }
            }

            // Strategy Cards / Empty State
            if (filteredStrategies.isEmpty()) {
                item {
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 16.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingCard),
                        border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Icon(
                                imageVector = Icons.Default.Psychology,
                                contentDescription = null,
                                tint = TradingTextSecondary,
                                modifier = Modifier.size(48.dp)
                            )
                            Spacer(modifier = Modifier.height(12.dp))
                            Text(
                                text = "لا توجد استراتيجيات تداول مدمجة حالياً",
                                fontWeight = FontWeight.Bold,
                                fontSize = 15.sp,
                                color = TradingTextPrimary
                            )
                            Spacer(modifier = Modifier.height(6.dp))
                            Text(
                                text = "تمت إزالة جميع الاستراتيجيات المدمجة. يمكنك إضافة وتسجيل استراتيجيات مخصصة للعمل بها.",
                                fontSize = 12.sp,
                                color = TradingTextSecondary,
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center
                            )
                        }
                    }
                }
            } else {
                items(filteredStrategies, key = { it.id }) { strategy ->
                val isExpanded = expandedStrategyId == strategy.id
                val currentParams = userParameters.getOrPut(strategy.id) {
                    strategy.defaultParameters.toMutableMap()
                }
                val errors = validationErrors[strategy.id] ?: emptyList()
                val presets = remember(strategy.id) { StrategyRegistry.getPresetsForStrategy(strategy.id) }

                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("strategy_card_${strategy.id}"),
                    shape = RoundedCornerShape(14.dp),
                    colors = CardDefaults.cardColors(containerColor = TradingCard),
                    border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Default.Psychology, contentDescription = null, tint = TradingAccentLight, modifier = Modifier.size(20.dp))
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        text = strategy.name,
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 14.sp
                                    )
                                }
                                Spacer(modifier = Modifier.height(4.dp))
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(4.dp))
                                            .background(TradingElevated)
                                            .padding(horizontal = 6.dp, vertical = 2.dp)
                                    ) {
                                        Text(text = strategy.category.displayNameAr, fontSize = 10.sp, color = TradingTextSecondary)
                                    }
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(4.dp))
                                            .background(TradingAccent.copy(alpha = 0.15f))
                                            .padding(horizontal = 6.dp, vertical = 2.dp)
                                    ) {
                                        Text(text = "v${strategy.version}.0", fontSize = 10.sp, color = TradingAccentLight, fontWeight = FontWeight.Bold)
                                    }
                                }
                            }

                            IconButton(onClick = { expandedStrategyId = if (isExpanded) null else strategy.id }) {
                                Icon(
                                    imageVector = if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                                    contentDescription = "تفاصيل"
                                )
                            }
                        }

                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = strategy.description,
                            fontSize = 12.sp,
                            color = TradingTextSecondary,
                            lineHeight = 18.sp
                        )

                        // Presets Row
                        if (presets.isNotEmpty()) {
                            Spacer(modifier = Modifier.height(10.dp))
                            Text(text = "النماذج الجاهزة (Presets):", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = TradingTextMuted)
                            Spacer(modifier = Modifier.height(4.dp))
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                items(presets) { p ->
                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(6.dp))
                                            .background(TradingElevated)
                                            .clickable {
                                                userParameters[strategy.id] = p.parameters.toMutableMap()
                                                val valid = StrategyValidator.validate(strategy, p.parameters)
                                                validationErrors = validationErrors + (strategy.id to valid.errors)
                                                statusMessage = "تم تطبيق نموذج '${p.name}'"
                                            }
                                            .padding(horizontal = 8.dp, vertical = 4.dp)
                                    ) {
                                        Text(text = p.name, fontSize = 11.sp, color = TradingTextPrimary)
                                    }
                                }
                            }
                        }

                        // Expanded Parameters Editor
                        if (isExpanded) {
                            Spacer(modifier = Modifier.height(12.dp))
                            HorizontalDivider(color = TradingBorder)
                            Spacer(modifier = Modifier.height(10.dp))
                            Text(text = "تعديل المعاملات والتحقق البرمجي:", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Spacer(modifier = Modifier.height(8.dp))

                            strategy.parameterDefinitions.forEach { def ->
                                val paramVal = currentParams[def.id] ?: def.defaultValue
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 4.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(text = def.name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                        if (def.description.isNotEmpty()) {
                                            Text(text = def.description, fontSize = 10.sp, color = TradingTextMuted)
                                        }
                                    }
                                    OutlinedTextField(
                                        value = paramVal.toString(),
                                        onValueChange = { newVal ->
                                            val parsed: Any = when (def.type) {
                                                ParameterType.INT -> newVal.toIntOrNull() ?: paramVal
                                                ParameterType.DOUBLE -> newVal.toDoubleOrNull() ?: paramVal
                                                else -> newVal
                                            }
                                            val updated = currentParams.toMutableMap()
                                            updated[def.id] = parsed
                                            userParameters[strategy.id] = updated
                                            val valid = StrategyValidator.validate(strategy, updated)
                                            validationErrors = validationErrors + (strategy.id to valid.errors)
                                        },
                                        modifier = Modifier.width(100.dp),
                                        singleLine = true,
                                        textStyle = MaterialTheme.typography.bodySmall
                                    )
                                }
                            }

                            // Validation Errors
                            if (errors.isNotEmpty()) {
                                Spacer(modifier = Modifier.height(6.dp))
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(TradingNegative.copy(alpha = 0.1f))
                                        .padding(8.dp)
                                ) {
                                    errors.forEach { err ->
                                        Text(text = "• ${err.message}", fontSize = 11.sp, color = TradingNegative)
                                    }
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(12.dp))
                        HorizontalDivider(color = TradingBorder)
                        Spacer(modifier = Modifier.height(10.dp))

                        // Actions Row
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            OutlinedButton(
                                onClick = {
                                    userParameters[strategy.id] = strategy.defaultParameters.toMutableMap()
                                    validationErrors = validationErrors - strategy.id
                                    statusMessage = "تمت إعادة ضبط المعاملات للافتراضي"
                                },
                                shape = RoundedCornerShape(8.dp),
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(14.dp))
                                Spacer(modifier = Modifier.width(4.dp))
                                Text("إعادة ضبط", fontSize = 11.sp)
                            }

                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                OutlinedButton(
                                    onClick = { onNavigateToReplay(strategy.id) },
                                    shape = RoundedCornerShape(8.dp),
                                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)
                                ) {
                                    Icon(Icons.Default.FastForward, contentDescription = null, modifier = Modifier.size(14.dp))
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("إعادة عرض", fontSize = 11.sp)
                                }

                                Button(
                                    onClick = { onNavigateToBacktest(strategy.id) },
                                    colors = ButtonDefaults.buttonColors(containerColor = TradingAccent),
                                    shape = RoundedCornerShape(8.dp),
                                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Icon(Icons.Default.AutoGraph, contentDescription = null, modifier = Modifier.size(16.dp))
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("اختبار تاريخي", fontSize = 12.sp)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
}
