import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/custom_collection.dart';
import '../screens/custom_collection_builder_screen.dart';
import '../screens/custom_collection_screen.dart';

final ValueNotifier<int> _customCollectionsRefresh = ValueNotifier<int>(0);

IconData _customCollectionIconFromKey(String key) {
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

class CustomCollectionsSidebar extends StatefulWidget {
  const CustomCollectionsSidebar({super.key});

  @override
  State<CustomCollectionsSidebar> createState() =>
      _CustomCollectionsSidebarState();
}

class _CustomCollectionsSidebarState extends State<CustomCollectionsSidebar> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  List<CustomCollection> _collections = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _customCollectionsRefresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _customCollectionsRefresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final collections = await _databaseHelper.getCustomCollections();
    collections.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (!mounted) return;

    setState(() {
      _collections = collections;
      _loading = false;
    });
  }

  Future<void> _openCollection(CustomCollection collection) async {
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

  @override
  Widget build(BuildContext context) {
    const textColor = Color(0xFFD8E4F0);
    const mutedColor = Color(0xFF91A9BF);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    if (_collections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(46, 4, 10, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'No custom collections yet',
            style: TextStyle(
              color: mutedColor,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final collection in _collections)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _openCollection(collection),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _customCollectionIconFromKey(collection.iconKey),
                        size: 20,
                        color: mutedColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          collection.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AddCollectionSidebarButton extends StatelessWidget {
  const AddCollectionSidebarButton({super.key});

  Future<void> _addCollection(BuildContext context) async {
    final created = await Navigator.push<CustomCollection>(
      context,
      MaterialPageRoute(
        builder: (context) => const CustomCollectionBuilderScreen(),
      ),
    );

    if (created == null) return;

    _customCollectionsRefresh.value++;

    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomCollectionScreen(
          collection: created,
        ),
      ),
    );

    _customCollectionsRefresh.value++;
  }

  @override
  Widget build(BuildContext context) {
    const antiqueGold = Color(0xFFC9A65A);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _addCollection(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 22,
                  color: antiqueGold,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Add Collection',
                    style: TextStyle(
                      color: antiqueGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
