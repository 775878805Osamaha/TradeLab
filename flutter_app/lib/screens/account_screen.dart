import 'package:flutter/material.dart';

import '../data/market_controller.dart';
import '../theme/tradelab_theme.dart';
import '../widgets/tradelab_dashboard_widgets.dart';

/// A presentation-only account dashboard. The existing broker connection,
/// account switching, refresh and appearance callbacks remain the authority.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    required this.controller,
    required this.darkMode,
    required this.onDarkModeChanged,
    super.key,
  });

  final bool darkMode;
  final MarketController controller;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final linked = controller.ctraderConnected;
    return ListView(
      key: const Key('account-dashboard-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const TradeDashboardTitle(
          title: 'الحساب',
          subtitle: 'مصادر السوق، الحسابات المصرّح بها، وتفضيلات التطبيق',
        ),
        const SizedBox(height: 18),
        Container(
          key: const Key('account-connection-hero'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF173D75), Color(0xFF0D1E38)],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 48, height: 48, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.person_outline_rounded,
                  color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('مركز الحساب',
                    style: TextStyle(color: Colors.white,
                      fontSize: 19, fontWeight: FontWeight.w800)),
                  Text(linked ? 'cTrader متصل للقراءة فقط' :
                      'اربط حسابك لعرض الذهب والفوركس',
                    maxLines: 2,
                    style: const TextStyle(
                      color: Color(0xFFCCD9EC), fontSize: 12, height: 1.5)),
                ],
              )),
            ]),
            const SizedBox(height: 17),
            Wrap(spacing: 8, runSpacing: 8, children: [
              TradeDashboardPill(
                label: linked ? 'cTrader متصل' : 'cTrader غير متصل',
                icon: linked ? Icons.check_circle_outline : Icons.link_off,
                active: linked, color: linked ? TradeColors.positive :
                    const Color(0xFFFFCA72),
              ),
              TradeDashboardPill(
                label: controller.binanceConnected
                    ? 'Binance نشط' : 'Binance غير محدّث',
                icon: Icons.currency_bitcoin,
                color: const Color(0xFFE8EFFF),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 22),
        const TradeDashboardSection('اتصال مصادر الأسعار',
          caption: 'الفوركس والذهب من cTrader · الكريبتو من Binance'),
        const SizedBox(height: 12),
        _sourceCard(context,
          title: 'cTrader',
          description: linked
              ? 'مصدر أسعار الذهب والفوركس · وصول للقراءة فقط'
              : 'ربط حسابك مطلوب لعرض الأسعار والشموع',
          icon: Icons.show_chart_rounded,
          connected: linked,
          color: TradeColors.blue),
        const SizedBox(height: 10),
        _sourceCard(context,
          title: 'Binance',
          description: controller.binanceConnected
              ? 'مصدر العملات الرقمية · بيانات مستلمة'
              : 'حدّث بيانات العملات الرقمية من المصدر',
          icon: Icons.currency_bitcoin_rounded,
          connected: controller.binanceConnected,
          color: TradeColors.gold),
        const SizedBox(height: 12),
        if (controller.busy || controller.loadingQuotes)
          const Padding(padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 3)),
        if (controller.error != null) ...[
          Text(controller.error!,
            style: TextStyle(color: scheme.error, fontSize: 12)),
          const SizedBox(height: 10),
        ],
        if (!linked)
          FilledButton.icon(
            key: const Key('ctrader-connect'),
            onPressed: controller.busy ? null : controller.connectCTrader,
            icon: const Icon(Icons.link_rounded),
            label: const Text('ربط حساب cTrader للقراءة فقط'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
        if (linked) ...[
          TradeDashboardPanel(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الحساب النشط لدى الوسيط',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const Key('ctrader-account-selector'),
                isExpanded: true,
                initialValue: controller.accountId,
                decoration: const InputDecoration(
                  labelText: 'حساب وسيط cTrader',
                  prefixIcon: Icon(Icons.account_balance_outlined)),
                items: controller.accounts.map((account) => DropdownMenuItem(
                  value: account.id,
                  child: Text(
                    '${account.broker} · ${account.id} ${account.isLive ? '(Live)' : '(Demo)'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr),
                )).toList(),
                onChanged: (value) {
                  if (value != null) controller.chooseAccount(value);
                },
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: controller.disconnect,
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('فصل حساب cTrader')),
              ),
            ],
          )),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: controller.loadingQuotes ? null : controller.refreshQuotes,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('جلب أحدث أسعار Binance'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
        ),
        const SizedBox(height: 24),
        const TradeDashboardSection('تفضيلات التطبيق',
          caption: 'إعدادات العرض فقط، دون تغيير الشموع أو الحسابات'),
        const SizedBox(height: 12),
        TradeDashboardPanel(
          padding: EdgeInsets.zero,
          child: SwitchListTile.adaptive(
            key: const Key('dark-mode-switch'),
            title: const Text('الوضع الداكن',
              style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('تغيير مظهر TradeLab مع الحفاظ على ألوان الشارت'),
            secondary: const TradeDashboardIcon(Icons.dark_mode_outlined),
            value: darkMode,
            onChanged: onDarkModeChanged,
          ),
        ),
        const SizedBox(height: 24),
        const TradeDashboardSection('عن TradeLab'),
        const SizedBox(height: 12),
        TradeDashboardPanel(child: Column(children: [
          _infoRow(context, 'التطبيق', 'TradeLab Flutter'),
          const Divider(height: 22),
          _infoRow(context, 'الشارت الافتراضي', 'التحليل'),
          const Divider(height: 22),
          _infoRow(context, 'أوامر التداول', 'تجريبية محلية فقط'),
          const Divider(height: 22),
          _infoRow(context, 'بيانات الحساب', 'محفوظة ضمن مصادرها المصرّح بها'),
        ])),
        const SizedBox(height: 14),
        Text(
          'حساب cTrader للبيانات فقط؛ لا يرسل TradeLab أوامر تداول حقيقية. '
          'سجل التداول التجريبي المحلي مستقل عن بيانات Room القديمة.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.7,
            color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _sourceCard(BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required bool connected,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TradeDashboardPanel(child: Row(children: [
      TradeDashboardIcon(icon, color: color, size: 46),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(description, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, height: 1.5,
              color: scheme.onSurfaceVariant)),
        ],
      )),
      const SizedBox(width: 8),
      Icon(connected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: connected ? TradeColors.positive :
            scheme.onSurfaceVariant.withValues(alpha: .65),
        size: 19),
    ]));
  }

  Widget _infoRow(BuildContext context, String title, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(flex: 2,
        child: Text(title, style: TextStyle(
          fontSize: 12, color: scheme.onSurfaceVariant))),
      Expanded(flex: 3,
        child: Text(value, maxLines: 3,
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700))),
    ]);
  }
}
