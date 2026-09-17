import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../database/database_helper.dart';
import '../models/imported_coin.dart';

class CoinDetailScreen extends StatefulWidget {
  final ImportedCoin coin;
  final String? initialImagePath;

  const CoinDetailScreen({
    super.key,
    required this.coin,
    this.initialImagePath,
  });

  @override
  State<CoinDetailScreen> createState() => _CoinDetailScreenState();
}

class _CoinDetailScreenState extends State<CoinDetailScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  late final TextEditingController _storageController;
  late final TextEditingController _gradeController;
  late final TextEditingController _notesController;
  late String _status;
  late String _imagePath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.coin.status;
    _imagePath = widget.initialImagePath?.trim().isNotEmpty == true
        ? widget.initialImagePath!.trim()
        : widget.coin.imagePath;
    _storageController = TextEditingController(text: widget.coin.storageLocation);
    _gradeController = TextEditingController(text: widget.coin.grade);
    _notesController = TextEditingController(text: widget.coin.notes);
  }

  @override
  void dispose() {
    _storageController.dispose();
    _gradeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    final filePath = file?.path;
    if (filePath == null || filePath.trim().isEmpty) return;
    setState(() => _imagePath = filePath.trim());
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _databaseHelper.createDatabaseBackup(reason: 'before_coin_edit');

      final updatedCoin = ImportedCoin(
        category: widget.coin.category,
        series: widget.coin.series,
        year: widget.coin.year,
        mint: widget.coin.mint,
        variety: widget.coin.variety,
        status: _status,
        storageLocation: _storageController.text.trim(),
        grade: _gradeController.text.trim(),
        notes: _notesController.text.trim(),
      );

      final changedRows = await _databaseHelper.updateImportedCoin(
        originalCoin: widget.coin,
        updatedCoin: updatedCoin,
      );

      if (!mounted) {
        return;
      }
      if (changedRows == 0) {
        throw Exception('The coin record could not be located.');
      }
      Navigator.pop(context, updatedCoin);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save coin: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.coin.displayName.isEmpty
        ? 'Coin Details'
        : widget.coin.displayName;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Wrap(
                    spacing: 28,
                    runSpacing: 16,
                    children: [
                      _ReadOnlyField(label: 'Category', value: widget.coin.category),
                      _ReadOnlyField(label: 'Series', value: widget.coin.series),
                      _ReadOnlyField(label: 'Year', value: widget.coin.year),
                      _ReadOnlyField(label: 'Mint', value: widget.coin.mint),
                      _ReadOnlyField(label: 'Variety', value: widget.coin.variety),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Coin Photo',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      if (_imagePath.isNotEmpty)
                        SizedBox(
                          height: 260,
                          width: double.infinity,
                          child: File(_imagePath).existsSync()
                              ? Image.file(File(_imagePath), fit: BoxFit.contain)
                              : const Center(
                                  child: Icon(Icons.broken_image_outlined, size: 52),
                                ),
                        )
                      else
                        const Text('No photo attached.'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _chooseImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _imagePath.isEmpty ? 'Choose Image' : 'Change Image',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collection Information',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Need', child: Text('Need')),
                          DropdownMenuItem(value: 'Owned', child: Text('Owned')),
                          DropdownMenuItem(
                            value: 'Untracked',
                            child: Text('Untracked'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _status = value);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _storageController,
                        decoration: const InputDecoration(
                          labelText: 'Binder / storage location',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _gradeController,
                        decoration: const InputDecoration(
                          labelText: 'Grade',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _notesController,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value.trim().isEmpty ? '—' : value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
