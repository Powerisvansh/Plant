import 'package:flutter/material.dart';

import '../../models/knowledge_models.dart';
import '../../services/knowledge/knowledge_repository.dart';
import '../../widgets/empty_state.dart';
import 'knowledge_plant_detail_screen.dart';

/// Offline knowledge browser backed by the bundled SQLite database.
///
/// This is the real knowledge path: it searches and lists the shipped plant
/// records instead of the small hard-coded Dart catalogue. It works with no
/// network, because the database is an asset inside the app.
class KnowledgeBrowserScreen extends StatefulWidget {
  const KnowledgeBrowserScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<KnowledgeBrowserScreen> createState() => _KnowledgeBrowserScreenState();
}

class _KnowledgeBrowserScreenState extends State<KnowledgeBrowserScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  late final Future<KnowledgeRepository> _repository = _open();

  List<KnowledgePlant> _results = const [];
  bool _searching = false;
  int _offset = 0;
  bool _exhausted = false;
  static const int _pageSize = 40;

  Future<KnowledgeRepository> _open() async {
    final repo = await KnowledgeRepository.open();
    if (_controller.text.trim().isEmpty) {
      await _loadFirstPage();
    } else {
      await _runSearch(_controller.text);
    }
    return repo;
  }

  Future<void> _loadFirstPage() async {
    final repo = KnowledgeRepository.instance;
    if (repo == null) return;
    setState(() {
      _searching = true;
      _exhausted = false;
    });
    try {
      final page = await repo.browse(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _results = page;
        _offset = page.length;
        _exhausted = page.length < _pageSize;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _loadMore() async {
    final repo = KnowledgeRepository.instance;
    if (repo == null || _exhausted || _searching) return;
    setState(() => _searching = true);
    try {
      final page = await repo.browse(limit: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        _results = [..._results, ...page];
        _offset += page.length;
        _exhausted = page.length < _pageSize;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _runSearch(String raw) async {
    final repo = KnowledgeRepository.instance;
    if (repo == null) return;
    setState(() {
      _searching = true;
      _exhausted = true;
    });
    try {
      final found = await repo.search(raw, limit: 60);
      if (!mounted) return;
      setState(() {
        _results = found;
        _offset = found.length;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plant knowledge base')),
      body: FutureBuilder<KnowledgeRepository>(
        future: _repository,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.storage_outlined,
              title: 'Knowledge base unavailable',
              message:
                  'The bundled plant database could not be opened on this '
                  'device. Identification still works, but the offline plant '
                  'records are not reachable.\n\n${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final repo = snapshot.data!;
          return _body(repo);
        },
      ),
    );
  }

  Widget _body(KnowledgeRepository repo) {
    final manifest = repo.manifest;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search common, local or scientific name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _loadFirstPage();
                      },
                    ),
            ),
            onSubmitted: _runSearch,
          ),
        ),
        _releaseBar(manifest),
        if (_searching && _results.isEmpty)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _results.isEmpty && !_searching
              ? EmptyState(
                  icon: Icons.search_off,
                  title: 'No matching plant',
                  message: _controller.text.trim().isEmpty
                      ? 'The knowledge base could not be searched.'
                      : 'Nothing in the offline database matches '
                            '"${_controller.text.trim()}". Try a scientific name, '
                            'a genus such as "Solanum", or a family name.',
                )
              : ListView.separated(
                  itemCount: _results.length + (_exhausted ? 0 : 1),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index >= _results.length) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: _loadMore,
                            icon: const Icon(Icons.expand_more),
                            label: const Text('Load more'),
                          ),
                        ),
                      );
                    }
                    final plant = _results[index];
                    return ListTile(
                      title: Text(plant.displayName),
                      subtitle: Text(
                        [
                          plant.scientificName,
                          if (plant.family != null) plant.family,
                        ].whereType<String>().join(' \u00b7 '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: plant.hasCommonName
                          ? null
                          : const Tooltip(
                              message:
                                  'No common name recorded - identified by '
                                  'its scientific name only',
                              child: Icon(Icons.help_outline, size: 18),
                            ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              KnowledgePlantDetailScreen(slug: plant.slug),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _releaseBar(KnowledgeManifest manifest) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Text(
        '${manifest.plantCount} plant records \u00b7 '
        '${manifest.diseaseCount} diseases \u00b7 '
        '${manifest.pestCount} pests \u00b7 '
        '${manifest.sourceCount} sources'
        '${manifest.dataRelease == null ? '' : ' \u00b7 release ${manifest.dataRelease}'}'
        ' \u00b7 offline',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
