package com.example.ui.navigation

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun TradingBottomBar(currentRoute: String?, onNavigate: (Screen) -> Unit) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val gestureNavigation = WindowInsets.navigationBars.getBottom(density) <= with(density) { 32.dp.roundToPx() }
    Box(Modifier.fillMaxWidth().background(Color(0xFF000D16))
        .then(if (currentRoute == Screen.Chart.route && gestureNavigation) Modifier.padding(bottom = 12.dp)
            else Modifier.navigationBarsPadding())
        .padding(horizontal = 7.dp, vertical = 6.dp).testTag("bottom_nav_bar")) {
        Surface(color = Color(0xFF06131F), shape = RoundedCornerShape(13.dp),
            border = BorderStroke(1.dp, Color(0xFF1B2B3C))) {
            Row(Modifier.fillMaxWidth().height(58.dp)) {
                // Parent is RTL: first destination is physically on the right.
                Screen.bottomNavItems.forEach { screen ->
                    val selected = currentRoute == screen.route
                    val color = if (selected) Color(0xFF2962FF) else Color(0xFF9097A3)
                    val label = when (screen) {
                        Screen.Market -> "السوق"
                        Screen.Chart -> "الشارت"
                        Screen.Results -> "النتائج"
                        else -> "الحساب"
                    }
                    Box(Modifier.weight(1f).fillMaxHeight()
                        .selectable(selected, role = Role.Tab, onClick = { onNavigate(screen) })
                        .testTag("nav_item_${screen.route}")) {
                        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(1.dp)) {
                            Icon(screen.unselectedIcon, label, tint = color, modifier = Modifier.size(25.dp))
                            Text(label, color = color, fontSize = 11.sp)
                        }
                        if (selected) Box(Modifier.align(Alignment.BottomCenter).width(44.dp).height(2.dp)
                            .background(color, RoundedCornerShape(topStart = 2.dp, topEnd = 2.dp)))
                    }
                }
            }
        }
    }
}
