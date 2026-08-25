class AtlasBookPage {
  final int? id;
  final int bookId;
  final String pageType;
  final int? personId;
  final int? relatedPersonId;
  final String heroPhotoPath;
  final int generationCount;
  final String collagePhotoPathsJson;
  final String collageTitle;
  final String collageSubtitle;
  final String collagePhotoLayoutJson;
  final String collageLayoutKey;
  final int collageLayoutSeed;
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
    this.collagePhotoPathsJson = '[]',
    this.collageTitle = '',
    this.collageSubtitle = '',
    this.collagePhotoLayoutJson = '[]',
    this.collageLayoutKey = 'balanced',
    this.collageLayoutSeed = 0,
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
        'collage_photo_paths_json': collagePhotoPathsJson,
        'collage_title': collageTitle,
        'collage_subtitle': collageSubtitle,
        'collage_photo_layout_json': collagePhotoLayoutJson,
        'collage_layout_key': collageLayoutKey,
        'collage_layout_seed': collageLayoutSeed,
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
        collagePhotoPathsJson:
            map['collage_photo_paths_json'] as String? ?? '[]',
        collageTitle: map['collage_title'] as String? ?? '',
        collageSubtitle: map['collage_subtitle'] as String? ?? '',
        collagePhotoLayoutJson:
            map['collage_photo_layout_json'] as String? ?? '[]',
        collageLayoutKey:
            map['collage_layout_key'] as String? ?? 'balanced',
        collageLayoutSeed:
            (map['collage_layout_seed'] as num?)?.toInt() ?? 0,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}