import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import '../services/coin_import_service.dart';
import '../reference/coin_series_reference.dart';
import '../widgets/series_card.dart';
import 'coins_screen.dart';
import 'series_detail_screen.dart';
import 'need_list_screen.dart';

class CoinSeriesExplorerScreen extends StatefulWidget {
  const CoinSeriesExplorerScreen({super.key});

  @override
  State<CoinSeriesExplorerScreen> createState() =>
      _CoinSeriesExplorerScreenState();
}

class _CoinSeriesExplorerScreenState extends State<CoinSeriesExplorerScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final CoinImportService _importService = CoinImportService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isImporting = false;
  String? _errorMessage;
  List<_SeriesProgress> _series = const [];
  String _searchText = '';
  String _selectedDenomination = 'All denominations';

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
      final importedCoins = await _databaseHelper.getImportedCoins();

      // CoinSeriesLibrary is the master catalog.
      final grouped = <String, List<ImportedCoin>>{
        for (final reference in CoinSeriesLibrary.series)
          reference.series: <ImportedCoin>[],
      };

      // Merge imported collection data into recognized catalog series.
      for (final coin in importedCoins) {
        final importedSeriesName = coin.series.trim();

        if (importedSeriesName.isEmpty) {
          continue;
        }

        final reference = CoinSeriesLibrary.find(importedSeriesName);

        // Do not create bogus cards from unrecognized spreadsheet values.
        if (reference == null) {
          continue;
        }

        grouped[reference.series]!.add(coin);
      }

      final progress = CoinSeriesLibrary.series.map((reference) {
        final coins = grouped[reference.series] ?? const <ImportedCoin>[];

        return _SeriesProgress(
          name: reference.series,
          owned: coins.where((coin) => coin.status == 'Owned').length,
          needed: coins.where((coin) => coin.status == 'Need').length,
          untracked: coins.where((coin) => coin.status == 'Untracked').length,
        );
      }).toList();

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

    return _series.where((series) {
      final matchesSearch =
          query.isEmpty || series.name.toLowerCase().contains(query);

      final reference = CoinSeriesLibrary.find(series.name);
      final matchesDenomination =
          _selectedDenomination == 'All denominations' ||
          reference?.denomination == _selectedDenomination;

      return matchesSearch && matchesDenomination;
    }).toList();
  }

  List<String> get _denominations {
    final denominations =
        CoinSeriesLibrary.series
            .map((reference) => reference.denomination)
            .toSet()
            .toList()
          ..sort();

    return ['All denominations', ...denominations];
  }

  Future<void> _importSpreadsheet() async {
    if (_isImporting) return;

    setState(() => _isImporting = true);

    try {
      final result = await _importService.chooseAndReadWorkbook();
      if (!mounted || result == null) return;

      final importMode = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import Coin Workbook'),
          content: SizedBox(
            width: 580,
            child: Text(
              '${result.fileName}\n\n'
              '${result.coins.length} coin entries were found.\n'
              'Owned: ${result.ownedCount}\n'
              'Needed: ${result.neededCount}\n'
              'Untracked: ${result.untrackedCount}\n\n'
              'Choose how Heirloom Atlas should import this workbook.\n\n'
              'Merge keeps your current collection and adds new coin entries. '
              'For matching coins, your existing Heirloom Atlas information '
              'is preserved.\n\n'
              'Replace removes the current imported coin list and replaces it '
              'with the workbook contents. A database backup is created first.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'merge'),
              icon: const Icon(Icons.merge_type),
              label: const Text('Merge'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'replace'),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Replace Current'),
            ),
          ],
        ),
      );

      if (!mounted || importMode == null) return;

      await _databaseHelper.createDatabaseBackup(
        reason: importMode == 'merge'
            ? 'before_spreadsheet_merge'
            : 'before_spreadsheet_replace',
      );

      late final int savedCount;
      var addedCount = 0;
      var preservedCount = 0;

      if (importMode == 'merge') {
        final currentCoins = await _databaseHelper.getImportedCoins();

        String coinKey(ImportedCoin coin) => [
              coin.category.trim().toLowerCase(),
              coin.series.trim().toLowerCase(),
              coin.year.trim().toLowerCase(),
              coin.mint.trim().toLowerCase(),
              coin.variety.trim().toLowerCase(),
            ].join('|');

        final merged = <String, ImportedCoin>{};

        // Workbook entries establish the incoming catalog.
        for (final coin in result.coins) {
          merged[coinKey(coin)] = coin;
        }

        // Existing Heirloom Atlas entries win on a match so user-entered
        // status, quantity, storage, grade, value, notes, and image are kept.
        for (final coin in currentCoins) {
          final key = coinKey(coin);
          if (merged.containsKey(key)) {
            preservedCount++;
          } else {
            addedCount++;
          }
          merged[key] = coin;
        }

        final incomingKeys = result.coins.map(coinKey).toSet();
        final currentKeys = currentCoins.map(coinKey).toSet();
        addedCount =
            incomingKeys.where((key) => !currentKeys.contains(key)).length;

        savedCount = await _databaseHelper.replaceImportedCoins(
          merged.values.toList(),
        );
      } else {
        savedCount = await _databaseHelper.replaceImportedCoins(result.coins);

        await _databaseHelper.replaceStorageLocations(
          result.storageLocations
              .map(
                (location) => <String, Object?>{
                  'brand': location.brand,
                  'color': location.color,
                  'number': location.number,
                  'title': location.title,
                  'year': location.year,
                  'notes': location.notes,
                },
              )
              .toList(),
        );
      }

      final savedStorageCount =
          importMode == 'replace' ? result.storageLocations.length : 0;

      await _loadSeries();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            importMode == 'merge'
                ? 'Coin Collection Merged'
                : 'Coin Collection Replaced',
          ),
          content: Text(
            importMode == 'merge'
                ? 'Saved $savedCount coin entries.\n'
                    'New workbook entries added: $addedCount\n'
                    'Existing matching entries preserved: $preservedCount\n\n'
                    'Existing storage locations were left unchanged.'
                : 'Saved $savedCount coin entries.\n'
                    'Storage locations: $savedStorageCount',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import spreadsheet: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _openSeries(String seriesName) async {
    if (seriesName.toLowerCase().contains('morgan')) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SeriesDetailScreen(seriesName: seriesName),
        ),
      );

      await _loadSeries();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CoinsScreen(initialSeries: seriesName),
      ),
    );

    await _loadSeries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 90,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
        title: const Text('Coin Series'),
        actions: [
          IconButton(
            tooltip: 'Import Coin Workbook',
            onPressed: (_isLoading || _isImporting) ? null : _importSpreadsheet,
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'Need List',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NeedListScreen()),
              );
            },
            icon: const Icon(Icons.checklist_rounded),
          ),
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
      return const Center(child: CircularProgressIndicator());
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
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Browse your collection the way collectors think about it.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
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
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedDenomination,
                decoration: const InputDecoration(
                  labelText: 'Denomination',
                  prefixIcon: Icon(Icons.filter_alt_outlined),
                ),
                items: _denominations
                    .map(
                      (denomination) => DropdownMenuItem<String>(
                        value: denomination,
                        child: Text(denomination),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedDenomination = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Coin series',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
                child: Text('No coin series match the current filters.'),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleSeries.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              childAspectRatio: 1.15,
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
