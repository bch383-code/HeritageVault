import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';

class CoinsScreen extends StatefulWidget {
  const CoinsScreen({super.key});

  @override
  State<CoinsScreen> createState() => _CoinsScreenState();
}

class _CoinsScreenState extends State<CoinsScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  List<ImportedCoin> _coins = [];
  List<String> _categories = [];
  String? _selectedStatus;
  String? _selectedCategory;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final coins = await _databaseHelper.getImportedCoins(
        status: _selectedStatus,
        category: _selectedCategory,
        searchText: _searchController.text,
      );
      final categories = await _databaseHelper.getImportedCategories();

      if (!mounted) {
        return;
      }

      setState(() {
        _coins = coins;
        _categories = categories;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load collection: $error')),
      );
    }
  }

  Future<void> _toggleStatus(ImportedCoin coin) async {
    final newStatus = coin.isNeeded ? 'Owned' : 'Need';

    await _databaseHelper.updateImportedCoinStatus(
      coin: coin,
      newStatus: newStatus,
    );

    await _loadData();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${coin.displayName} marked $newStatus.'),
      ),
    );
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus = null;
      _selectedCategory = null;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coin Collection'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search year, mint, variety, series, binder, or notes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _loadData();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadData(),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String?>(
                  segments: const [
                    ButtonSegment<String?>(
                      value: null,
                      label: Text('All'),
                    ),
                    ButtonSegment<String?>(
                      value: 'Need',
                      icon: Icon(Icons.star_outline),
                      label: Text('Needed'),
                    ),
                    ButtonSegment<String?>(
                      value: 'Owned',
                      icon: Icon(Icons.check_circle_outline),
                      label: Text('Owned'),
                    ),
                  ],
                  selected: {_selectedStatus},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _selectedStatus = selection.first;
                    });
                    _loadData();
                  },
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All categories'),
                      ),
                      ..._categories.map(
                        (category) => DropdownMenuItem<String?>(
                          value: category,
                          child: Text(category),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value;
                      });
                      _loadData();
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear'),
                ),
                Text('${_coins.length} coins'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_coins.isEmpty) {
      return const Center(
        child: Text(
          'No imported coins found.\nImport your spreadsheet from the home screen.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: _coins.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final coin = _coins[index];
        final subtitleParts = <String>[
          coin.category,
          if (coin.series.isNotEmpty) coin.series,
          if (coin.storageLocation.isNotEmpty)
            'Storage: ${coin.storageLocation}',
          if (coin.notes.isNotEmpty) coin.notes,
        ];

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                coin.isNeeded
                    ? Icons.star_outline
                    : Icons.check_circle_outline,
              ),
            ),
            title: Text(
              coin.displayName.isEmpty
                  ? 'Unnamed coin'
                  : coin.displayName,
            ),
            subtitle: Text(subtitleParts.join(' • ')),
            trailing: FilledButton.tonalIcon(
              onPressed: () => _toggleStatus(coin),
              icon: Icon(
                coin.isNeeded ? Icons.add_task : Icons.undo,
              ),
              label: Text(
                coin.isNeeded ? 'Mark Owned' : 'Mark Needed',
              ),
            ),
          ),
        );
      },
    );
  }
}
