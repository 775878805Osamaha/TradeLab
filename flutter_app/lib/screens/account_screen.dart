import 'package:flutter/material.dart';

import '../theme/tradelab_theme.dart';
import '../widgets/trade_components.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    required this.darkMode,
    required this.onDarkModeChanged,
    super.key,
  });

  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('الحساب والإعدادات',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          )),
      const SizedBox(height: 8),
      Text('إعدادات تجربة TradeLab الجديدة',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
      const SizedBox(height: 20),
      TradeSurface(
        child: Row(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: TradeColors.blue.withValues(alpha: .1),
            child: const Icon(Icons.person_outline, color: TradeColors.blue, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الحساب الشخصي',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 3),
                Text('غير متصل في معاينة Flutter',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
              ])),
          const TradeStatusChip(label: 'غير متصل'),
        ]),
      ),
      const SizedBox(height: 24),
      const TradeSectionTitle('مصادر البيانات'),
      TradeSurface(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _sourceTile(context,
              title: 'cTrader',
              subtitle: 'مصدر الذهب والفوركس · يتطلب ربط حسابك',
              icon: Icons.show_chart),
          const Divider(height: 1),
          _sourceTile(context,
              title: 'Binance',
              subtitle: 'مصدر العملات الرقمية · غير متصل بعد',
              icon: Icons.currency_bitcoin),
        ]),
      ),
      const SizedBox(height: 22),
      const TradeSectionTitle('مظهر التطبيق'),
      TradeSurface(
        padding: EdgeInsets.zero,
        child: SwitchListTile.adaptive(
          key: const Key('dark-mode-switch'),
          title: const Text('الوضع الداكن'),
          subtitle: const Text('الحفاظ على ألوان الشارت في كلا الوضعين'),
          secondary: const Icon(Icons.dark_mode_outlined),
          value: darkMode,
          onChanged: onDarkModeChanged,
        ),
      ),
      const SizedBox(height: 22),
      const TradeSectionTitle('حول TradeLab'),
      TradeSurface(child: Column(children: [
        _infoRow(context, 'التطبيق', 'TradeLab Flutter'),
        const SizedBox(height: 12),
        _infoRow(context, 'حالة الإصدار', 'معاينة تصميم'),
        const SizedBox(height: 12),
        _infoRow(context, 'الوضع الافتراضي للشارت', 'التحليل'),
        const SizedBox(height: 12),
        _infoRow(context, 'التداول والأرصدة', 'غير مفعّلة'),
      ])),
      const SizedBox(height: 24),
      const Text(
        'هذه النسخة لا تنقل بيانات Room أو عمليات حسابك من تطبيق Android الحالي. '
        'سيتم تنفيذ الربط والتحقق من سلامة البيانات في مرحلة مستقلة.',
        style: TextStyle(fontSize: 12, height: 1.6),
        textAlign: TextAlign.center,
      ),
    ]);
  }

  Widget _sourceTile(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) => ListTile(
        leading: Icon(icon, color: TradeColors.blue),
        title: Text(title, textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.link_off, size: 18),
      );

  Widget _infoRow(BuildContext context, String title, String value) => Row(
        children: [
          Expanded(child: Text(title, style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
}
