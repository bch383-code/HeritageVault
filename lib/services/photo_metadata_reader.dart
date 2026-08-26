import 'dart:convert';
import 'dart:io';

import 'package:exif/exif.dart';
import 'package:xml/xml.dart';

class PhotoMetadata {
  final String dateTaken;
  final String description;
  final List<String> tags;
  final String latitude;
  final String longitude;
  final String cameraMake;
  final String cameraModel;
  final String rating;
  final Map<String, String> technical;

  const PhotoMetadata({
    this.dateTaken = '',
    this.description = '',
    this.tags = const [],
    this.latitude = '',
    this.longitude = '',
    this.cameraMake = '',
    this.cameraModel = '',
    this.rating = '',
    this.technical = const {},
  });
}

class PhotoMetadataReader {
  static Future<PhotoMetadata> read(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return const PhotoMetadata();

    String dateTaken = '';
    String description = '';
    String exifDescription = '';
    String latitude = '';
    String longitude = '';
    String cameraMake = '';
    String cameraModel = '';
    String rating = '';
    final tags = <String>{};
    final technical = <String, String>{};

    try {
      final bytes = await file.readAsBytes();
      final exif = await readExifFromBytes(bytes);

      String value(String key) => exif[key]?.printable.trim() ?? '';

      dateTaken = _firstNonEmpty([
        value('EXIF DateTimeOriginal'),
        value('EXIF DateTimeDigitized'),
        value('Image DateTime'),
      ]);

      exifDescription = _firstNonEmpty([
        value('Image ImageDescription'),
        value('EXIF UserComment'),
      ]);

      cameraMake = value('Image Make');
      cameraModel = value('Image Model');

      final lat = value('GPS GPSLatitude');
      final latRef = value('GPS GPSLatitudeRef');
      final lon = value('GPS GPSLongitude');
      final lonRef = value('GPS GPSLongitudeRef');
      if (lat.isNotEmpty) latitude = '$lat $latRef'.trim();
      if (lon.isNotEmpty) longitude = '$lon $lonRef'.trim();

      for (final entry in exif.entries) {
        final printed = entry.value.printable.trim();
        if (printed.isNotEmpty) technical[entry.key] = printed;
      }

      // digiKam commonly stores keywords/captions/ratings in embedded XMP.
      final raw = latin1.decode(bytes, allowInvalid: true);
      for (final packet in _extractXmpPackets(raw)) {
        try {
          final document = XmlDocument.parse(packet);

          for (final element in document.descendants.whereType<XmlElement>()) {
            final local = element.name.local.toLowerCase();

            if (local == 'subject') {
              for (final li in element.descendants.whereType<XmlElement>()) {
                if (li.name.local.toLowerCase() == 'li') {
                  final text = li.innerText.trim();
                  if (text.isNotEmpty) tags.add(text);
                }
              }
            }

            if (description.isEmpty && local == 'description') {
              for (final li in element.descendants.whereType<XmlElement>()) {
                if (li.name.local.toLowerCase() == 'li') {
                  final text = li.innerText.trim();
                  if (text.isNotEmpty) {
                    description = text;
                    break;
                  }
                }
              }
            }

            if (rating.isEmpty && local == 'rating') {
              rating = element.innerText.trim();
            }

            if (dateTaken.isEmpty &&
                (local == 'createdate' || local == 'datetimeoriginal')) {
              dateTaken = element.innerText.trim();
            }

            for (final attribute in element.attributes) {
              final attr = attribute.name.local.toLowerCase();
              final text = attribute.value.trim();
              if (text.isEmpty) continue;

              if (rating.isEmpty && attr == 'rating') rating = text;
              if (dateTaken.isEmpty &&
                  (attr == 'createdate' || attr == 'datetimeoriginal')) {
                dateTaken = text;
              }
            }
          }
        } catch (_) {
          // Ignore malformed or unsupported XMP.
        }
      }

      if (description.isEmpty) {
        description = exifDescription;
      }
    } catch (_) {
      // Metadata problems must never prevent the photo from opening.
      description = exifDescription;
    }

    // ExifTool is also used by Heirloom Atlas to write metadata. When it is
    // available, read back the exact XMP fields we write so verification is
    // symmetrical and does not depend on raw XMP packet parsing.
    try {
      final exifTool = await _findExifTool();
      if (exifTool != null) {
        final result = await Process.run(exifTool, [
          '-j',
          '-XMP-dc:Description',
          '-XMP-dc:Subject',
          '-XMP-iptcCore:Location',
          filePath,
        ], runInShell: false);

        if (result.exitCode == 0) {
          final decoded = jsonDecode(result.stdout.toString());
          if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
            final row = Map<String, dynamic>.from(decoded.first as Map);

            final xmpDescription =
                (row['Description'] ?? row['XMP-dc:Description'] ?? '')
                    .toString()
                    .trim();
            if (xmpDescription.isNotEmpty) {
              description = xmpDescription;
            }

            final subject = row['Subject'] ?? row['XMP-dc:Subject'];
            if (subject is List) {
              for (final item in subject) {
                final value = item.toString().trim();
                if (value.isNotEmpty) tags.add(value);
              }
            } else if (subject != null) {
              final rawSubject = subject.toString().trim();
              if (rawSubject.isNotEmpty) {
                for (final item in rawSubject.split(',')) {
                  final value = item.trim();
                  if (value.isNotEmpty) tags.add(value);
                }
              }
            }

            final xmpLocation =
                (row['Location'] ?? row['XMP-iptcCore:Location'] ?? '')
                    .toString()
                    .trim();
            if (xmpLocation.isNotEmpty) {
              technical['XMP Location'] = xmpLocation;
            }
          }
        }
      }
    } catch (_) {
      // ExifTool read-back is optional. Existing EXIF/XMP parsing remains
      // the fallback for normal metadata display.
    }

    return PhotoMetadata(
      dateTaken: dateTaken,
      description: description,
      tags: tags.toList()..sort(),
      latitude: latitude,
      longitude: longitude,
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      rating: rating,
      technical: technical,
    );
  }

  static Future<String?> _findExifTool() async {
    const directWindowsPath = r'C:\ExifTool\exiftool.exe';

    final directFile = File(directWindowsPath);
    if (await directFile.exists()) {
      try {
        final result = await Process.run(directWindowsPath, [
          '-ver',
        ], runInShell: false);
        if (result.exitCode == 0) return directWindowsPath;
      } catch (_) {}
    }

    for (final candidate in ['exiftool.exe', 'exiftool']) {
      try {
        final result = await Process.run(candidate, ['-ver'], runInShell: true);
        if (result.exitCode == 0) return candidate;
      } catch (_) {}
    }

    return null;
  }

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static List<String> _extractXmpPackets(String raw) {
    final packets = <String>[];
    var start = 0;

    while (true) {
      final xmpStart = raw.indexOf('<x:xmpmeta', start);
      if (xmpStart < 0) break;

      final xmpEnd = raw.indexOf('</x:xmpmeta>', xmpStart);
      if (xmpEnd < 0) break;

      final end = xmpEnd + '</x:xmpmeta>'.length;
      packets.add(raw.substring(xmpStart, end));
      start = end;
    }

    return packets;
  }
}
