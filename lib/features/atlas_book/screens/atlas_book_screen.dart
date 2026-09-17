import 'package:flutter/material.dart';

import '../data/atlas_book_repository.dart';
import '../models/atlas_book_project.dart';
import 'atlas_book_workspace_screen.dart';

class AtlasBookScreen extends StatefulWidget {
  const AtlasBookScreen({super.key});

  @override
  State<AtlasBookScreen> createState() => _AtlasBookScreenState();
}

class _AtlasBookScreenState extends State<AtlasBookScreen> {
  final AtlasBookRepository _repository = AtlasBookRepository();

  List<AtlasBookProject> _books = [];
  final TextEditingController _searchController = TextEditingController();
  final Map<int, _AtlasBookSummary> _bookSummaries = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    final books = await _repository.getBooks();
    final summaries = <int, _AtlasBookSummary>{};

    for (final book in books) {
      final id = book.id;
      if (id == null) continue;

      final people = await _repository.getBookPersonIds(id);
      final photos = await _repository.getBookPhotoPaths(id);
      final pages = await _repository.getBookPages(id);

      summaries[id] = _AtlasBookSummary(
        peopleCount: people.length,
        photoCount: photos.length,
        pageCount: pages.length,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _books = books;
      _bookSummaries
        ..clear()
        ..addAll(summaries);
      _loading = false;
    });
  }

  Future<void> _createBook() async {
    final titleController = TextEditingController();
    final subtitleController = TextEditingController();

    AtlasBookScope selectedScope = AtlasBookScope.people;

    final result = await showDialog<_NewBookData>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create New Atlas Book'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Book name',
                          hintText: 'The Hoffman Family Story',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: subtitleController,
                        decoration: const InputDecoration(
                          labelText: 'Subtitle (optional)',
                          hintText:
                              'Four generations of family, stories, and keepsakes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'What will this book follow?',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      RadioGroup<AtlasBookScope>(
                        groupValue: selectedScope,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            selectedScope = value;
                          });
                        },
                        child: Column(
                          children: AtlasBookScope.values.map((scope) {
                            return RadioListTile<AtlasBookScope>(
                              value: scope,
                              title: Text(scope.label),
                              secondary: Icon(scope.icon),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: const Text('Create Book'),
                  onPressed: () {
                    final title = titleController.text.trim();

                    if (title.isEmpty) {
                      return;
                    }

                    Navigator.pop(
                      context,
                      _NewBookData(
                        title: title,
                        subtitle: subtitleController.text.trim(),
                        scope: selectedScope,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    subtitleController.dispose();

    if (result == null) {
      return;
    }

    final newBook = await _repository.createBook(
      AtlasBookProject(
        title: result.title,
        subtitle: result.subtitle,
        scope: result.scope,
        status: 'Planning',
        createdAt: DateTime.now(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadBooks();

    if (!mounted) {
      return;
    }

    _openBook(newBook);
  }

  Future<void> _deleteBook(AtlasBookProject book) async {
    final bookId = book.id;
    if (bookId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this book?'),
        content: Text(
          '“${book.title}” and its Atlas Book pages will be deleted. '
          'Your original family-tree people, photos, and other Heirloom Atlas '
          'items will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete Book'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _repository.deleteBook(bookId);
    await _loadBooks();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('“${book.title}” deleted.')));
  }

  Future<void> _openBook(AtlasBookProject book) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AtlasBookWorkspaceScreen(book: book)),
    );

    if (!mounted) return;
    await _loadBooks();
  }

  static const Color _heritageGold = Color(0xFFC9A65A);
  static const Color _heritageCream = Color(0xFFF3E9D1);
  static const Color _panelNavy = Color(0xFF071A2B);

  List<AtlasBookProject> get _visibleBooks {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _books;

    return _books.where((book) {
      return book.title.toLowerCase().contains(query) ||
          book.subtitle.toLowerCase().contains(query) ||
          book.scope.label.toLowerCase().contains(query) ||
          book.status.toLowerCase().contains(query);
    }).toList();
  }

  int get _totalPages => _bookSummaries.values.fold(
        0,
        (total, summary) => total + summary.pageCount,
      );

  Widget _buildBanner() {
    return Container(
      height: 210,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _panelNavy,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _heritageGold.withValues(alpha: 0.55),
          width: .8,
        ),
      ),
      child: Image.asset(
        'assets/atlas_book_decor/atlas_book_banner.png',
        width: double.infinity,
        height: 210,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: _panelNavy,
            alignment: Alignment.center,
            child: Text(
              'Atlas Book banner image not found',
              style: TextStyle(color: _heritageCream),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _panelNavy.withValues(alpha: .92),
        border: Border.all(
          color: _heritageGold.withValues(alpha: .25),
          width: .8,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          _LibraryStat(
            icon: Icons.auto_stories_outlined,
            value: '${_books.length}',
            label: _books.length == 1 ? 'BOOK' : 'BOOKS',
          ),
          const SizedBox(width: 18),
          Container(
            height: 28,
            width: 1,
            color: _heritageGold.withValues(alpha: .22),
          ),
          const SizedBox(width: 18),
          _LibraryStat(
            icon: Icons.description_outlined,
            value: '$_totalPages',
            label: _totalPages == 1 ? 'PAGE' : 'PAGES',
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _createBook,
            icon: const Icon(Icons.add),
            label: const Text('Create New Book'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndTemplateStrip() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search your Atlas Books...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 7,
          child: Container(
            constraints: const BoxConstraints(minHeight: 49),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: _panelNavy.withValues(alpha: .68),
              border: Border.all(
                color: _heritageGold.withValues(alpha: .20),
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: const [
                Text(
                  'PAGE TEMPLATES',
                  style: TextStyle(
                    color: _heritageGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
                _TemplateBadge(
                  icon: Icons.person_outline,
                  label: 'Person Profile',
                ),
                _TemplateBadge(
                  icon: Icons.family_restroom_outlined,
                  label: 'Family Group',
                ),
                _TemplateBadge(
                  icon: Icons.hub_outlined,
                  label: 'Fan Chart',
                ),
                _TemplateBadge(
                  icon: Icons.grid_view_outlined,
                  label: 'Photo Collage',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBanner(),
              const SizedBox(height: 12),
              _buildActionBar(),
              const SizedBox(height: 14),
              _buildSearchAndTemplateStrip(),
              const SizedBox(height: 28),
              Row(
                children: [
                  const Icon(
                    Icons.menu_book_outlined,
                    color: _heritageGold,
                    size: 22,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Your Atlas Books',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _heritageCream,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B2742).withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _heritageGold.withValues(alpha: 0.20),
                  ),
                ),
                child: _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _books.isEmpty
                    ? _EmptyAtlasLibrary(onCreateBook: _createBook)
                    : _visibleBooks.isEmpty
                    ? const _NoAtlasBookResults()
                    : Wrap(
                        spacing: 18,
                        runSpacing: 18,
                        children: _visibleBooks.map((book) {
                          return _AtlasBookCard(
                            book: book,
                            summary: book.id == null
                                ? const _AtlasBookSummary()
                                : (_bookSummaries[book.id!] ??
                                    const _AtlasBookSummary()),
                            onTap: () => _openBook(book),
                            onDelete: () => _deleteBook(book),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AtlasBookCard extends StatelessWidget {
  final AtlasBookProject book;
  final _AtlasBookSummary summary;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AtlasBookCard({
    required this.book,
    required this.summary,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        color: const Color(0xFF0B2742).withValues(alpha: 0.54),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: const Color(0xFFC9A65A).withValues(alpha: 0.42),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 42,
                  color: const Color(0xFFC9A65A),
                ),
                const SizedBox(height: 18),
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFF3E9D1),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (book.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    book.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(book.scope.icon, size: 18),
                    const SizedBox(width: 8),
                    Text(book.scope.label),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _BookMetric(
                      icon: Icons.people_outline,
                      value: summary.peopleCount,
                      label: 'people',
                    ),
                    _BookMetric(
                      icon: Icons.photo_outlined,
                      value: summary.photoCount,
                      label: 'photos',
                    ),
                    _BookMetric(
                      icon: Icons.description_outlined,
                      value: summary.pageCount,
                      label: 'pages',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Chip(label: Text(book.status)),
                    const Spacer(),
                    Text(
                      'Created ${_formatDate(book.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(
                          summary.pageCount == 0
                              ? 'Build Book'
                              : 'Continue Book',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Delete book',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _AtlasBookSummary {
  final int peopleCount;
  final int photoCount;
  final int pageCount;

  const _AtlasBookSummary({
    this.peopleCount = 0,
    this.photoCount = 0,
    this.pageCount = 0,
  });
}

class _LibraryStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _LibraryStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFC9A65A), size: 18),
        const SizedBox(width: 7),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFF3E9D1),
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFFF3E9D1).withValues(alpha: .68),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .7,
          ),
        ),
      ],
    );
  }
}

class _TemplateBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TemplateBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(
          color: const Color(0xFFC9A65A).withValues(alpha: .22),
        ),
        borderRadius: BorderRadius.circular(3),
        color: const Color(0xFF0B2742).withValues(alpha: .52),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFFB8C7D1)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD8DDE0),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookMetric extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  const _BookMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF071A2B).withValues(alpha: .62),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: const Color(0xFFC9A65A).withValues(alpha: .18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFFC9A65A)),
          const SizedBox(width: 5),
          Text(
            '$value $label',
            style: const TextStyle(
              color: Color(0xFFD8DDE0),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoAtlasBookResults extends StatelessWidget {
  const _NoAtlasBookResults();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 38),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 42,
              color: Color(0xFFC9A65A),
            ),
            SizedBox(height: 10),
            Text(
              'No Atlas Books match this search.',
              style: TextStyle(
                color: Color(0xFFF3E9D1),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAtlasLibrary extends StatelessWidget {
  final VoidCallback onCreateBook;

  const _EmptyAtlasLibrary({required this.onCreateBook});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0B2742).withValues(alpha: 0.54),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: const Color(0xFFC9A65A).withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 68,
                color: const Color(0xFFC9A65A),
              ),
              const SizedBox(height: 18),
              Text(
                'Your first family story starts here',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFFF3E9D1),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Create an Atlas Book and Heirloom Atlas will help you '
                'bring together the people, photos, documents, stories, '
                'and keepsakes that belong in it.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCreateBook,
                icon: const Icon(Icons.add),
                label: const Text('Create Your First Book'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewBookData {
  final String title;
  final String subtitle;
  final AtlasBookScope scope;

  const _NewBookData({
    required this.title,
    required this.subtitle,
    required this.scope,
  });
}
