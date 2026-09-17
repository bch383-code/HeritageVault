import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/custom_collection.dart';
import '../models/custom_collection_item.dart';
import '../models/family_person.dart';
import 'family_person_screen.dart';

class CustomCollectionItemEditScreen extends StatefulWidget {
  final CustomCollection collection;
  final CustomCollectionItem? item;

  const CustomCollectionItemEditScreen({
    super.key,
    required this.collection,
    this.item,
  });

  @override
  State<CustomCollectionItemEditScreen> createState() =>
      _CustomCollectionItemEditScreenState();
}

class _CustomCollectionItemEditScreenState
    extends State<CustomCollectionItemEditScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  final Map<String, TextEditingController> _controllers = {};
  List<String> _photoPaths = [];
  List<String> _documentPaths = [];
  bool _saving = false;
  List<FamilyPerson> _familyPeople = const [];
  Set<int> _selectedFamilyPersonIds = <int>{};

  @override
  void initState() {
    super.initState();

    final values = widget.item?.values ?? const <String, String>{};

    for (final field in widget.collection.enabledFields) {
      if (field == CustomCollectionField.photos ||
          field == CustomCollectionField.documents) {
        continue;
      }

      _controllers[field] = TextEditingController(text: values[field] ?? '');
    }

    _photoPaths = [...?widget.item?.photoPaths];
    _documentPaths = [...?widget.item?.documentPaths];
    _loadFamilyConnections();
  }

  Future<void> _loadFamilyConnections() async {
    final people = await _databaseHelper.getFamilyPeople();
    final itemId = widget.item?.id;
    final linked = itemId == null
        ? <FamilyPerson>[]
        : await _databaseHelper.getFamilyPeopleForItem(
            itemType: 'custom_collection_item',
            itemKey: itemId.toString(),
          );
    if (!mounted) return;
    setState(() {
      _familyPeople = people;
      _selectedFamilyPersonIds = linked
          .map((p) => p.id)
          .whereType<int>()
          .toSet();
    });
  }

  Future<void> _chooseFamilyPeople() async {
    if (_familyPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add people to the Family Tree first.')),
      );
      return;
    }
    final selected = <int>{..._selectedFamilyPersonIds};
    var query = '';
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final visible = _familyPeople
              .where(
                (p) => q.isEmpty || p.displayName.toLowerCase().contains(q),
              )
              .toList();
          return Dialog(
            child: SizedBox(
              width: 700,
              height: 650,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.account_tree_outlined),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Family Connections',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) => setDialogState(() => query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search Family Tree...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: visible.map((person) {
                        final id = person.id!;
                        return CheckboxListTile(
                          value: selected.contains(id),
                          title: Text(person.displayName),
                          secondary: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked ?? false) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text('${selected.length} connected'),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () =>
                              Navigator.pop(dialogContext, selected),
                          icon: const Icon(Icons.check),
                          label: const Text('Use People'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _selectedFamilyPersonIds = result);
  }

  Future<void> _openFamilyPerson(FamilyPerson person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FamilyPersonScreen(person: person)),
    );

    await _loadFamilyConnections();
  }

  Widget _familyConnectionsSection() {
    final selectedPeople = _familyPeople
        .where((p) => p.id != null && _selectedFamilyPersonIds.contains(p.id))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Family Connections',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _chooseFamilyPeople,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    selectedPeople.isEmpty ? 'Choose People' : 'Manage',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect this item to the people who owned it, used it, made it, '
              'inherited it, or are part of its story.',
            ),
            if (selectedPeople.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: selectedPeople
                    .map(
                      (p) => ActionChip(
                        avatar: const Icon(Icons.person_outline, size: 17),
                        label: Text(p.displayName),
                        tooltip: 'Open Family Tree person',
                        onPressed: () => _openFamilyPerson(p),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.pickFiles(
      // Multiple photos are intentionally supported.
      // ignore: deprecated_member_use
      allowMultiple: true,
      type: FileType.image,
    );

    final paths = result
        .map((file) => file.path)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList();

    if (!mounted) return;

    setState(() {
      for (final path in paths) {
        if (!_photoPaths.contains(path)) {
          _photoPaths.add(path);
        }
      }
    });
  }

  Future<void> _pickDocuments() async {
    final result = await FilePicker.pickFiles(
      // Multiple documents are intentionally supported.
      // ignore: deprecated_member_use
      allowMultiple: true,
      type: FileType.any,
    );

    final paths = result
        .map((file) => file.path)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList();

    if (!mounted) return;

    setState(() {
      for (final path in paths) {
        if (!_documentPaths.contains(path)) {
          _documentPaths.add(path);
        }
      }
    });
  }

  Future<void> _save() async {
    final title = _controllers[CustomCollectionField.title]?.text.trim() ?? '';

    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final preserved = <String, String>{...?widget.item?.values};

      for (final entry in _controllers.entries) {
        preserved[entry.key] = entry.value.text.trim();
      }

      final item = CustomCollectionItem(
        id: widget.item?.id,
        collectionId: widget.collection.id!,
        values: preserved,
        photoPaths: _photoPaths,
        documentPaths: _documentPaths,
        createdAtMilliseconds: widget.item?.createdAtMilliseconds ?? now,
        updatedAtMilliseconds: now,
      );

      final int itemId;
      if (widget.item == null) {
        itemId = await _databaseHelper.insertCustomCollectionItem(item);
      } else {
        await _databaseHelper.updateCustomCollectionItem(item);
        itemId = item.id!;
      }

      final existingPeople = await _databaseHelper.getFamilyPeopleForItem(
        itemType: 'custom_collection_item',
        itemKey: itemId.toString(),
      );
      final existingIds = existingPeople
          .map((person) => person.id)
          .whereType<int>()
          .toSet();

      for (final personId in existingIds.difference(_selectedFamilyPersonIds)) {
        await _databaseHelper.unlinkFamilyPersonFromItem(
          personId: personId,
          itemType: 'custom_collection_item',
          itemKey: itemId.toString(),
        );
      }
      for (final personId in _selectedFamilyPersonIds.difference(existingIds)) {
        await _databaseHelper.linkFamilyPersonToItem(
          personId: personId,
          itemType: 'custom_collection_item',
          itemKey: itemId.toString(),
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save item: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.collection.enabledFields;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? 'Add Item' : 'Edit Item'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final field in fields) ...[
                if (field == CustomCollectionField.photos)
                  _fileSection(
                    title: 'Photos',
                    paths: _photoPaths,
                    onAdd: _pickPhotos,
                    onRemove: (path) {
                      setState(() => _photoPaths.remove(path));
                    },
                  )
                else if (field == CustomCollectionField.documents)
                  _fileSection(
                    title: 'Documents / Attachments',
                    paths: _documentPaths,
                    onAdd: _pickDocuments,
                    onRemove: (path) {
                      setState(() => _documentPaths.remove(path));
                    },
                  )
                else
                  _textField(field),
                const SizedBox(height: 14),
              ],
              _familyConnectionsSection(),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save Item'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField(String field) {
    final controller = _controllers[field]!;
    final label = CustomCollectionField.label(field);

    final multiline =
        field == CustomCollectionField.description ||
        field == CustomCollectionField.notes;

    TextInputType keyboardType = TextInputType.text;
    if (field == CustomCollectionField.value ||
        field == CustomCollectionField.quantity) {
      keyboardType = TextInputType.number;
    }

    return TextField(
      controller: controller,
      maxLines: multiline ? 4 : 1,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _fileSection({
    required String title,
    required List<String> paths,
    required VoidCallback onAdd,
    required ValueChanged<String> onRemove,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (paths.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final path in paths)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(
                    path.split(RegExp(r'[\\/]')).last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    onPressed: () => onRemove(path),
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
