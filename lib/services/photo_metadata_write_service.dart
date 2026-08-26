import '../models/photo_catalog_metadata.dart';
import '../models/vault_photo.dart';

class PhotoMetadataWritePlan {
  final VaultPhoto photo;
  final List<String> people;
  final List<String> tags;
  final String approximateDate;
  final String location;
  final String description;

  const PhotoMetadataWritePlan({
    required this.photo,
    required this.people,
    required this.tags,
    required this.approximateDate,
    required this.location,
    required this.description,
  });

  bool get hasMetadata =>
      people.isNotEmpty ||
      tags.isNotEmpty ||
      approximateDate.isNotEmpty ||
      location.isNotEmpty ||
      description.isNotEmpty;

  int get populatedFieldCount {
    var count = 0;

    if (people.isNotEmpty) count++;
    if (tags.isNotEmpty) count++;
    if (approximateDate.isNotEmpty) count++;
    if (location.isNotEmpty) count++;
    if (description.isNotEmpty) count++;

    return count;
  }
}

class PhotoMetadataWriteService {
  const PhotoMetadataWriteService();

  PhotoMetadataWritePlan createPlan({
    required VaultPhoto photo,
    PhotoCatalogMetadata? metadata,
  }) {
    return PhotoMetadataWritePlan(
      photo: photo,
      people: _cleanList(metadata?.people),
      tags: _cleanList(metadata?.tags),
      approximateDate: metadata?.approximateDate.trim() ?? '',
      location: metadata?.location.trim() ?? '',
      description: metadata?.description.trim() ?? '',
    );
  }

  List<PhotoMetadataWritePlan> createPlans({
    required List<VaultPhoto> photos,
    required Map<String, PhotoCatalogMetadata> catalogByPath,
  }) {
    return photos
        .map(
          (photo) => createPlan(
            photo: photo,
            metadata: catalogByPath[photo.filePath],
          ),
        )
        .toList();
  }

  List<String> _cleanList(List<String>? values) {
    if (values == null) return const [];

    final cleaned = <String>{};

    for (final value in values) {
      final trimmed = value.trim();

      if (trimmed.isNotEmpty) {
        cleaned.add(trimmed);
      }
    }

    return cleaned.toList();
  }
}