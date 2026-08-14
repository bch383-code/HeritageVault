import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import 'series_storage_summary.dart';

class SeriesCollectionTab extends StatelessWidget {
  final String seriesName;

  const SeriesCollectionTab({
    super.key,
    required this.seriesName,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ImportedCoin>>(
      future: DatabaseHelper.instance.getImportedCoins(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Could not load this collection.\n\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final normalizedSeries = seriesName.trim().toLowerCase();
        final seriesCoins = (snapshot.data ?? []).where((coin) {
          final coinSeries = coin.series.trim().toLowerCase();
          return coinSeries == normalizedSeries ||
              coinSeries.contains(normalizedSeries) ||
              normalizedSeries.contains(coinSeries);
        }).toList();

        if (seriesCoins.isEmpty) {
          return const Center(child: Text('No coins were found for this series.'));
        }

        final needed =
            seriesCoins.where((coin) => coin.status == 'Need').toList();
        final owned =
            seriesCoins.where((coin) => coin.status == 'Owned').toList();
        final untracked =
            seriesCoins.where((coin) => coin.status == 'Untracked').toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth >= 760;

            return ListView(
              padding: const EdgeInsets.all(28),
              children: [
                if (twoColumn)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _CollectionSummary(
                            total: seriesCoins.length,
                            owned: owned.length,
                            needed: needed.length,
                            untracked: untracked.length,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: SeriesStorageSummary(
                                coins: seriesCoins,
                                embedded: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _CollectionSummary(
                    total: seriesCoins.length,
                    owned: owned.length,
                    needed: needed.length,
                    untracked: untracked.length,
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: SeriesStorageSummary(
                        coins: seriesCoins,
                        embedded: true,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                if (needed.isNotEmpty)
                  _CoinSection(
                    title: 'Need',
                    icon: Icons.star_border_rounded,
                    coins: needed,
                    twoColumn: twoColumn,
                  ),
                if (needed.isNotEmpty && owned.isNotEmpty)
                  const SizedBox(height: 28),
                if (owned.isNotEmpty)
                  _CoinSection(
                    title: 'Owned',
                    icon: Icons.check_circle_outline,
                    coins: owned,
                    twoColumn: twoColumn,
                  ),
                if (untracked.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _CoinSection(
                    title: 'Untracked',
                    icon: Icons.help_outline,
                    coins: untracked,
                    twoColumn: twoColumn,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CollectionSummary extends StatelessWidget {
  final int total;
  final int owned;
  final int needed;
  final int untracked;

  const _CollectionSummary({
    required this.total,
    required this.owned,
    required this.needed,
    required this.untracked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracked = owned + needed;
    final completionRate = tracked == 0 ? 0.0 : owned / tracked;
    final percent = (completionRate * 100).round();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Collection',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  '$percent%',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('complete'),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: completionRate,
              minHeight: 9,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 22,
              runSpacing: 8,
              children: [
                Text('$owned Owned'),
                Text('$needed Needed'),
                Text('$total Total'),
                if (untracked > 0) Text('$untracked Untracked'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ImportedCoin> coins;
  final bool twoColumn;

  const _CoinSection({
    required this.title,
    required this.icon,
    required this.coins,
    required this.twoColumn,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text('${coins.length} coins'),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: coins.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: twoColumn ? 2 : 1,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 76,
          ),
          itemBuilder: (context, index) => _CoinCard(coin: coins[index]),
        ),
      ],
    );
  }
}

class _CoinCard extends StatelessWidget {
  final ImportedCoin coin;

  const _CoinCard({required this.coin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      if (coin.mint.trim().isNotEmpty) coin.mint.trim(),
      if (coin.variety.trim().isNotEmpty) coin.variety.trim(),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                coin.year.isEmpty ? '—' : coin.year,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                details.isEmpty ? coin.series : details.join(' • '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (coin.storageLocation.trim().isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  coin.storageLocation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
