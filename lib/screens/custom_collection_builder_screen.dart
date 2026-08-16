import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/custom_collection.dart';

const _customCollectionIconKeys = <String>[
  'inventory','collections','sports','military','jewelry',
  'book','tools','art','star','archive',
];

IconData _customCollectionIconFromKey(String key) {
  switch (key) {
    case 'collections': return Icons.collections_bookmark_outlined;
    case 'sports': return Icons.sports_baseball_outlined;
    case 'military': return Icons.military_tech_outlined;
    case 'jewelry': return Icons.diamond_outlined;
    case 'book': return Icons.menu_book_outlined;
    case 'tools': return Icons.handyman_outlined;
    case 'art': return Icons.palette_outlined;
    case 'star': return Icons.star_outline;
    case 'archive': return Icons.archive_outlined;
    default: return Icons.inventory_2_outlined;
  }
}

String _customCollectionIconLabel(String key) {
  switch (key) {
    case 'collections': return 'Collection';
    case 'sports': return 'Sports';
    case 'military': return 'Military';
    case 'jewelry': return 'Jewelry';
    case 'book': return 'Books';
    case 'tools': return 'Tools';
    case 'art': return 'Art';
    case 'star': return 'Favorites';
    case 'archive': return 'Archive';
    default: return 'General';
  }
}


class CustomCollectionBuilderScreen extends StatefulWidget {
  const CustomCollectionBuilderScreen({super.key});

  @override
  State<CustomCollectionBuilderScreen> createState() =>
      _CustomCollectionBuilderScreenState();
}

class _CustomCollectionBuilderScreenState
    extends State<CustomCollectionBuilderScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _nameController = TextEditingController();

  String _iconKey = 'inventory';
  final Set<String> _fields = {...CustomCollectionField.defaults};
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a collection name.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final fields = CustomCollectionField.all
          .where(_fields.contains)
          .toList();

      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final id = await _databaseHelper.insertCustomCollection(
        CustomCollection(
          name: name,
          iconKey: _iconKey,
          enabledFields: fields,
          createdAtMilliseconds: createdAt,
        ),
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        CustomCollection(
          id: id,
          name: name,
          iconKey: _iconKey,
          enabledFields: fields,
          createdAtMilliseconds: createdAt,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create collection: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Collection')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Text(
                'New Custom Collection',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a name, icon, and the information each item should contain.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Collection Name',
                  hintText: 'Baseball Cards, Military Memorabilia, Tools...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Icon',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in _customCollectionIconKeys)
                    ChoiceChip(
                      selected: _iconKey == key,
                      avatar: Icon(_customCollectionIconFromKey(key), size: 20),
                      label: Text(_customCollectionIconLabel(key)),
                      onSelected: (_) => setState(() => _iconKey = key),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'Item Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              const Text('Title is always included. Choose the rest.'),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    for (final field in CustomCollectionField.all)
                      CheckboxListTile(
                        value: field == CustomCollectionField.title ||
                            _fields.contains(field),
                        onChanged: field == CustomCollectionField.title
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _fields.add(field);
                                  } else {
                                    _fields.remove(field);
                                  }
                                });
                              },
                        title: Text(CustomCollectionField.label(field)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.add),
                label: Text(_saving ? 'Creating...' : 'Create Collection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
