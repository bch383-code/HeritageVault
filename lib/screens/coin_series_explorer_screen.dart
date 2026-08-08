import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import '../widgets/series_card.dart';
import 'coins_screen.dart';
import 'series_detail_screen.dart';

class CoinSeriesExplorerScreen extends StatefulWidget {
  const CoinSeriesExplorerScreen({super.key});

  @override
  State<CoinSeriesExplorerScreen> createState() =>
      _CoinSeriesExplorerScreenState();
}

class _CoinSeriesExplorerScreenState
    extends State<CoinSeriesExplorerScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<_SeriesProgress> _series = const [];
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final coins = await _databaseHelper.getImportedCoins();

      final grouped = <String, List<ImportedCoin>>{};

      for (final coin in coins) {
        final seriesName = coin.series.trim();

        if (seriesName.isEmpty) {
          continue;
        }

        grouped.putIfAbsent(seriesName, () => []).add(coin);
      }

      final progress = grouped.entries.map((entry) {
        final coins = entry.value;

        return _SeriesProgress(
          name: entry.key,
          owned: coins.where((coin) => coin.status == 'Owned').length,
          needed: coins.where((coin) => coin.status == 'Need').length,
          untracked:
              coins.where((coin) => coin.status == 'Untracked').length,
        );
      }).toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(
                b.name.toLowerCase(),
              ),
        );

      if (!mounted) return;

      setState(() {
        _series = progress;
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

  List<_SeriesProgress> get _visibleSeries {
    final query = _searchText.trim().toLowerCase();

    if (query.isEmpty) {
      return _series;
    }

    return _series
        .where(
          (series) => series.name.toLowerCase().contains(query),
        )
        .toList();
  }

Future<void> _openSeries(String seriesName) async {
  if (seriesName.toLowerCase().contains('morgan')) {
    await Navigator.push(
      context,
      MaterialPageRoute(
       builder: (context) => SeriesDetailScreen(
  seriesName: seriesName,
),
      ),
    );

    await _loadSeries();
    return;
  }

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => CoinsScreen(
        initialSearchText: seriesName,
      ),
    ),
  );

  await _loadSeries();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coin Series'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadSeries,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Could not load coin series.\n\n$_errorMessage',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final visibleSeries = _visibleSeries;

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
      children: [
        Text(
          'United States Coin Series',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Browse your collection the way collectors think about it.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Find a series',
            hintText: 'Morgan, Peace, Lincoln, Buffalo...',
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
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Coin series',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text('${visibleSeries.length} shown'),
          ],
        ),
        const SizedBox(height: 14),
        if (visibleSeries.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No coin series were found in the imported data.',
                ),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleSeries.length,
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              childAspectRatio: 1.25,
            ),
            itemBuilder: (context, index) {
              final series = visibleSeries[index];

              return SeriesCard(
                title: series.name,
                owned: series.owned,
                needed: series.needed,
                untracked: series.untracked,
                onTap: () => _openSeries(series.name),
              );
            },
          ),
      ],
    );
  }
}

class _SeriesProgress {
  final String name;
  final int owned;
  final int needed;
  final int untracked;

  const _SeriesProgress({
    required this.name,
    required this.owned,
    required this.needed,
    required this.untracked,
  });
}