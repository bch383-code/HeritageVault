import 'package:flutter/material.dart';

import '../reference/coin_series_reference.dart';

class SeriesOverviewTab extends StatelessWidget {
  final CoinSeriesReference? reference;

  const SeriesOverviewTab({
    super.key,
    required this.reference,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (reference == null) {
      return const Center(
        child: Text('Reference information is not available yet.'),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          'Quick Facts',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _MuseumFactCard(
              icon: Icons.payments_outlined,
              label: 'Denomination',
              value: reference!.denomination,
            ),
            _MuseumFactCard(
              icon: Icons.calendar_month_outlined,
              label: 'Years',
              value: reference!.years,
            ),
            _MuseumFactCard(
              icon: Icons.draw_outlined,
              label: 'Designer',
              value: reference!.designer,
            ),
            _MuseumFactCard(
              icon: Icons.balance_outlined,
              label: 'Composition',
              value: reference!.composition,
            ),
            _MuseumFactCard(
              icon: Icons.account_balance_outlined,
              label: 'Mints',
              value: reference!.mints.join(' • '),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'About This Series',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Text(
              reference!.history,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MuseumFactCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MuseumFactCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: colors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}