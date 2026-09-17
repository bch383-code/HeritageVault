class DocumentRecord {
  final int? id;
  final String title;
  final String documentDate;
  final String documentType;
  final String people;
  final String description;
  final String source;
  final String filePath;
  final int createdAtMilliseconds;
  final int updatedAtMilliseconds;

  const DocumentRecord({
    this.id,
    required this.title,
    this.documentDate = '',
    this.documentType = '',
    this.people = '',
    this.description = '',
    this.source = '',
    required this.filePath,
    this.createdAtMilliseconds = 0,
    this.updatedAtMilliseconds = 0,
  });

  factory DocumentRecord.fromMap(Map<String, Object?> map) {
    return DocumentRecord(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      documentDate: map['document_date'] as String? ?? '',
      documentType: map['document_type'] as String? ?? '',
      people: map['people'] as String? ?? '',
      description: map['description'] as String? ?? '',
      source: map['source'] as String? ?? '',
      filePath: map['file_path'] as String? ?? '',
      createdAtMilliseconds: map['created_at_milliseconds'] as int? ?? 0,
      updatedAtMilliseconds: map['updated_at_milliseconds'] as int? ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'document_date': documentDate,
      'document_type': documentType,
      'people': people,
      'description': description,
      'source': source,
      'file_path': filePath,
      'created_at_milliseconds': createdAtMilliseconds,
      'updated_at_milliseconds': updatedAtMilliseconds,
    };
  }
}
