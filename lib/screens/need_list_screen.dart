import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import 'coin_detail_screen.dart';

class NeedListScreen extends StatefulWidget {
  const NeedListScreen({super.key});

  @override
  State<NeedListScreen> createState() => _NeedListScreenState();
}

class _NeedListScreenState extends State<NeedListScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<ImportedCoin> _neededCoins = const [];
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _loadNeededCoins();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNeededCoins() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final coins = await _databaseHelper.getImportedCoins();

      final needed = coins
          .where((coin) => coin.isNeeded)
          .toList()
        ..sort((a, b) {
          final seriesCompare = a.series
              .toLowerCase()
              .compareTo(b.series.toLowerCase());

          if (seriesCompare != 0) {
            return seriesCompare;
          }

          return a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase());
        });

      if (!mounted) return;

      setState(() {
        _neededCoins = needed;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  List<ImportedCoin> get _visibleCoins {
    final query = _searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return _neededCoins;
    }

    return _neededCoins.where((coin) {
      return coin.series.toLowerCase().contains(query) ||
          coin.year.toLowerCase().contains(query) ||
          coin.mint.toLowerCase().contains(query) ||
          coin.variety.toLowerCase().contains(query) ||
          coin.storageLocation.toLowerCase().contains(query);
    }).toList();
  }

  Map<String, List<ImportedCoin>> _groupBySeries(
    List<ImportedCoin> coins,
  ) {
    final grouped = <String, List<ImportedCoin>>{};

    for (final coin in coins) {
      final series = coin.series.trim().isEmpty
          ? 'Unknown Series'
          : coin.series.trim();

      grouped.putIfAbsent(series, () => []).add(coin);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Need List'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Could not load the Need List.\n\n$_errorMessage',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final visibleCoins = _visibleCoins;
    final grouped = _groupBySeries(visibleCoins);
    final seriesNames = grouped.keys.toList()
      ..sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Need List'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadNeededCoins,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
        children: [
          Text(
            'Coins I Need',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${visibleCoins.length} coins needed across '
            '${seriesNames.length} series',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search Need List',
              hintText: 'Series, year, mint, variety, binder...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchText.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchText = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) {
              setState(() => _searchText = value);
            },
          ),
          const SizedBox(height: 26),

          if (visibleCoins.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text(
                    'No needed coins match your search.',
                  ),
                ),
              ),
            )
          else
            for (final seriesName in seriesNames) ...[
              _NeedSeriesSection(
                seriesName: seriesName,
                coins: grouped[seriesName]!,
                onCoinChanged: _loadNeededCoins,
              ),
              const SizedBox(height: 26),
            ],
        ],
      ),
    );
  }
}

class _NeedSeriesSection extends StatelessWidget {
  final String seriesName;
  final List<ImportedCoin> coins;
  final Future<void> Function() onCoinChanged;

  const _NeedSeriesSection({
    required this.seriesName,
    required this.coins,
    required this.onCoinChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                seriesName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text('${coins.length} needed'),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0;
                  index < coins.length;
                  index++) ...[
                _NeedCoinRow(
                  coin: coins[index],
                  onCoinChanged: onCoinChanged,
                ),
                if (index != coins.length - 1)
                  const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NeedCoinRow extends StatelessWidget {
  final ImportedCoin coin;
  final Future<void> Function() onCoinChanged;

  const _NeedCoinRow({
    required this.coin,
    required this.onCoinChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CoinDetailScreen(
              coin: coin,
            ),
          ),
        );

        await onCoinChanged();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.radio_button_unchecked_rounded,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coin.displayName.isEmpty
                        ? coin.series
                        : coin.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (coin.storageLocation.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      coin.storageLocation,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}