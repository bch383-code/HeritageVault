import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/postcard.dart';

class PostcardEditScreen extends StatefulWidget {
  final Postcard? postcard;

  const PostcardEditScreen({
    super.key,
    this.postcard,
  });

  @override
  State<PostcardEditScreen> createState() => _PostcardEditScreenState();
}

class _PostcardEditScreenState extends State<PostcardEditScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _yearController;
  late final TextEditingController _acquiredFromController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _estimatedValueController;
  late final TextEditingController _notesController;

  String _frontImagePath = '';
  String _backImagePath = '';
  bool _isSaving = false;

  bool get _isEditing => widget.postcard?.id != null;

  @override
  void initState() {
    super.initState();
    final postcard = widget.postcard;

    _titleController = TextEditingController(text: postcard?.title ?? '');
    _descriptionController =
        TextEditingController(text: postcard?.description ?? '');
    _yearController = TextEditingController(text: postcard?.year ?? '');
    _acquiredFromController =
        TextEditingController(text: postcard?.acquiredFrom ?? '');
    _purchasePriceController = TextEditingController(
      text: postcard?.purchasePrice?.toStringAsFixed(2) ?? '',
    );
    _estimatedValueController = TextEditingController(
      text: postcard?.estimatedValue?.toStringAsFixed(2) ?? '',
    );
    _notesController = TextEditingController(text: postcard?.notes ?? '');
    _frontImagePath = postcard?.frontImagePath ?? '';
    _backImagePath = postcard?.backImagePath ?? '';
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

  Future<String?> _pickAndCopyImage(String side) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );

    if (result == null || result.isEmpty) return null;

    final sourcePath = result.single.path;
    if (sourcePath == null || sourcePath.isEmpty) return null;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      path.join(
        documentsDirectory.path,
        'Heirloom Atlas',
        'Postcards',
        'Images',
      ),
    );

    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }

    final extension = path.extension(sourcePath);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final destination = path.join(
      imageDirectory.path,
      'postcard_${timestamp}_$side$extension',
    );

    await File(sourcePath).copy(destination);
    return destination;
  }

  Future<void> _pickFrontImage() async {
    final copiedPath = await _pickAndCopyImage('front');
    if (copiedPath == null || !mounted) return;
    setState(() => _frontImagePath = copiedPath);
  }

  Future<void> _pickBackImage() async {
    final copiedPath = await _pickAndCopyImage('back');
    if (copiedPath == null || !mounted) return;
    setState(() => _backImagePath = copiedPath);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final postcard = Postcard(
        id: widget.postcard?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        year: _yearController.text.trim(),
        acquiredFrom: _acquiredFromController.text.trim(),
        purchasePrice: _parseMoney(_purchasePriceController.text),
        estimatedValue: _parseMoney(_estimatedValueController.text),
        frontImagePath: _frontImagePath,
        backImagePath: _backImagePath,
        notes: _notesController.text.trim(),
      );

      await _databaseHelper.createDatabaseBackup(
        reason: _isEditing ? 'before_postcard_update' : 'before_postcard_add',
      );

      if (_isEditing) {
        await _databaseHelper.updatePostcard(postcard);
      } else {
        await _databaseHelper.insertPostcard(postcard);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save postcard: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final postcard = widget.postcard;
    if (postcard?.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete postcard?'),
        content: const Text(
          'This removes the postcard record from Heirloom Atlas. '
          'The copied image files will be left in the Postcards image folder.',
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
      reason: 'before_postcard_delete',
    );
    await _databaseHelper.deletePostcard(postcard!.id!);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _imagePanel({
    required String label,
    required String imagePath,
    required VoidCallback onPick,
  }) {
    final file = imagePath.trim().isEmpty ? null : File(imagePath);
    final exists = file != null && file.existsSync();

    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                child: exists
                    ? Image.file(
                        file,
                        fit: BoxFit.contain,
                      )
                    : const Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 64,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(exists ? 'Replace' : 'Choose Image'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Postcard' : 'Add Postcard'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete Postcard',
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
                  SizedBox(
                    height: 340,
                    child: Row(
                      children: [
                        _imagePanel(
                          label: 'Front',
                          imagePath: _frontImagePath,
                          onPick: _pickFrontImage,
                        ),
                        const SizedBox(width: 16),
                        _imagePanel(
                          label: 'Back',
                          imagePath: _backImagePath,
                          onPick: _pickBackImage,
                        ),
                      ],
                    ),
                  ),
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
                            hintText: '1912, c. 1910, Unknown...',
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
                            hintText: 'Antique shop, estate sale, family...',
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'Saving...' : 'Save Postcard'),
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

