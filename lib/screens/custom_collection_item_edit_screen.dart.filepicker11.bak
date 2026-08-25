import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/custom_collection.dart';
import '../models/custom_collection_item.dart';

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

  @override
  void initState() {
    super.initState();

    final values = widget.item?.values ?? const <String, String>{};

    for (final field in widget.collection.enabledFields) {
      if (field == CustomCollectionField.photos ||
          field == CustomCollectionField.documents) {
        continue;
      }

      _controllers[field] = TextEditingController(
        text: values[field] ?? '',
      );
    }

    _photoPaths = [...?widget.item?.photoPaths];
    _documentPaths = [...?widget.item?.documentPaths];
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
      allowMultiple: true,
      type: FileType.image,
    );

    if (result == null) return;

    final paths = result.files
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
      allowMultiple: true,
      type: FileType.any,
    );

    if (result == null) return;

    final paths = result.files
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final preserved = <String, String>{
        ...?widget.item?.values,
      };

      for (final entry in _controllers.entries) {
        preserved[entry.key] = entry.value.text.trim();
      }

      final item = CustomCollectionItem(
        id: widget.item?.id,
        collectionId: widget.collection.id!,
        values: preserved,
        photoPaths: _photoPaths,
        documentPaths: _documentPaths,
        createdAtMilliseconds:
            widget.item?.createdAtMilliseconds ?? now,
        updatedAtMilliseconds: now,
      );

      if (widget.item == null) {
        await _databaseHelper.insertCustomCollectionItem(item);
      } else {
        await _databaseHelper.updateCustomCollectionItem(item);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save item: $error')),
      );
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
              const SizedBox(height: 10),
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

    final multiline = field == CustomCollectionField.description ||
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
