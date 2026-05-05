import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../config/app_config.dart';
import '../../services/api_service.dart';
import '../../services/local_db.dart';

class SharedVocabScreen extends StatefulWidget {
  const SharedVocabScreen({super.key});

  @override
  State<SharedVocabScreen> createState() => _SharedVocabScreenState();
}

class _SharedVocabScreenState extends State<SharedVocabScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _importingDeckId;
  List<Map<String, dynamic>> _decks = [];
  String? _level;

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDecks() async {
    setState(() => _loading = true);
    try {
      final res = await apiService.listSharedVocabDecks(
        query: _searchCtrl.text,
        level: _level,
        limit: 50,
      );
      final decks = ((res['decks'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) {
        setState(() {
          _decks = decks;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载共享词库失败：$e')),
        );
      }
    }
  }

  String? _absoluteCoverUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '${AppConfig.serverRoot}$raw';
  }

  Future<String?> _downloadCover(String? rawUrl) async {
    final url = _absoluteCoverUrl(rawUrl);
    if (url == null) return null;
    try {
      final res = await apiService.dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      final docsDir = await getApplicationDocumentsDirectory();
      final coverDir = Directory(p.join(docsDir.path, 'vocab_covers'));
      await coverDir.create(recursive: true);
      final ext = p.extension(Uri.parse(url).path).isEmpty
          ? '.jpg'
          : p.extension(Uri.parse(url).path);
      final dest = p.join(
          coverDir.path, 'shared_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(dest).writeAsBytes(bytes);
      return dest;
    } catch (_) {
      return null;
    }
  }

  String _deckRoot(String deckName) => deckName.split('::').first;

  String _coverDeckName(Set<String> deckNames, String fallbackDeckName) {
    if (deckNames.contains(fallbackDeckName)) return fallbackDeckName;
    final roots = deckNames.map(_deckRoot).toSet();
    if (roots.length == 1) return roots.first;
    return deckNames.isNotEmpty ? deckNames.first : fallbackDeckName;
  }

  Future<void> _importDeck(Map<String, dynamic> deck) async {
    final deckId = deck['id']?.toString();
    if (deckId == null || deckId.isEmpty || _importingDeckId != null) return;
    setState(() => _importingDeckId = deckId);
    try {
      final data = await apiService.importSharedVocabDeck(deckId);
      final remoteDeck = Map<String, dynamic>.from(data['deck'] as Map);
      final cards = ((data['cards'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (cards.isEmpty) throw Exception('共享词库没有可导入卡片');

      const uuid = Uuid();
      final deckName =
          (remoteDeck['title'] ?? deck['title'] ?? '共享词库').toString();
      final rows = cards.map((card) {
        final sharedDeckName = card['deck_name']?.toString().trim();
        final localDeckName = sharedDeckName == null || sharedDeckName.isEmpty
            ? deckName
            : sharedDeckName;
        return {
          'id': uuid.v4(),
          'word': (card['word'] ?? '').toString(),
          'reading': (card['reading'] ?? card['word'] ?? '').toString(),
          'meaning_zh': (card['meaning_zh'] ?? '-').toString(),
          'meaning_en': card['meaning_en'],
          'example_sentence': card['example_sentence'],
          'example_reading': card['example_reading'],
          'example_meaning_zh': card['example_meaning_zh'],
          'example_audio_url': card['example_audio_url'],
          'audio_url': card['audio_url'],
          'part_of_speech': (card['part_of_speech'] ?? 'other').toString(),
          'jlpt_level': (card['jlpt_level'] ?? remoteDeck['jlpt_level'] ?? 'N3')
              .toString(),
          'deck_name': localDeckName,
          'synced': 1,
        };
      }).toList();

      final imported = await localDb.insertCards(rows);
      final coverPath = await _downloadCover(
        (remoteDeck['cover_url'] ?? deck['cover_url'])?.toString(),
      );
      final importedDeckNames = rows
          .map((row) => row['deck_name']?.toString() ?? deckName)
          .where((name) => name.isNotEmpty)
          .toSet();
      final coverDeckName = _coverDeckName(importedDeckNames, deckName);
      final metaDeckNames = {...importedDeckNames, coverDeckName};
      for (final importedDeckName in metaDeckNames) {
        final isCoverDeck = importedDeckName == coverDeckName;
        await localDb.upsertDeckMeta(
          deckName: importedDeckName,
          displayName:
              isCoverDeck ? deckName : importedDeckName.split('::').last,
          coverImagePath: isCoverDeck ? coverPath : null,
          description:
              isCoverDeck ? remoteDeck['description']?.toString() : null,
          sourceType: 'shared',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $imported 张卡片')),
      );
      context.go('/local-vocab?from=shared');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final message = status == 401
          ? '请先登录后导入共享词库'
          : '导入失败：${e.response?.data is Map ? (e.response?.data['error'] ?? e.message) : e.message}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importingDeckId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('共享词库'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadDecks,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: '搜索词库名称或介绍',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _loadDecks(),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: _level,
                hint: const Text('等级'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('全部')),
                  DropdownMenuItem(value: 'N5', child: Text('N5')),
                  DropdownMenuItem(value: 'N4', child: Text('N4')),
                  DropdownMenuItem(value: 'N3', child: Text('N3')),
                  DropdownMenuItem(value: 'N2', child: Text('N2')),
                  DropdownMenuItem(value: 'N1', child: Text('N1')),
                ],
                onChanged: (v) {
                  setState(() => _level = v);
                  _loadDecks();
                },
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _decks.isEmpty
                    ? Center(
                        child:
                            Text('暂无共享词库', style: TextStyle(color: cs.outline)))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final crossAxisCount = width >= 900
                              ? 5
                              : width >= 700
                                  ? 4
                                  : width >= 520
                                      ? 3
                                      : 2;

                          return RefreshIndicator(
                            onRefresh: _loadDecks,
                            child: GridView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 18,
                                crossAxisSpacing: 18,
                                childAspectRatio: 0.62,
                              ),
                              itemCount: _decks.length,
                              itemBuilder: (_, i) => _SharedDeckCard(
                                deck: _decks[i],
                                coverUrl: _absoluteCoverUrl(
                                    _decks[i]['cover_url']?.toString()),
                                importing: _importingDeckId ==
                                    _decks[i]['id']?.toString(),
                                index: i,
                                onImport: () => _importDeck(_decks[i]),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SharedDeckCard extends StatelessWidget {
  final Map<String, dynamic> deck;
  final String? coverUrl;
  final bool importing;
  final int index;
  final VoidCallback onImport;

  const _SharedDeckCard({
    required this.deck,
    required this.coverUrl,
    required this.importing,
    required this.index,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final owner = deck['owner'] is Map
        ? Map<String, dynamic>.from(deck['owner'] as Map)
        : null;
    final colors = [
      const Color(0xFF9F4F53),
      const Color(0xFF2F6F73),
      const Color(0xFF7357A6),
      const Color(0xFFD17A22),
      const Color(0xFF4F6F9F),
      const Color(0xFF6B7F3A),
    ];
    final cover = colors[index % colors.length];
    final title = (deck['title'] ?? '共享词库').toString();
    final subtitle = (deck['description'] ?? owner?['username'] ?? '个人共享词库')
        .toString();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: importing ? null : onImport,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.78,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: coverUrl == null ? cover : null,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withAlpha(30),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  if (coverUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        coverUrl!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: cover,
                          child: Icon(Icons.menu_book_rounded,
                              size: 48, color: cs.onPrimary),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Icon(Icons.menu_book_rounded,
                          size: 48, color: cs.onPrimary.withOpacity(0.75)),
                    ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Align(
                      alignment: AlignmentDirectional.bottomEnd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          importing ? '导入中' : '导入',
                          style: TextStyle(
                            color: importing ? cs.primary : cs.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ],
      ),
    );
  }
}
