import 'dart:async';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';
import 'coin_detail_screen.dart';

class CoinsScreen extends StatefulWidget {
  final String? initialStatus;
  final String? initialCategory;
  final String? initialSearchText;

  const CoinsScreen({
    super.key,
    this.initialStatus,
    this.initialCategory,
    this.initialSearchText,
  });

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
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatus;
    _selectedCategory = widget.initialCategory;
    _searchController.text = widget.initialSearchText ?? '';
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

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

      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load collection: $error')),
      );
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      _loadData,
    );
  }

  Future<void> _openDetails(ImportedCoin coin) async {
    final updatedCoin = await Navigator.push<ImportedCoin>(
      context,
      MaterialPageRoute(
        builder: (context) => CoinDetailScreen(coin: coin),
      ),
    );

    if (updatedCoin != null) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coin changes saved.')),
        );
      }
    }
  }

  Future<void> _setStatus(ImportedCoin coin, String newStatus) async {
    await _databaseHelper.createDatabaseBackup(
      reason: 'before_status_change',
    );
    await _databaseHelper.updateImportedCoinStatus(
      coin: coin,
      newStatus: newStatus,
    );
    await _loadData();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {});
    _loadData();
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _selectedStatus = null;
      _selectedCategory = null;
    });
    _loadData();
  }

  IconData _statusIcon(ImportedCoin coin) {
    switch (coin.status) {
      case 'Owned':
        return Icons.check_circle_outline;
      case 'Need':
        return Icons.star_outline;
      default:
        return Icons.radio_button_unchecked;
    }
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
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Search year, mint, variety, series, binder, or notes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                _searchDebounce?.cancel();
                _loadData();
              },
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String?>(
                  segments: const [
                    ButtonSegment<String?>(value: null, label: Text('All')),
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
                    ButtonSegment<String?>(
                      value: 'Untracked',
                      icon: Icon(Icons.radio_button_unchecked),
                      label: Text('Untracked'),
                    ),
                  ],
                  selected: {_selectedStatus},
                  onSelectionChanged: (selection) {
                    setState(() => _selectedStatus = selection.first);
                    _loadData();
                  },
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedCategory,
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
                      setState(() => _selectedCategory = value);
                      _loadData();
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear'),
                ),
                Text('${_coins.length} entries'),
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
          'No matching coin entries found.\n'
          'Import the workbook again to load every category.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      itemCount: _coins.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final coin = _coins[index];
        final subtitleParts = <String>[
          coin.category,
          if (coin.series.isNotEmpty) coin.series,
          'Status: ${coin.status}',
          if (coin.storageLocation.isNotEmpty)
            'Storage: ${coin.storageLocation}',
          if (coin.grade.isNotEmpty) 'Grade: ${coin.grade}',
          if (coin.notes.isNotEmpty) coin.notes,
        ];

        return Card(
          child: ListTile(
            onTap: () => _openDetails(coin),
            leading: CircleAvatar(child: Icon(_statusIcon(coin))),
            title: Text(
              coin.displayName.isEmpty ? 'Unnamed coin' : coin.displayName,
            ),
            subtitle: Text(subtitleParts.join(' • ')),
            trailing: PopupMenuButton<String>(
              tooltip: 'Change status',
              onSelected: (status) => _setStatus(coin, status),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'Need', child: Text('Mark Needed')),
                PopupMenuItem(value: 'Owned', child: Text('Mark Owned')),
                PopupMenuItem(
                  value: 'Untracked',
                  child: Text('Mark Untracked'),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ),
        );
      },
    );
  }
}
