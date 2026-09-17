import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LocalNetworkPairingResult {
  const LocalNetworkPairingResult({
    required this.ok,
    required this.message,
  });

  final bool ok;
  final String message;
}

class LocalNetworkTransferResult {
  const LocalNetworkTransferResult({
    required this.ok,
    required this.message,
    this.remoteAntiqueId,
    this.remoteSportsCardId,
    this.duplicate = false,
  });

  final bool ok;
  final String message;
  final int? remoteAntiqueId;
  final int? remoteSportsCardId;
  final bool duplicate;
}

/// Android/iOS client for the private-beta local network sync receiver.
///
/// Pairing information is kept in memory and also persisted in the app's
/// private documents directory so a mobile restart does not require pairing
/// again while the Windows receiver/token remain valid.
class LocalNetworkSyncClient {
  static String? _pairedHost;
  static int? _pairedPort;
  static String? _pairedToken;

  static bool get hasActivePairing =>
      (_pairedHost?.isNotEmpty ?? false) &&
      (_pairedPort ?? 0) > 0 &&
      (_pairedToken?.isNotEmpty ?? false);

  static bool _storedPairingLoaded = false;

  static Future<File> _pairingFile() async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(path.join(documents.path, 'Heirloom Atlas'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File(path.join(folder.path, 'mobile_windows_pairing.json'));
  }

  static Future<bool> restoreStoredPairing() async {
    if (_storedPairingLoaded) return hasActivePairing;
    _storedPairingLoaded = true;

    try {
      final file = await _pairingFile();
      if (!await file.exists()) return false;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return false;

      final host = decoded['host']?.toString().trim() ?? '';
      final port = int.tryParse(decoded['port']?.toString() ?? '');
      final token = decoded['token']?.toString().trim().toUpperCase() ?? '';

      if (host.isEmpty || port == null || port <= 0 || port > 65535 || token.isEmpty) {
        return false;
      }

      _pairedHost = host;
      _pairedPort = port;
      _pairedToken = token;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _persistPairing() async {
    final host = _pairedHost;
    final port = _pairedPort;
    final token = _pairedToken;
    if (host == null || port == null || token == null) return;

    final file = await _pairingFile();
    await file.writeAsString(jsonEncode({
      'host': host,
      'port': port,
      'token': token,
    }), flush: true);
  }

  Future<LocalNetworkPairingResult> checkPairing({
    required String host,
    required int port,
    required String pairingToken,
  }) async {
    final cleanHost = host.trim();
    final cleanToken = pairingToken.trim().toUpperCase();

    if (cleanHost.isEmpty) {
      return const LocalNetworkPairingResult(
        ok: false,
        message: 'Enter the Windows address.',
      );
    }
    if (port <= 0 || port > 65535) {
      return const LocalNetworkPairingResult(
        ok: false,
        message: 'Enter a valid receiver port.',
      );
    }
    if (cleanToken.isEmpty) {
      return const LocalNetworkPairingResult(
        ok: false,
        message: 'Enter the pairing token shown on Windows.',
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri(
        scheme: 'http',
        host: cleanHost,
        port: port,
        path: '/pairing/check',
      );
      final request = await client.postUrl(uri);
      request.headers.set('x-heirloom-pairing-token', cleanToken);
      request.headers.contentType = ContentType.json;
      request.write('{}');

      final response = await request.close().timeout(const Duration(seconds: 6));
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.ok) {
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['ok'] == true) {
            _pairedHost = cleanHost;
            _pairedPort = port;
            _pairedToken = cleanToken;
            _storedPairingLoaded = true;
            await _persistPairing();
            return const LocalNetworkPairingResult(
              ok: true,
              message: 'Paired with Heirloom Atlas on Windows.',
            );
          }
        } catch (_) {}
      }

      if (response.statusCode == HttpStatus.unauthorized) {
        return const LocalNetworkPairingResult(
          ok: false,
          message: 'The pairing token was not accepted.',
        );
      }

      return LocalNetworkPairingResult(
        ok: false,
        message: 'Windows receiver returned HTTP ${response.statusCode}.',
      );
    } on SocketException catch (error) {
      return LocalNetworkPairingResult(
        ok: false,
        message: 'Could not reach the Windows receiver: ${error.message}',
      );
    } on TimeoutException {
      return const LocalNetworkPairingResult(
        ok: false,
        message: 'The Windows receiver did not respond in time.',
      );
    } catch (error) {
      return LocalNetworkPairingResult(
        ok: false,
        message: 'Could not pair with Windows: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<LocalNetworkTransferResult> sendAntique({
    required String changeUuid,
    required String recordUuid,
    required String title,
    required String description,
    required String notes,
    required String imagePath,
  }) async {
    await restoreStoredPairing();
    final host = _pairedHost;
    final port = _pairedPort;
    final token = _pairedToken;
    if (host == null || port == null || token == null) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'Pair with the Windows receiver before syncing.',
      );
    }

    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The saved Antique photo could not be found.',
      );
    }

    final imageLength = await imageFile.length();
    if (imageLength <= 0 || imageLength > 25 * 1024 * 1024) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The Antique photo is too large for this beta sync test.',
      );
    }

    final imageBytes = await imageFile.readAsBytes();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/sync/antique',
      );
      final request = await client.postUrl(uri);
      request.headers.set('x-heirloom-pairing-token', token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'change_uuid': changeUuid,
        'record_uuid': recordUuid,
        'entity_type': 'antique',
        'operation': 'create',
        'antique': {
          'title': title,
          'description': description,
          'notes': notes,
        },
        'image': {
          'filename': imageFile.uri.pathSegments.isEmpty
              ? 'antique.jpg'
              : imageFile.uri.pathSegments.last,
          'base64': base64Encode(imageBytes),
        },
      }));

      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(body);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}

      if (response.statusCode == HttpStatus.ok && decoded?['ok'] == true) {
        final rawId = decoded?['antique_id'];
        final antiqueId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        final duplicate = decoded?['duplicate'] == true;
        return LocalNetworkTransferResult(
          ok: true,
          remoteAntiqueId: antiqueId,
          duplicate: duplicate,
          message: duplicate
              ? 'Windows already received this Antique.'
              : 'Antique synced to Heirloom Atlas on Windows.',
        );
      }

      if (response.statusCode == HttpStatus.unauthorized) {
        return const LocalNetworkTransferResult(
          ok: false,
          message: 'Windows no longer accepts this pairing token. Pair again.',
        );
      }

      final receiverError = decoded?['error']?.toString().trim() ?? '';
      return LocalNetworkTransferResult(
        ok: false,
        message: receiverError.isEmpty
            ? 'Windows receiver returned HTTP ${response.statusCode}.'
            : 'Windows receiver could not import the Antique: $receiverError',
      );
    } on SocketException catch (error) {
      return LocalNetworkTransferResult(
        ok: false,
        message: 'Could not reach the Windows receiver: ${error.message}',
      );
    } on TimeoutException {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The Windows receiver did not finish the transfer in time.',
      );
    } catch (error) {
      return LocalNetworkTransferResult(
        ok: false,
        message: 'Could not sync the Antique to Windows: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<LocalNetworkTransferResult> sendSportsCard({
    required String changeUuid,
    required String recordUuid,
    required String player,
    required String year,
    required String brand,
    required String setName,
    required String cardNumber,
    required String condition,
    required String storageLocation,
    required String notes,
    required String frontImagePath,
    String backImagePath = '',
    String sport = 'Baseball',
    String team = '',
  }) async {
    await restoreStoredPairing();
    final host = _pairedHost;
    final port = _pairedPort;
    final token = _pairedToken;
    if (host == null || port == null || token == null) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'Pair with the Windows receiver before syncing.',
      );
    }

    final frontFile = File(frontImagePath);
    if (!await frontFile.exists()) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The saved Sports Card front photo could not be found.',
      );
    }

    final frontLength = await frontFile.length();
    if (frontLength <= 0 || frontLength > 25 * 1024 * 1024) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The Sports Card front photo is too large for this beta sync test.',
      );
    }

    File? backFile;
    if (backImagePath.trim().isNotEmpty) {
      final candidate = File(backImagePath);
      if (await candidate.exists()) {
        final backLength = await candidate.length();
        if (backLength <= 0 || backLength > 25 * 1024 * 1024) {
          return const LocalNetworkTransferResult(
            ok: false,
            message: 'The Sports Card back photo is too large for this beta sync test.',
          );
        }
        backFile = candidate;
      }
    }

    final frontBytes = await frontFile.readAsBytes();
    final backBytes = backFile == null ? null : await backFile.readAsBytes();

    Map<String, Object?> imagePayload(File file, List<int> bytes) => {
      'filename': file.uri.pathSegments.isEmpty
          ? 'sports_card.jpg'
          : file.uri.pathSegments.last,
      'base64': base64Encode(bytes),
    };

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/sync/sports-card',
      );
      final request = await client.postUrl(uri);
      request.headers.set('x-heirloom-pairing-token', token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'change_uuid': changeUuid,
        'record_uuid': recordUuid,
        'entity_type': 'sports_card',
        'operation': 'create',
        'card': {
          'sport': sport,
          'year': year,
          'brand': brand,
          'set_name': setName,
          'card_number': cardNumber,
          'player': player,
          'team': team,
          'condition': condition,
          'storage_location': storageLocation,
          'notes': notes,
        },
        'front_image': imagePayload(frontFile, frontBytes),
        if (backFile != null && backBytes != null)
          'back_image': imagePayload(backFile, backBytes),
      }));

      final response = await request.close().timeout(const Duration(seconds: 25));
      final body = await response.transform(utf8.decoder).join();
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(body);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}

      if (response.statusCode == HttpStatus.ok && decoded?['ok'] == true) {
        final rawId = decoded?['sports_card_id'];
        final sportsCardId =
            rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        final duplicate = decoded?['duplicate'] == true;
        return LocalNetworkTransferResult(
          ok: true,
          remoteSportsCardId: sportsCardId,
          duplicate: duplicate,
          message: duplicate
              ? 'Windows already received this Sports Card.'
              : 'Sports Card synced to Heirloom Atlas on Windows.',
        );
      }

      if (response.statusCode == HttpStatus.unauthorized) {
        return const LocalNetworkTransferResult(
          ok: false,
          message: 'Windows no longer accepts this pairing token. Pair again.',
        );
      }

      final receiverError = decoded?['error']?.toString().trim() ?? '';
      return LocalNetworkTransferResult(
        ok: false,
        message: receiverError.isEmpty
            ? 'Windows receiver returned HTTP ${response.statusCode}.'
            : 'Windows receiver could not import the Sports Card: $receiverError',
      );
    } on SocketException catch (error) {
      return LocalNetworkTransferResult(
        ok: false,
        message: 'Could not reach the Windows receiver: ${error.message}',
      );
    } on TimeoutException {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The Windows receiver did not finish the Sports Card transfer in time.',
      );
    } catch (error) {
      return LocalNetworkTransferResult(
        ok: false,
        message: 'Could not sync the Sports Card to Windows: $error',
      );
    } finally {
      client.close(force: true);
    }
  }


  Future<LocalNetworkTransferResult> sendCoin({
    required String changeUuid,
    required String recordUuid,
    required String category,
    required String series,
    required String year,
    required String mint,
    required String variety,
    required String grade,
    required String storageLocation,
    required String notes,
    required String frontImagePath,
    String backImagePath = '',
  }) async {
    await restoreStoredPairing();
    final host = _pairedHost;
    final port = _pairedPort;
    final token = _pairedToken;
    if (host == null || port == null || token == null) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'Pair with the Windows receiver before syncing.',
      );
    }

    final frontFile = File(frontImagePath);
    if (!await frontFile.exists()) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The saved Coin front photo could not be found.',
      );
    }

    final frontLength = await frontFile.length();
    if (frontLength <= 0 || frontLength > 25 * 1024 * 1024) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The Coin front photo is too large for this beta sync test.',
      );
    }

    File? backFile;
    if (backImagePath.trim().isNotEmpty) {
      final candidate = File(backImagePath);
      if (await candidate.exists()) {
        final backLength = await candidate.length();
        if (backLength <= 0 || backLength > 25 * 1024 * 1024) {
          return const LocalNetworkTransferResult(
            ok: false,
            message: 'The Coin back photo is too large for this beta sync test.',
          );
        }
        backFile = candidate;
      }
    }

    final frontBytes = await frontFile.readAsBytes();
    final backBytes = backFile == null ? null : await backFile.readAsBytes();

    Map<String, Object?> imagePayload(File file, List<int> bytes) => {
      'filename': file.uri.pathSegments.isEmpty
          ? 'coin.jpg'
          : file.uri.pathSegments.last,
      'base64': base64Encode(bytes),
    };

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/sync/coin',
      );
      final request = await client.postUrl(uri);
      request.headers.set('x-heirloom-pairing-token', token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'change_uuid': changeUuid,
        'record_uuid': recordUuid,
        'entity_type': 'coin',
        'operation': 'create',
        'coin': {
          'category': category,
          'series': series,
          'year': year,
          'mint': mint,
          'variety': variety,
          'grade': grade,
          'storage_location': storageLocation,
          'notes': notes,
        },
        'front_image': imagePayload(frontFile, frontBytes),
        if (backFile != null && backBytes != null)
          'back_image': imagePayload(backFile, backBytes),
      }));

      final response =
          await request.close().timeout(const Duration(seconds: 25));
      final body = await response.transform(utf8.decoder).join();
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(body);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}

      if (response.statusCode == HttpStatus.ok && decoded?['ok'] == true) {
        final duplicate = decoded?['duplicate'] == true;
        return LocalNetworkTransferResult(
          ok: true,
          duplicate: duplicate,
          message: duplicate
              ? 'Windows already received this Coin.'
              : 'Coin synced to Heirloom Atlas on Windows.',
        );
      }

      if (response.statusCode == HttpStatus.unauthorized) {
        return const LocalNetworkTransferResult(
          ok: false,
          message: 'Windows no longer accepts this pairing token. Pair again.',
        );
      }

      final receiverError = decoded?['error']?.toString().trim() ?? '';
      return LocalNetworkTransferResult(
        ok: false,
        message: receiverError.isEmpty
            ? 'Windows receiver returned HTTP ${response.statusCode}.'
            : 'Windows receiver could not import the Coin: $receiverError',
      );
    } on SocketException catch (error) {
      return LocalNetworkTransferResult(
        ok: false,
        message: 'Could not reach the Windows receiver: ${error.message}',
      );
    } on TimeoutException {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The Windows receiver did not finish the Coin transfer in time.',
      );
    } catch (error) {
      return LocalNetworkTransferResult(
        ok: false,
        message: 'Could not sync the Coin to Windows: $error',
      );
    } finally {
      client.close(force: true);
    }
  }


  Future<LocalNetworkTransferResult> sendDocument({
    required String changeUuid,
    required String recordUuid,
    required String title,
    required String documentDate,
    required String documentType,
    required String people,
    required String description,
    required String source,
    required List<String> pagePaths,
  }) async {
    await restoreStoredPairing();
    final host = _pairedHost;
    final port = _pairedPort;
    final token = _pairedToken;
    if (host == null || port == null || token == null) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'Pair with the Windows receiver before syncing.',
      );
    }

    if (pagePaths.isEmpty) {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'This Document does not have any saved pages to sync.',
      );
    }

    final pages = <Map<String, Object?>>[];
    var totalBytes = 0;
    for (var i = 0; i < pagePaths.length; i++) {
      final file = File(pagePaths[i]);
      if (!await file.exists()) {
        return LocalNetworkTransferResult(
          ok: false,
          message: 'Document page ${i + 1} could not be found.',
        );
      }
      final length = await file.length();
      if (length <= 0 || length > 25 * 1024 * 1024) {
        return LocalNetworkTransferResult(
          ok: false,
          message: 'Document page ${i + 1} is too large for this beta sync test.',
        );
      }
      totalBytes += length;
      if (totalBytes > 100 * 1024 * 1024) {
        return const LocalNetworkTransferResult(
          ok: false,
          message: 'This Document is too large for this beta sync test.',
        );
      }
      final bytes = await file.readAsBytes();
      pages.add({
        'filename': file.uri.pathSegments.isEmpty
            ? 'document_page_${i + 1}.jpg'
            : file.uri.pathSegments.last,
        'base64': base64Encode(bytes),
      });
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/sync/document',
      );
      final request = await client.postUrl(uri);
      request.headers.set('x-heirloom-pairing-token', token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'change_uuid': changeUuid,
        'record_uuid': recordUuid,
        'entity_type': 'document',
        'operation': 'create',
        'document': {
          'title': title,
          'document_date': documentDate,
          'document_type': documentType,
          'people': people,
          'description': description,
          'source': source,
        },
        'pages': pages,
      }));

      final response =
          await request.close().timeout(const Duration(seconds: 60));
      final body = await response.transform(utf8.decoder).join();
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(body);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}

      if (response.statusCode == HttpStatus.ok && decoded?['ok'] == true) {
        final duplicate = decoded?['duplicate'] == true;
        return LocalNetworkTransferResult(
          ok: true,
          duplicate: duplicate,
          message: duplicate
              ? 'Windows already received this Document.'
              : 'Document synced to Heirloom Atlas on Windows.',
        );
      }

      if (response.statusCode == HttpStatus.unauthorized) {
        return const LocalNetworkTransferResult(
          ok: false,
          message: 'Windows no longer accepts this pairing token. Pair again.',
        );
      }

      final receiverError = decoded?['error']?.toString().trim() ?? '';
      return LocalNetworkTransferResult(
        ok: false,
        message: receiverError.isEmpty
            ? 'Windows receiver returned HTTP ${response.statusCode}.'
            : 'Windows receiver could not import the Document: $receiverError',
      );
    } on SocketException catch (error) {
      return LocalNetworkTransferResult(
        ok: false,
        message: 'Could not reach the Windows receiver: ${error.message}',
      );
    } on TimeoutException {
      return const LocalNetworkTransferResult(
        ok: false,
        message: 'The Windows receiver did not finish the Document transfer in time.',
      );
    } catch (error) {
      return LocalNetworkTransferResult(
        ok: false,
        message: 'Could not sync the Document to Windows: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

}
