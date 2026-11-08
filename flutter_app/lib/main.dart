import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/account_screen.dart';
import 'screens/chart_screen.dart';
import 'screens/markets_screen.dart';
import 'screens/results_screen.dart';
import 'theme/tradelab_theme.dart';

void main() => runApp(const TradeLabApp());

class TradeLabApp extends StatefulWidget {
  const TradeLabApp({super.key});

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
          darkMode: _themeMode == ThemeMode.dark,
          onDarkModeChanged: (enabled) => setState(() {
            _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
          }),
        ),
      );
}

class TradeLabShell extends StatefulWidget {
  const TradeLabShell({
    required this.darkMode,
    required this.onDarkModeChanged,
    super.key,
  });

  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<TradeLabShell> createState() => _TradeLabShellState();
}

class _TradeLabShellState extends State<TradeLabShell> {
  // The approved tab order is Market → Chart → Results → Account (RTL).
  // Chart opens in ANALYSIS mode, never an implicit Replay session.
  int _selectedIndex = 1;

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
            const FlutterPreviewNotice(),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  const MarketsScreen(),
                  const ChartScreen(),
                  const ResultsScreen(),
                  AccountScreen(
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
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

class FlutterPreviewNotice extends StatelessWidget {
  const FlutterPreviewNotice({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'نسخة واجهات تجريبية. أسعار السوق الحقيقية غير متصلة.',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: TradeColors.blue.withValues(alpha: .08),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.design_services_outlined,
                  size: 15, color: TradeColors.blue),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'معاينة تصميم Flutter · بيانات السوق غير متصلة',
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
