import '../database/database_helper.dart';
import '../models/photo_catalog_metadata.dart';
import '../models/vault_photo.dart';
import 'photo_metadata_reader.dart';

class MetadataImportProgress {
  final int currentPhoto;
  final int totalPhotos;
  final String fileName;
  final int tagsImported;
  final int peopleImported;
  final bool dateImported;
  final bool locationImported;
  final bool descriptionImported;
  final bool foundAnyMetadata;

  const MetadataImportProgress({
    required this.currentPhoto,
    required this.totalPhotos,
    required this.fileName,
    required this.tagsImported,
    required this.peopleImported,
    required this.dateImported,
    required this.locationImported,
    required this.descriptionImported,
    required this.foundAnyMetadata,
  });
}

class PhotoMetadataImportService {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  Future<void> importPhotos(
    List<VaultPhoto> photos, {
    required Future<void> Function(
      VaultPhoto photo,
      MetadataImportProgress progress,
    ) onPhotoComplete,
    bool Function()? shouldCancel,
  }) async {
    for (var index = 0; index < photos.length; index++) {
      if (shouldCancel?.call() == true) break;

      final photo = photos[index];

      var tagsImported = 0;
      var peopleImported = 0;
      var dateImported = false;
      var locationImported = false;
      var descriptionImported = false;
      var foundAnyMetadata = false;

      try {
        final embedded = await PhotoMetadataReader.read(photo.filePath);
        final existing =
            await _databaseHelper.getPhotoCatalogMetadata(photo.filePath);

        final importedPeople = <String>{};
        final importedTags = <String>{};

        for (final rawTag in embedded.tags) {
          final tag = rawTag.trim();
          if (tag.isEmpty) continue;

          if (tag.toLowerCase().startsWith('person:')) {
            final person = tag.substring(tag.indexOf(':') + 1).trim();
            if (person.isNotEmpty) {
              importedPeople.add(person);
            }
          } else {
            importedTags.add(tag);
          }
        }

        final mergedPeople = <String>{
          ...existing.people,
          ...importedPeople,
        }.toList();

        final mergedTags = <String>{
          ...existing.tags,
          ...importedTags,
        }.toList();

        peopleImported = mergedPeople.length - existing.people.toSet().length;
        tagsImported = mergedTags.length - existing.tags.toSet().length;

        var date = existing.approximateDate;
        if (date.trim().isEmpty && embedded.dateTaken.trim().isNotEmpty) {
          date = embedded.dateTaken.trim();
          dateImported = true;
        }

        var location = existing.location;
        final gpsLocation = [
          embedded.latitude.trim(),
          embedded.longitude.trim(),
        ].where((value) => value.isNotEmpty).join(', ');

        if (location.trim().isEmpty && gpsLocation.isNotEmpty) {
          location = gpsLocation;
          locationImported = true;
        }

        var description = existing.description;
        if (description.trim().isEmpty &&
            embedded.description.trim().isNotEmpty) {
          description = embedded.description.trim();
          descriptionImported = true;
        }

        foundAnyMetadata = embedded.tags.isNotEmpty ||
            embedded.dateTaken.trim().isNotEmpty ||
            gpsLocation.isNotEmpty ||
            embedded.description.trim().isNotEmpty;

        final changed = peopleImported > 0 ||
            tagsImported > 0 ||
            dateImported ||
            locationImported ||
            descriptionImported;

        if (changed) {
          await _databaseHelper.savePhotoCatalogMetadata(
            PhotoCatalogMetadata(
              filePath: existing.filePath,
              people: mergedPeople,
              tags: mergedTags,
              approximateDate: date,
              location: location,
              description: description,
              notes: existing.notes,
            ),
          );
        }
      } catch (_) {
        // One unreadable file should not stop a bulk import.
      }

      await _databaseHelper.markPhotoMetadataImported(photo);

      await onPhotoComplete(
        photo,
        MetadataImportProgress(
          currentPhoto: index + 1,
          totalPhotos: photos.length,
          fileName: photo.fileName,
          tagsImported: tagsImported,
          peopleImported: peopleImported,
          dateImported: dateImported,
          locationImported: locationImported,
          descriptionImported: descriptionImported,
          foundAnyMetadata: foundAnyMetadata,
        ),
      );
    }
  }
}
