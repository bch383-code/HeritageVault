import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import 'coin_detail_screen.dart';

class StorageDetailScreen extends StatefulWidget {
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
  State<StorageDetailScreen> createState() =>
      _StorageDetailScreenState();
}

class _StorageDetailScreenState
    extends State<StorageDetailScreen> {
  late List<ImportedCoin> _coins;

  @override
  void initState() {
    super.initState();
    _coins = List<ImportedCoin>.from(widget.coins);
  }

  Future<void> _reloadCoins() async {
    final allCoins =
        await DatabaseHelper.instance.getImportedCoins();

    final location =
        widget.location.trim().toLowerCase();

    final series =
        widget.seriesName.trim().toLowerCase();

    final refreshedCoins = allCoins.where((coin) {
      return coin.storageLocation.trim().toLowerCase() == location &&
          coin.series.trim().toLowerCase() == series;
    }).toList();

    if (!mounted) {
      return;
    }

    setState(() {
      _coins = refreshedCoins;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final owned =
        _coins.where((coin) => coin.isOwned).toList();

    final needed =
        _coins.where((coin) => coin.isNeeded).toList();

    final untracked = _coins
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
          title: Text(widget.location),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                24,
                20,
                24,
                18,
              ),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 90,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(14),
                      color:
                          theme.colorScheme.primaryContainer,
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.location.toUpperCase(),
                          style:
                              theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.seriesName,
                          style: theme
                              .textTheme.headlineMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$percent%',
                              style: theme
                                  .textTheme.displaySmall
                                  ?.copyWith(
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Padding(
                              padding:
                                  EdgeInsets.only(bottom: 7),
                              child: Text('complete'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: completionRate,
                          minHeight: 10,
                          borderRadius:
                              BorderRadius.circular(999),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 22,
                          runSpacing: 8,
                          children: [
                            Text('${owned.length} Owned'),
                            Text('${needed.length} Needed'),
                            Text('${_coins.length} Total'),
                            if (untracked.isNotEmpty)
                              Text(
                                '${untracked.length} Untracked',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
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
                  _CoinList(
                    coins: _coins,
                    onRefresh: _reloadCoins,
                  ),
                  _CoinList(
                    coins: owned,
                    onRefresh: _reloadCoins,
                  ),
                  _CoinList(
                    coins: needed,
                    onRefresh: _reloadCoins,
                  ),
                  _CoinList(
                    coins: untracked,
                    onRefresh: _reloadCoins,
                  ),
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
  final Future<void> Function() onRefresh;

  const _CoinList({
    required this.coins,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (coins.isEmpty) {
      return const Center(
        child: Text('No coins in this section.'),
      );
    }

    return ListView.builder(
      padding:
          const EdgeInsets.fromLTRB(28, 24, 28, 32),
      itemCount: coins.length,
      itemBuilder: (context, index) {
        final coin = coins[index];
        final theme = Theme.of(context);

        final statusIcon = coin.isOwned
            ? Icons.check_circle_rounded
            : coin.isNeeded
                ? Icons.radio_button_unchecked_rounded
                : Icons.help_outline_rounded;

        final statusText = coin.isOwned
            ? 'Owned'
            : coin.isNeeded
                ? 'Need'
                : 'Untracked';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CoinDetailScreen(
                    coin: coin,
                  ),
                ),
              );

              await onRefresh();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme
                          .surfaceContainerHighest,
                      border: Border.all(
                        color:
                            theme.colorScheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.monetization_on_outlined,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          coin.displayName.isEmpty
                              ? coin.series
                              : coin.displayName,
                          style: theme
                              .textTheme.titleMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (coin.grade
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Grade: ${coin.grade}',
                            style:
                                theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    children: [
                      Icon(
                        statusIcon,
                        size: 26,
                        color: coin.isOwned
                            ? theme.colorScheme.primary
                            : theme.colorScheme
                                .onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusText,
                        style: theme
                            .textTheme.labelMedium
                            ?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}