import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/vault_photo.dart';
import '../services/photo_metadata_import_service.dart';

class PhotoMetadataImportScreen extends StatefulWidget {
  final List<VaultPhoto> photos;

  const PhotoMetadataImportScreen({
    super.key,
    required this.photos,
  });

  @override
  State<PhotoMetadataImportScreen> createState() =>
      _PhotoMetadataImportScreenState();
}

class _PhotoMetadataImportScreenState
    extends State<PhotoMetadataImportScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final PhotoMetadataImportService _importService =
      PhotoMetadataImportService();

  bool _loading = true;
  bool _running = false;
  bool _stopRequested = false;

  List<VaultPhoto> _remainingPhotos = const [];

  int _processedThisRun = 0;
  int _photosWithMetadata = 0;
  int _photosChanged = 0;
  int _peopleImported = 0;
  int _tagsImported = 0;
  int _datesImported = 0;
  int _locationsImported = 0;
  int _descriptionsImported = 0;

  String _currentFileName = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final versions =
          await _databaseHelper.getPhotoMetadataImportVersions();

      final remaining = <VaultPhoto>[];

      for (final photo in widget.photos) {
        final importedVersion = versions[photo.filePath];

        if (importedVersion == null ||
            importedVersion != photo.modifiedMilliseconds) {
          remaining.add(photo);
        }
      }

      if (!mounted) return;

      setState(() {
        _remainingPhotos = remaining;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _start() async {
    if (_running || _remainingPhotos.isEmpty) return;

    final photosToProcess = [..._remainingPhotos];

    setState(() {
      _running = true;
      _stopRequested = false;
      _processedThisRun = 0;
      _photosWithMetadata = 0;
      _photosChanged = 0;
      _peopleImported = 0;
      _tagsImported = 0;
      _datesImported = 0;
      _locationsImported = 0;
      _descriptionsImported = 0;
      _currentFileName = '';
      _error = null;
    });

    try {
      await _importService.importPhotos(
        photosToProcess,
        shouldCancel: () => _stopRequested,
        onPhotoComplete: (photo, progress) async {
          final changed = progress.peopleImported > 0 ||
              progress.tagsImported > 0 ||
              progress.dateImported ||
              progress.locationImported ||
              progress.descriptionImported;

          if (!mounted) return;

          setState(() {
            _processedThisRun++;
            _currentFileName = progress.fileName;

            if (progress.foundAnyMetadata) {
              _photosWithMetadata++;
            }
            if (changed) {
              _photosChanged++;
            }

            _peopleImported += progress.peopleImported;
            _tagsImported += progress.tagsImported;
            if (progress.dateImported) _datesImported++;
            if (progress.locationImported) _locationsImported++;
            if (progress.descriptionImported) _descriptionsImported++;
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _running = false;
      });

      await _prepare();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _running = false;
      });
    }
  }

  void _stopSafely() {
    setState(() => _stopRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.photos.length;
    final remaining = _remainingPhotos.length;
    final current = total - remaining;

    final runTarget = _processedThisRun + remaining;
    final progress =
        runTarget == 0 ? 0.0 : _processedThisRun / runTarget;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Embedded Photo Metadata'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: ListView(
                  padding: const EdgeInsets.all(32),
                  shrinkWrap: true,
                  children: [
                    const Icon(Icons.manage_search_outlined, size: 72),
                    const SizedBox(height: 16),
                    Text(
                      'Bulk Metadata Import',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Heirloom Atlas reads metadata already embedded in '
                      'your photos and merges it into the searchable catalog. '
                      'Existing Heirloom Atlas information is preserved.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Merge rules: Tags and People are added without '
                          'duplicates. Date, Location, and Description are '
                          'imported only when the Heirloom Atlas field is empty. '
                          'Notes are never changed.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            _statRow('Photos in library', '$total'),
                            _statRow(
                              'Already current',
                              '$current',
                            ),
                            _statRow('Remaining', '$remaining'),
                            if (_running || _processedThisRun > 0) ...[
                              const Divider(height: 26),
                              _statRow(
                                'Processed this run',
                                '$_processedThisRun',
                              ),
                              _statRow(
                                'Photos containing metadata',
                                '$_photosWithMetadata',
                              ),
                              _statRow(
                                'Photos changed',
                                '$_photosChanged',
                              ),
                              _statRow(
                                'People imported',
                                '$_peopleImported',
                              ),
                              _statRow(
                                'Tags imported',
                                '$_tagsImported',
                              ),
                              _statRow(
                                'Dates imported',
                                '$_datesImported',
                              ),
                              _statRow(
                                'Locations imported',
                                '$_locationsImported',
                              ),
                              _statRow(
                                'Descriptions imported',
                                '$_descriptionsImported',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_running) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 10),
                      Text(
                        _currentFileName.isEmpty
                            ? 'Starting...'
                            : _currentFileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      if (_stopRequested) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Stopping safely after the current photo...',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    if (!_running && remaining > 0)
                      FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          current == 0
                              ? 'Start Metadata Import'
                              : 'Resume Metadata Import',
                        ),
                      ),
                    if (_running)
                      FilledButton.tonalIcon(
                        onPressed:
                            _stopRequested ? null : _stopSafely,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop Safely'),
                      ),
                    if (!_running && remaining == 0) ...[
                      const SizedBox(height: 14),
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline),
                              SizedBox(width: 10),
                              Text(
                                'All indexed photos are current.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
