import 'package:flutter/material.dart';

import '../theme/tradelab_theme.dart';

class TradeSectionTitle extends StatelessWidget {
  const TradeSectionTitle(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class TradeSurface extends StatelessWidget {
  const TradeSurface({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding ?? const EdgeInsets.all(TradeSpacing.md),
          child: child,
        ),
      );
}

class TradeStatusChip extends StatelessWidget {
  const TradeStatusChip({required this.label, this.connected = false, super.key});

  final String label;
  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: (connected ? TradeColors.positive : Theme.of(context).colorScheme.outline)
              .withValues(alpha: .11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(connected ? Icons.check_circle : Icons.circle_outlined,
                size: 12,
                color: connected
                    ? TradeColors.positive
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
}

class TradeEmptyState extends StatelessWidget {
  const TradeEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(TradeSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: TradeColors.blueLight),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 6),
              Text(description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
            ],
          ),
        ),
      );
}
