import 'package:flutter/material.dart';

import '../data/market_controller.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({required this.controller, super.key});

  final MarketController controller;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String _period = 'إجمالي';
  int _page = 0;

  static const _pages = [
    'نظرة عامة', 'المنحنيات البيانية', 'يوميات الصفقات',
    'إحصائيات الصفقات', 'النتائج اليومية',
  ];
  static const _periods = [
    'إجمالي', 'الكل', 'سنة', '6 أشهر', '3 أشهر', 'شهر', 'أسبوع', 'مخصص',
  ];
  static const _stats = [
    ('نسبة الفوز', Icons.donut_small),
    ('إجمالي الصفقات', Icons.swap_horiz),
    ('معامل الربح', Icons.functions),
    ('أقصى تراجع', Icons.trending_down),
    ('التوقع الرياضي', Icons.calculate_outlined),
    ('أطول سلسلة أرباح', Icons.trending_up),
    ('أطول سلسلة خسائر', Icons.south_east),
    ('متوسط مدة الصفقة', Icons.timer_outlined),
    ('معامل شارب', Icons.insights_outlined),
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAccountChange);
  }

  @override
  void didUpdateWidget(covariant ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onAccountChange);
      widget.controller.addListener(_onAccountChange);
    }
  }

  void _onAccountChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAccountChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        color: colors.surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('النتائج والتحليلات',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ))),
            TradeStatusChip(
              label: widget.controller.ctraderConnected
                  ? 'cTrader متصل'
                  : 'لا يوجد سجل تداول',
              connected: widget.controller.ctraderConnected,
            ),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < _pages.length; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(_pages[i]),
                    selected: _page == i,
                    onSelected: (_) => setState(() => _page = i),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final period in _periods)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 7),
                child: FilterChip(
                  label: Text(period),
                  selected: _period == period,
                  onSelected: (_) => period == 'مخصص'
                      ? _selectCustomPeriod()
                      : setState(() => _period = period),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        if (widget.controller.ctraderConnected) ...[
          TradeSurface(child: Row(children: [
            const Icon(Icons.info_outline, color: TradeColors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'حساب cTrader متصل لقراءة أسعار السوق. نتائج التداول التجريبي '
              'تحتاج إلى نقل سجل Room من تطبيق Android القديم أو تسجيل '
              'الصفقات في قاعدة Flutter مستقلة. لن نعرض أرصدة أو أرباحًا مفترضة.',
              style: Theme.of(context).textTheme.bodySmall,
            )),
          ])),
          const SizedBox(height: 14),
        ],
        if (_page == 0) ...[
          const TradeSectionTitle('ملخص الحساب'),
          _summary(),
          const SizedBox(height: 20),
          _curve(),
          const SizedBox(height: 20),
          _statistics(),
          const SizedBox(height: 20),
          _recentTrades(),
        ] else if (_page == 1) ...[
          _curve(),
          const SizedBox(height: 12),
          _emptyMessage('المنحنى سيُحسب من الصفقات المسجلة محليًا، بلا بيانات وهمية.'),
        ] else if (_page == 2) ...[
          _recentTrades(),
          const SizedBox(height: 12),
          _emptyMessage('لا توجد صفقات مغلقة لعرض يومياتها بعد.'),
        ] else if (_page == 3) ...[
          _statistics(),
          const SizedBox(height: 12),
          _emptyMessage('تُحسب المؤشرات بعد الربط بقاعدة الصفقات الفعلية.'),
        ] else ...[
          const TradeSectionTitle('صافي النتائج اليومية'),
          TradeSurface(child: SizedBox(
            height: 240,
            child: TradeEmptyState(
              icon: Icons.calendar_month_outlined,
              title: 'لا توجد نتائج يومية بعد',
              description: 'ستظهر النتائج حسب تواريخ إغلاق الصفقات.',
            ),
          )),
        ],
      ])),
    ]);
  }

  Widget _summary() => GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
        children: [
          _metric('صافي الربح', Icons.trending_up, TradeColors.positive),
          _metric('إجمالي الإيداعات', Icons.south_west, TradeColors.blue),
          _metric('الرصيد الابتدائي', Icons.account_balance_wallet_outlined, TradeColors.blue),
          _metric('الرصيد النهائي', Icons.account_balance_outlined, TradeColors.gold),
        ],
      );

  Widget _metric(String title, IconData icon, Color color) => TradeSurface(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, maxLines: 1,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            Icon(icon, color: color, size: 19),
          ]),
          const Spacer(),
          const Text('—', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Text('لا توجد بيانات', style: TextStyle(fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );

  Widget _curve() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TradeSectionTitle('منحنى الرصيد (Equity)'),
        TradeSurface(child: SizedBox(
          height: 240,
          child: const TradeEmptyState(
            icon: Icons.show_chart,
            title: 'في انتظار سجل التداول',
            description: 'لا يتم رسم أرباح افتراضية مكان بياناتك الحقيقية.',
          ),
        )),
      ]);

  Widget _statistics() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TradeSectionTitle('إحصائيات الصفقات'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _stats.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8,
            childAspectRatio: .97,
          ),
          itemBuilder: (context, index) => TradeSurface(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_stats[index].$2, size: 19, color: TradeColors.blue),
              const SizedBox(height: 7),
              const Text('—', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(_stats[index].$1, maxLines: 2, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, height: 1.2)),
            ]),
          ),
        ),
      ]);

  Widget _recentTrades() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TradeSectionTitle('آخر الصفقات المغلقة'),
        const TradeSurface(child: SizedBox(height: 190,
          child: TradeEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'لا توجد صفقات',
            description: 'ستظهر آخر خمس صفقات من قاعدة البيانات بعد الربط.',
          ),
        )),
      ]);

  Widget _emptyMessage(String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(value, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      );

  Future<void> _selectCustomPeriod() async {
    final now = DateTime.now();
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (dates != null && mounted) setState(() => _period = 'مخصص');
  }
}
