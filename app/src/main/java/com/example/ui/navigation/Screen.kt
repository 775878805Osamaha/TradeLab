package com.example.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.ui.graphics.vector.ImageVector

sealed class Screen(
    val route: String,
    val titleResId: Int,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
) {
    object Account : Screen(
        route = "account",
        titleResId = com.example.R.string.nav_account,
        selectedIcon = Icons.Filled.AccountBalance,
        unselectedIcon = Icons.Outlined.AccountBalance
    )

    object Market : Screen(
        route = "market",
        titleResId = com.example.R.string.nav_market,
        selectedIcon = Icons.Filled.TrendingUp,
        unselectedIcon = Icons.Outlined.TrendingUp
    )

    object Chart : Screen(
        route = "chart",
        titleResId = com.example.R.string.nav_chart,
        selectedIcon = Icons.Filled.ShowChart,
        unselectedIcon = Icons.Outlined.ShowChart
    )

    object Trade : Screen(
        route = "trade",
        titleResId = com.example.R.string.nav_trade,
        selectedIcon = Icons.Filled.SwapVert,
        unselectedIcon = Icons.Outlined.SwapVert
    )

    object Results : Screen(
        route = "results",
        titleResId = com.example.R.string.nav_results,
        selectedIcon = Icons.Filled.Leaderboard,
        unselectedIcon = Icons.Outlined.Leaderboard
    )

    // Secondary sub-screens
    object History : Screen(
        route = "history",
        titleResId = com.example.R.string.title_history,
        selectedIcon = Icons.Filled.History,
        unselectedIcon = Icons.Outlined.History
    )

    object Replay : Screen(
        route = "replay",
        titleResId = com.example.R.string.title_replay,
        selectedIcon = Icons.Filled.PlayCircle,
        unselectedIcon = Icons.Outlined.PlayCircle
    )

    object Backtest : Screen(
        route = "backtest",
        titleResId = com.example.R.string.title_backtest,
        selectedIcon = Icons.Filled.AutoGraph,
        unselectedIcon = Icons.Outlined.AutoGraph
    )

    object Strategies : Screen(
        route = "strategies",
        titleResId = com.example.R.string.title_strategies,
        selectedIcon = Icons.Filled.Psychology,
        unselectedIcon = Icons.Outlined.Psychology
    )

    object Calendar : Screen(
        route = "calendar",
        titleResId = com.example.R.string.title_calendar,
        selectedIcon = Icons.Filled.CalendarMonth,
        unselectedIcon = Icons.Outlined.CalendarMonth
    )

    object Challenge : Screen(
        route = "challenge",
        titleResId = com.example.R.string.title_account_rules,
        selectedIcon = Icons.Filled.MilitaryTech,
        unselectedIcon = Icons.Outlined.MilitaryTech
    )

    object Settings : Screen(
        route = "settings",
        titleResId = com.example.R.string.title_settings,
        selectedIcon = Icons.Filled.Settings,
        unselectedIcon = Icons.Outlined.Settings
    )

    companion object {
        val bottomNavItems = listOf(Market, Chart, Trade, Results, Account)
    }
}
