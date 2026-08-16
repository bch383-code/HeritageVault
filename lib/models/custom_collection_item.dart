import 'dart:convert';

class CustomCollectionItem {
  final int? id;
  final int collectionId;
  final Map<String, String> values;
  final List<String> photoPaths;
  final List<String> documentPaths;
  final int createdAtMilliseconds;
  final int updatedAtMilliseconds;

  const CustomCollectionItem({
    this.id,
    required this.collectionId,
    required this.values,
    required this.photoPaths,
    required this.documentPaths,
    required this.createdAtMilliseconds,
    required this.updatedAtMilliseconds,
  });

  String get title => values['title']?.trim().isNotEmpty == true
      ? values['title']!.trim()
      : 'Untitled Item';

  Map<String, Object?> toMap() => {
        'id': id,
        'collection_id': collectionId,
        'values_json': jsonEncode(values),
        'photo_paths_json': jsonEncode(photoPaths),
        'document_paths_json': jsonEncode(documentPaths),
        'created_at_milliseconds': createdAtMilliseconds,
        'updated_at_milliseconds': updatedAtMilliseconds,
      };

  factory CustomCollectionItem.fromMap(Map<String, Object?> map) {
    Map<String, String> decodeValues(Object? value) {
      try {
        final decoded = jsonDecode(value?.toString() ?? '{}');
        if (decoded is Map) {
          return decoded.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          );
        }
      } catch (_) {}
      return <String, String>{};
    }

    List<String> decodeList(Object? value) {
      try {
        final decoded = jsonDecode(value?.toString() ?? '[]');
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toList();
        }
      } catch (_) {}
      return const [];
    }

    int toInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return CustomCollectionItem(
      id: map['id'] as int?,
      collectionId: toInt(map['collection_id']),
      values: decodeValues(map['values_json']),
      photoPaths: decodeList(map['photo_paths_json']),
      documentPaths: decodeList(map['document_paths_json']),
      createdAtMilliseconds: toInt(map['created_at_milliseconds']),
      updatedAtMilliseconds: toInt(map['updated_at_milliseconds']),
    );
  }

  CustomCollectionItem copyWith({
    int? id,
    int? collectionId,
    Map<String, String>? values,
    List<String>? photoPaths,
    List<String>? documentPaths,
    int? createdAtMilliseconds,
    int? updatedAtMilliseconds,
  }) {
    return CustomCollectionItem(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      values: values ?? this.values,
      photoPaths: photoPaths ?? this.photoPaths,
      documentPaths: documentPaths ?? this.documentPaths,
      createdAtMilliseconds:
          createdAtMilliseconds ?? this.createdAtMilliseconds,
      updatedAtMilliseconds:
          updatedAtMilliseconds ?? this.updatedAtMilliseconds,
    );
  }
}
