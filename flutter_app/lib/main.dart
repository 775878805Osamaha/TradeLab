import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/market_controller.dart';
import 'paper/paper_journal_controller.dart';
import 'paper/paper_journal_store.dart';

import 'screens/account_screen.dart';
import 'screens/chart_screen.dart';
import 'screens/markets_screen.dart';
import 'screens/results_screen.dart';
import 'theme/tradelab_theme.dart';

void main() {
  // Release builds otherwise replace a failed widget with an opaque grey area.
  // Keep a visible recovery message without exposing broker or account data.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Flutter has already reported the build error. Re-reporting here can
    // duplicate diagnostics and obscure the original exception.
    return const Material(
      color: Color(0xFFF7F8FB),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 36, color: Color(0xFFB42318)),
              SizedBox(height: 12),
              Text('تعذر عرض هذا القسم',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text('حدث خطأ في واجهة التطبيق. جرّب فتح قسم آخر ثم العودة.',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl),
            ],
          ),
        ),
      ),
    );
  };
  runApp(const TradeLabApp());
}

class TradeLabApp extends StatefulWidget {
  const TradeLabApp({this.controller, this.journal, super.key});

  final MarketController? controller;
  final PaperJournalController? journal;

  @override
  State<TradeLabApp> createState() => _TradeLabAppState();
}

class _TradeLabAppState extends State<TradeLabApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'TradeLab',
        debugShowCheckedModeBanner: false,
        theme: TradeTheme.light(),
        darkTheme: TradeTheme.dark(),
        themeMode: _themeMode,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: TradeLabShell(
          controller: widget.controller,
          journal: widget.journal,
          darkMode: _themeMode == ThemeMode.dark,
          onDarkModeChanged: (enabled) => setState(() {
            _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
          }),
        ),
      );
}

class TradeLabShell extends StatefulWidget {
  const TradeLabShell({
    this.controller,
    this.journal,
    required this.darkMode,
    required this.onDarkModeChanged,
    super.key,
  });

  final bool darkMode;
  final MarketController? controller;
  final PaperJournalController? journal;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<TradeLabShell> createState() => _TradeLabShellState();
}

class _TradeLabShellState extends State<TradeLabShell> {
  // The approved tab order is Market → Chart → Results → Account (RTL).
  // Chart opens in ANALYSIS mode, never an implicit Replay session.
  int _selectedIndex = 1;
  late final MarketController _market = widget.controller ?? MarketController();
  late final PaperJournalController _journal = widget.journal ??
      PaperJournalController(store: SqlitePaperJournalStore());

  @override
  void initState() {
    super.initState();
    _market.addListener(_onAccountChanged);
    _journal.useAccount(_market.accountId);
    if (widget.controller == null) _market.initialize();
  }

  void _onAccountChanged() {
    if (_market.accountId != null || _journal.accountKey != 'local:guest') {
      _journal.useAccount(_market.accountId);
    }
  }

  @override
  void dispose() {
    _market.removeListener(_onAccountChanged);
    if (widget.controller == null) _market.dispose();
    if (widget.journal == null) _journal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destinations = const [
      NavigationDestination(
        icon: Icon(Icons.show_chart_outlined),
        selectedIcon: Icon(Icons.show_chart),
        label: 'السوق',
      ),
      NavigationDestination(
        icon: Icon(Icons.candlestick_chart_outlined),
        selectedIcon: Icon(Icons.candlestick_chart),
        label: 'الشارت',
      ),
      NavigationDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
        label: 'النتائج',
      ),
      NavigationDestination(
        icon: Icon(Icons.account_balance_outlined),
        selectedIcon: Icon(Icons.account_balance),
        label: 'الحساب',
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AnimatedBuilder(animation: _market,
              builder: (context, _) => MarketSourceNotice(controller: _market)),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  MarketsScreen(controller: _market),
                  ChartScreen(controller: _market, journal: _journal,
                    onOpenAccount: () => setState(() => _selectedIndex = 3)),
                  ResultsScreen(controller: _market, journal: _journal),
                  AccountScreen(
                    controller: _market,
                    darkMode: widget.darkMode,
                    onDarkModeChanged: widget.onDarkModeChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: destinations,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) _market.refreshQuotes();
        },
      ),
    );
  }
}

class MarketSourceNotice extends StatelessWidget {
  const MarketSourceNotice({required this.controller, super.key});

  final MarketController controller;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'حالة ربط مصادر بيانات السوق',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: TradeColors.blue.withValues(alpha: .08),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_outlined,
                  size: 15, color: TradeColors.blue),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  controller.ctraderConnected
                    ? 'cTrader مرتبط للقراءة فقط · بيانات الرموز الأخرى حسب مصدرها'
                    : controller.binanceConnected
                      ? 'Binance متصل · cTrader يتطلب ربط حسابك'
                      : 'cTrader غير مرتبط · لا تُعرض شموع الذهب والفوركس قبل تسجيل الدخول',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: TradeColors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
}
