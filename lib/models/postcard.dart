class Postcard {
  final int? id;
  final String title;
  final String description;
  final String year;
  final String acquiredFrom;
  final double? purchasePrice;
  final double? estimatedValue;
  final String frontImagePath;
  final String backImagePath;
  final String notes;

  const Postcard({
    this.id,
    this.title = '',
    this.description = '',
    this.year = '',
    this.acquiredFrom = '',
    this.purchasePrice,
    this.estimatedValue,
    this.frontImagePath = '',
    this.backImagePath = '',
    this.notes = '',
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'year': year,
      'acquired_from': acquiredFrom,
      'purchase_price': purchasePrice,
      'estimated_value': estimatedValue,
      'front_image_path': frontImagePath,
      'back_image_path': backImagePath,
      'notes': notes,
    };
  }

  factory Postcard.fromMap(Map<String, Object?> map) {
    double? toDouble(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return Postcard(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      year: map['year'] as String? ?? '',
      acquiredFrom: map['acquired_from'] as String? ?? '',
      purchasePrice: toDouble(map['purchase_price']),
      estimatedValue: toDouble(map['estimated_value']),
      frontImagePath: map['front_image_path'] as String? ?? '',
      backImagePath: map['back_image_path'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
    );
  }

  Postcard copyWith({
    int? id,
    String? title,
    String? description,
    String? year,
    String? acquiredFrom,
    double? purchasePrice,
    double? estimatedValue,
    String? frontImagePath,
    String? backImagePath,
    String? notes,
  }) {
    return Postcard(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      year: year ?? this.year,
      acquiredFrom: acquiredFrom ?? this.acquiredFrom,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      estimatedValue: estimatedValue ?? this.estimatedValue,
      frontImagePath: frontImagePath ?? this.frontImagePath,
      backImagePath: backImagePath ?? this.backImagePath,
      notes: notes ?? this.notes,
    );
  }
}
