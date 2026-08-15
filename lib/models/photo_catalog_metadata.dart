import 'dart:convert';

class PhotoCatalogMetadata {
  final String filePath;
  final List<String> people;
  final List<String> tags;
  final String approximateDate;
  final String location;
  final String description;
  final String notes;

  const PhotoCatalogMetadata({
    required this.filePath,
    this.people = const [],
    this.tags = const [],
    this.approximateDate = '',
    this.location = '',
    this.description = '',
    this.notes = '',
  });

  Map<String, Object?> toMap() {
    return {
      'file_path': filePath,
      'people_json': jsonEncode(people),
      'tags_json': jsonEncode(tags),
      'approximate_date': approximateDate,
      'location': location,
      'description': description,
      'notes': notes,
    };
  }

  factory PhotoCatalogMetadata.fromMap(Map<String, Object?> map) {
    List<String> decodeList(Object? value) {
      if (value == null || value.toString().trim().isEmpty) return const [];
      try {
        final decoded = jsonDecode(value.toString());
        if (decoded is List) {
          return decoded
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList();
        }
      } catch (_) {}
      return const [];
    }

    return PhotoCatalogMetadata(
      filePath: map['file_path'] as String? ?? '',
      people: decodeList(map['people_json']),
      tags: decodeList(map['tags_json']),
      approximateDate: map['approximate_date'] as String? ?? '',
      location: map['location'] as String? ?? '',
      description: map['description'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
    );
  }
}
