import 'package:flutter/material.dart';

import '../data/tradelab_data.dart';
import '../data/market_controller.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';
import '../widgets/tradelab_dashboard_widgets.dart';

class MarketsScreen extends StatefulWidget {
  const MarketsScreen({required this.controller, this.onSymbolSelected,
    super.key});

  final MarketController controller;
  final ValueChanged<TradeSymbol>? onSymbolSelected;

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  final _search = TextEditingController();
  final _favorites = <String>{'XAUUSD', 'EURUSD'};
  String _filter = 'الكل';
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _search.dispose();
    super.dispose();
  }

  List<TradeSymbol> get _visible {
    final query = _search.text.trim().toLowerCase();
    return tradeSymbols.where((symbol) {
      final matchesKind = switch (_filter) {
        'الذهب' => symbol.kind == InstrumentKind.gold,
        'فوركس' => symbol.kind == InstrumentKind.forex,
        'كريبتو' => symbol.kind == InstrumentKind.crypto,
        _ => true,
      };
      return matchesKind &&
          (!_favoritesOnly || _favorites.contains(symbol.code)) &&
          (symbol.code.toLowerCase().contains(query) ||
              symbol.title.toLowerCase().contains(query));
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final symbols = _visible;
    return Column(children: [
      Container(
        color: scheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('قائمة المراقبة',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900))),
              IconButton(
                key: const Key('watchlist-favorites-toggle'),
                tooltip: 'عرض المفضلة فقط',
                onPressed: () => setState(
                    () => _favoritesOnly = !_favoritesOnly),
                icon: Icon(_favoritesOnly
                    ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: _favoritesOnly ? TradeColors.gold :
                        scheme.onSurfaceVariant),
              ),
              IconButton.filledTonal(
                key: const Key('watchlist-refresh'),
                tooltip: 'تحديث أسعار Binance',
                onPressed: widget.controller.loadingQuotes
                    ? null : widget.controller.refreshQuotes,
                icon: widget.controller.loadingQuotes
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              key: const Key('watchlist-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ابحث عن رمز أو سوق...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () => setState(() => _search.clear()),
                        icon: const Icon(Icons.close_rounded, size: 20))
                    : null,
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(vertical: 11,
                  horizontal: 12),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final filter in const ['الكل', 'الذهب', 'فوركس', 'كريبتو'])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 7),
                    child: ChoiceChip(
                      key: Key('watchlist-filter-$filter'),
                      label: Text(filter),
                      selected: _filter == filter,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ]),
            ),
          ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: symbols.isEmpty
            ? TradeEmptyState(
                icon: _favoritesOnly ? Icons.star_border_rounded
                    : Icons.search_off_rounded,
                title: 'لا توجد رموز مطابقة',
                description: _favoritesOnly
                    ? 'أضف رموزًا إلى المفضلة أو أوقف التصفية.'
                    : 'جرّب تغيير البحث أو اختيار نوع سوق آخر.',
              )
            : ListView.separated(
                key: const Key('markets-symbol-list'),
                padding: const EdgeInsets.fromLTRB(16, 9, 16, 22),
                itemCount: symbols.length + 1,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Row(children: [
                      Expanded(child: Text(
                        _favoritesOnly ? 'الرموز المفضلة' : 'جميع الرموز',
                        style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800),
                      )),
                      Text('${symbols.length} رمز',
                        style: TextStyle(fontSize: 12,
                          color: scheme.onSurfaceVariant)),
                    ]);
                  }
                  return _symbolCard(context, symbols[index - 1]);
                },
              ),
      ),
    ]);
  }

  Widget _symbolCard(BuildContext context, TradeSymbol symbol) {
    final scheme = Theme.of(context).colorScheme;
    final isFavorite = _favorites.contains(symbol.code);
    final isGold = symbol.kind == InstrumentKind.gold;
    final isCrypto = symbol.kind == InstrumentKind.crypto;
    final accent = isGold ? TradeColors.gold :
        isCrypto ? const Color(0xFF8B68D6) : TradeColors.blue;
    final price = symbol.source == TradeSource.ctrader
        ? widget.controller.forexPrices[symbol.code]
        : widget.controller.cryptoPrices[symbol.code];
    final decimals = symbol.code == 'USDJPY' ? 3 :
        symbol.kind == InstrumentKind.forex ? 5 : 2;
    final hasPrice = price != null && price.isFinite;
    final source = symbol.source == TradeSource.ctrader
        ? 'cTrader' : 'Binance';
    final status = hasPrice
        ? symbol.source == TradeSource.ctrader
            ? 'سعر BID من cTrader' : 'سعر من Binance'
        : symbol.source == TradeSource.ctrader &&
                !widget.controller.ctraderConnected
            ? 'يتطلب ربط cTrader' : 'لا يتوفر سعر مؤكد';

    return TradeDashboardPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: Key('market-open-chart-${symbol.code}'),
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onSymbolSelected == null
            ? null : () => widget.onSymbolSelected!(symbol),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            TradeDashboardIcon(
              isGold ? Icons.auto_awesome_rounded :
                  isCrypto ? Icons.currency_bitcoin_rounded :
                    Icons.show_chart_rounded,
              color: accent, size: 38),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(symbol.code, textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(symbol.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11,
                    color: scheme.onSurfaceVariant)),
                const SizedBox(height: 5),
                Text(source, textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w700, color: accent)),
              ],
            )),
            const SizedBox(width: 8),
            Flexible(child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(hasPrice ? price.toStringAsFixed(decimals) : '—',
                  maxLines: 1, softWrap: false,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(status, maxLines: 2,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 10, height: 1.35,
                    color: hasPrice ? TradeColors.positive :
                        scheme.onSurfaceVariant)),
              ],
            )),
            const SizedBox(width: 4),
            IconButton(
              tooltip: isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
              onPressed: () => setState(() {
                if (!_favorites.add(symbol.code)) {
                  _favorites.remove(symbol.code);
                }
              }),
              icon: Icon(isFavorite
                  ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isFavorite ? TradeColors.gold :
                      scheme.onSurfaceVariant, size: 24),
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              padding: EdgeInsets.zero,
            ),
          ]),
        ),
      ),
    );
  }
}
