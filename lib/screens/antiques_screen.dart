import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/antique.dart';
import 'antique_edit_screen.dart';

class AntiquesScreen extends StatefulWidget {
  const AntiquesScreen({super.key});

  @override
  State<AntiquesScreen> createState() => _AntiquesScreenState();
}

class _AntiquesScreenState extends State<AntiquesScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isLoading = true;
  String? _errorMessage;
  List<Antique> _antiques = const [];

  @override
  void initState() {
    super.initState();
    _loadAntiques();
  }

  Future<void> _loadAntiques() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final antiques = await _databaseHelper.getAntiques();
      if (!mounted) return;

      setState(() {
        _antiques = antiques;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _addAntique() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const AntiqueEditScreen(),
      ),
    );

    if (saved == true) await _loadAntiques();
  }

  Future<void> _editAntique(Antique antique) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AntiqueEditScreen(antique: antique),
      ),
    );

    if (saved == true) await _loadAntiques();
  }

  String _titleFor(Antique antique) {
    if (antique.title.trim().isNotEmpty) return antique.title.trim();
    if (antique.year.trim().isNotEmpty) {
      return 'Antique • ${antique.year.trim()}';
    }
    return 'Untitled Antique';
  }

  String _money(double? value) {
    if (value == null) return '';
    return '\$${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Antiques'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAntiques,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAntique,
        icon: const Icon(Icons.add),
        label: const Text('Add Antique'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Could not load antiques.\n\n$_errorMessage',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_antiques.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 64),
                    const SizedBox(height: 18),
                    Text(
                      'Your antiques collection is empty',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add antiques with photos, history, acquisition details, purchase price, and estimated value.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _addAntique,
                      icon: const Icon(Icons.add),
                      label: const Text('Add First Antique'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      itemCount: _antiques.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (context, index) {
        final antique = _antiques[index];
        File? imageFile;

        if (antique.imagePaths.isNotEmpty) {
          final candidate = File(antique.imagePaths.first);
          if (candidate.existsSync()) imageFile = candidate;
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _editAntique(antique),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: imageFile != null
                        ? Image.file(
                            imageFile,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                              child: Icon(Icons.broken_image_outlined, size: 52),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.inventory_2_outlined, size: 60),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleFor(antique),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (antique.year.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(antique.year.trim()),
                      ],
                      if (antique.estimatedValue != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Estimated value: ${_money(antique.estimatedValue)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
