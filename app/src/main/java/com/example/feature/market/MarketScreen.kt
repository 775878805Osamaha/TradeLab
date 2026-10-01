package com.example.feature.market

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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
import com.example.core.model.ProviderConnectionStatus
import com.example.ui.components.DataSourceBadge
import com.example.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MarketScreen(
    viewModel: MarketViewModel,
    onSelectSymbol: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val uiState by viewModel.uiState.collectAsState()
    val timeFormat = remember { SimpleDateFormat("HH:mm:ss", Locale.US) }

    Scaffold(
        modifier = modifier.testTag("market_screen"),
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "مراقبة السوق (Market Watch)",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        DataSourceBadge(sourceType = uiState.dataSourceType)
                    }
                },
                actions = {
                    // Connection Status Indicator Dot
                    val (connColor, connDesc) = when (uiState.connectionStatus) {
                        ProviderConnectionStatus.CONNECTED -> Pair(TradingPositive, "متصل")
                        ProviderConnectionStatus.CONNECTING, ProviderConnectionStatus.RECONNECTING -> Pair(TradingGold, "جاري الاتصال")
                        ProviderConnectionStatus.DEGRADED -> Pair(Color(0xFFF97316), "اتصال ضعيف")
                        ProviderConnectionStatus.DISCONNECTED, ProviderConnectionStatus.ERROR -> Pair(TradingNegative, "غير متصل")
                    }
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(connColor)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    IconButton(
                        onClick = { viewModel.toggleFavoritesFilter() },
                        modifier = Modifier.testTag("filter_favorites_btn")
                    ) {
                        Icon(
                            imageVector = if (uiState.showOnlyFavorites) Icons.Default.Star else Icons.Default.StarBorder,
                            contentDescription = "المفضلة",
                            tint = if (uiState.showOnlyFavorites) TradingGold else TradingTextSecondary
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = TradingBackground)
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp)
        ) {
            // Search Bar
            OutlinedTextField(
                value = uiState.searchQuery,
                onValueChange = { viewModel.updateSearchQuery(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("market_search_input"),
                placeholder = { Text("بحث عن رمز (XAUUSD, BTCUSDT, EURUSD...)", fontSize = 13.sp) },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = TradingTextSecondary) },
                trailingIcon = {
                    if (uiState.searchQuery.isNotEmpty()) {
                        IconButton(onClick = { viewModel.updateSearchQuery("") }) {
                            Icon(Icons.Default.Clear, contentDescription = "مسح")
                        }
                    }
                },
                singleLine = true,
                shape = RoundedCornerShape(10.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = TradingAccent,
                    unfocusedBorderColor = TradingBorder,
                    focusedContainerColor = TradingCard,
                    unfocusedContainerColor = TradingCard
                )
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Sorting Filter Chips Row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = "ترتيب حسب:",
                    fontSize = 11.sp,
                    color = TradingTextSecondary,
                    modifier = Modifier.align(Alignment.CenterVertically)
                )
                listOf(
                    Pair(MarketSort.SYMBOL, "الرمز"),
                    Pair(MarketSort.SPREAD, "أقل سبريد"),
                    Pair(MarketSort.CHANGE_PCT, "التغير %")
                ).forEach { (sortOpt, title) ->
                    val isSel = uiState.sortOption == sortOpt
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(if (isSel) TradingAccent else TradingElevated)
                            .clickable { viewModel.setSortOption(sortOpt) }
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text(
                            text = title,
                            fontSize = 11.sp,
                            fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal,
                            color = if (isSel) Color.White else TradingTextSecondary
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Market Watchlist Column Headers
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(text = "الرمز / المصدر", fontSize = 11.sp, color = TradingTextSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(36.dp)) {
                    Text(text = "طلب (Ask)", fontSize = 11.sp, color = TradingTextSecondary)
                    Text(text = "عرض (Bid)", fontSize = 11.sp, color = TradingTextSecondary)
                }
            }

            HorizontalDivider(color = TradingBorder)

            // Symbols List
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(vertical = 8.dp)
            ) {
                items(uiState.rows.size) { index ->
                    val row = uiState.rows[index]
                    val sym = row.symbolInfo
                    val tick = row.tick

                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelectSymbol(sym.symbol) }
                            .testTag("symbol_card_${sym.symbol}"),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = TradingCard),
                        border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            // Left: Favorite + Symbol + Category + Spread + Source
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                IconButton(
                                    onClick = { viewModel.toggleSymbolFavorite(sym.symbol, sym.isFavorite) },
                                    modifier = Modifier.size(28.dp).testTag("fav_btn_${sym.symbol}")
                                ) {
                                    Icon(
                                        imageVector = if (sym.isFavorite) Icons.Default.Star else Icons.Default.StarBorder,
                                        contentDescription = "تفضيل",
                                        tint = if (sym.isFavorite) TradingGold else TradingTextMuted,
                                        modifier = Modifier.size(18.dp)
                                    )
                                }
                                Spacer(modifier = Modifier.width(6.dp))
                                Column {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(
                                            text = sym.symbol,
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 15.sp,
                                            color = TradingTextPrimary
                                        )
                                        Spacer(modifier = Modifier.width(6.dp))
                                        // Category Badge
                                        Box(
                                            modifier = Modifier
                                                .clip(RoundedCornerShape(4.dp))
                                                .background(TradingElevated)
                                                .padding(horizontal = 4.dp, vertical = 2.dp)
                                        ) {
                                            Text(
                                                text = sym.category,
                                                fontSize = 9.sp,
                                                color = TradingTextSecondary
                                            )
                                        }
                                    }
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text(
                                            text = "السبريد: ${String.format(Locale.US, "%.1f", row.spreadPips)} نقطة",
                                            fontSize = 11.sp,
                                            color = TradingTextMuted
                                        )
                                        Spacer(modifier = Modifier.width(6.dp))
                                        val sourceLabel = tick?.source ?: if (sym.category == "Crypto") "BINANCE" else "BENCHMARK"
                                        Text(
                                            text = "• $sourceLabel",
                                            fontSize = 9.sp,
                                            color = if (sourceLabel.contains("LIVE") || sourceLabel.contains("BINANCE")) TradingCyan else TradingTextMuted
                                        )
                                    }
                                }
                            }

                            // Right: Ask and Bid prices
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(16.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                // Ask Box
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(TradingElevated)
                                        .border(1.dp, TradingCyan.copy(alpha = 0.4f), RoundedCornerShape(6.dp))
                                        .padding(horizontal = 8.dp, vertical = 6.dp)
                                ) {
                                    val askStr = if (tick != null) sym.formatPrice(tick.ask) else "--"
                                    Text(
                                        text = askStr,
                                        color = TradingCyan,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }

                                // Bid Box
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(TradingElevated)
                                        .border(1.dp, TradingBorder, RoundedCornerShape(6.dp))
                                        .padding(horizontal = 8.dp, vertical = 6.dp)
                                ) {
                                    val bidStr = if (tick != null) sym.formatPrice(tick.bid) else "--"
                                    Text(
                                        text = bidStr,
                                        color = TradingTextPrimary,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
