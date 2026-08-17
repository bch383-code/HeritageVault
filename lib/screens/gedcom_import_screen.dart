import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/gedcom_import_service.dart';

class GedcomImportScreen extends StatefulWidget {
  const GedcomImportScreen({super.key});

  @override
  State<GedcomImportScreen> createState() => _GedcomImportScreenState();
}

class _GedcomImportScreenState extends State<GedcomImportScreen> {
  final GedcomImportService _service = GedcomImportService();

  GedcomPreview? _preview;
  String? _filePath;
  bool _busy = false;
  String _stage = '';
  String _status = '';
  double? _progress;
  String? _error;

  Future<void> _chooseFile() async {
    setState(() {
      _busy = true;
      _error = null;
      _stage = 'Reading';
      _status = 'Reading GEDCOM...';
      _progress = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['ged'],
      );

      final filePath = result?.files.single.path;
      if (filePath == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final preview = await _service.preview(filePath);
      if (!mounted) return;

      setState(() {
        _filePath = filePath;
        _preview = preview;
        _busy = false;
        _stage = '';
        _status = '';
        _progress = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  Future<void> _run(GedcomImportMode mode) async {
    final filePath = _filePath;
    if (filePath == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _stage = 'Starting';
      _status = 'Preparing GEDCOM...';
      _progress = null;
    });

    try {
      final result = await _service.import(
        filePath,
        mode: mode,
        onProgress: (value) {
          if (!mounted) return;
          setState(() {
            _stage = value.stage;
            _status = value.message;
            _progress = value.fraction;
          });
        },
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            mode == GedcomImportMode.repairRelationships
                ? 'Relationships Repaired'
                : 'GEDCOM Imported',
          ),
          content: Text(
            'People created: ${result.peopleCreated}\n'
            'Existing people matched: ${result.peopleMatched}\n'
            'GEDCOM people linked: ${result.linkedXrefs}\n'
            'Parent/child links written: ${result.parentChildLinksWritten}\n'
            'Spouse links written: ${result.spouseLinksWritten}\n'
            'Unresolved people: ${result.unresolvedIndividuals}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
        _stage = 'Failed';
        _status = 'The import stopped.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('GEDCOM Import & Repair')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const Icon(Icons.account_tree_outlined, size: 70),
              const SizedBox(height: 14),
              Text(
                'Large GEDCOM Import',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Optimized for very large family trees. Relationships are written in batches.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _busy ? null : _chooseFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Choose GEDCOM File'),
              ),
              if (_busy) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(_stage,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const Spacer(),
                            if (_progress != null)
                              Text('${(_progress! * 100).toStringAsFixed(0)}%'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: _progress),
                        const SizedBox(height: 10),
                        Text(_status),
                      ],
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText('Import error:\n\n$_error'),
                  ),
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: 22),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _row('Individuals', preview.individualCount),
                        _row('Families', preview.familyCount),
                        _row('Parent / child links', preview.parentChildLinks),
                        _row('Spouse links', preview.spouseLinks),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Because your people are already imported, use Repair Relationships Only first.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(GedcomImportMode.repairRelationships),
                  icon: const Icon(Icons.link_outlined),
                  label: const Text('Repair Relationships Only'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(GedcomImportMode.fullImport),
                  icon: const Icon(Icons.download_done_outlined),
                  label: const Text('Full Import (Create Missing People)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$value',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
