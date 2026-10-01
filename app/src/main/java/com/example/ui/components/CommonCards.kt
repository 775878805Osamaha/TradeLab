package com.example.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.model.DataSourceType
import com.example.ui.theme.*

@Composable
fun DataSourceBadge(
    sourceType: DataSourceType,
    modifier: Modifier = Modifier
) {
    val (badgeBg, badgeText, badgeColor) = when (sourceType) {
        DataSourceType.LIVE_DATA -> Triple(TradingPositiveBg, "LIVE DATA", TradingPositive)
        DataSourceType.DEMO_DATA -> Triple(Color(0x26F59E0B), "DEMO DATA", TradingGold)
        DataSourceType.REPLAY_DATA -> Triple(Color(0x268B5CF6), "REPLAY DATA", TradingAccentLight)
        DataSourceType.STALE_DATA -> Triple(Color(0x26EF4444), "STALE DATA", TradingNegative)
    }

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(badgeBg)
            .border(1.dp, badgeColor.copy(alpha = 0.5f), RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 3.dp)
            .testTag("data_source_badge"),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(badgeColor)
        )
        Spacer(modifier = Modifier.width(5.dp))
        Text(
            text = badgeText,
            color = badgeColor,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
fun VirtualDisclaimerBanner(modifier: Modifier = Modifier) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .testTag("virtual_disclaimer_card"),
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = TradingElevated.copy(alpha = 0.8f))
    ) {
        Row(
            modifier = Modifier.padding(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(TradingGold)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "تداول افتراضي 100% • بدون ربط حساب بنكي أو وساطة حقيقية",
                color = TradingTextSecondary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
fun StatTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    isPositive: Boolean? = null,
    subtitle: String? = null
) {
    val valueColor = when (isPositive) {
        true -> TradingPositive
        false -> TradingNegative
        null -> TradingTextPrimary
    }

    Card(
        modifier = modifier.testTag("stat_tile_${label.replace(" ", "_")}"),
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = TradingCard),
        border = CardDefaults.outlinedCardBorder().copy(brush = androidx.compose.ui.graphics.SolidColor(TradingBorder))
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = label,
                color = TradingTextSecondary,
                fontSize = 11.sp,
                fontWeight = FontWeight.Normal
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = value,
                color = valueColor,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold
            )
            if (subtitle != null) {
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = subtitle,
                    color = TradingTextMuted,
                    fontSize = 10.sp
                )
            }
        }
    }
}
