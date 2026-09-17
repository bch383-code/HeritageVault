import 'package:flutter/material.dart';

import '../../../database/database_helper.dart';
import '../../../models/custom_collection.dart';
import '../../../screens/custom_collection_screen.dart';

class AllCollectionsScreen extends StatefulWidget {
  final VoidCallback? onOpenCoins;
  final VoidCallback? onOpenPostcards;
  final VoidCallback? onOpenValuables;
  final VoidCallback? onOpenAntiques;
  final VoidCallback? onOpenSportsCards;
  final VoidCallback? onOpenDocuments;
  final VoidCallback? onOpenStories;

  const AllCollectionsScreen({
    super.key,
    this.onOpenCoins,
    this.onOpenPostcards,
    this.onOpenValuables,
    this.onOpenAntiques,
    this.onOpenSportsCards,
    this.onOpenDocuments,
    this.onOpenStories,
  });

  @override
  State<AllCollectionsScreen> createState() => _AllCollectionsScreenState();
}

class _AllCollectionsScreenState extends State<AllCollectionsScreen> {
  static const _navy = Color(0xFF071A2B);
  static const _navy2 = Color(0xFF0A2943);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);
  static const _muted = Color(0xFF9CB0BC);

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _loading = true;
  List<CustomCollection> _customCollections = const [];

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  Future<void> _loadCollections() async {
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
        builder: (context) => CustomCollectionScreen(collection: collection),
      ),
    );

    await _loadCollections();
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 760;

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CollectionMuseumBanner(
                title: 'All Collections',
                subtitle:
                    'Your stories, memories, and keepsakes — all in one place.',
              ),
              SizedBox(height: compact ? 12 : 16),
              _buildActionBar(compact),
              SizedBox(height: compact ? 12 : 16),
              Row(
                children: [
                  Text(
                    'YOUR COLLECTIONS',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _cream,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: _gold.withValues(alpha: .28),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 10 : 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildCollectionGrid(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionBar(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: .78),
        border: Border.all(color: _gold.withValues(alpha: .24), width: .8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _actionButton(
            icon: Icons.add_box_outlined,
            label: 'New Collection',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Use Add Collection in the sidebar.'),
                ),
              );
            },
          ),
          _actionButton(
            icon: Icons.category_outlined,
            label: 'Manage Categories',
            onPressed: null,
          ),
          _actionButton(
            icon: Icons.swap_vert_outlined,
            label: 'Reorder Collections',
            onPressed: null,
          ),
          _actionButton(
            icon: Icons.search,
            label: 'Search Collections',
            onPressed: null,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _cream,
        side: BorderSide(color: _gold.withValues(alpha: .42)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
    );
  }

  Widget _buildCollectionGrid() {
    final items = <_CollectionItem>[
      _CollectionItem(
        name: 'Coins',
        subtitle: 'Coins, sets, storage, and your need list.',
        icon: Icons.monetization_on_outlined,
        onTap: widget.onOpenCoins,
      ),
      _CollectionItem(
        name: 'Sports Cards',
        subtitle: 'Cards, sets, players, teams, and images.',
        icon: Icons.sports_baseball_outlined,
        onTap: widget.onOpenSportsCards,
      ),
      _CollectionItem(
        name: 'Antiques',
        subtitle: 'Inherited objects, identification, history, and value.',
        icon: Icons.inventory_2_outlined,
        onTap: widget.onOpenAntiques,
      ),
      _CollectionItem(
        name: 'Valuables',
        subtitle: 'Important items, provenance, condition, and value.',
        icon: Icons.diamond_outlined,
        onTap: widget.onOpenValuables,
      ),
      _CollectionItem(
        name: 'Postcards',
        subtitle: 'Postcards, places, messages, dates, and people.',
        icon: Icons.markunread_mailbox_outlined,
        onTap: widget.onOpenPostcards,
      ),
      _CollectionItem(
        name: 'Documents',
        subtitle: 'Letters, records, certificates, and family papers.',
        icon: Icons.description_outlined,
        onTap: widget.onOpenDocuments,
      ),
      _CollectionItem(
        name: 'Stories',
        subtitle: 'Memories and stories behind the things you preserve.',
        icon: Icons.menu_book_outlined,
        onTap: widget.onOpenStories,
      ),
      for (final collection in _customCollections)
        _CollectionItem(
          name: collection.name,
          subtitle: 'Custom Heirloom Atlas collection.',
          icon: _iconForKey(collection.iconKey),
          onTap: () => _openCustomCollection(collection),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const minTileWidth = 235.0;
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(2, 4);
        const gap = 12.0;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return SingleChildScrollView(
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(
                  width: tileWidth,
                  height: 118,
                  child: _collectionCard(item),
                ),
              SizedBox(
                width: tileWidth,
                height: 118,
                child: _createCollectionCard(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _collectionCard(_CollectionItem item) {
    final enabled = item.onTap != null;

    return Material(
      color: _navy.withValues(alpha: .72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: _gold.withValues(alpha: .26), width: .8),
      ),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _navy2.withValues(alpha: .88),
                  border: Border.all(color: _gold.withValues(alpha: .36)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(
                  item.icon,
                  color: enabled ? _gold : _muted,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _cream,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _muted,
                            height: 1.25,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: enabled ? _gold.withValues(alpha: .72) : _muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createCollectionCard() {
    return Material(
      color: _navy.withValues(alpha: .40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(
          color: _gold.withValues(alpha: .36),
          width: .8,
        ),
      ),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Use Add Collection in the sidebar.')),
          );
        },
        borderRadius: BorderRadius.circular(3),
        child: const Padding(
          padding: EdgeInsets.all(15),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, color: _gold, size: 32),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create New Collection',
                      style: TextStyle(
                        color: _cream,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Add a collection for anything you preserve.',
                      style: TextStyle(color: _muted, height: 1.25),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CollectionMuseumBanner extends StatelessWidget {
  static const _navy = Color(0xFF071A2B);
  static const _gold = Color(0xFFC9A65A);
  static const _cream = Color(0xFFF3E9D1);

  final String title;
  final String subtitle;

  const CollectionMuseumBanner({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 210,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _gold.withValues(alpha: .42), width: .8),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/collections_decor/all_collections_banner.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) {
              return const ColoredBox(color: _navy);
            },
          ),

          // Keep live Flutter text available for future reusable/dynamic
          // collection banners. The generated All Collections artwork already
          // contains its own title, so this overlay is intentionally hidden
          // on this screen.
          if (title != 'All Collections')
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 28, 390, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 46, height: 1, color: _gold),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: _cream,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .25,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _gold.withValues(alpha: .90),
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CollectionItem {
  final String name;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _CollectionItem({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}
