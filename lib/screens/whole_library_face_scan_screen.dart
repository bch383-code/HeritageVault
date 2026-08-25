import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/vault_photo.dart';
import '../services/face_recognition_service.dart';
import 'face_review_screen.dart';

class WholeLibraryFaceScanScreen extends StatefulWidget {
  final List<VaultPhoto> photos;

  const WholeLibraryFaceScanScreen({
    super.key,
    required this.photos,
  });

  @override
  State<WholeLibraryFaceScanScreen> createState() =>
      _WholeLibraryFaceScanScreenState();
}

class _WholeLibraryFaceScanScreenState
    extends State<WholeLibraryFaceScanScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final FaceRecognitionService _faceService = FaceRecognitionService();

  bool _loading = true;
  bool _running = false;
  bool _stopRequested = false;

  List<VaultPhoto> _remainingPhotos = const [];
  final List<String> _processedPaths = <String>[];

  int _processedThisRun = 0;
  int _facesThisRun = 0;
  int _photosWithFacesThisRun = 0;
  String _currentFileName = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final versions = await _databaseHelper.getPhotoFaceScanVersions();

      final remaining = <VaultPhoto>[];

      for (final photo in widget.photos) {
        final scannedVersion = versions[photo.filePath];

    if (scannedVersion == null ||
      scannedVersion != photo.modifiedMilliseconds) {
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
    if (_remainingPhotos.isEmpty || _running) return;

    setState(() {
      _running = true;
      _stopRequested = false;
      _processedThisRun = 0;
      _facesThisRun = 0;
      _photosWithFacesThisRun = 0;
      _processedPaths.clear();
      _currentFileName = '';
      _error = null;
    });

    try {
      await _faceService.scanPhotosIncrementally(
        _remainingPhotos,
        shouldCancel: () => _stopRequested,
        onPhotoComplete: (photo, faces, progress) async {
          await _databaseHelper.replaceFacesForPhotos(
            [photo.filePath],
            faces,
          );

          await _databaseHelper.markPhotoFaceScanned(
            photo: photo,
            faceCount: faces.length,
          );

          _processedPaths.add(photo.filePath);

          if (!mounted) return;

          setState(() {
            _processedThisRun++;
            _facesThisRun += faces.length;
            if (faces.isNotEmpty) {
              _photosWithFacesThisRun++;
            }
            _currentFileName = photo.fileName;
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

  Future<void> _reviewThisRun() async {
    if (_processedPaths.isEmpty) return;

    final faces = await _databaseHelper.getFacesForPhotoPaths(
      _processedPaths,
    );

    final unconfirmed = faces
        .where((face) => !face.confirmed)
        .toList();

    if (!mounted) return;

    if (unconfirmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No unconfirmed faces from this run need review.'),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceReviewScreen(
          faces: unconfirmed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.photos.length;
    final remaining = _remainingPhotos.length;
    final currentOverall = total - remaining;

    final runTarget = _processedThisRun + remaining;
    final runProgress = runTarget == 0
        ? 0.0
        : _processedThisRun / runTarget;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Whole Library Face Scan'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(32),
                  shrinkWrap: true,
                  children: [
                    const Icon(
                      Icons.face_retouching_natural,
                      size: 72,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Whole Library Facial Recognition',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Heirloom Atlas saves progress after every photo. '
                      'Photos already scanned are skipped unless the file '
                      'has changed, so you can stop and resume later.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            _statRow('Photos in library', '$total'),
                            _statRow(
                              'Current / already scanned',
                              '$currentOverall',
                            ),
                            _statRow('Remaining', '$remaining'),
                            if (_processedThisRun > 0 || _running) ...[
                              const Divider(height: 26),
                              _statRow(
                                'Processed this run',
                                '$_processedThisRun',
                              ),
                              _statRow(
                                'Faces found this run',
                                '$_facesThisRun',
                              ),
                              _statRow(
                                'Photos with faces',
                                '$_photosWithFacesThisRun',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
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
                      LinearProgressIndicator(value: runProgress),
                      const SizedBox(height: 12),
                      Text(
                        _currentFileName.isEmpty
                            ? 'Starting scan...'
                            : _currentFileName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                          currentOverall == 0
                              ? 'Start Whole Library Scan'
                              : 'Resume Scan',
                        ),
                      ),
                    if (_running)
                      FilledButton.tonalIcon(
                        onPressed:
                            _stopRequested ? null : _stopSafely,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop Safely'),
                      ),
                    if (!_running && _processedPaths.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _reviewThisRun,
                        icon: const Icon(Icons.groups_2_outlined),
                        label: const Text('Review Faces From This Run'),
                      ),
                    ],
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
