import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/antique.dart';

class LocalNetworkReceiverStatus {
  const LocalNetworkReceiverStatus({
    required this.running,
    required this.port,
    required this.pairingToken,
  });

  final bool running;
  final int port;
  final String pairingToken;
}

/// Small authenticated LAN listener used by the private-beta mobile sync flow.
///
/// Authenticated private-beta LAN receiver for pairing and Antique capture import.
class LocalNetworkSyncService {
  HttpServer? _server;
  String? _pairingToken;

  bool get isRunning => _server != null;

  Future<LocalNetworkReceiverStatus> startReceiver({int port = 47831}) async {
    if (_server != null) {
      return LocalNetworkReceiverStatus(
        running: true,
        port: _server!.port,
        pairingToken: _pairingToken!,
      );
    }

    if (!Platform.isWindows) {
      throw StateError('The local receiver can currently run only on Windows.');
    }

    final token = _createPairingToken();
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: false,
    );

    _pairingToken = token;
    _server = server;
    server.listen(
      _handleRequest,
      onError: (_) {},
      cancelOnError: false,
    );

    return LocalNetworkReceiverStatus(
      running: true,
      port: server.port,
      pairingToken: token,
    );
  }

  Future<void> stopReceiver() async {
    final server = _server;
    _server = null;
    _pairingToken = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        _json(request.response, HttpStatus.ok, {
          'service': 'heirloom_atlas_local_sync',
          'status': 'ready',
          'version': 1,
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/pairing/check') {
        final supplied = request.headers.value('x-heirloom-pairing-token') ?? '';
        if (supplied.isEmpty || supplied != _pairingToken) {
          _json(request.response, HttpStatus.unauthorized, {
            'ok': false,
            'error': 'invalid_pairing_token',
          });
          return;
        }
        _json(request.response, HttpStatus.ok, {'ok': true});
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/sync/antique') {
        final supplied = request.headers.value('x-heirloom-pairing-token') ?? '';
        if (supplied.isEmpty || supplied != _pairingToken) {
          _json(request.response, HttpStatus.unauthorized, {
            'ok': false, 'error': 'invalid_pairing_token',
          });
          return;
        }
        await _importAntique(request);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/sync/sports-card') {
        final supplied = request.headers.value('x-heirloom-pairing-token') ?? '';
        if (supplied.isEmpty || supplied != _pairingToken) {
          _json(request.response, HttpStatus.unauthorized, {
            'ok': false, 'error': 'invalid_pairing_token',
          });
          return;
        }
        await _importSportsCard(request);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/sync/coin') {
        final supplied = request.headers.value('x-heirloom-pairing-token') ?? '';
        if (supplied.isEmpty || supplied != _pairingToken) {
          _json(request.response, HttpStatus.unauthorized, {
            'ok': false, 'error': 'invalid_pairing_token',
          });
          return;
        }
        await _importCoin(request);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/sync/document') {
        final supplied = request.headers.value('x-heirloom-pairing-token') ?? '';
        if (supplied.isEmpty || supplied != _pairingToken) {
          _json(request.response, HttpStatus.unauthorized, {'ok': false, 'error': 'invalid_pairing_token'});
          return;
        }
        await _importDocument(request);
        return;
      }

      _json(request.response, HttpStatus.notFound, {
        'ok': false,
        'error': 'not_found',
      });
    } catch (_) {
      try {
        _json(request.response, HttpStatus.internalServerError, {
          'ok': false,
          'error': 'receiver_error',
        });
      } catch (_) {
        await request.response.close();
      }
    }
  }

  Future<void> _importAntique(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid sync payload.');
    final payload = Map<String, dynamic>.from(decoded);
    final changeUuid = payload['change_uuid']?.toString().trim() ?? '';
    final recordUuid = payload['record_uuid']?.toString().trim() ?? '';
    final antiqueRaw = payload['antique'];
    final imageRaw = payload['image'];
    if (changeUuid.isEmpty || recordUuid.isEmpty || antiqueRaw is! Map || imageRaw is! Map) {
      _json(request.response, HttpStatus.badRequest, {'ok': false, 'error': 'invalid_payload'});
      return;
    }

    final db = DatabaseHelper.instance;
    final database = await db.database;
    final existing = await database.query(
      'sync_change_log',
      columns: ['change_uuid'],
      where: 'change_uuid = ?',
      whereArgs: [changeUuid],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      _json(request.response, HttpStatus.ok, {'ok': true, 'duplicate': true});
      return;
    }

    final antiqueMap = Map<String, dynamic>.from(antiqueRaw);
    final imageMap = Map<String, dynamic>.from(imageRaw);
    final encoded = imageMap['base64']?.toString() ?? '';
    if (encoded.isEmpty) {
      _json(request.response, HttpStatus.badRequest, {'ok': false, 'error': 'missing_image'});
      return;
    }
    final bytes = base64Decode(encoded);
    if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
      _json(request.response, HttpStatus.badRequest, {'ok': false, 'error': 'invalid_image_size'});
      return;
    }

    final docs = await getApplicationDocumentsDirectory();
    final imageDir = Directory(path.join(docs.path, 'Heirloom Atlas', 'Antiques', 'Images'));
    await imageDir.create(recursive: true);
    var ext = path.extension(imageMap['filename']?.toString() ?? '');
    if (ext.isEmpty || ext.length > 8) ext = '.jpg';
    final imagePath = path.join(
      imageDir.path,
      'antique_mobile_received_${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    final imageFile = File(imagePath);
    int? antiqueId;
    try {
      await imageFile.writeAsBytes(bytes, flush: true);
      antiqueId = await db.insertAntique(Antique(
        title: antiqueMap['title']?.toString() ?? 'Mobile antique capture',
        description: antiqueMap['description']?.toString() ?? '',
        notes: antiqueMap['notes']?.toString() ?? '',
        imagePaths: [imagePath],
      ));
      final device = await db.ensureCurrentSyncDevice(displayName: 'Heirloom Atlas Windows');
      await db.recordSyncChange(
        changeUuid: changeUuid,
        deviceId: device['device_id']?.toString() ?? '',
        entityType: 'antique',
        localKey: antiqueId.toString(),
        operation: 'create',
        detailsJson: jsonEncode({
          'received_from': 'mobile_local_network',
          'record_uuid': recordUuid,
        }),
      );
      await db.markSyncChangeProcessed(changeUuid);
      await db.upsertSyncRecord(
        recordUuid: recordUuid,
        entityType: 'antique',
        localKey: antiqueId.toString(),
        localModifiedMilliseconds: DateTime.now().millisecondsSinceEpoch,
        syncState: 'synced',
      );
      _json(request.response, HttpStatus.ok, {'ok': true, 'antique_id': antiqueId});
    } catch (_) {
      // If the database insert never completed, remove the newly received file.
      // If it did complete, keep the file so the saved Antique never points at a deleted image.
      if (antiqueId == null && await imageFile.exists()) {
        try { await imageFile.delete(); } catch (_) {}
      }
      rethrow;
    }
  }


  Future<void> _importSportsCard(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid sync payload.');
    final payload = Map<String, dynamic>.from(decoded);

    final changeUuid = payload['change_uuid']?.toString().trim() ?? '';
    final recordUuid = payload['record_uuid']?.toString().trim() ?? '';
    final cardRaw = payload['card'];
    final frontRaw = payload['front_image'];

    if (changeUuid.isEmpty ||
        recordUuid.isEmpty ||
        cardRaw is! Map ||
        frontRaw is! Map) {
      _json(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'invalid_payload',
      });
      return;
    }

    final db = DatabaseHelper.instance;
    final database = await db.database;

    final existingChange = await database.query(
      'sync_change_log',
      columns: ['change_uuid'],
      where: 'change_uuid = ?',
      whereArgs: [changeUuid],
      limit: 1,
    );
    if (existingChange.isNotEmpty) {
      _json(request.response, HttpStatus.ok, {
        'ok': true,
        'duplicate': true,
      });
      return;
    }

    final card = Map<String, dynamic>.from(cardRaw);
    final front = Map<String, dynamic>.from(frontRaw);
    final backRaw = payload['back_image'];
    final back = backRaw is Map ? Map<String, dynamic>.from(backRaw) : null;

    List<int>? decodeImage(Map<String, dynamic>? image) {
      if (image == null) return null;
      final encoded = image['base64']?.toString() ?? '';
      if (encoded.isEmpty) return null;
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
        throw const FormatException('invalid_image_size');
      }
      return bytes;
    }

    final frontBytes = decodeImage(front);
    if (frontBytes == null) {
      _json(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'missing_front_image',
      });
      return;
    }
    final backBytes = decodeImage(back);

    final docs = await getApplicationDocumentsDirectory();
    final imageDir = Directory(
      path.join(docs.path, 'Heirloom Atlas', 'Sports Cards', 'Images'),
    );
    await imageDir.create(recursive: true);

    String extensionFor(Map<String, dynamic>? image) {
      var ext = path.extension(image?['filename']?.toString() ?? '');
      if (ext.isEmpty || ext.length > 8) ext = '.jpg';
      return ext;
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final frontPath = path.join(
      imageDir.path,
      'sports_card_mobile_received_${stamp}_front${extensionFor(front)}',
    );
    final backPath = backBytes == null
        ? ''
        : path.join(
            imageDir.path,
            'sports_card_mobile_received_${stamp}_back${extensionFor(back)}',
          );

    final frontFile = File(frontPath);
    final backFile = backPath.isEmpty ? null : File(backPath);
    int? catalogId;

    try {
      await frontFile.writeAsBytes(frontBytes, flush: true);
      if (backFile != null && backBytes != null) {
        await backFile.writeAsBytes(backBytes, flush: true);
      }

      final sport = card['sport']?.toString().trim() ?? 'Baseball';
      final year = card['year']?.toString().trim() ?? '';
      final brand = card['brand']?.toString().trim() ?? '';
      final setName = card['set_name']?.toString().trim() ?? '';
      final cardNumber = card['card_number']?.toString().trim() ?? '';
      final player = card['player']?.toString().trim() ?? '';
      final team = card['team']?.toString().trim() ?? '';
      final condition = card['condition']?.toString().trim() ?? '';
      final storageLocation =
          card['storage_location']?.toString().trim() ?? '';
      final userNotes = card['notes']?.toString().trim() ?? '';

      final where = <String>[
        'year = ?',
        'LOWER(brand) = LOWER(?)',
        'LOWER(card_number) = LOWER(?)',
      ];
      final args = <Object?>[year, brand, cardNumber];
      if (setName.isNotEmpty) {
        where.add('LOWER(set_name) = LOWER(?)');
        args.add(setName);
      }

      final matches = await database.query(
        'sports_card_catalog',
        columns: ['id'],
        where: where.join(' AND '),
        whereArgs: args,
        limit: 2,
      );

      if (matches.length == 1) {
        catalogId = matches.first['id'] as int?;
      }

      if (catalogId == null) {
        final normalizedKey = [
          year.toLowerCase(),
          brand.toLowerCase(),
          setName.toLowerCase(),
          if (cardNumber.isEmpty) recordUuid.toLowerCase(),
        ].join('|');
        final sourceKey = 'mobile:$normalizedKey';
        final now = DateTime.now().millisecondsSinceEpoch;

        await database.rawInsert('''
          INSERT OR IGNORE INTO sports_card_sets
          (source_key, source_name, sport, year, brand, set_name,
           installed_at_milliseconds, refreshed_at_milliseconds)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          sourceKey,
          'Mobile Capture',
          sport,
          year,
          brand,
          setName,
          now,
          now,
        ]);

        await database.rawInsert('''
          INSERT OR IGNORE INTO sports_card_catalog
          (source_key, sport, year, brand, set_name, card_number,
           player, team, attributes, catalog_notes)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          sourceKey,
          sport,
          year,
          brand,
          setName,
          cardNumber,
          player,
          team,
          '',
          'Created from Heirloom Atlas mobile capture.',
        ]);

        final created = await database.query(
          'sports_card_catalog',
          columns: ['id'],
          where: 'source_key = ? AND card_number = ?',
          whereArgs: [sourceKey, cardNumber],
          limit: 1,
        );
        if (created.isEmpty) {
          throw StateError('sports_card_catalog_insert_failed');
        }
        catalogId = created.first['id'] as int?;
      }

      if (catalogId == null) {
        throw StateError('sports_card_catalog_match_failed');
      }

      final currentCollection = await database.query(
        'sports_card_collection',
        where: 'catalog_id = ?',
        whereArgs: [catalogId],
        limit: 1,
      );
      final current = currentCollection.isEmpty
          ? <String, Object?>{}
          : currentCollection.first;

      final notesParts = <String>[
        if (userNotes.isNotEmpty) userNotes,
        if (backPath.isNotEmpty) 'Back image: $backPath',
        'Captured with Heirloom Atlas mobile companion.',
      ];
      final now = DateTime.now().millisecondsSinceEpoch;

      await database.rawInsert('''
        INSERT OR REPLACE INTO sports_card_collection
        (catalog_id, status, quantity_owned, grade, storage_location,
         value, value_source, value_updated_at_milliseconds,
         image_path, notes, updated_at_milliseconds)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        catalogId,
        'Owned',
        ((current['quantity_owned'] as int?) ?? 0) > 0
            ? current['quantity_owned']
            : 1,
        condition.isNotEmpty
            ? condition
            : (current['grade']?.toString() ?? ''),
        storageLocation.isNotEmpty
            ? storageLocation
            : (current['storage_location']?.toString() ?? ''),
        current['value'],
        current['value_source']?.toString() ?? '',
        current['value_updated_at_milliseconds'] ?? 0,
        frontPath,
        notesParts.join('\n'),
        now,
      ]);

      final device = await db.ensureCurrentSyncDevice(
        displayName: 'Heirloom Atlas Windows',
      );
      await db.recordSyncChange(
        changeUuid: changeUuid,
        deviceId: device['device_id']?.toString() ?? '',
        entityType: 'sports_card',
        localKey: catalogId.toString(),
        operation: 'create',
        detailsJson: jsonEncode({
          'received_from': 'mobile_local_network',
          'record_uuid': recordUuid,
        }),
      );
      await db.markSyncChangeProcessed(changeUuid);
      await db.upsertSyncRecord(
        recordUuid: recordUuid,
        entityType: 'sports_card',
        localKey: catalogId.toString(),
        localModifiedMilliseconds: now,
        syncState: 'synced',
      );

      _json(request.response, HttpStatus.ok, {
        'ok': true,
        'sports_card_id': catalogId,
      });
    } catch (_) {
      if (catalogId == null) {
        if (await frontFile.exists()) {
          try { await frontFile.delete(); } catch (_) {}
        }
        if (backFile != null && await backFile.exists()) {
          try { await backFile.delete(); } catch (_) {}
        }
      }
      rethrow;
    }
  }


  Future<void> _importCoin(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid sync payload.');
    final payload = Map<String, dynamic>.from(decoded);

    final changeUuid = payload['change_uuid']?.toString().trim() ?? '';
    final recordUuid = payload['record_uuid']?.toString().trim() ?? '';
    final coinRaw = payload['coin'];
    final frontRaw = payload['front_image'];

    if (changeUuid.isEmpty ||
        recordUuid.isEmpty ||
        coinRaw is! Map ||
        frontRaw is! Map) {
      _json(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'invalid_payload',
      });
      return;
    }

    final db = DatabaseHelper.instance;
    final database = await db.database;

    final existingChange = await database.query(
      'sync_change_log',
      columns: ['change_uuid'],
      where: 'change_uuid = ?',
      whereArgs: [changeUuid],
      limit: 1,
    );
    if (existingChange.isNotEmpty) {
      _json(request.response, HttpStatus.ok, {
        'ok': true,
        'duplicate': true,
      });
      return;
    }

    final coin = Map<String, dynamic>.from(coinRaw);
    final front = Map<String, dynamic>.from(frontRaw);
    final backRaw = payload['back_image'];
    final back = backRaw is Map ? Map<String, dynamic>.from(backRaw) : null;

    List<int>? decodeImage(Map<String, dynamic>? image) {
      if (image == null) return null;
      final encoded = image['base64']?.toString() ?? '';
      if (encoded.isEmpty) return null;
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
        throw const FormatException('invalid_image_size');
      }
      return bytes;
    }

    final frontBytes = decodeImage(front);
    if (frontBytes == null) {
      _json(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'missing_front_image',
      });
      return;
    }
    final backBytes = decodeImage(back);

    final docs = await getApplicationDocumentsDirectory();
    final imageDir = Directory(
      path.join(docs.path, 'Heirloom Atlas', 'Coins', 'Images'),
    );
    await imageDir.create(recursive: true);

    String extensionFor(Map<String, dynamic>? image) {
      var ext = path.extension(image?['filename']?.toString() ?? '');
      if (ext.isEmpty || ext.length > 8) ext = '.jpg';
      return ext;
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final frontPath = path.join(
      imageDir.path,
      'coin_mobile_received_${stamp}_front${extensionFor(front)}',
    );
    final backPath = backBytes == null
        ? ''
        : path.join(
            imageDir.path,
            'coin_mobile_received_${stamp}_back${extensionFor(back)}',
          );

    final frontFile = File(frontPath);
    final backFile = backPath.isEmpty ? null : File(backPath);
    int? importedCoinId;
    bool databaseCommitted = false;

    try {
      await frontFile.writeAsBytes(frontBytes, flush: true);
      if (backFile != null && backBytes != null) {
        await backFile.writeAsBytes(backBytes, flush: true);
      }

      final category = coin['category']?.toString().trim() ?? '';
      final series = coin['series']?.toString().trim() ?? '';
      final year = coin['year']?.toString().trim() ?? '';
      final mint = coin['mint']?.toString().trim() ?? '';
      final variety = coin['variety']?.toString().trim() ?? '';
      final grade = coin['grade']?.toString().trim() ?? '';
      final storageLocation =
          coin['storage_location']?.toString().trim() ?? '';
      final userNotes = coin['notes']?.toString().trim() ?? '';

      final matches = await database.query(
        'imported_coins',
        where: '''
          category = ? AND
          series = ? AND
          year = ? AND
          mint = ? AND
          variety = ?
        ''',
        whereArgs: [category, series, year, mint, variety],
        limit: 2,
      );

      final notesParts = <String>[
        if (userNotes.isNotEmpty) userNotes,
        if (backPath.isNotEmpty) 'Back image: $backPath',
        'Captured with Heirloom Atlas mobile companion.',
      ];

      if (matches.length == 1) {
        final existing = matches.first;
        importedCoinId = existing['id'] as int?;
        final currentQuantity = existing['quantity_owned'] is int
            ? existing['quantity_owned'] as int
            : int.tryParse(existing['quantity_owned']?.toString() ?? '') ?? 0;

        await database.update(
          'imported_coins',
          {
            'status': 'Owned',
            'quantity_owned': currentQuantity > 0 ? currentQuantity : 1,
            'storage_location': storageLocation.isNotEmpty
                ? storageLocation
                : (existing['storage_location']?.toString() ?? ''),
            'grade': grade.isNotEmpty
                ? grade
                : (existing['grade']?.toString() ?? ''),
            'notes': notesParts.join('\n'),
            'image_path': frontPath,
          },
          where: 'id = ?',
          whereArgs: [importedCoinId],
        );
      } else {
        importedCoinId = await database.insert(
          'imported_coins',
          {
            'category': category.isEmpty ? 'Coins' : category,
            'series': series,
            'year': year,
            'mint': mint,
            'variety': variety,
            'status': 'Owned',
            'quantity_owned': 1,
            'storage_location': storageLocation,
            'grade': grade,
            'value': null,
            'notes': notesParts.join('\n'),
            'image_path': frontPath,
          },
        );
      }

      databaseCommitted = true;
      final now = DateTime.now().millisecondsSinceEpoch;

      final device = await db.ensureCurrentSyncDevice(
        displayName: 'Heirloom Atlas Windows',
      );
      await db.recordSyncChange(
        changeUuid: changeUuid,
        deviceId: device['device_id']?.toString() ?? '',
        entityType: 'coin',
        localKey: importedCoinId.toString(),
        operation: 'create',
        detailsJson: jsonEncode({
          'received_from': 'mobile_local_network',
          'record_uuid': recordUuid,
        }),
      );
      await db.markSyncChangeProcessed(changeUuid);
      await db.upsertSyncRecord(
        recordUuid: recordUuid,
        entityType: 'coin',
        localKey: importedCoinId.toString(),
        localModifiedMilliseconds: now,
        syncState: 'synced',
      );

      _json(request.response, HttpStatus.ok, {
        'ok': true,
        'coin_id': importedCoinId,
      });
    } catch (_) {
      if (!databaseCommitted) {
        if (await frontFile.exists()) {
          try {
            await frontFile.delete();
          } catch (_) {}
        }
        if (backFile != null && await backFile.exists()) {
          try {
            await backFile.delete();
          } catch (_) {}
        }
      }
      rethrow;
    }
  }

  Future<void> _importDocument(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid sync payload.');
    final payload = Map<String, dynamic>.from(decoded);
    final changeUuid = payload['change_uuid']?.toString().trim() ?? '';
    final recordUuid = payload['record_uuid']?.toString().trim() ?? '';
    final documentRaw = payload['document'];
    final pagesRaw = payload['pages'];
    if (changeUuid.isEmpty || recordUuid.isEmpty || documentRaw is! Map || pagesRaw is! List || pagesRaw.isEmpty) {
      _json(request.response, HttpStatus.badRequest, {'ok': false, 'error': 'invalid_payload'});
      return;
    }

    final db = DatabaseHelper.instance;
    final database = await db.database;
    final existingChange = await database.query('sync_change_log', columns: ['change_uuid'], where: 'change_uuid = ?', whereArgs: [changeUuid], limit: 1);
    if (existingChange.isNotEmpty) {
      _json(request.response, HttpStatus.ok, {'ok': true, 'duplicate': true});
      return;
    }

    final document = Map<String, dynamic>.from(documentRaw);
    final pageBytes = <List<int>>[];
    final pageNames = <String>[];
    var totalBytes = 0;
    for (final item in pagesRaw) {
      if (item is! Map) throw const FormatException('invalid_page');
      final page = Map<String, dynamic>.from(item);
      final encoded = page['base64']?.toString() ?? '';
      if (encoded.isEmpty) throw const FormatException('missing_page_data');
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) throw const FormatException('invalid_page_size');
      totalBytes += bytes.length;
      if (totalBytes > 100 * 1024 * 1024) throw const FormatException('document_too_large');
      pageBytes.add(bytes);
      pageNames.add(page['filename']?.toString() ?? 'page.jpg');
    }

    final docs = await getApplicationDocumentsDirectory();
    final pageDir = Directory(path.join(docs.path, 'Heirloom Atlas', 'Documents', 'Pages'));
    await pageDir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final savedFiles = <File>[];
    int? documentId;
    try {
      for (var i = 0; i < pageBytes.length; i++) {
        var ext = path.extension(pageNames[i]);
        if (ext.isEmpty || ext.length > 8) ext = '.jpg';
        final file = File(path.join(pageDir.path, 'document_mobile_received_${stamp}_page_${i + 1}$ext'));
        await file.writeAsBytes(pageBytes[i], flush: true);
        savedFiles.add(file);
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await database.transaction((txn) async {
        await txn.execute('CREATE TABLE IF NOT EXISTS document_pages (id INTEGER PRIMARY KEY AUTOINCREMENT, document_id INTEGER NOT NULL, page_index INTEGER NOT NULL DEFAULT 0, file_path TEXT NOT NULL, created_at_milliseconds INTEGER NOT NULL DEFAULT 0, UNIQUE(document_id, page_index))');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_document_pages_document_order ON document_pages(document_id, page_index)');
        documentId = await txn.insert('documents', {
          'title': document['title']?.toString().trim() ?? '',
          'document_date': document['document_date']?.toString().trim() ?? '',
          'document_type': document['document_type']?.toString().trim() ?? '',
          'people': document['people']?.toString().trim() ?? '',
          'description': document['description']?.toString().trim() ?? '',
          'source': document['source']?.toString().trim() ?? '',
          'file_path': savedFiles.first.path,
          'created_at_milliseconds': now,
          'updated_at_milliseconds': now,
        });
        for (var i = 0; i < savedFiles.length; i++) {
          await txn.insert('document_pages', {'document_id': documentId, 'page_index': i, 'file_path': savedFiles[i].path, 'created_at_milliseconds': now});
        }
      });

      final device = await db.ensureCurrentSyncDevice(displayName: 'Heirloom Atlas Windows');
      await db.recordSyncChange(changeUuid: changeUuid, deviceId: device['device_id']?.toString() ?? '', entityType: 'document', localKey: documentId.toString(), operation: 'create', detailsJson: jsonEncode({'received_from': 'mobile_local_network', 'record_uuid': recordUuid, 'page_count': savedFiles.length}));
      await db.markSyncChangeProcessed(changeUuid);
      await db.upsertSyncRecord(recordUuid: recordUuid, entityType: 'document', localKey: documentId.toString(), localModifiedMilliseconds: now, syncState: 'synced');
      _json(request.response, HttpStatus.ok, {'ok': true, 'document_id': documentId, 'page_count': savedFiles.length});
    } catch (_) {
      if (documentId == null) {
        for (final file in savedFiles) {
          if (await file.exists()) { try { await file.delete(); } catch (_) {} }
        }
      }
      rethrow;
    }
  }

  void _json(HttpResponse response, int statusCode, Map<String, Object?> body) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }

  String _createPairingToken() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final chars = List.generate(
      12,
      (_) => alphabet[random.nextInt(alphabet.length)],
    );
    return '${chars.take(4).join()}-${chars.skip(4).take(4).join()}-${chars.skip(8).join()}';
  }
}
