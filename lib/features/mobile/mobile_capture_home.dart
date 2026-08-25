import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../database/database_helper.dart';
import '../../models/sports_card.dart';

enum MobileCaptureType {
  photo,
  sportsCard,
  coin,
  antique,
}

extension MobileCaptureTypeDetails on MobileCaptureType {
  String get title {
    switch (this) {
      case MobileCaptureType.photo:
        return 'Photo';
      case MobileCaptureType.sportsCard:
        return 'Sports Card';
      case MobileCaptureType.coin:
        return 'Coin';
      case MobileCaptureType.antique:
        return 'Antique';
    }
  }

  String get folderName {
    switch (this) {
      case MobileCaptureType.photo:
        return 'Photos';
      case MobileCaptureType.sportsCard:
        return 'Sports Cards';
      case MobileCaptureType.coin:
        return 'Coins';
      case MobileCaptureType.antique:
        return 'Antiques';
    }
  }

  IconData get icon {
    switch (this) {
      case MobileCaptureType.photo:
        return Icons.photo_camera_outlined;
      case MobileCaptureType.sportsCard:
        return Icons.style_outlined;
      case MobileCaptureType.coin:
        return Icons.monetization_on_outlined;
      case MobileCaptureType.antique:
        return Icons.inventory_2_outlined;
    }
  }

  String get helper {
    switch (this) {
      case MobileCaptureType.photo:
        return 'Capture a family or heritage photo.';
      case MobileCaptureType.sportsCard:
        return 'Photograph a card for your collection.';
      case MobileCaptureType.coin:
        return 'Capture a clear image of a coin.';
      case MobileCaptureType.antique:
        return 'Photograph an antique or heirloom.';
    }
  }
}

class MobileCaptureHome extends StatelessWidget {
  const MobileCaptureHome({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF071A2B);
    const gold = Color(0xFFC9A65A);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text(
          'Heirloom Atlas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 54,
              color: gold,
            ),
            const SizedBox(height: 12),
            Text(
              'Capture & Add',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose what you want to photograph.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 26),
            for (final type in MobileCaptureType.values) ...[
              _CaptureTypeCard(type: type),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 10),
            Text(
              'Mobile prototype • captures are saved locally on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureTypeCard extends StatelessWidget {
  final MobileCaptureType type;

  const _CaptureTypeCard({
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => type == MobileCaptureType.sportsCard
                  ? const MobileSportsCardCaptureScreen()
                  : MobileCaptureScreen(type: type),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  type.icon,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 3),
                    Text(type.helper),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}


class MobileSportsCardCaptureScreen extends StatefulWidget {
  const MobileSportsCardCaptureScreen({super.key});

  @override
  State<MobileSportsCardCaptureScreen> createState() =>
      _MobileSportsCardCaptureScreenState();
}

class _MobileSportsCardCaptureScreenState
    extends State<MobileSportsCardCaptureScreen> {
  final ImagePicker _picker = ImagePicker();

  XFile? _front;
  XFile? _back;
  XFile? _numberCloseup;
  bool _saving = false;
  bool _saved = false;
  bool _identifying = false;
  String _recognizedText = '';
  String _backRecognizedText = '';
  String _identificationMessage = '';
  _CardChecklistMatch? _pendingMatch;
  List<_CardChecklistMatch> _candidateMatches = [];
  bool _pendingMatchFromChecklist = false;
  _CardChecklistMatch? _acceptedMatch;

  final _playerController = TextEditingController();
  final _yearController = TextEditingController();
  final _brandSetController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _conditionController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _playerController.dispose();
    _yearController.dispose();
    _brandSetController.dispose();
    _cardNumberController.dispose();
    _conditionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<XFile?> _capture(ImageSource source) {
    return _picker.pickImage(
      source: source,
      imageQuality: 95,
      preferredCameraDevice: CameraDevice.rear,
    );
  }

  Future<void> _takeFront() async {
    final file = await _capture(ImageSource.camera);
    if (file == null || !mounted) return;
    setState(() {
      _front = file;
      _saved = false;
      _recognizedText = '';
      _backRecognizedText = '';
      _identificationMessage = '';
      _pendingMatch = null;
      _candidateMatches = [];
      _pendingMatchFromChecklist = false;
      _acceptedMatch = null;
    });
  }

  Future<void> _takeBack() async {
    final file = await _capture(ImageSource.camera);
    if (file == null || !mounted) return;
    setState(() {
      _back = file;
      _saved = false;
      _recognizedText = '';
      _backRecognizedText = '';
      _identificationMessage = '';
      _pendingMatch = null;
      _candidateMatches = [];
      _pendingMatchFromChecklist = false;
      _acceptedMatch = null;
    });
  }

  Future<void> _chooseFront() async {
    final file = await _capture(ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() {
      _front = file;
      _saved = false;
      _recognizedText = '';
      _backRecognizedText = '';
      _identificationMessage = '';
      _pendingMatch = null;
      _candidateMatches = [];
      _pendingMatchFromChecklist = false;
      _acceptedMatch = null;
    });
  }

  Future<void> _chooseBack() async {
    final file = await _capture(ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() {
      _back = file;
      _saved = false;
      _recognizedText = '';
      _backRecognizedText = '';
      _identificationMessage = '';
      _pendingMatch = null;
      _candidateMatches = [];
      _pendingMatchFromChecklist = false;
      _acceptedMatch = null;
    });
  }

  Future<void> _captureCardNumber() async {
    if (_identifying || _saving) return;

    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null || !mounted) return;

      setState(() {
        _numberCloseup = image;
        _saved = false;
        _pendingMatch = null;
        _pendingMatchFromChecklist = false;
        _acceptedMatch = null;
        _identificationMessage =
            'Card # close-up captured. Tap Identify Card.';
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture card number: $error')),
      );
    }
  }

  Future<void> _identifyCard() async {
    final front = _front;
    if (front == null || _identifying) return;

    setState(() {
      _identifying = true;
      _identificationMessage = '';
    });

    final recognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );

    try {
      Future<String> scan(XFile file) async {
        final inputImage = InputImage.fromFilePath(file.path);
        final result = await recognizer.processImage(inputImage);
        return result.text.trim();
      }

      final frontText = await scan(front);
      final backText = _back == null ? '' : await scan(_back!);
      final closeupNumberText =
          _numberCloseup == null ? '' : await scan(_numberCloseup!);
      final recognized = [
        if (frontText.isNotEmpty) 'FRONT:\n$frontText',
        if (backText.isNotEmpty) 'BACK:\n$backText',
        if (closeupNumberText.isNotEmpty)
          'CARD # CLOSE-UP:\n$closeupNumberText',
      ].join('\n\n');

      final frontSuggestions = _suggestCardFields(frontText);
      final backSuggestions = _suggestCardFields(backText);
      final suggestions = _CardTextSuggestions(
        year: backSuggestions.year.isNotEmpty
            ? backSuggestions.year
            : frontSuggestions.year,
        cardNumber: '',
        brand: frontSuggestions.brand.isNotEmpty
            ? frontSuggestions.brand
            : backSuggestions.brand,
        player: frontSuggestions.player,
      );

      if (!mounted) return;

      if (suggestions.year.isNotEmpty &&
          _yearController.text.trim().isEmpty) {
        _yearController.text = suggestions.year;
      }

      if (suggestions.brand.isNotEmpty &&
          _brandSetController.text.trim().isEmpty) {
        _brandSetController.text = suggestions.brand;
      }

      // Player and card number remain manual until a checklist match
      // validates them. This avoids saving misleading OCR guesses.
      _playerController.clear();

      setState(() {
        _recognizedText = recognized;
        _backRecognizedText = backText;
        _pendingMatch = null;
        _pendingMatchFromChecklist = false;
        _acceptedMatch = null;
        _identificationMessage = recognized.isEmpty
            ? 'No readable text was found. Enter Year, Brand / Set, and Card # manually.'
            : suggestions.hasAny
                ? 'OCR filled what it could. Enter Card #, then tap Match Checklist. Brand / Set is optional but helps ranking.'
                : 'Text was recognized. Enter Year, Brand / Set, and Card #, then tap Match Checklist.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _identificationMessage = 'Could not identify this card: $error';
      });
    } finally {
      await recognizer.close();
      if (mounted) {
        setState(() => _identifying = false);
      }
    }
  }

  Future<void> _matchManualCardNumber() async {
    if (_identifying || _saving) return;

    final year = _yearController.text.trim();
    final brandOrSet = _brandSetController.text.trim();
    final cardNumber = _cardNumberController.text.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(year)) {
      setState(() {
        _identificationMessage =
            'Enter a 4-digit year before matching the checklist.';
      });
      return;
    }

    if (cardNumber.isEmpty) {
      setState(() {
        _identificationMessage =
            'Enter the card number before matching the checklist.';
      });
      return;
    }

    setState(() {
      _identifying = true;
      _pendingMatch = null;
      _candidateMatches = [];
      _pendingMatchFromChecklist = false;
      _acceptedMatch = null;
      _identificationMessage = 'Searching checklist...';
    });

    try {
      final matches = await _matchCardListsChecklist(
        year: year,
        brandOrSet: brandOrSet,
        cardNumber: cardNumber,
      );

      if (!mounted) return;

      setState(() {
        _candidateMatches = matches;
        _pendingMatch = matches.length == 1 ? matches.first : null;
        _pendingMatchFromChecklist = matches.isNotEmpty;
        _identificationMessage = matches.isEmpty
            ? 'No checklist matches found for $year #$cardNumber.'
            : matches.length == 1
                ? 'Checklist match found. Confirm it below.'
                : '${matches.length} checklist matches found. Choose the correct card below.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _identificationMessage =
            'Could not search the checklist: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _identifying = false);
      }
    }
  }

  Future<List<_CardChecklistMatch>> _matchCardListsChecklist({
    required String year,
    required String brandOrSet,
    required String cardNumber,
  }) async {
    if (!RegExp(r'^\d{4}$').hasMatch(year) || cardNumber.isEmpty) {
      return const [];
    }

    final client = HttpClient()..userAgent = 'HeirloomAtlas/1.0';

    String normalize(String value) => value
        .toLowerCase()
        .replaceAll('—', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\.json$'), '')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    try {
      final listingUri = Uri.parse(
        'https://api.github.com/repos/robert-porter/CardLists/'
        'contents/baseball/$year?ref=main',
      );

      final listingRequest = await client.getUrl(listingUri);
      listingRequest.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final listingResponse = await listingRequest.close();

      if (listingResponse.statusCode != HttpStatus.ok) {
        return const [];
      }

      final listingBody =
          await listingResponse.transform(utf8.decoder).join();
      final decodedListing = jsonDecode(listingBody);
      if (decodedListing is! List) return const [];

      final wanted = normalize(brandOrSet)
          .replaceFirst(RegExp('^$year '), '')
          .trim();
      final wantedWords =
          wanted.split(' ').where((word) => word.length >= 3).toSet();

      final files = decodedListing
          .whereType<Map>()
          .where((item) =>
              item['type'] == 'file' &&
              (item['name']?.toString().toLowerCase().endsWith('.json') ??
                  false))
          .map((item) {
            final name = item['name']?.toString() ?? '';
            final normalizedName =
                normalize(name).replaceFirst(RegExp('^$year '), '').trim();
            return _ChecklistFileCandidate(
              name: name,
              path: item['path']?.toString() ?? '',
              normalizedName: normalizedName,
              downloadUrl: item['download_url']?.toString() ?? '',
            );
          })
          .where((file) => file.downloadUrl.isNotEmpty)
          .toList();

      int brandScore(_ChecklistFileCandidate file) {
        if (wanted.isEmpty) return 0;
        if (file.normalizedName == wanted) return 100;
        if (file.normalizedName.contains(wanted) ||
            wanted.contains(file.normalizedName)) {
          return 75;
        }
        final fileWords = file.normalizedName.split(' ').toSet();
        return wantedWords.where(fileWords.contains).length * 10;
      }

      // Search likely brand files first, but do not exclude other sets.
      files.sort((a, b) {
        final scoreCompare = brandScore(b).compareTo(brandScore(a));
        if (scoreCompare != 0) return scoreCompare;
        return a.normalizedName.compareTo(b.normalizedName);
      });

      final allMatches = <_CardChecklistMatch>[];

      for (final candidate in files) {
        final request = await client.getUrl(Uri.parse(candidate.downloadUrl));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) continue;

        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is! Map) continue;

        final root = Map<String, dynamic>.from(decoded);
        final rawSets = root['sets'];
        if (rawSets is! List) continue;

        final resolvedBrand = candidate.normalizedName
            .split(' ')
            .map((part) => part.isEmpty
                ? part
                : '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');

        for (final rawSet in rawSets) {
          if (rawSet is! Map) continue;

          final set = Map<String, dynamic>.from(rawSet);
          final setName = set['name']?.toString().trim() ?? '';
          final rawCards = set['cards'];
          if (rawCards is! List) continue;

          final setCards = <SportsCard>[];

          for (final rawCard in rawCards) {
            if (rawCard is! Map) continue;
            final card = Map<String, dynamic>.from(rawCard);
            final number = card['number']?.toString().trim() ?? '';
            final player = card['name']?.toString().trim() ?? '';
            if (number.isEmpty || player.isEmpty) continue;

            final attributes = card['attributes'] is List
                ? (card['attributes'] as List)
                    .map((value) => value.toString())
                    .where((value) => value.trim().isNotEmpty)
                    .join(', ')
                : '';

            setCards.add(
              SportsCard(
                sport: 'Baseball',
                year: year,
                brand: resolvedBrand,
                setName: setName,
                cardNumber: number,
                player: player,
                attributes: attributes,
              ),
            );
          }

          for (final card in setCards) {
            if (_sameCardNumber(card.cardNumber, cardNumber)) {
              allMatches.add(
                _CardChecklistMatch(
                  year: year,
                  brand: resolvedBrand,
                  setName: setName,
                  cardNumber: card.cardNumber,
                  player: card.player,
                  sourceKey: candidate.path.isEmpty
                      ? ''
                      : 'cardlists:${candidate.path}#$setName',
                  cards: setCards,
                  brandScore: brandScore(candidate),
                ),
              );
            }
          }
        }
      }

      allMatches.sort((a, b) {
        final scoreCompare = b.brandScore.compareTo(a.brandScore);
        if (scoreCompare != 0) return scoreCompare;

        final aBase = a.setName.toLowerCase().contains('base set') ? 1 : 0;
        final bBase = b.setName.toLowerCase().contains('base set') ? 1 : 0;
        if (aBase != bBase) return bBase.compareTo(aBase);

        return a.player.compareTo(b.player);
      });

      // Avoid duplicate entries representing the same card.
      final unique = <String, _CardChecklistMatch>{};
      for (final match in allMatches) {
        final key = [
          normalize(match.brand),
          normalize(match.setName),
          match.cardNumber.toUpperCase(),
          normalize(match.player),
        ].join('|');
        unique.putIfAbsent(key, () => match);
      }

      return unique.values.toList();
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  bool _sameCardNumber(String checklistNumber, String scannedNumber) {
    String clean(String value) => value
        .toUpperCase()
        .replaceAll('#', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();

    final a = clean(checklistNumber);
    final b = clean(scannedNumber);

    if (a == b) return true;

    final aNumeric = int.tryParse(a);
    final bNumeric = int.tryParse(b);

    return aNumeric != null &&
        bNumeric != null &&
        aNumeric == bNumeric;
  }

  _CardTextSuggestions _suggestCardFields(String rawText) {
    final normalized = rawText
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();

    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    String year = '';
    final yearMatches =
        RegExp(r'\b(19[4-9]\d|20[0-3]\d)\b').allMatches(normalized);
    if (yearMatches.isNotEmpty) {
      year = yearMatches.first.group(1) ?? '';
    }

    String cardNumber = '';
    final numberPatterns = <RegExp>[
      RegExp(r'#\s*([A-Z0-9\-]+)', caseSensitive: false),
      RegExp(
        r'\b(?:NO|N0|N°|NUM|NUMBER)\.?\s*#?\s*([A-Z0-9\-]+)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\bCARD\s*(?:NO|N0|NUMBER)?\.?\s*#?\s*([A-Z0-9\-]+)\b',
        caseSensitive: false,
      ),
    ];

    for (final pattern in numberPatterns) {
      final match = pattern.firstMatch(normalized);
      if (match != null) {
        final candidate = match.group(1) ?? '';
        if (RegExp(r'\d').hasMatch(candidate)) {
          cardNumber = candidate;
          break;
        }
      }
    }

    const knownBrands = <String>[
      'Topps',
      'Bowman',
      'Donruss',
      'Fleer',
      'Upper Deck',
      'Panini',
      'Score',
      'Leaf',
      'Select',
      'Prizm',
      'Stadium Club',
      'Heritage',
    ];

    String brand = '';
    final lower = normalized.toLowerCase();

    for (final candidate in knownBrands) {
      if (lower.contains(candidate.toLowerCase())) {
        brand = candidate;
        break;
      }
    }

    String player = '';

    final excluded = <String>{
      ...knownBrands.map((value) => value.toLowerCase()),
      'baseball',
      'football',
      'basketball',
      'hockey',
      'rookie',
      'rookie card',
      'trading card',
      'copyright',
      'printed in usa',
      'ab',
      'avg',
      'bb',
      'cs',
      'era',
      'g',
      'gs',
      'h',
      'hr',
      'ip',
      'obp',
      'ops',
      'r',
      'rbi',
      'sb',
      'slg',
      'so',
      'w',
      'l',
      'sv',
      'sb slg bb',
    };

    final likelyNameLines = lines.where((line) {
      if (line.length < 4 || line.length > 40) return false;
      if (RegExp(r'\d').hasMatch(line)) return false;

      final clean = line
          .replaceAll(RegExp(r"[^A-Za-z .\'-]"), '')
          .trim();

      if (clean.split(RegExp(r'\s+')).length < 2) return false;

      final low = clean.toLowerCase();
      if (excluded.any((value) => low == value || low.contains('$value '))) {
        return false;
      }

      final words = clean.split(RegExp(r'\s+'));
      final statLike = words.length >= 2 &&
          words.every((word) => word.length <= 4 && word == word.toUpperCase());
      if (statLike) return false;

      return RegExp(r"^[A-Za-z][A-Za-z .\'-]+$").hasMatch(clean);
    }).toList();

    if (likelyNameLines.isNotEmpty) {
      player = likelyNameLines.first
          .replaceAll(RegExp(r"[^A-Za-z .\'-]"), '')
          .trim();
    }

    return _CardTextSuggestions(
      year: year,
      cardNumber: cardNumber,
      brand: brand,
      player: player,
    );
  }

  void _chooseCandidateMatch(_CardChecklistMatch match) {
    setState(() {
      _pendingMatch = match;
      _candidateMatches = [];
      _pendingMatchFromChecklist = true;
      _identificationMessage =
          'Checklist match selected. Confirm it below.';
    });
  }

  void _usePendingMatch() {
    final match = _pendingMatch;
    if (match == null) return;

    setState(() {
      _acceptedMatch = match;
      _playerController.text = match.player;
      _cardNumberController.text = match.cardNumber;

      if (match.setName.isNotEmpty) {
        _brandSetController.text =
            '${match.brand} — ${match.setName}';
      } else {
        _brandSetController.text = match.brand;
      }

      _pendingMatch = null;
      _candidateMatches = [];
      _pendingMatchFromChecklist = false;
      _identificationMessage =
          'Card suggestion applied. You can still edit any field before saving.';
    });
  }

  void _rejectPendingMatch() {
    setState(() {
      _pendingMatch = null;
      _candidateMatches = [];
      _pendingMatchFromChecklist = false;
      _acceptedMatch = null;
      _identificationMessage =
          'Card suggestion rejected. Keep or edit the recognized details manually.';
    });
  }

  Future<void> _saveImages() async {
    final front = _front;
    if (front == null || _saving) return;

    setState(() => _saving = true);

    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(
        path.join(
          docs.path,
          'Heirloom Atlas',
          'Mobile Captures',
          'Sports Cards',
        ),
      );
      await folder.create(recursive: true);

      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');

      final baseName =
          'sports_card_${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}';

      Future<String> copySide(XFile file, String side) async {
        final extension = path.extension(file.path).isEmpty
            ? '.jpg'
            : path.extension(file.path);
        final destination =
            path.join(folder.path, '${baseName}_$side$extension');
        await File(file.path).copy(destination);
        return destination;
      }

      final frontPath = await copySide(front, 'front');
      String backPath = '';

      if (_back != null) {
        backPath = await copySide(_back!, 'back');
      }

      final userNotes = _notesController.text.trim();
      final combinedNotes = [
        if (userNotes.isNotEmpty) userNotes,
        if (backPath.isNotEmpty) 'Back image: $backPath',
      ].join('\n');

      final detailsFile = File(
        path.join(folder.path, '${baseName}_details.txt'),
      );
      await detailsFile.writeAsString(
        'Player: ${_playerController.text.trim()}\n'
        'Year: ${_yearController.text.trim()}\n'
        'Brand/Set: ${_brandSetController.text.trim()}\n'
        'Card #: ${_cardNumberController.text.trim()}\n'
        'Condition: ${_conditionController.text.trim()}\n'
        'Notes: $combinedNotes\n',
      );

      var linkedToCollection = false;
      final accepted = _acceptedMatch;

      if (accepted != null &&
          accepted.sourceKey.isNotEmpty &&
          accepted.cards.isNotEmpty) {
        await DatabaseHelper.instance.importSportsCardSet(
          sourceKey: accepted.sourceKey,
          sourceName: 'CardLists',
          sport: 'Baseball',
          year: accepted.year,
          brand: accepted.brand,
          setName: accepted.setName,
          cards: accepted.cards,
        );

        final catalogCard = await DatabaseHelper.instance.findSportsCard(
          year: accepted.year,
          brand: accepted.brand,
          setName: accepted.setName,
          cardNumber: accepted.cardNumber,
        );

        if (catalogCard != null) {
          await DatabaseHelper.instance.updateSportsCard(
            catalogCard.copyWith(
              status: 'Owned',
              quantityOwned:
                  catalogCard.quantityOwned == 0 ? 1 : catalogCard.quantityOwned,
              grade: _conditionController.text.trim(),
              imagePath: frontPath,
              notes: combinedNotes,
            ),
          );
          linkedToCollection = true;
        }
      }

      if (!mounted) return;

      setState(() => _saved = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            linkedToCollection
                ? '${_playerController.text.trim()} saved as Owned in Sports Cards.'
                : 'Card capture saved locally. Confirm a Checklist Match to link it to Sports Cards.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _startAnother() {
    setState(() {
      _front = null;
      _back = null;
      _numberCloseup = null;
      _saved = false;
      _recognizedText = '';
      _backRecognizedText = '';
      _identificationMessage = '';
      _pendingMatch = null;
      _candidateMatches = [];
      _pendingMatchFromChecklist = false;
      _acceptedMatch = null;
    });
    _playerController.clear();
    _yearController.clear();
    _brandSetController.clear();
    _cardNumberController.clear();
    _conditionController.clear();
    _notesController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports Card Capture'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              'Photograph the card',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Capture the front first. The back is optional, but useful for '
              'condition, identification, and future value research.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _CardSideCapturePanel(
              title: 'Front',
              requiredSide: true,
              file: _front,
              onCamera: _takeFront,
              onGallery: _chooseFront,
              onRemove: _front == null
                  ? null
                  : () => setState(() {
                        _front = null;
                        _saved = false;
                      }),
            ),
            const SizedBox(height: 16),
            _CardSideCapturePanel(
              title: 'Back',
              requiredSide: false,
              file: _back,
              onCamera: _takeBack,
              onGallery: _chooseBack,
              onRemove: _back == null
                  ? null
                  : () => setState(() {
                        _back = null;
                                          _saved = false;
                      }),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed:
                    _front == null || _identifying || _saving
                        ? null
                        : _captureCardNumber,
                icon: const Icon(Icons.center_focus_strong),
                label: Text(
                  _numberCloseup == null
                      ? 'Scan Card # Close-Up'
                      : 'Retake Card # Close-Up',
                ),
              ),
            ),
            if (_numberCloseup != null) ...[
              const SizedBox(height: 6),
              const Text(
                'Close-up captured. Keep the card number large and centered.',
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.tonalIcon(
                onPressed:
                    _front == null || _identifying ? null : _identifyCard,
                icon: _identifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(
                  _identifying ? 'Reading Card...' : 'Identify Card',
                ),
              ),
            ),
            if (_identificationMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_identificationMessage),
              ),
            ],
            if (_candidateMatches.length > 1) ...[
              const SizedBox(height: 10),
              _CardMatchChooserPanel(
                matches: _candidateMatches,
                onChoose: _chooseCandidateMatch,
              ),
            ],
            if (_pendingMatch != null) ...[
              const SizedBox(height: 10),
              _CardMatchConfirmationPanel(
                match: _pendingMatch!,
                fromChecklist: _pendingMatchFromChecklist,
                onUse: _usePendingMatch,
                onReject: _rejectPendingMatch,
              ),
            ],
            if (_recognizedText.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Recognized Text'),
                subtitle: Text(
                  _backRecognizedText.isNotEmpty
                      ? 'Front and back OCR shown separately for troubleshooting.'
                      : 'Front OCR shown for troubleshooting.',
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    child: SelectableText(_recognizedText),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Card Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add what you know now. We can automate more of this later.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _playerController,
              onChanged: (_) => _acceptedMatch = null,
              decoration: const InputDecoration(
                labelText: 'Player',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _yearController,
                    onChanged: (_) => _acceptedMatch = null,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _cardNumberController,
                    onChanged: (_) {
                      _acceptedMatch = null;
                      _pendingMatch = null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Card #',
                      hintText: 'Enter manually if OCR misses it',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _brandSetController,
              onChanged: (_) {
                _acceptedMatch = null;
                _pendingMatch = null;
              },
              decoration: const InputDecoration(
                labelText: 'Brand / Set',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: FilledButton.tonalIcon(
                onPressed: _identifying || _saving
                    ? null
                    : _matchManualCardNumber,
                icon: _identifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search),
                label: Text(
                  _identifying ? 'Searching...' : 'Match Checklist',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _conditionController,
              decoration: const InputDecoration(
                labelText: 'Condition',
                hintText: 'Optional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            if (_saved) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Saved locally on this device.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed:
                    _front == null || _saving || _saved ? null : _saveImages,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _saved
                      ? 'Saved'
                      : _back == null
                          ? 'Save Card'
                          : 'Save Card',
                ),
              ),
            ),
            if (_saved) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _startAnother,
                  icon: const Icon(Icons.add),
                  label: const Text('Capture Another Card'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}





class _CardMatchChooserPanel extends StatelessWidget {
  final List<_CardChecklistMatch> matches;
  final ValueChanged<_CardChecklistMatch> onChoose;

  const _CardMatchChooserPanel({
    required this.matches,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose the matching card',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Card number appears in more than one ${matches.first.year} checklist.',
            ),
            const SizedBox(height: 10),
            for (final match in matches.take(20))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  match.player,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    match.brand,
                    if (match.setName.isNotEmpty) match.setName,
                    '#${match.cardNumber}',
                  ].join(' • '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onChoose(match),
              ),
            if (matches.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${matches.length - 20} more matches not shown. '
                  'Add a Brand / Set clue to narrow the results.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardMatchConfirmationPanel extends StatelessWidget {
  final _CardChecklistMatch match;
  final bool fromChecklist;
  final VoidCallback onUse;
  final VoidCallback onReject;

  const _CardMatchConfirmationPanel({
    required this.match,
    required this.fromChecklist,
    required this.onUse,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  fromChecklist ? 'Checklist Match' : 'OCR Suggestion',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              match.player,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (match.brand.isNotEmpty) match.brand,
                if (match.setName.isNotEmpty) match.setName,
                if (match.cardNumber.isNotEmpty) '#${match.cardNumber}',
              ].join(' • '),
            ),
            const SizedBox(height: 6),
            Text(
              fromChecklist
                  ? 'Matched against the downloaded card checklist.'
                  : 'Read from the card image. Verify before accepting.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onUse,
                    icon: const Icon(Icons.check),
                    label: const Text('Use This Card'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close),
                    label: const Text('Not This Card'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistFileCandidate {
  final String name;
  final String path;
  final String normalizedName;
  final String downloadUrl;

  const _ChecklistFileCandidate({
    required this.name,
    required this.path,
    required this.normalizedName,
    required this.downloadUrl,
  });
}

class _CardChecklistMatch {
  final String year;
  final String brand;
  final String setName;
  final String cardNumber;
  final String player;
  final String sourceKey;
  final List<SportsCard> cards;
  final int brandScore;

  const _CardChecklistMatch({
    required this.year,
    required this.brand,
    required this.setName,
    required this.cardNumber,
    required this.player,
    required this.sourceKey,
    required this.cards,
    this.brandScore = 0,
  });
}

class _CardTextSuggestions {
  final String year;
  final String cardNumber;
  final String brand;
  final String player;

  const _CardTextSuggestions({
    required this.year,
    required this.cardNumber,
    required this.brand,
    required this.player,
  });

  bool get hasAny =>
      year.isNotEmpty ||
      cardNumber.isNotEmpty ||
      brand.isNotEmpty ||
      player.isNotEmpty;
}

class _CardSideCapturePanel extends StatelessWidget {
  final String title;
  final bool requiredSide;
  final XFile? file;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback? onRemove;

  const _CardSideCapturePanel({
    required this.title,
    required this.requiredSide,
    required this.file,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final selected = file;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  requiredSide ? 'Required' : 'Optional',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (selected != null)
                  IconButton(
                    tooltip: 'Remove $title',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 2.5 / 3.5,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                child: selected == null
                    ? Center(
                        child: Icon(
                          Icons.style_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.file(
                          File(selected.path),
                          fit: BoxFit.contain,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(
                      selected == null ? 'Take $title' : 'Retake $title',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Choose $title from gallery',
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MobileCaptureScreen extends StatefulWidget {
  final MobileCaptureType type;

  const MobileCaptureScreen({
    super.key,
    required this.type,
  });

  @override
  State<MobileCaptureScreen> createState() =>
      _MobileCaptureScreenState();
}

class _MobileCaptureScreenState extends State<MobileCaptureScreen> {
  final ImagePicker _picker = ImagePicker();

  XFile? _capturedFile;
  String? _savedPath;
  bool _saving = false;

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (file == null || !mounted) return;

    setState(() {
      _capturedFile = file;
      _savedPath = null;
    });
  }

  Future<void> _chooseFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );

    if (file == null || !mounted) return;

    setState(() {
      _capturedFile = file;
      _savedPath = null;
    });
  }

  Future<void> _saveCapture() async {
    final captured = _capturedFile;
    if (captured == null || _saving) return;

    setState(() => _saving = true);

    try {
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(
        path.join(
          docs.path,
          'Heirloom Atlas',
          'Mobile Captures',
          widget.type.folderName,
        ),
      );

      await folder.create(recursive: true);

      final extension = path.extension(captured.path).isEmpty
          ? '.jpg'
          : path.extension(captured.path);

      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');

      final filename =
          '${widget.type.folderName.replaceAll(' ', '_').toLowerCase()}_'
          '${now.year}${two(now.month)}${two(now.day)}_'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}'
          '$extension';

      final destination = path.join(folder.path, filename);

      await File(captured.path).copy(destination);

      if (!mounted) return;

      setState(() {
        _savedPath = destination;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.type.title} image saved.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _retake() {
    setState(() {
      _capturedFile = null;
      _savedPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final captured = _capturedFile;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.type.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  child: captured == null
                      ? _EmptyCaptureState(type: widget.type)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.file(
                            File(captured.path),
                            fit: BoxFit.contain,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              if (captured == null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Open Camera'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _chooseFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose Existing Image'),
                  ),
                ),
              ] else ...[
                if (_savedPath != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Saved on this device',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _retake,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _savedPath != null || _saving
                            ? null
                            : _saveCapture,
                        icon: _saving
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _savedPath != null ? 'Saved' : 'Save',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCaptureState extends StatelessWidget {
  final MobileCaptureType type;

  const _EmptyCaptureState({
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type.icon,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Capture ${type.title}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              type.helper,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
