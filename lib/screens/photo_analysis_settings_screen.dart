import 'package:flutter/material.dart';

import '../database/database_helper.dart';

class PhotoAnalysisSettingsScreen extends StatefulWidget {
  const PhotoAnalysisSettingsScreen({super.key});

  @override
  State<PhotoAnalysisSettingsScreen> createState() =>
      _PhotoAnalysisSettingsScreenState();
}

class _PhotoAnalysisSettingsScreenState
    extends State<PhotoAnalysisSettingsScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _loading = true;
  bool _saving = false;

  bool _analyzeNewPhotos = true;
  bool _automaticDuplicates = true;
  bool _automaticFaces = false;
  bool _automaticMetadataImport = true;
  bool _automaticOcr = false;
  bool _manualOnly = false;
  bool _allowCloudAi = false;

  static const _keyAnalyzeNewPhotos = 'photo_analysis_analyze_new';
  static const _keyAutomaticDuplicates = 'photo_analysis_duplicates';
  static const _keyAutomaticFaces = 'photo_analysis_faces';
  static const _keyAutomaticMetadata = 'photo_analysis_metadata';
  static const _keyAutomaticOcr = 'photo_analysis_ocr';
  static const _keyManualOnly = 'photo_analysis_manual_only';
  static const _keyAllowCloudAi = 'photo_analysis_cloud_ai';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _databaseHelper.getSetting(_keyAnalyzeNewPhotos),
        _databaseHelper.getSetting(_keyAutomaticDuplicates),
        _databaseHelper.getSetting(_keyAutomaticFaces),
        _databaseHelper.getSetting(_keyAutomaticMetadata),
        _databaseHelper.getSetting(_keyAutomaticOcr),
        _databaseHelper.getSetting(_keyManualOnly),
        _databaseHelper.getSetting(_keyAllowCloudAi),
      ]);

      if (!mounted) return;

      setState(() {
        _analyzeNewPhotos = _readBool(values[0], fallback: true);
        _automaticDuplicates = _readBool(values[1], fallback: true);
        _automaticFaces = _readBool(values[2], fallback: false);
        _automaticMetadataImport = _readBool(values[3], fallback: true);
        _automaticOcr = _readBool(values[4], fallback: false);
        _manualOnly = _readBool(values[5], fallback: false);
        _allowCloudAi = _readBool(values[6], fallback: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _readBool(String? value, {required bool fallback}) {
    if (value == null) return fallback;
    return value == 'true';
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      await Future.wait([
        _databaseHelper.setSetting(
          _keyAnalyzeNewPhotos,
          _analyzeNewPhotos.toString(),
        ),
        _databaseHelper.setSetting(
          _keyAutomaticDuplicates,
          _automaticDuplicates.toString(),
        ),
        _databaseHelper.setSetting(
          _keyAutomaticFaces,
          _automaticFaces.toString(),
        ),
        _databaseHelper.setSetting(
          _keyAutomaticMetadata,
          _automaticMetadataImport.toString(),
        ),
        _databaseHelper.setSetting(
          _keyAutomaticOcr,
          _automaticOcr.toString(),
        ),
        _databaseHelper.setSetting(
          _keyManualOnly,
          _manualOnly.toString(),
        ),
        _databaseHelper.setSetting(
          _keyAllowCloudAi,
          _allowCloudAi.toString(),
        ),
      ]);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo analysis settings saved.'),
        ),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save settings: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Analysis Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _loading || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _IntroCard(
                  title: 'Choose how much Heirloom Atlas does for you',
                  body:
                      'Turn analysis features on or off depending on how much '
                      'automation and detail you want to maintain. These '
                      'settings control future photo-processing workflows.',
                ),
                const SizedBox(height: 18),
                _SettingsSection(
                  title: 'When to analyze',
                  subtitle:
                      'Control when Heirloom Atlas processes your photo library.',
                  children: [
                    SwitchListTile(
                      value: _analyzeNewPhotos,
                      onChanged: _manualOnly
                          ? null
                          : (value) =>
                              setState(() => _analyzeNewPhotos = value),
                      title: const Text('Analyze new and changed photos'),
                      subtitle: const Text(
                        'Reuse saved analysis for existing photos and process '
                        'only files that are new or have changed.',
                      ),
                      secondary: const Icon(Icons.auto_awesome_outlined),
                    ),
                    SwitchListTile(
                      value: _manualOnly,
                      onChanged: (value) {
                        setState(() {
                          _manualOnly = value;
                          if (value) {
                            _analyzeNewPhotos = false;
                          }
                        });
                      },
                      title: const Text('Manual analysis only'),
                      subtitle: const Text(
                        'Nothing runs automatically. You start analysis tools '
                        'when you want them.',
                      ),
                      secondary: const Icon(Icons.touch_app_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SettingsSection(
                  title: 'Photo organization',
                  subtitle:
                      'Choose which organization tools should be available for '
                      'automatic processing.',
                  children: [
                    SwitchListTile(
                      value: _automaticDuplicates,
                      onChanged: (value) =>
                          setState(() => _automaticDuplicates = value),
                      title: const Text('Check for duplicates'),
                      subtitle: const Text(
                        'Use the saved visual fingerprint index to flag likely '
                        'duplicate or similar photos.',
                      ),
                      secondary: const Icon(Icons.compare_outlined),
                    ),
                    SwitchListTile(
                      value: _automaticFaces,
                      onChanged: (value) =>
                          setState(() => _automaticFaces = value),
                      title: const Text('Detect faces'),
                      subtitle: const Text(
                        'Look for faces in new photos so they can be reviewed '
                        'and connected to people.',
                      ),
                      secondary:
                          const Icon(Icons.face_retouching_natural_outlined),
                    ),
                    SwitchListTile(
                      value: _automaticMetadataImport,
                      onChanged: (value) =>
                          setState(() => _automaticMetadataImport = value),
                      title: const Text('Read embedded metadata'),
                      subtitle: const Text(
                        'Read dates, descriptions, keywords, and location data '
                        'already stored inside photo files.',
                      ),
                      secondary: const Icon(Icons.data_object_outlined),
                    ),
                    SwitchListTile(
                      value: _automaticOcr,
                      onChanged: (value) =>
                          setState(() => _automaticOcr = value),
                      title: const Text('Read text in photos (OCR)'),
                      subtitle: const Text(
                        'Prepare photos for future text extraction such as '
                        'handwritten labels, signs, and document scans.',
                      ),
                      secondary: const Icon(Icons.document_scanner_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SettingsSection(
                  title: 'Cloud & AI',
                  subtitle:
                      'Local processing stays separate from services that may '
                      'send data outside this computer.',
                  children: [
                    SwitchListTile(
                      value: _allowCloudAi,
                      onChanged: (value) =>
                          setState(() => _allowCloudAi = value),
                      title: const Text('Allow cloud/AI analysis'),
                      subtitle: const Text(
                        'Off by default. Future features that require an '
                        'external AI or cloud service must respect this choice.',
                      ),
                      secondary: const Icon(Icons.cloud_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.shield_outlined),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'These switches save preferences only. Existing '
                            'photo files are not moved, renamed, deleted, or '
                            'uploaded by this screen.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final String title;
  final String body;

  const _IntroCard({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tune_outlined, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 7),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}
