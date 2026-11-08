import 'package:flutter/material.dart';

import '../data/tradelab_data.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  final _search = TextEditingController();
  final _favorites = <String>{'XAUUSD', 'EURUSD'};
  String _filter = 'الكل';
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TradeSymbol> get _visible => tradeSymbols.where((symbol) {
        final category = switch (_filter) {
          'الذهب' => symbol.kind == InstrumentKind.gold,
          'فوركس' => symbol.kind == InstrumentKind.forex,
          'كريبتو' => symbol.kind == InstrumentKind.crypto,
          _ => true,
        };
        final query = _search.text.trim().toLowerCase();
        return category &&
            (!_favoritesOnly || _favorites.contains(symbol.code)) &&
            (symbol.code.toLowerCase().contains(query) ||
                symbol.title.toLowerCase().contains(query));
      }).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        color: colors.surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('الأسواق',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800))),
            const TradeStatusChip(label: 'غير متصل'),
            IconButton(
              tooltip: 'عرض المفضلة فقط',
              icon: Icon(_favoritesOnly ? Icons.star : Icons.star_border,
                  color: _favoritesOnly ? TradeColors.gold : colors.onSurface),
              onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'ابحث عن الذهب، العملات أو الكريبتو',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final filter in const ['الكل', 'الذهب', 'فوركس', 'كريبتو'])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _visible.isEmpty
            ? const TradeEmptyState(
                icon: Icons.search_off,
                title: 'لا توجد رموز مطابقة',
                description: 'غيّر كلمات البحث أو نوع السوق.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: _visible.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('الرموز المتاحة · الأسعار تنتظر الربط',
                          style: TextStyle(fontSize: 12)),
                    );
                  }
                  final symbol = _visible[index - 1];
                  return TradeSurface(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (symbol.kind == InstrumentKind.gold
                                  ? TradeColors.gold
                                  : TradeColors.blue)
                              .withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          symbol.kind == InstrumentKind.gold
                              ? Icons.currency_exchange
                              : symbol.kind == InstrumentKind.crypto
                                  ? Icons.currency_bitcoin
                                  : Icons.show_chart,
                          color: symbol.kind == InstrumentKind.gold
                              ? TradeColors.gold
                              : TradeColors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(symbol.code, textDirection: TextDirection.ltr,
                              style: const TextStyle(fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                          Text(symbol.title,
                              style: TextStyle(color: colors.onSurfaceVariant,
                                  fontSize: 12)),
                        ],
                      )),
                      Column(crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                        const Text('—', style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(symbol.source == TradeSource.ctrader
                            ? 'cTrader · غير متصل' : 'Binance · غير متصل',
                            style: TextStyle(fontSize: 10,
                                color: colors.onSurfaceVariant)),
                      ]),
                      IconButton(
                        tooltip: _favorites.contains(symbol.code)
                            ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                        icon: Icon(_favorites.contains(symbol.code)
                            ? Icons.star : Icons.star_border,
                            color: _favorites.contains(symbol.code)
                                ? TradeColors.gold : colors.onSurfaceVariant),
                        onPressed: () => setState(() {
                          if (!_favorites.add(symbol.code)) {
                            _favorites.remove(symbol.code);
                          }
                        }),
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
