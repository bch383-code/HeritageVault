import 'dart:convert';

class DetectedFaceRecord {
  final int? id;
  final String photoFilePath;
  final int faceIndex;
  final double left;
  final double top;
  final double width;
  final double height;
  final double detectionScore;
  final List<double> embedding;
  final String thumbnailPath;
  final String personName;
  final bool confirmed;

  const DetectedFaceRecord({
    this.id,
    required this.photoFilePath,
    required this.faceIndex,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.detectionScore,
    required this.embedding,
    required this.thumbnailPath,
    this.personName = '',
    this.confirmed = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'photo_file_path': photoFilePath,
        'face_index': faceIndex,
        'box_left': left,
        'box_top': top,
        'box_width': width,
        'box_height': height,
        'detection_score': detectionScore,
        'embedding_json': jsonEncode(embedding),
        'thumbnail_path': thumbnailPath,
        'person_name': personName,
        'confirmed': confirmed ? 1 : 0,
      };

  factory DetectedFaceRecord.fromMap(Map<String, Object?> map) {
    double toDouble(Object? value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    int toInt(Object? value) =>
        value is int ? value : value is num ? value.toInt() : int.tryParse('$value') ?? 0;

    List<double> decodeEmbedding(Object? value) {
      try {
        final decoded = jsonDecode(value?.toString() ?? '[]');
        if (decoded is List) {
          return decoded.map((e) => (e as num).toDouble()).toList();
        }
      } catch (_) {}
      return const [];
    }

    return DetectedFaceRecord(
      id: map['id'] as int?,
      photoFilePath: map['photo_file_path'] as String? ?? '',
      faceIndex: toInt(map['face_index']),
      left: toDouble(map['box_left']),
      top: toDouble(map['box_top']),
      width: toDouble(map['box_width']),
      height: toDouble(map['box_height']),
      detectionScore: toDouble(map['detection_score']),
      embedding: decodeEmbedding(map['embedding_json']),
      thumbnailPath: map['thumbnail_path'] as String? ?? '',
      personName: map['person_name'] as String? ?? '',
      confirmed: toInt(map['confirmed']) == 1,
    );
  }
}
