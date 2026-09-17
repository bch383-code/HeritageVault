import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/vault_photo.dart';
import '../services/sync_service.dart';
import '../services/photo_metadata_writer.dart';

class PhotoBatchEditScreen extends StatefulWidget {
  final List<VaultPhoto> photos;

  const PhotoBatchEditScreen({super.key, required this.photos});

  @override
  State<PhotoBatchEditScreen> createState() => _PhotoBatchEditScreenState();
}

class _PhotoBatchEditScreenState extends State<PhotoBatchEditScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final SyncService _syncService = SyncService();

  final TextEditingController _peopleController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _applyPeople = false;
  bool _applyTags = false;
  bool _applyDate = false;
  bool _applyLocation = false;
  bool _applyDescription = false;

  bool _saving = false;
  int _savedCount = 0;
  String _dateType = 'Approximate';

  @override
  void dispose() {
    _peopleController.dispose();
    _tagsController.dispose();
    _dateController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<String> _commaList(String value) {
    final values = <String>{};
    for (final raw in value.split(',')) {
      final item = raw.trim();
      if (item.isNotEmpty) values.add(item);
    }
    return values.toList();
  }

  String _storedDate() {
    final value = _dateController.text.trim();
    switch (_dateType) {
      case 'Unknown':
        return 'Unknown';
      case 'Approximate':
        return value.isEmpty ? '' : 'c. $value';
      case 'Decade':
        if (value.isEmpty) return '';
        return value.endsWith('s') ? value : '${value}s';
      default:
        return value;
    }
  }

  Future<void> _applyChanges() async {
    final hasAnyField =
        _applyPeople ||
        _applyTags ||
        _applyDate ||
        _applyLocation ||
        _applyDescription;

    if (!hasAnyField) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one field to apply.')),
      );
      return;
    }

    final peopleToAdd = _commaList(_peopleController.text);
    final tagsToAdd = _commaList(_tagsController.text);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Update ${widget.photos.length} photos?'),
        content: const Text(
          'Only the checked fields will change. People and Tags are added '
          'without removing existing values. Date, Location, and Description '
          'replace those Heirloom Atlas fields. Portable metadata will also be '
          'written to supported original image files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apply to Selected'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _savedCount = 0;
    });

    var originalWriteFailures = 0;

    try {
      for (final photo in widget.photos) {
        final existing = await _databaseHelper.getPhotoCatalogMetadata(
          photo.filePath,
        );

        final changedFields = <String>[];
        if (_applyPeople && peopleToAdd.isNotEmpty) changedFields.add('People');
        if (_applyTags && tagsToAdd.isNotEmpty) changedFields.add('Tags');
        if (_applyDate) changedFields.add('Date');
        if (_applyLocation) changedFields.add('Location');
        if (_applyDescription) changedFields.add('Description');

        final updated = PhotoCatalogMetadata(
          filePath: photo.filePath,
          people: <String>{
            ...existing.people,
            if (_applyPeople) ...peopleToAdd,
          }.toList(),
          tags: <String>{
            ...existing.tags,
            if (_applyTags) ...tagsToAdd,
          }.toList(),
          approximateDate: _applyDate
              ? _storedDate()
              : existing.approximateDate,
          location: _applyLocation
              ? _locationController.text.trim()
              : existing.location,
          description: _applyDescription
              ? _descriptionController.text.trim()
              : existing.description,
          backWriting: existing.backWriting,
          notes: existing.notes,
        );

        await _databaseHelper.savePhotoCatalogMetadata(updated);

        if (changedFields.isNotEmpty) {
          await _syncService.recordLocalChange(
            entityType: 'photo',
            localKey: updated.filePath,
            operation: 'update',
            changedFields: changedFields,
          );

          final writeResult = await PhotoMetadataWriter.write(
            filePath: photo.filePath,
            metadata: updated,
          );
          if (!writeResult.success) {
            originalWriteFailures++;
          }
        }

        if (!mounted) return;
        setState(() => _savedCount++);
      }

      if (!mounted) return;
      if (originalWriteFailures > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated $_savedCount photos. $originalWriteFailures original '
              'file${originalWriteFailures == 1 ? '' : 's'} could not be updated.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Batch edit stopped after $_savedCount photos: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _fieldCard({
    required bool enabled,
    required ValueChanged<bool?> onChanged,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CheckboxListTile(
              value: enabled,
              onChanged: _saving ? null : onChanged,
              contentPadding: EdgeInsets.zero,
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(subtitle),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (enabled) ...[const SizedBox(height: 8), child],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Batch Edit • ${widget.photos.length} Photos'),
      ),
      body: Row(
        children: [
          SizedBox(
            width: 250,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(
                    'Selected Photos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final photo in widget.photos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 54,
                            height: 42,
                            child: File(photo.filePath).existsSync()
                                ? Image.file(
                                    File(photo.filePath),
                                    fit: BoxFit.contain,
                                    cacheWidth: 150,
                                  )
                                : const Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              photo.fileName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
              children: [
                Text(
                  'Apply Shared Metadata',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Nothing changes unless you check a field. People and Tags '
                  'are added to existing values; the other checked fields replace existing values.',
                ),
                const SizedBox(height: 18),
                _fieldCard(
                  enabled: _applyPeople,
                  onChanged: (value) =>
                      setState(() => _applyPeople = value ?? false),
                  title: 'People',
                  subtitle: 'Add these people to every selected photo.',
                  child: TextField(
                    controller: _peopleController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'People to add',
                      hintText: 'Fred Hoffman, Rita Hoffman',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                _fieldCard(
                  enabled: _applyTags,
                  onChanged: (value) =>
                      setState(() => _applyTags = value ?? false),
                  title: 'Tags',
                  subtitle: 'Add these tags without removing existing tags.',
                  child: TextField(
                    controller: _tagsController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Tags to add',
                      hintText: 'Christmas, Family, 1960s',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                _fieldCard(
                  enabled: _applyDate,
                  onChanged: (value) =>
                      setState(() => _applyDate = value ?? false),
                  title: 'Date',
                  subtitle: 'Set the date the selected photos were taken.',
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 500;
                      final typeField = DropdownButtonFormField<String>(
                        initialValue: _dateType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Date type',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            const [
                                  'Exact',
                                  'Approximate',
                                  'Year only',
                                  'Decade',
                                  'Unknown',
                                ]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _dateType = value);
                                }
                              },
                      );
                      final dateField = TextField(
                        controller: _dateController,
                        enabled: !_saving && _dateType != 'Unknown',
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          hintText: '1960, Summer 1948...',
                          border: OutlineInputBorder(),
                        ),
                      );
                      if (narrow) {
                        return Column(
                          children: [
                            typeField,
                            const SizedBox(height: 10),
                            dateField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          SizedBox(width: 190, child: typeField),
                          const SizedBox(width: 12),
                          Expanded(child: dateField),
                        ],
                      );
                    },
                  ),
                ),
                _fieldCard(
                  enabled: _applyLocation,
                  onChanged: (value) =>
                      setState(() => _applyLocation = value ?? false),
                  title: 'Location',
                  subtitle: 'Replace the location on all selected photos.',
                  child: TextField(
                    controller: _locationController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText: 'Rome, New York',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                _fieldCard(
                  enabled: _applyDescription,
                  onChanged: (value) =>
                      setState(() => _applyDescription = value ?? false),
                  title: 'Description',
                  subtitle: 'Replace the description on all selected photos.',
                  child: TextField(
                    controller: _descriptionController,
                    enabled: !_saving,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Shared description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _saving
                        ? 'Updating $_savedCount of ${widget.photos.length}...'
                        : '${widget.photos.length} photos selected',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _applyChanges,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all),
                  label: const Text('Apply to Selected'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
