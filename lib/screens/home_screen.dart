import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/coin_import_service.dart';
import '../widgets/collection_card.dart';
import 'coins_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenCollections;

  const HomeScreen({super.key, this.onOpenCollections});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CoinImportService _importService = CoinImportService();
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isImporting = false;
  bool _isLoadingDashboard = true;
  CollectionSummary _summary = const CollectionSummary(
    total: 0,
    owned: 0,
    needed: 0,
    untracked: 0,
    categories: 0,
  );
  List<CategoryProgress> _categoryProgress = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    try {
      final summary = await _databaseHelper.getCollectionSummary();
      final progress = await _databaseHelper.getCategoryProgress();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _categoryProgress = progress;
        _isLoadingDashboard = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingDashboard = false);
    }
  }

  Future<void> _importSpreadsheet() async {
    setState(() => _isImporting = true);

    try {
      final result = await _importService.chooseAndReadWorkbook();
      if (!mounted || result == null) return;

      final shouldImport = await _showImportPreview(result);
      if (!mounted || shouldImport != true) return;

      await _databaseHelper.createDatabaseBackup(
        reason: 'before_spreadsheet_import',
      );
      final savedCount = await _databaseHelper.replaceImportedCoins(
        result.coins,
      );
      final savedStorageCount = await _databaseHelper.replaceStorageLocations(
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
      await _loadDashboard();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Collection Imported'),
          content: Text(
            'Saved $savedCount collection entries.\n'
            'Storage locations: $savedStorageCount\n\n'
            'Owned: ${result.ownedCount}\n'
            'Needed: ${result.neededCount}\n'
            'Untracked: ${result.untrackedCount}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _openCoins();
              },
              child: const Text('View Coins'),
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
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<bool?> _showImportPreview(CoinImportResult result) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import Preview'),
        content: SizedBox(
          width: 650,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.fileName),
              const SizedBox(height: 8),
              Text(
                '${result.trackedCount} collection entries across '
                '${result.categories.length} categories\n'
                '${result.storageLocations.length} storage locations found',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Divider(),
              Expanded(
                child: ListView.separated(
                  itemCount: result.categories.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final category = result.categories[index];
                    return ListTile(
                      dense: true,
                      title: Text(category.category),
                      subtitle: Text(
                        'Owned ${category.owned}  •  '
                        'Need ${category.needed}  •  '
                        'Untracked ${category.untracked}',
                      ),
                      trailing: Text('${category.total}'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.download_done),
            label: const Text('Import All'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCoins({String? status, String? category}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CoinsScreen(
          initialStatus: status,
          initialCategory: category,
        ),
      ),
    );
    await _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 10),
          sliver: SliverToBoxAdapter(
            child: _buildHero(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 14, 28, 32),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoadingDashboard)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _buildSummaryCards(),
                  const SizedBox(height: 24),
                  _buildQuickActions(),
                  const SizedBox(height: 28),
                  _buildCategoryProgress(),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _isImporting ? null : _importSpreadsheet,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(
                    _isImporting
                        ? 'Reading Collection...'
                        : 'Import Coin Spreadsheet',
                  ),
                ),
                const SizedBox(height: 16),
                _buildOtherCollections(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.tertiary],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Heritage Vault',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A living museum for your family collections and history.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.onPrimary.withValues(alpha: 0.9),
                      ),
                ),
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  onPressed: widget.onOpenCollections,
                  icon: const Icon(Icons.collections_bookmark_outlined),
                  label: const Text('Explore Collections'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Icon(
            Icons.account_balance_outlined,
            size: 88,
            color: colors.onPrimary.withValues(alpha: 0.86),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final percent = (_summary.completionRate * 100).toStringAsFixed(1);
    final cards = [
      ('Cataloged', _summary.total, Icons.inventory_2_outlined, null),
      ('Owned', _summary.owned, Icons.check_circle_outline, 'Owned'),
      ('Needed', _summary.needed, Icons.star_outline, 'Need'),
      ('Untracked', _summary.untracked, Icons.radio_button_unchecked, 'Untracked'),
      ('Categories', _summary.categories, Icons.category_outlined, null),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: cards.map((item) {
            return SizedBox(
              width: 180,
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: item.$4 == null
                      ? null
                      : () => _openCoins(status: item.$4),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.$3, size: 30),
                        const SizedBox(height: 12),
                        Text(
                          '${item.$2}',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(item.$1),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.insights_outlined),
                    const SizedBox(width: 10),
                    Text(
                      'Tracked collection completion: $percent%',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _summary.completionRate),
                const SizedBox(height: 8),
                const Text('Completion is based on entries marked Owned or Need.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: () => _openCoins(status: 'Need'),
          icon: const Icon(Icons.star_outline),
          label: const Text('View Needed Coins'),
        ),
        OutlinedButton.icon(
          onPressed: _openCoins,
          icon: const Icon(Icons.monetization_on_outlined),
          label: const Text('Browse All Coins'),
        ),
        OutlinedButton.icon(
          onPressed: () => _openCoins(status: 'Untracked'),
          icon: const Icon(Icons.rule_folder_outlined),
          label: const Text('Review Untracked'),
        ),
      ],
    );
  }

  Widget _buildCategoryProgress() {
    if (_categoryProgress.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Import your spreadsheet to see category progress.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Collection explorer',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose a coin category to view its checklist and collection progress.',
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _categoryProgress.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 420,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.65,
          ),
          itemBuilder: (context, index) {
            final category = _categoryProgress[index];

            return CollectionCard(
              title: category.category,
              owned: category.owned,
              needed: category.needed,
              untracked: category.untracked,
              icon: Icons.monetization_on_outlined,
              onTap: () => _openCoins(category: category.category),
            );
          },
        ),
      ],
    );
  }

  Widget _buildOtherCollections() {
    final items = [
      ('Photos', Icons.photo_library_outlined),
      ('Documents', Icons.description_outlined),
      ('Family Tree', Icons.account_tree_outlined),
      ('Antiques', Icons.chair_outlined),
      ('Stories', Icons.menu_book_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Future collections',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((item) {
            return SizedBox(
              width: 190,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(item.$2),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item.$1)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
