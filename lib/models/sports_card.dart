class SportsCard {
  final int? id;
  final String sport;
  final String year;
  final String brand;
  final String setName;
  final String cardNumber;
  final String player;
  final String team;
  final String attributes;
  final String status;
  final int quantityOwned;
  final String grade;
  final String storageLocation;
  final double? value;
  final String valueSource;
  final int valueUpdatedAtMilliseconds;
  final String imagePath;
  final String notes;

  const SportsCard({
    this.id,
    required this.sport,
    required this.year,
    required this.brand,
    required this.setName,
    required this.cardNumber,
    required this.player,
    this.team = '',
    this.attributes = '',
    this.status = 'Untracked',
    this.quantityOwned = 0,
    this.grade = '',
    this.storageLocation = '',
    this.value,
    this.valueSource = '',
    this.valueUpdatedAtMilliseconds = 0,
    this.imagePath = '',
    this.notes = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'sport': sport,
        'year': year,
        'brand': brand,
        'set_name': setName,
        'card_number': cardNumber,
        'player': player,
        'team': team,
        'attributes': attributes,
        'status': status,
        'quantity_owned': quantityOwned,
        'grade': grade,
        'storage_location': storageLocation,
        'value': value,
        'value_source': valueSource,
        'value_updated_at_milliseconds': valueUpdatedAtMilliseconds,
        'image_path': imagePath,
        'notes': notes,
      };

  factory SportsCard.fromMap(Map<String, Object?> m) => SportsCard(
        id: m['id'] as int?,
        sport: m['sport'] as String? ?? '',
        year: m['year'] as String? ?? '',
        brand: m['brand'] as String? ?? '',
        setName: m['set_name'] as String? ?? '',
        cardNumber: m['card_number'] as String? ?? '',
        player: m['player'] as String? ?? '',
        team: m['team'] as String? ?? '',
        attributes: m['attributes'] as String? ?? '',
        status: m['status'] as String? ?? 'Untracked',
        quantityOwned: (m['quantity_owned'] as num?)?.toInt() ?? 0,
        grade: m['grade'] as String? ?? '',
        storageLocation: m['storage_location'] as String? ?? '',
        value: (m['value'] as num?)?.toDouble(),
        valueSource: m['value_source'] as String? ?? '',
        valueUpdatedAtMilliseconds:
            (m['value_updated_at_milliseconds'] as num?)?.toInt() ?? 0,
        imagePath: m['image_path'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
      );

  SportsCard copyWith({
    String? status,
    int? quantityOwned,
    String? grade,
    String? storageLocation,
    double? value,
    String? valueSource,
    int? valueUpdatedAtMilliseconds,
    String? imagePath,
    String? notes,
  }) =>
      SportsCard(
        id: id,
        sport: sport,
        year: year,
        brand: brand,
        setName: setName,
        cardNumber: cardNumber,
        player: player,
        team: team,
        attributes: attributes,
        status: status ?? this.status,
        quantityOwned: quantityOwned ?? this.quantityOwned,
        grade: grade ?? this.grade,
        storageLocation: storageLocation ?? this.storageLocation,
        value: value ?? this.value,
        valueSource: valueSource ?? this.valueSource,
        valueUpdatedAtMilliseconds:
            valueUpdatedAtMilliseconds ?? this.valueUpdatedAtMilliseconds,
        imagePath: imagePath ?? this.imagePath,
        notes: notes ?? this.notes,
      );
}
