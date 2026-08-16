import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/vault_photo.dart';
import '../services/face_recognition_service.dart';
import 'face_review_screen.dart';

class FaceScanScreen extends StatefulWidget {
  final List<VaultPhoto> photos;

  const FaceScanScreen({
    super.key,
    required this.photos,
  });

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final FaceRecognitionService _faceService = FaceRecognitionService();

  int _currentPhoto = 0;
  int _facesFound = 0;
  String _currentFileName = '';
  bool _running = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    try {
      final faces = await _faceService.scanPhotos(
        widget.photos,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _currentPhoto = progress.currentPhoto;
            _currentFileName = progress.fileName;
            _facesFound += progress.facesFound;
          });
        },
      );

      await _databaseHelper.replaceFacesForPhotos(
        widget.photos.map((photo) => photo.filePath).toList(),
        faces,
      );

      final savedFaces = await _databaseHelper.getFacesForPhotoPaths(
        widget.photos.map((photo) => photo.filePath).toList(),
      );

      if (!mounted) return;
      setState(() => _running = false);

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FaceReviewScreen(
            faces: savedFaces,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.photos.length;
    final progress = total == 0 ? 0.0 : _currentPhoto / total;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanning Faces'),
        automaticallyImplyLeading: !_running,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'Face scan could not complete.',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _error!,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.face_retouching_natural, size: 72),
                      const SizedBox(height: 20),
                      Text(
                        '$_currentPhoto of $total photos scanned',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 16),
                      Text(
                        _currentFileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Faces found: $_facesFound',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Everything is processed locally on this computer.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
