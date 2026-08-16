import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:face_detection_tflite/face_detection_tflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/detected_face_record.dart';
import '../models/vault_photo.dart';

class FaceScanProgress {
  final int currentPhoto;
  final int totalPhotos;
  final String fileName;
  final int facesFound;

  const FaceScanProgress({
    required this.currentPhoto,
    required this.totalPhotos,
    required this.fileName,
    required this.facesFound,
  });
}

class FaceRecognitionService {
  Future<List<DetectedFaceRecord>> scanPhotos(
    List<VaultPhoto> photos, {
    void Function(FaceScanProgress progress)? onProgress,
  }) async {
    final detector = await FaceDetector.create();
    final results = <DetectedFaceRecord>[];

    try {
      for (var photoIndex = 0; photoIndex < photos.length; photoIndex++) {
        final photo = photos[photoIndex];
        var foundThisPhoto = 0;

        try {
          final file = File(photo.filePath);
          if (!await file.exists()) continue;

          final bytes = await file.readAsBytes();
          final faces = await detector.detectFacesFromBytes(
            bytes,
            mode: FaceDetectionMode.full,
          );
          foundThisPhoto = faces.length;

          for (var faceIndex = 0; faceIndex < faces.length; faceIndex++) {
            final face = faces[faceIndex];
            final embedding = await detector.getFaceEmbedding(face, bytes);
            final box = face.boundingBox;

            final thumbnailPath = await _writeFaceThumbnail(
              photo: photo,
              imageBytes: bytes,
              faceIndex: faceIndex,
              left: box.topLeft.x.toDouble(),
              top: box.topLeft.y.toDouble(),
              width: box.width.toDouble(),
              height: box.height.toDouble(),
            );

            results.add(
              DetectedFaceRecord(
                photoFilePath: photo.filePath,
                faceIndex: faceIndex,
                left: box.topLeft.x.toDouble(),
                top: box.topLeft.y.toDouble(),
                width: box.width.toDouble(),
                height: box.height.toDouble(),
                detectionScore: face.score,
                embedding: embedding.map((v) => v.toDouble()).toList(),
                thumbnailPath: thumbnailPath,
              ),
            );
          }
        } catch (_) {
          // Skip unreadable/unsupported individual photos.
        } finally {
          onProgress?.call(
            FaceScanProgress(
              currentPhoto: photoIndex + 1,
              totalPhotos: photos.length,
              fileName: photo.fileName,
              facesFound: foundThisPhoto,
            ),
          );
        }
      }
    } finally {
      await detector.dispose();
    }

    return results;
  }

  Future<String> _writeFaceThumbnail({
    required VaultPhoto photo,
    required Uint8List imageBytes,
    required int faceIndex,
    required double left,
    required double top,
    required double width,
    required double height,
  }) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final padX = width * 0.35;
    final padY = height * 0.45;
    final src = ui.Rect.fromLTRB(
      math.max(0.0, left - padX),
      math.max(0.0, top - padY),
      math.min(image.width.toDouble(), left + width + padX),
      math.min(image.height.toDouble(), top + height + padY),
    );

    const size = 256.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      const ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint(),
    );

    final picture = recorder.endRecording();
    final output = await picture.toImage(size.toInt(), size.toInt());
    final data = await output.toByteData(format: ui.ImageByteFormat.png);

    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(
      path.join(documents.path, 'Heritage Vault', 'Faces', 'Thumbnails'),
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final baseName = path
        .basenameWithoutExtension(photo.fileName)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final destination =
        path.join(dir.path, '${baseName}_${stamp}_face_$faceIndex.png');

    await File(destination).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
    output.dispose();
    return destination;
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || a.length != b.length) return -1;
    var dot = 0.0;
    var aa = 0.0;
    var bb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    if (aa == 0 || bb == 0) return -1;
    return dot / (math.sqrt(aa) * math.sqrt(bb));
  }

  static List<List<DetectedFaceRecord>> groupSimilarFaces(
    List<DetectedFaceRecord> faces, {
    double threshold = 0.60,
  }) {
    final groups = <List<DetectedFaceRecord>>[];

    for (final face in faces) {
      var match = -1;
      var best = -1.0;

      for (var i = 0; i < groups.length; i++) {
        final similarity =
            cosineSimilarity(groups[i].first.embedding, face.embedding);
        if (similarity >= threshold && similarity > best) {
          match = i;
          best = similarity;
        }
      }

      if (match == -1) {
        groups.add([face]);
      } else {
        groups[match].add(face);
      }
    }

    groups.sort((a, b) => b.length.compareTo(a.length));
    return groups;
  }
}
