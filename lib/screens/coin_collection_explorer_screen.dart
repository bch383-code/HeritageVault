import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../widgets/collection_card.dart';
import 'coins_screen.dart';

class CoinCollectionExplorerScreen extends StatefulWidget {
  const CoinCollectionExplorerScreen({super.key});

  @override
  State<CoinCollectionExplorerScreen> createState() =>
      _CoinCollectionExplorerScreenState();
}

class _CoinCollectionExplorerScreenState
    extends State<CoinCollectionExplorerScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  CollectionSummary? _summary;
  List<CategoryProgress> _categories = const [];
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _loadExplorer();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExplorer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<Object>([
        _databaseHelper.getCollectionSummary(),
        _databaseHelper.getCategoryProgress(),
      ]);

      if (!mounted) return;

      setState(() {
        _summary = results[0] as CollectionSummary;
        _categories = results[1] as List<CategoryProgress>;
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

  List<CategoryProgress> get _visibleCategories {
    final query = _searchText.trim().toLowerCase();
    if (query.isEmpty) return _categories;

    return _categories
        .where((category) => category.category.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _openCoins({String? category, String? status}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CoinsScreen(
          initialCategory: category,
          initialStatus: status,
        ),
      ),
    );

    await _loadExplorer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coin Collection Explorer'),
        actions: [
          IconButton(
            tooltip: 'Refresh collection',
            onPressed: _isLoading ? null : _loadExplorer,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadExplorer,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
if (_isLoading) {
  return ListView(
    physics: AlwaysScrollableScrollPhysics(),
    children: [
      SizedBox(height: 240),
      Center(
        child: CircularProgressIndicator(),
      ),
    ],
  );
}

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.error_outline,
            size: 52,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'The coin collection could not be loaded.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: _loadExplorer,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ),
        ],
      );
    }

    final summary = _summary;
    if (summary == null || summary.total == 0) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 140),
          const Icon(Icons.monetization_on_outlined, size: 64),
          const SizedBox(height: 16),
          Text(
            'No coin collection has been imported yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Return to Overview and import your coin spreadsheet.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final completionPercent = (summary.completionRate * 100).round();
    final visibleCategories = _visibleCategories;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
      children: [
        Text(
          'United States Coins',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a category to view its checklist, or open the coins you still need.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 22),
        _buildSummaryPanel(summary, completionPercent),
        const SizedBox(height: 18),
        _buildQuickActions(summary),
        const SizedBox(height: 24),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Find a coin category',
            hintText: 'Examples: Cents, Dollars, Proofs',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchText.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchText = '');
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onChanged: (value) => setState(() => _searchText = value),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Coin categories',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text('${visibleCategories.length} shown'),
          ],
        ),
        const SizedBox(height: 14),
        if (visibleCategories.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text('No coin categories match that search.'),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleCategories.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              childAspectRatio: 1.65,
            ),
            itemBuilder: (context, index) {
              final category = visibleCategories[index];

              return CollectionCard(
                title: category.category,
                owned: category.owned,
                needed: category.needed,
                untracked: category.untracked,
                icon: _iconForCategory(category.category),
                onTap: () => _openCoins(category: category.category),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSummaryPanel(
    CollectionSummary summary,
    int completionPercent,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.monetization_on_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$completionPercent% complete',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        '${summary.owned} owned of '
                        '${summary.owned + summary.needed} tracked coins',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: summary.completionRate,
              minHeight: 10,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                _SummaryCount(label: 'Cataloged', value: summary.total),
                _SummaryCount(label: 'Owned', value: summary.owned),
                _SummaryCount(label: 'Need', value: summary.needed),
                _SummaryCount(label: 'Untracked', value: summary.untracked),
                _SummaryCount(label: 'Categories', value: summary.categories),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(CollectionSummary summary) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: summary.needed == 0
              ? null
              : () => _openCoins(status: 'Need'),
          icon: const Icon(Icons.star_outline),
          label: Text('View Needed (${summary.needed})'),
        ),
        OutlinedButton.icon(
          onPressed: () => _openCoins(),
          icon: const Icon(Icons.list_alt_outlined),
          label: const Text('Browse All Coins'),
        ),
        OutlinedButton.icon(
          onPressed: summary.untracked == 0
              ? null
              : () => _openCoins(status: 'Untracked'),
          icon: const Icon(Icons.rule_folder_outlined),
          label: Text('Review Untracked (${summary.untracked})'),
        ),
      ],
    );
  }

  IconData _iconForCategory(String category) {
    final normalized = category.toLowerCase();

    if (normalized.contains('proof')) {
      return Icons.workspace_premium_outlined;
    }
    if (normalized.contains('set')) {
      return Icons.grid_view_outlined;
    }
    if (normalized.contains('dollar')) {
      return Icons.paid_outlined;
    }
    if (normalized.contains('cent')) {
      return Icons.circle_outlined;
    }
    if (normalized.contains('silver')) {
      return Icons.brightness_5_outlined;
    }

    return Icons.monetization_on_outlined;
  }
}

class _SummaryCount extends StatelessWidget {
  final String label;
  final int value;

  const _SummaryCount({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        Text(label),
      ],
    );
  }
}
