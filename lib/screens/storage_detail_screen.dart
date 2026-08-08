import 'package:flutter/material.dart';

import '../models/imported_coin.dart';

class StorageDetailScreen extends StatelessWidget {
  final String location;
  final String seriesName;
  final List<ImportedCoin> coins;

  const StorageDetailScreen({
    super.key,
    required this.location,
    required this.seriesName,
    required this.coins,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final owned =
        coins.where((coin) => coin.isOwned).toList();

    final needed =
        coins.where((coin) => coin.isNeeded).toList();

    final untracked = coins
        .where((coin) => !coin.isOwned && !coin.isNeeded)
        .toList();

    final tracked = owned.length + needed.length;

    final completionRate =
        tracked == 0 ? 0.0 : owned.length / tracked;

    final percent = (completionRate * 100).round();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(location),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                28,
                24,
                28,
                20,
              ),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        location,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        seriesName,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
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
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 22,
                        runSpacing: 8,
                        children: [
                          Text('${owned.length} Owned'),
                          Text('${needed.length} Needed'),
                          Text('${coins.length} Total'),
                          if (untracked.isNotEmpty)
                            Text('${untracked.length} Untracked'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'All'),
                Tab(text: 'Owned'),
                Tab(text: 'Need'),
                Tab(text: 'Untracked'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _CoinList(coins: coins),
                  _CoinList(coins: owned),
                  _CoinList(coins: needed),
                  _CoinList(coins: untracked),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinList extends StatelessWidget {
  final List<ImportedCoin> coins;

  const _CoinList({
    required this.coins,
  });

  @override
  Widget build(BuildContext context) {
    if (coins.isEmpty) {
      return const Center(
        child: Text('No coins in this section.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(28),
      itemCount: coins.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1),
      itemBuilder: (context, index) {
        final coin = coins[index];

        return ListTile(
          leading: Icon(
            coin.isOwned
                ? Icons.check_circle_outline
                : coin.isNeeded
                    ? Icons.star_border_rounded
                    : Icons.help_outline,
          ),
          title: Text(
            coin.displayName.isEmpty
                ? coin.series
                : coin.displayName,
          ),
          subtitle: Text(
            [
              coin.status,
              if (coin.grade.trim().isNotEmpty)
                'Grade: ${coin.grade}',
            ].join(' • '),
          ),
        );
      },
    );
  }
}