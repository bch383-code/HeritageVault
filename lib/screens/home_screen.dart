import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/custom_collection.dart';
import '../screens/custom_collection_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenCollections;

  const HomeScreen({
    super.key,
    this.onOpenCollections,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _loading = true;
  List<CustomCollection> _customCollections = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final collections = await _databaseHelper.getCustomCollections();
      collections.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      if (!mounted) return;

      setState(() {
        _customCollections = collections;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openCustomCollection(CustomCollection collection) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomCollectionScreen(
          collection: collection,
        ),
      ),
    );

    await _load();
  }

  IconData _iconForKey(String key) {
    switch (key) {
      case 'collections':
        return Icons.collections_bookmark_outlined;
      case 'sports':
        return Icons.sports_baseball_outlined;
      case 'military':
        return Icons.military_tech_outlined;
      case 'jewelry':
        return Icons.diamond_outlined;
      case 'book':
        return Icons.menu_book_outlined;
      case 'tools':
        return Icons.handyman_outlined;
      case 'art':
        return Icons.palette_outlined;
      case 'star':
        return Icons.star_outline;
      case 'archive':
        return Icons.archive_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
          sliver: SliverToBoxAdapter(
            child: _buildHero(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  'Your Heritage',
                  'Start with the people and photographs at the heart of the vault.',
                ),
                const SizedBox(height: 14),
                _buildHeritageCards(),
                const SizedBox(height: 32),
                _sectionTitle(
                  'Collections',
                  'Browse the objects, records, and keepsakes you are preserving.',
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else
                  _buildCollections(),
                const SizedBox(height: 32),
                _sectionTitle(
                  'Quick Start',
                  'Common places to continue working in Heritage Vault.',
                ),
                const SizedBox(height: 14),
                _buildQuickStart(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 16 / 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/family_heritage_banner.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_not_supported_outlined, size: 48),
                      SizedBox(height: 10),
                      Text('Home banner image not found'),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildHeritageCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep Photos, Coin Series, and Family Tree on one row.
        final width = (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _largeFeatureCard(
              width: width,
              icon: Icons.photo_library_outlined,
              title: 'Photos',
              subtitle:
                  'Browse your family photo archive, people, metadata, and face recognition.',
              note: 'Open Photos from the left sidebar',
            ),
            _largeFeatureCard(
              width: width,
              icon: Icons.monetization_on_outlined,
              title: 'Coin Series',
              subtitle:
                  'Explore your coin series, collection checklists, and collecting progress.',
              note: 'Open Coin Series from All Collections',
              onTap: widget.onOpenCollections,
            ),
            _largeFeatureCard(
              width: width,
              icon: Icons.account_tree_outlined,
              title: 'Family Tree',
              subtitle:
                  'Connect generations and build the family relationships behind your archive.',
              note: 'Family Tree workspace',
            ),
          ],
        );
      },
    );
  }

  Widget _largeFeatureCard({
    required double width,
    required IconData icon,
    required String title,
    required String subtitle,
    required String note,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 34),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Text(subtitle),
                    const SizedBox(height: 12),
                    Text(
                      note,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollections() {
    final builtIn = <({String name, IconData icon})>[
      (name: 'Coins', icon: Icons.monetization_on_outlined),
      (name: 'Antiques', icon: Icons.inventory_2_outlined),
      (name: 'Postcards', icon: Icons.markunread_mailbox_outlined),
      (name: 'Valuables', icon: Icons.diamond_outlined),
      (name: 'Documents', icon: Icons.description_outlined),
      (name: 'Stories', icon: Icons.menu_book_outlined),
    ];

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final item in builtIn)
          _collectionTile(
            name: item.name,
            icon: item.icon,
            onTap: widget.onOpenCollections,
          ),
        for (final collection in _customCollections)
          _collectionTile(
            name: collection.name,
            icon: _iconForKey(collection.iconKey),
            onTap: () => _openCustomCollection(collection),
          ),
      ],
    );
  }

  Widget _collectionTile({
    required String name,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: 205,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 32),
                const SizedBox(height: 16),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStart() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: widget.onOpenCollections,
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('All Collections'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Open Photos from the left sidebar.'),
              ),
            );
          },
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Photos'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Open Family Tree from the left sidebar.'),
              ),
            );
          },
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('Family Tree'),
        ),
      ],
    );
  }
}
