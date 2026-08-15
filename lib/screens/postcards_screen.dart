import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/postcard.dart';
import 'postcard_edit_screen.dart';

class PostcardsScreen extends StatefulWidget {
  const PostcardsScreen({super.key});

  @override
  State<PostcardsScreen> createState() => _PostcardsScreenState();
}

class _PostcardsScreenState extends State<PostcardsScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isLoading = true;
  String? _errorMessage;
  List<Postcard> _postcards = const [];

  @override
  void initState() {
    super.initState();
    _loadPostcards();
  }

  Future<void> _loadPostcards() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final postcards = await _databaseHelper.getPostcards();
      if (!mounted) return;

      setState(() {
        _postcards = postcards;
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

  Future<void> _addPostcard() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const PostcardEditScreen(),
      ),
    );

    if (saved == true) {
      await _loadPostcards();
    }
  }

  Future<void> _editPostcard(Postcard postcard) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PostcardEditScreen(postcard: postcard),
      ),
    );

    if (saved == true) {
      await _loadPostcards();
    }
  }

  String _displayTitle(Postcard postcard) {
    if (postcard.title.trim().isNotEmpty) return postcard.title.trim();
    if (postcard.year.trim().isNotEmpty) {
      return 'Postcard • ${postcard.year.trim()}';
    }
    return 'Untitled Postcard';
  }

  String _money(double? value) {
    if (value == null) return '';
    return '\$${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Postcards'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadPostcards,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPostcard,
        icon: const Icon(Icons.add),
        label: const Text('Add Postcard'),
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
            'Could not load postcards.\n\n$_errorMessage',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_postcards.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.markunread_mailbox_outlined, size: 64),
                    const SizedBox(height: 18),
                    Text(
                      'Your postcard collection is empty',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add a postcard to save its front and back images, history, acquisition details, and value.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _addPostcard,
                      icon: const Icon(Icons.add),
                      label: const Text('Add First Postcard'),
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
      itemCount: _postcards.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, index) {
        final postcard = _postcards[index];
        final imagePath = postcard.frontImagePath.trim();
        final file = imagePath.isEmpty ? null : File(imagePath);
        final imageExists = file != null && file.existsSync();

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _editPostcard(postcard),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: imageExists
                        ? Image.file(
                            file,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 52,
                              ),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 56,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayTitle(postcard),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      if (postcard.year.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(postcard.year.trim()),
                      ],
                      if (postcard.estimatedValue != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Estimated value: ${_money(postcard.estimatedValue)}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
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
