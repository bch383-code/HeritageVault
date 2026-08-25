import 'dart:convert';
import 'dart:io';

class SportsCardPriceQuote {
  final String provider;
  final String query;
  final String productId;
  final String productName;
  final String setName;
  final Map<String, double> prices;

  const SportsCardPriceQuote({
    required this.provider,
    required this.query,
    required this.productId,
    required this.productName,
    required this.setName,
    required this.prices,
  });
}

abstract class SportsCardPriceProvider {
  String get name;

  Future<SportsCardPriceQuote?> lookup({
    required String token,
    required String query,
  });
}

class SportsCardsProPriceProvider implements SportsCardPriceProvider {
  @override
  String get name => 'SportsCardsPro';

  @override
  Future<SportsCardPriceQuote?> lookup({
    required String token,
    required String query,
  }) async {
    final cleanToken = token.trim();
    final cleanQuery = query.trim();

    if (cleanToken.isEmpty) {
      throw ArgumentError('An API token is required.');
    }
    if (cleanQuery.isEmpty) {
      throw ArgumentError('A search query is required.');
    }

    final uri = Uri.https(
      'www.sportscardspro.com',
      '/api/product',
      {
        't': cleanToken,
        'q': cleanQuery,
      },
    );

    final client = HttpClient();

    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'HeirloomAtlas/1.0',
      );

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Pricing service returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map) {
        throw const FormatException(
          'Unexpected pricing response.',
        );
      }

      final json = Map<String, dynamic>.from(decoded);

      if ((json['status']?.toString() ?? '').toLowerCase() != 'success') {
        final message = json['error']?.toString() ??
            json['message']?.toString() ??
            'No matching card was found.';
        throw StateError(message);
      }

      final prices = <String, double>{};

      void addPrice(String key, String label) {
        final raw = json[key];
        if (raw == null) return;

        final pennies = raw is num
            ? raw.toDouble()
            : double.tryParse(raw.toString());

        if (pennies == null || pennies <= 0) return;
        prices[label] = pennies / 100.0;
      }

      addPrice('loose-price', 'Ungraded / Raw');
      addPrice('condition-10-price', 'Grade 2');
      addPrice('condition-13-price', 'Grade 3');
      addPrice('condition-14-price', 'Grade 4');
      addPrice('condition-15-price', 'Grade 5');
      addPrice('condition-16-price', 'Grade 6');
      addPrice('cib-price', 'Grade 7 / 7.5');
      addPrice('box-only-price', 'Grade 9.5');
      addPrice('new-price', 'Grade 10');
      addPrice('bgs-10-price', 'BGS 10');
      addPrice('condition-17-price', 'CGC 10');

      return SportsCardPriceQuote(
        provider: name,
        query: cleanQuery,
        productId: json['id']?.toString() ?? '',
        productName: json['product-name']?.toString() ?? '',
        setName: json['console-name']?.toString() ?? '',
        prices: prices,
      );
    } finally {
      client.close(force: true);
    }
  }
}
