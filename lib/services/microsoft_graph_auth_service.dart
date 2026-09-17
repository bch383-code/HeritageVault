import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class MicrosoftGraphAuthSession {
  const MicrosoftGraphAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.accountDisplayName,
    required this.accountEmail,
    required this.driveId,
    required this.driveName,
    required this.driveType,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String accountDisplayName;
  final String accountEmail;
  final String driveId;
  final String driveName;
  final String driveType;

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));
}

class MicrosoftGraphDriveItem {
  const MicrosoftGraphDriveItem({
    required this.id,
    required this.name,
    required this.parentId,
    required this.eTag,
    required this.lastModifiedMilliseconds,
    required this.size,
  });

  final String id;
  final String name;
  final String parentId;
  final String eTag;
  final int lastModifiedMilliseconds;
  final int size;
}

class MicrosoftGraphAuthService {
  MicrosoftGraphAuthService();

  static const String _dartDefineClientId =
      String.fromEnvironment('HEIRLOOM_ATLAS_MS_CLIENT_ID');

  static const List<String> readOnlyScopes = [
    'openid',
    'profile',
    'email',
    'offline_access',
    'User.Read',
    'Files.Read',
  ];

  String get clientId {
    final fromDefine = _dartDefineClientId.trim();
    if (fromDefine.isNotEmpty) return fromDefine;

    return (Platform.environment['HEIRLOOM_ATLAS_MS_CLIENT_ID'] ?? '').trim();
  }

  bool get isConfigured => clientId.isNotEmpty;

  Future<MicrosoftGraphAuthSession> authorizeReadOnly() async {
    if (!Platform.isWindows) {
      throw StateError(
        'Microsoft account authorization is currently enabled for Windows only.',
      );
    }

    final cleanClientId = clientId;
    if (cleanClientId.isEmpty) {
      throw StateError(
        'Microsoft client ID is not configured. Set '
        'HEIRLOOM_ATLAS_MS_CLIENT_ID before starting the app.',
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://localhost:${server.port}';
    final verifier = _createPkceVerifier();
    final challenge = _sha256Base64Url(verifier);
    final state = _randomToken(32);

    final authorizeUri = Uri.https(
      'login.microsoftonline.com',
      '/common/oauth2/v2.0/authorize',
      {
        'client_id': cleanClientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'response_mode': 'query',
        'scope': readOnlyScopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'prompt': 'select_account',
      },
    );

    try {
      await _openSystemBrowser(authorizeUri.toString());

      final callback = await server.first.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException(
          'Microsoft sign-in timed out. Start the connection again.',
        ),
      );

      final params = callback.uri.queryParameters;
      final returnedState = params['state'] ?? '';
      final error = params['error'] ?? '';
      final errorDescription = params['error_description'] ?? '';

      if (error.isNotEmpty) {
        await _respondToBrowser(
          callback,
          'Microsoft sign-in was not completed.',
        );
        throw StateError(
          errorDescription.isNotEmpty
              ? errorDescription
              : 'Microsoft sign-in failed ($error).',
        );
      }

      if (returnedState != state) {
        await _respondToBrowser(
          callback,
          'The sign-in response could not be verified.',
        );
        throw StateError('Microsoft sign-in state verification failed.');
      }

      final code = params['code'] ?? '';
      if (code.isEmpty) {
        await _respondToBrowser(
          callback,
          'Microsoft did not return an authorization code.',
        );
        throw StateError('Microsoft did not return an authorization code.');
      }

      await _respondToBrowser(
        callback,
        'Microsoft sign-in completed. You can close this browser tab and return to Heirloom Atlas.',
      );

      final token = await _postForm(
        Uri.parse(
          'https://login.microsoftonline.com/common/oauth2/v2.0/token',
        ),
        {
          'client_id': cleanClientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'code_verifier': verifier,
          'scope': readOnlyScopes.join(' '),
        },
      );

      final accessToken = token['access_token']?.toString().trim() ?? '';
      if (accessToken.isEmpty) {
        throw StateError(
          _oauthErrorMessage(
            token,
            fallback: 'Microsoft did not return an access token.',
          ),
        );
      }

      final refreshToken = token['refresh_token']?.toString().trim() ?? '';
      final expiresIn = _asInt(token['expires_in'], fallback: 3600);

      final me = await _getJson(
        Uri.parse(
          'https://graph.microsoft.com/v1.0/me'
          r'?$select=displayName,mail,userPrincipalName',
        ),
        accessToken,
      );
      final drive = await _getJson(
        Uri.parse(
          'https://graph.microsoft.com/v1.0/me/drive'
          r'?$select=id,name,driveType',
        ),
        accessToken,
      );

      return MicrosoftGraphAuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        accountDisplayName:
            me['displayName']?.toString().trim() ?? '',
        accountEmail:
            (me['mail']?.toString().trim().isNotEmpty == true
                    ? me['mail']
                    : me['userPrincipalName'])
                ?.toString()
                .trim() ??
            '',
        driveId: drive['id']?.toString().trim() ?? '',
        driveName: drive['name']?.toString().trim() ?? '',
        driveType: drive['driveType']?.toString().trim() ?? '',
      );
    } finally {
      await server.close(force: true);
    }
  }

  String _createPkceVerifier() => _randomToken(64);

  String _randomToken(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _sha256Base64Url(String value) {
    final bytes = utf8.encode(value);
    final digest = _sha256(bytes);
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  List<int> _sha256(List<int> input) {
    const k = <int>[
      0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
      0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
      0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
      0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
      0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
      0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
      0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
      0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
    ];

    int rotr(int x, int n) => (x >>> n) | ((x << (32 - n)) & 0xffffffff);
    int add32(int x) => x & 0xffffffff;

    final message = <int>[...input, 0x80];
    while (message.length % 64 != 56) {
      message.add(0);
    }

    final bitLength = input.length * 8;
    for (var i = 7; i >= 0; i--) {
      message.add((bitLength >>> (i * 8)) & 0xff);
    }

    var h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    var h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
    final w = List<int>.filled(64, 0);

    for (var offset = 0; offset < message.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        w[i] = ((message[j] << 24) |
                (message[j + 1] << 16) |
                (message[j + 2] << 8) |
                message[j + 3]) &
            0xffffffff;
      }

      for (var i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = add32(w[i - 16] + s0 + w[i - 7] + s1);
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = add32(h + s1 + ch + k[i] + w[i]);
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = add32(s0 + maj);

        h = g; g = f; f = e; e = add32(d + temp1);
        d = c; c = b; b = a; a = add32(temp1 + temp2);
      }

      h0 = add32(h0 + a); h1 = add32(h1 + b); h2 = add32(h2 + c); h3 = add32(h3 + d);
      h4 = add32(h4 + e); h5 = add32(h5 + f); h6 = add32(h6 + g); h7 = add32(h7 + h);
    }

    final out = <int>[];
    for (final value in [h0,h1,h2,h3,h4,h5,h6,h7]) {
      out.add((value >>> 24) & 0xff);
      out.add((value >>> 16) & 0xff);
      out.add((value >>> 8) & 0xff);
      out.add(value & 0xff);
    }
    return out;
  }

  Future<void> _respondToBrowser(
    HttpRequest request,
    String message,
  ) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.html;
    final safe = const HtmlEscape().convert(message);
    request.response.write(
      '<!doctype html><html><body style="font-family:Segoe UI,Arial,sans-serif;'
      'padding:40px;max-width:720px;margin:auto;">'
      '<h2>Heirloom Atlas</h2><p>$safe</p></body></html>',
    );
    await request.response.close();
  }

  Future<MicrosoftGraphDriveItem?> resolveDriveItemByPath({
    required MicrosoftGraphAuthSession session,
    required String relativePath,
  }) async {
    final clean = relativePath
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();

    if (clean.isEmpty) return null;

    final encodedPath = clean.map(Uri.encodeComponent).join('/');
    final uri = Uri.parse(
      'https://graph.microsoft.com/v1.0/me/drive/root:/$encodedPath'
      r'?$select=id,name,eTag,lastModifiedDateTime,size,parentReference',
    );

    final result = await _getJsonOrNull(uri, session.accessToken);
    if (result == null) return null;

    final id = result['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;

    final parent = result['parentReference'];
    var parentId = '';
    if (parent is Map) {
      parentId = parent['id']?.toString().trim() ?? '';
    }

    final modifiedText =
        result['lastModifiedDateTime']?.toString().trim() ?? '';
    final modified = DateTime.tryParse(modifiedText);

    return MicrosoftGraphDriveItem(
      id: id,
      name: result['name']?.toString().trim() ?? '',
      parentId: parentId,
      eTag: result['eTag']?.toString().trim() ?? '',
      lastModifiedMilliseconds:
          modified?.millisecondsSinceEpoch ?? 0,
      size: int.tryParse(result['size']?.toString() ?? '') ?? 0,
    );
  }

  Future<Map<String, Object?>?> _getJsonOrNull(
    Uri uri,
    String accessToken,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response =
          await request.close().timeout(const Duration(seconds: 8));
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == HttpStatus.notFound) {
        return null;
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw StateError('Microsoft Graph returned an unexpected response.');
      }

      final result = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          _graphErrorMessage(
            result,
            fallback:
                'Microsoft Graph request failed (${response.statusCode}).',
          ),
        );
      }

      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> _postForm(
    Uri uri,
    Map<String, String> fields, {
    bool allowOAuthErrors = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      request.write(
        fields.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}='
                  '${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&'),
      );

      final response =
          await request.close().timeout(const Duration(seconds: 8));
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw StateError('Microsoft returned an unexpected response.');
      }

      final result = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (allowOAuthErrors && result['error'] != null) {
          return result;
        }
        throw StateError(
          _oauthErrorMessage(
            result,
            fallback:
                'Microsoft request failed (${response.statusCode}).',
          ),
        );
      }

      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> _getJson(
    Uri uri,
    String accessToken,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response =
          await request.close().timeout(const Duration(seconds: 8));
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(body);

      if (decoded is! Map) {
        throw StateError('Microsoft Graph returned an unexpected response.');
      }

      final result = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          _graphErrorMessage(
            result,
            fallback:
                'Microsoft Graph request failed (${response.statusCode}).',
          ),
        );
      }

      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openSystemBrowser(String url) async {
    if (!Platform.isWindows) {
      throw StateError('System browser launch is currently Windows-only.');
    }

    try {
      await Process.start(
        'rundll32.exe',
        ['url.dll,FileProtocolHandler', url],
        mode: ProcessStartMode.detached,
      );
      return;
    } catch (_) {
      try {
        await Process.start(
          'explorer.exe',
          [url],
          mode: ProcessStartMode.detached,
        );
        return;
      } catch (_) {
        throw StateError(
          'Could not open the Microsoft sign-in page in the system browser.',
        );
      }
    }
  }

  int _asInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _oauthErrorMessage(
    Map<String, Object?> response, {
    required String fallback,
  }) {
    final description =
        response['error_description']?.toString().trim() ?? '';
    if (description.isNotEmpty) return description;

    final error = response['error']?.toString().trim() ?? '';
    return error.isEmpty ? fallback : '$fallback ($error)';
  }

  String _graphErrorMessage(
    Map<String, Object?> response, {
    required String fallback,
  }) {
    final error = response['error'];
    if (error is Map) {
      final message = error['message']?.toString().trim() ?? '';
      if (message.isNotEmpty) return message;
    }
    return fallback;
  }
}
