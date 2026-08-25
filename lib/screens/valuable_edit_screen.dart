import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/valuable.dart';

class ValuableEditScreen extends StatefulWidget {
  final Valuable? valuable;

  const ValuableEditScreen({
    super.key,
    this.valuable,
  });

  @override
  State<ValuableEditScreen> createState() => _ValuableEditScreenState();
}

class _ValuableEditScreenState extends State<ValuableEditScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _yearController;
  late final TextEditingController _acquiredFromController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _estimatedValueController;
  late final TextEditingController _notesController;

  late List<String> _imagePaths;
  bool _isSaving = false;

  bool get _isEditing => widget.valuable?.id != null;

  @override
  void initState() {
    super.initState();
    final valuable = widget.valuable;

    _titleController = TextEditingController(text: valuable?.title ?? '');
    _descriptionController =
        TextEditingController(text: valuable?.description ?? '');
    _yearController = TextEditingController(text: valuable?.year ?? '');
    _acquiredFromController =
        TextEditingController(text: valuable?.acquiredFrom ?? '');
    _purchasePriceController = TextEditingController(
      text: valuable?.purchasePrice?.toStringAsFixed(2) ?? '',
    );
    _estimatedValueController = TextEditingController(
      text: valuable?.estimatedValue?.toStringAsFixed(2) ?? '',
    );
    _notesController = TextEditingController(text: valuable?.notes ?? '');
    _imagePaths = List<String>.from(valuable?.imagePaths ?? const []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _yearController.dispose();
    _acquiredFromController.dispose();
    _purchasePriceController.dispose();
    _estimatedValueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double? _parseMoney(String value) {
    final cleaned = value
        .replaceAll(r'$', '')
        .replaceAll(',', '')
        .trim();

    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _addImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: false,
    );

    if (result == null || result.isEmpty) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      path.join(
        documentsDirectory.path,
        'Heirloom Atlas',
        'Valuables',
        'Images',
      ),
    );

    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }

    final copied = <String>[];

    for (final pickedFile in result) {
      final sourcePath = pickedFile.path;
      if (sourcePath == null || sourcePath.isEmpty) continue;

      final extension = path.extension(sourcePath);
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final destination = path.join(
        imageDirectory.path,
        'valuable_${timestamp}_${copied.length}$extension',
      );

      await File(sourcePath).copy(destination);
      copied.add(destination);
    }

    if (!mounted || copied.isEmpty) return;
    setState(() => _imagePaths.addAll(copied));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final valuable = Valuable(
        id: widget.valuable?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        year: _yearController.text.trim(),
        acquiredFrom: _acquiredFromController.text.trim(),
        purchasePrice: _parseMoney(_purchasePriceController.text),
        estimatedValue: _parseMoney(_estimatedValueController.text),
        notes: _notesController.text.trim(),
        imagePaths: _imagePaths,
      );

      await _databaseHelper.createDatabaseBackup(
        reason: _isEditing ? 'before_valuable_update' : 'before_valuable_add',
      );

      if (_isEditing) {
        await _databaseHelper.updateValuable(valuable);
      } else {
        await _databaseHelper.insertValuable(valuable);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save valuable: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final valuable = widget.valuable;
    if (valuable?.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete valuable?'),
        content: const Text(
          'This removes the valuable record from Heirloom Atlas. '
          'Copied image files will remain in the Valuables image folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _databaseHelper.createDatabaseBackup(
      reason: 'before_valuable_delete',
    );
    await _databaseHelper.deleteValuable(valuable!.id!);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _imagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Photos',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _addImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add Photos'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_imagePaths.isEmpty)
          Container(
            height: 180,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined, size: 54),
                SizedBox(height: 8),
                Text('No photos added yet'),
              ],
            ),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _imagePaths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final imagePath = _imagePaths[index];
                final file = File(imagePath);

                return SizedBox(
                  width: 260,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        file.existsSync()
                            ? Image.file(file, fit: BoxFit.cover)
                            : const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton.filledTonal(
                            tooltip: 'Remove from record',
                            onPressed: () {
                              setState(() => _imagePaths.removeAt(index));
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Valuable' : 'Add Valuable'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete Valuable',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _imagesSection(),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'Optional short name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _yearController,
                          decoration: const InputDecoration(
                            labelText: 'Year / Date',
                            hintText: '1950, c. 1900, Unknown...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _acquiredFromController,
                          decoration: const InputDecoration(
                            labelText: 'Where Acquired',
                            hintText: 'Estate sale, family, auction...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Purchase Price',
                            prefixText: '\$',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return null;
                            return _parseMoney(text) == null
                                ? 'Enter a valid amount'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _estimatedValueController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Estimated Value',
                            prefixText: '\$',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return null;
                            return _parseMoney(text) == null
                                ? 'Enter a valid amount'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'Saving...' : 'Save Valuable'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

