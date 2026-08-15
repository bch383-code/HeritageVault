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

      description = _firstNonEmpty([
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

            if (description.isEmpty &&
                (local == 'description' || local == 'title')) {
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
    } catch (_) {
      // Metadata problems must never prevent the photo from opening.
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
