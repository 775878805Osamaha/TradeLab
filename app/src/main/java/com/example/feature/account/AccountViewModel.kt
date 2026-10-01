package com.example.feature.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.core.challenge.FtmoChallengeEvaluator
import com.example.core.model.ChallengeConfig
import com.example.core.model.ChallengeStatus
import com.example.core.model.VirtualAccount
import com.example.core.statistics.StatisticsCalculator
import com.example.data.repository.TradingRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.*

data class AccountUiState(
    val selectedAccount: VirtualAccount? = null,
    val allAccounts: List<VirtualAccount> = emptyList(),
    val challengeStatus: ChallengeStatus? = null,
    val totalClosedTrades: Int = 0,
    val openPositionsCount: Int = 0,
    val pendingOrdersCount: Int = 0,
    val unrealizedProfitLoss: Double = 0.0,
    val realizedProfitLoss: Double = 0.0,
    val todayProfitLoss: Double = 0.0,
    val totalProfitLoss: Double = 0.0,
    val winRatePct: Double = 0.0,
    val profitFactor: Double? = null,
    val maxDrawdown: Double = 0.0,
    val isMarginWarning: Boolean = false,
    val isLoading: Boolean = false,
    val message: String? = null
)

class AccountViewModel(
    private val tradingRepository: TradingRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(AccountUiState(isLoading = true))
    val uiState: StateFlow<AccountUiState> = _uiState.asStateFlow()

    init {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)

        viewModelScope.launch {
            tradingRepository.initializeDefaultAccountIfNeeded()

            combine(
                tradingRepository.selectedAccount,
                tradingRepository.allAccounts
            ) { selected, accounts ->
                Pair(selected, accounts)
            }.collect { (selected, accounts) ->
                if (selected != null) {
                    combine(
                        tradingRepository.getTradesForAccount(selected.id),
                        tradingRepository.getPositionsForAccount(selected.id),
                        tradingRepository.getPendingOrdersForAccount(selected.id)
                    ) { trades, positions, pendingOrders ->
                        withContext(Dispatchers.Default) {
                            val todayStr = sdf.format(Date())
                            val todayTrades = trades.filter { sdf.format(Date(it.closeTime)) == todayStr }
                            val todayPl = todayTrades.sumOf { it.netProfitLoss }
                            val unrealized = positions.sumOf { it.profitLoss }
                            val realized = trades.sumOf { it.netProfitLoss }

                            val metrics = StatisticsCalculator.calculate(
                                initialBalance = selected.initialBalance,
                                trades = trades,
                                currentEquity = selected.equity
                            )

                            val challenge = FtmoChallengeEvaluator.evaluate(
                                account = selected,
                                trades = trades,
                                config = ChallengeConfig(accountSize = selected.initialBalance)
                            )

                            val marginWarning = selected.freeMargin < 15.0 || (selected.margin > 0 && selected.marginLevel < 120.0)

                            AccountUiState(
                                selectedAccount = selected,
                                allAccounts = accounts,
                                challengeStatus = challenge,
                                totalClosedTrades = trades.size,
                                openPositionsCount = positions.size,
                                pendingOrdersCount = pendingOrders.size,
                                unrealizedProfitLoss = unrealized,
                                realizedProfitLoss = realized,
                                todayProfitLoss = todayPl,
                                totalProfitLoss = selected.equity - selected.initialBalance,
                                winRatePct = metrics.winRatePct,
                                profitFactor = metrics.profitFactor,
                                maxDrawdown = metrics.maxDrawdown,
                                isMarginWarning = marginWarning,
                                isLoading = false
                            )
                        }
                    }.collect { newState ->
                        _uiState.update { newState.copy(message = it.message) }
                    }
                } else {
                    _uiState.update {
                        it.copy(allAccounts = accounts, isLoading = false)
                    }
                }
            }
        }
    }

    fun createAccount(name: String, initialBalance: Double, leverage: Double) {
        if (initialBalance <= 0.0 || leverage <= 0.0) {
            _uiState.update { it.copy(message = "الرصيد والرافعة المالية يجب أن تكون أكبر من الصفر") }
            return
        }
        val safeName = name.ifBlank { "محفظة تداول افتراضية" }
        viewModelScope.launch {
            tradingRepository.createAccount(safeName, initialBalance, leverage)
            _uiState.update { it.copy(message = "تم إنشاء الحساب الافتراضي بنجاح") }
        }
    }

    fun selectAccount(id: Long) {
        viewModelScope.launch {
            tradingRepository.selectAccount(id)
        }
    }

    fun resetAccount(balance: Double = 50.0) {
        val current = _uiState.value.selectedAccount ?: return
        viewModelScope.launch {
            tradingRepository.resetAccount(current.id, balance)
            _uiState.update { it.copy(message = "تمت إعادة تعيين الحساب إلى $${balance}") }
        }
    }

    fun deleteAccount(id: Long) {
        if (_uiState.value.allAccounts.size <= 1) {
            _uiState.update { it.copy(message = "لا يمكن حذف الحساب الوحيد المتبقي في التطبيق") }
            return
        }
        viewModelScope.launch {
            tradingRepository.deleteAccount(id)
            _uiState.update { it.copy(message = "تم حذف الحساب بنجاح") }
        }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }
}
