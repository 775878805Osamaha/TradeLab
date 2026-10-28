package com.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.*
import com.example.feature.account.AccountScreen
import com.example.feature.account.AccountViewModel
import com.example.feature.backtest.BacktestScreen
import com.example.feature.backtest.BacktestViewModel
import com.example.feature.calendar.TradingCalendarScreen
import com.example.feature.calendar.TradingCalendarViewModel
import com.example.feature.challenge.ChallengeScreen
import com.example.feature.chart.ChartScreen
import com.example.feature.chart.ChartViewModel
import com.example.feature.history.HistoryScreen
import com.example.feature.history.HistoryViewModel
import com.example.feature.market.MarketScreen
import com.example.feature.market.MarketViewModel
import com.example.feature.replay.ReplayScreen
import com.example.feature.replay.ReplayViewModel
import com.example.feature.results.ResultsScreen
import com.example.feature.results.ResultsViewModel
import com.example.feature.settings.SettingsScreen
import com.example.feature.strategy.StrategyScreen
import com.example.feature.trade.TradeScreen
import com.example.feature.trade.TradeViewModel
import com.example.ui.navigation.Screen
import com.example.ui.theme.TradeLabTheme
import com.example.ui.theme.TradingBackground
import com.example.ui.theme.TradingBorder
import com.example.ui.theme.TradingCard

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = androidx.activity.SystemBarStyle.dark(android.graphics.Color.rgb(0, 13, 22))
        )

        setContent {
            val app = LocalContext.current.applicationContext as TradeLabApplication

            // ViewModels scoped cleanly with dependencies
            val accountViewModel by remember { lazy { AccountViewModel(app.tradingRepository) } }
            val marketViewModel = remember { MarketViewModel(app.marketDataRepository) }
            val chartViewModel = remember { ChartViewModel(app.marketDataRepository, app.tradingRepository, app.database.drawingDao()) }
            val tradeViewModel by remember { lazy { TradeViewModel(app.tradingRepository, app.marketDataRepository) } }
            val resultsViewModel by remember { lazy { ResultsViewModel(app.tradingRepository, app.trainingSessionStore) } }
            val historyViewModel by remember { lazy { HistoryViewModel(app.tradingRepository) } }
            val replayViewModel = remember { ReplayViewModel(app.marketDataRepository, reportSink = { app.tradingRepository.replayReport.value = it }, sessionStore = app.trainingSessionStore) }
            val backtestViewModel by remember { lazy { BacktestViewModel(app.marketDataRepository, tradingRepository = app.tradingRepository) } }
            val calendarViewModel by remember { lazy { TradingCalendarViewModel(app.tradingRepository) } }

            TradeLabTheme {
                // Arabic RTL as primary layout direction
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    val navController = rememberNavController()
                    val navBackStackEntry by navController.currentBackStackEntryAsState()
                    val currentRoute = navBackStackEntry?.destination?.route
                    var embeddedReplayLaunchRequest by remember { mutableIntStateOf(0) }
                    val openReplayOnChart = {
                        embeddedReplayLaunchRequest++
                        navController.navigate(Screen.Chart.route) {
                            launchSingleTop = true
                        }
                    }

                    var chartImmersive by remember { mutableStateOf(true) }
                    // Keep the four primary destinations accessible even when the chart
                    // uses its edge-to-edge layout. Immersive affects chart chrome,
                    // not the app's primary navigation.
                    val showBottomNav = currentRoute in Screen.bottomNavItems.map { it.route }

                    Scaffold(
                        modifier = Modifier
                            .fillMaxSize()
                            .testTag("app_root_scaffold"),
                        containerColor = TradingBackground,
                        bottomBar = {
                            if (showBottomNav) {
                                com.example.ui.navigation.TradingBottomBar(currentRoute) { screen ->
                                    navController.navigate(screen.route) {
                                        popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                        launchSingleTop = true
                                        restoreState = true
                                    }
                                }
                            }
                        }
                    ) { innerPadding ->
                        NavHost(
                            navController = navController,
                            startDestination = Screen.Chart.route,
                            modifier = Modifier.padding(innerPadding)
                        ) {
                            // Primary Tab: Account
                            composable(Screen.Account.route) {
                                com.example.feature.account.TrainingAccountScreen(replayViewModel,openReplayOnChart)
                            }

                            // Primary Tab: Market
                            composable(Screen.Market.route) {
                                MarketScreen(
                                    viewModel = marketViewModel,
                                    onSelectSymbol = { symbol ->
                                        chartViewModel.selectSymbol(symbol)
                                        navController.navigate(Screen.Chart.route)
                                    }
                                )
                            }

                            // Primary Tab: Chart
                            composable(Screen.Chart.route) {
                                ChartScreen(
                                    viewModel = chartViewModel,
                                    replayViewModel = replayViewModel,
                                    embeddedReplayLaunchRequest = embeddedReplayLaunchRequest,
                                    onEmbeddedReplayLaunchConsumed = { embeddedReplayLaunchRequest = 0 },
                                    onNavigateToReplay = openReplayOnChart,
                                    onImmersiveChanged = { chartImmersive = it }
                                )
                            }

                            // Primary Tab: Trade
                            composable(Screen.Trade.route) {
                                androidx.compose.runtime.LaunchedEffect(Unit) { openReplayOnChart() }
                            }

                            // Primary Tab: Results
                            composable(Screen.Results.route) {
                                ResultsScreen(
                                    viewModel = resultsViewModel,
                                    onNavigateToHistory = { resultsViewModel.setSelectedTab(com.example.feature.results.ResultsTab.JOURNAL) },
                                    onNavigateToBacktest = openReplayOnChart
                                )
                            }

                            // Sub-Screen: History Journal
                            composable(Screen.History.route) {
                                HistoryScreen(
                                    viewModel = historyViewModel,
                                    onBack = { navController.popBackStack() }
                                )
                            }

                            // Sub-Screen: Historical Replay
                            composable(Screen.Replay.route) {
                                LaunchedEffect(Unit) {
                                    embeddedReplayLaunchRequest++
                                    navController.navigate(Screen.Chart.route) {
                                        popUpTo(Screen.Replay.route) { inclusive = true }
                                        launchSingleTop = true
                                    }
                                }
                            }

                            // Sub-Screen: Backtest
                            composable(Screen.Backtest.route) {
                                BacktestScreen(
                                    viewModel = backtestViewModel,
                                    onBack = { navController.popBackStack() }
                                )
                            }

                            // Sub-Screen: Strategies
                            composable(Screen.Strategies.route) {
                                StrategyScreen(
                                    onNavigateToBacktest = { strategyId ->
                                        val strat = com.example.core.strategy.StrategyRegistry.getStrategy(strategyId)
                                        if (strat != null) {
                                            backtestViewModel.selectStrategy(strat)
                                        }
                                        navController.navigate(Screen.Backtest.route)
                                    },
                                    onNavigateToReplay = { strategyId ->
                                        openReplayOnChart()
                                    },
                                    onBack = { navController.popBackStack() }
                                )
                            }

                            // Sub-Screen: Trading Calendar
                            composable(Screen.Calendar.route) {
                                TradingCalendarScreen(
                                    viewModel = calendarViewModel,
                                    onBack = { navController.popBackStack() }
                                )
                            }

                            // Sub-Screen: Challenge & Discipline Rules
                            composable(Screen.Challenge.route) {
                                ChallengeScreen(
                                    viewModel = accountViewModel,
                                    onBack = { navController.popBackStack() }
                                )
                            }

                            // Sub-Screen: Settings & Data Provider
                            composable(Screen.Settings.route) {
                                SettingsScreen(
                                    provider = app.marketDataProvider,
                                    onBack = { navController.popBackStack() }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
