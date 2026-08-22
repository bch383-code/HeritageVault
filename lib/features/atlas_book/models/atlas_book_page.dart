class AtlasBookPage {
  final int? id;
  final int bookId;
  final String pageType;
  final int? personId;
  final int? relatedPersonId;
  final String heroPhotoPath;
  final int generationCount;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AtlasBookPage({
    this.id,
    required this.bookId,
    required this.pageType,
    this.personId,
    this.relatedPersonId,
    this.heroPhotoPath = '',
    this.generationCount = 4,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'page_type': pageType,
        'person_id': personId,
        'related_person_id': relatedPersonId,
        'hero_photo_path': heroPhotoPath,
        'generation_count': generationCount,
        'sort_order': sortOrder,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory AtlasBookPage.fromMap(Map<String, Object?> map) => AtlasBookPage(
        id: map['id'] as int?,
        bookId: (map['book_id'] as num).toInt(),
        pageType: map['page_type'] as String? ?? 'person_profile',
        personId: (map['person_id'] as num?)?.toInt(),
        relatedPersonId: (map['related_person_id'] as num?)?.toInt(),
        heroPhotoPath: map['hero_photo_path'] as String? ?? '',
        generationCount: (map['generation_count'] as num?)?.toInt() ?? 4,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
