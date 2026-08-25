import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/custom_collection.dart';
import '../models/custom_collection_item.dart';
import 'custom_collection_item_edit_screen.dart';

class CustomCollectionScreen extends StatefulWidget {
  final CustomCollection collection;

  const CustomCollectionScreen({
    super.key,
    required this.collection,
  });

  @override
  State<CustomCollectionScreen> createState() => _CustomCollectionScreenState();
}

class _CustomCollectionScreenState extends State<CustomCollectionScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  List<CustomCollectionItem> _items = const [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.collection.id;
    if (id == null) return;

    final results = await Future.wait([
      _databaseHelper.getCustomCollectionItems(id),
      _databaseHelper.getCustomCollections(),
    ]);

    if (!mounted) return;

    setState(() {
      _items = results[0] as List<CustomCollectionItem>;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomCollectionItemEditScreen(
          collection: widget.collection,
        ),
      ),
    );

    if (changed == true) await _load();
  }

  Future<void> _editItem(CustomCollectionItem item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomCollectionItemEditScreen(
          collection: widget.collection,
          item: item,
        ),
      ),
    );

    if (changed == true) await _load();
  }

  Future<void> _deleteItem(CustomCollectionItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove item?'),
        content: Text(
          'Remove "${item.title}" from Heirloom Atlas? '
          'Linked photos and documents will not be deleted from your computer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove Item'),
          ),
        ],
      ),
    );

    if (confirmed != true || item.id == null) return;

    await _databaseHelper.deleteCustomCollectionItem(item.id!);
    await _load();
  }

  Future<void> _moveItem(CustomCollectionItem item) async {
    // Reload collections at the moment Move is opened so the list cannot
    // be stale if another collection was created after this screen opened.
    final allCollections =
        await _databaseHelper.getCustomCollections();

    if (!mounted) return;

    final currentId = widget.collection.id;
    final currentName = widget.collection.name.trim().toLowerCase();

    final destinations = allCollections.where((collection) {
      final sameScreenCollection =
          currentId != null && collection.id == currentId;
      final sameItemCollection =
          collection.id != null && collection.id == item.collectionId;
      final sameName =
          collection.name.trim().toLowerCase() == currentName;

      return collection.id != null &&
          !sameScreenCollection &&
          !sameItemCollection &&
          !sameName;
    }).toList();

    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No other custom collections are available. '
            'Create another custom collection before moving this item.',
          ),
        ),
      );
      return;
    }

    CustomCollection selected = destinations.first;

    final destination = await showDialog<CustomCollection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Move to Collection'),
          content: DropdownButtonFormField<int>(
            initialValue: selected.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Destination',
              border: OutlineInputBorder(),
            ),
            items: destinations
                .map(
                  (collection) => DropdownMenuItem<int>(
                    value: collection.id!,
                    child: Text(collection.name),
                  ),
                )
                .toList(),
            onChanged: (id) {
              if (id == null) return;

              final match = destinations.firstWhere(
                (collection) => collection.id == id,
              );

              setDialogState(() => selected = match);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                selected,
              ),
              child: const Text('Move Item'),
            ),
          ],
        ),
      ),
    );

    if (destination == null ||
        item.id == null ||
        destination.id == null) {
      return;
    }

    await _databaseHelper.moveCustomCollectionItem(
      itemId: item.id!,
      destinationCollectionId: destination.id!,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"${item.title}" moved to ${destination.name}.',
        ),
      ),
    );

    await _load();
  }


  List<CustomCollectionItem> get _visibleItems {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return _items;

    return _items.where((item) {
      final haystack = [
        item.title,
        ...item.values.values,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collection.name),
        actions: [
          FilledButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text('Add Item'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      hintText: 'Search this collection...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: _visibleItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 72),
                              const SizedBox(height: 16),
                              Text(
                                _items.isEmpty
                                    ? 'No items yet.'
                                    : 'No items match your search.',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (_items.isEmpty) ...[
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _addItem,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add First Item'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _visibleItems.length,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 300,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.88,
                          ),
                          itemBuilder: (context, index) {
                            final item = _visibleItems[index];
                            return _itemCard(item);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _itemCard(CustomCollectionItem item) {
    final imagePath =
        item.photoPaths.isEmpty ? null : item.photoPaths.first;
    final imageFile = imagePath == null ? null : File(imagePath);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editItem(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                child: imageFile != null && imageFile.existsSync()
                    ? Image.file(
                        imageFile,
                        fit: BoxFit.contain,
                        cacheWidth: 600,
                      )
                    : const Center(
                        child: Icon(Icons.inventory_2_outlined, size: 58),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if ((item.values[CustomCollectionField.date] ?? '')
                            .trim()
                            .isNotEmpty)
                          Text(
                            item.values[CustomCollectionField.date]!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if ((item.values[CustomCollectionField.value] ?? '')
                            .trim()
                            .isNotEmpty)
                          Text(
                            'Value: ${item.values[CustomCollectionField.value]}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Item actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editItem(item);
                          break;
                        case 'move':
                          _moveItem(item);
                          break;
                        case 'delete':
                          _deleteItem(item);
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'move',
                        child: ListTile(
                          leading: Icon(Icons.drive_file_move_outline),
                          title: Text('Move to Collection'),
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Remove Item'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
