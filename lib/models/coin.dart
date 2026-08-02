class Coin {
  final int? id;
  final String year;
  final String name;
  final String mintMark;
  final String country;
  final String notes;

  const Coin({
    this.id,
    required this.year,
    required this.name,
    required this.mintMark,
    required this.country,
    this.notes = '',
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'year': year,
      'name': name,
      'mint_mark': mintMark,
      'country': country,
      'notes': notes,
    };
  }

  factory Coin.fromMap(Map<String, Object?> map) {
    return Coin(
      id: map['id'] as int?,
      year: map['year'] as String,
      name: map['name'] as String,
      mintMark: map['mint_mark'] as String? ?? '',
      country: map['country'] as String? ?? 'Unknown',
      notes: map['notes'] as String? ?? '',
    );
  }
}