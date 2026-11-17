import 'package:flutter/material.dart';

import '../theme/tradelab_theme.dart';

/// TradeLab's shared, RTL-safe dashboard presentation system.
/// Presentation only: these widgets never generate trading or market data.
class TradeDashboardPanel extends StatelessWidget {
  const TradeDashboardPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: background ?? scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ?? scheme.outline.withValues(alpha: .16),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

class TradeDashboardTitle extends StatelessWidget {
  const TradeDashboardTitle({
    required this.title,
    required this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900, letterSpacing: -.35,
            )),
          const SizedBox(height: 5),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.5,
              color: scheme.onSurfaceVariant)),
        ],
      )),
      if (action != null) ...[const SizedBox(width: 8), action!],
    ]);
  }
}

class TradeDashboardSection extends StatelessWidget {
  const TradeDashboardSection(this.title, {this.caption, this.action,
    super.key});

  final String title;
  final String? caption;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Container(width: 3, height: 19,
        decoration: BoxDecoration(color: TradeColors.blue,
          borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 9),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800)),
          if (caption != null) Text(caption!,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      )),
      if (action != null) action!,
    ]);
  }
}

class TradeDashboardPill extends StatelessWidget {
  const TradeDashboardPill({
    required this.label,
    this.icon,
    this.active = false,
    this.color,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? (active ? TradeColors.positive :
        scheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 5),
        ],
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: accent, fontSize: 11,
            fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class TradeDashboardIcon extends StatelessWidget {
  const TradeDashboardIcon(this.icon, {this.color = TradeColors.blue,
    this.size = 42, super.key});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size, alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(13),
      color: color.withValues(alpha: .10),
    ),
    child: Icon(icon, color: color, size: size * .52),
  );
}
