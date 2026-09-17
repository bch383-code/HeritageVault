class HeritageStory {
  final int? id;
  final String title, storyText, dateText, place, authorSource, notes, attachmentPath;
  final int createdAtMilliseconds, updatedAtMilliseconds;

  const HeritageStory({
    this.id, required this.title, this.storyText = '', this.dateText = '',
    this.place = '', this.authorSource = '', this.notes = '',
    this.attachmentPath = '', this.createdAtMilliseconds = 0,
    this.updatedAtMilliseconds = 0,
  });

  factory HeritageStory.fromMap(Map<String, Object?> map) {
    int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return HeritageStory(
      id: asInt(map['id']), title: map['title'] as String? ?? '',
      storyText: map['story_text'] as String? ?? '',
      dateText: map['date_text'] as String? ?? '',
      place: map['place'] as String? ?? '',
      authorSource: map['author_source'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      attachmentPath: map['attachment_path'] as String? ?? '',
      createdAtMilliseconds: asInt(map['created_at_milliseconds']),
      updatedAtMilliseconds: asInt(map['updated_at_milliseconds']),
    );
  }

  Map<String, Object?> toMap() => {
    'title': title.trim(), 'story_text': storyText.trim(),
    'date_text': dateText.trim(), 'place': place.trim(),
    'author_source': authorSource.trim(), 'notes': notes.trim(),
    'attachment_path': attachmentPath.trim(),
    'created_at_milliseconds': createdAtMilliseconds,
    'updated_at_milliseconds': updatedAtMilliseconds,
  };
}
