import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/local_db.dart';

/// 显示从字典保存的词条
class SavedDictionaryScreen extends StatefulWidget {
  const SavedDictionaryScreen({super.key});

  @override
  State<SavedDictionaryScreen> createState() => _SavedDictionaryScreenState();
}

class _SavedDictionaryScreenState extends State<SavedDictionaryScreen> {
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  int _totalCount = 0;
  int _displayCount = 50;
  static const _loadMoreCount = 50;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadEntries();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      if (_displayCount < _entries.length) {
        setState(() => _displayCount += _loadMoreCount);
      }
    }
  }

  Future<void> _loadEntries() async {
    try {
      final entries = await localDb.getSavedDictEntries(limit: 1000);
      final count = await localDb.getSavedDictEntriesCount();
      if (mounted) {
        setState(() {
          _entries = entries;
          _totalCount = count;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteEntry(int id) async {
    try {
      await localDb.deleteSavedDictEntry(id);
      setState(() => _entries.removeWhere((e) => e['id'] == id));
    } catch (_) {}
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: Text('将删除所有 $_totalCount 条已保存的词条，此操作无法撤销'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await localDb.clearSavedDictEntries();
      if (mounted) {
        setState(() {
          _entries = [];
          _totalCount = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清空'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('保存的词条')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_entries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('保存的词条')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_outline, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              const Text('还没有保存任何词条'),
              const SizedBox(height: 8),
              const Text('从字典搜索结果中点击"保存"按钮', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final displayedEntries = _entries.take(_displayCount).toList();
    final hasMore = _displayCount < _entries.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('保存的词条 ($_totalCount)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_entries.isNotEmpty)
            PopupMenuButton(
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  child: const Row(children: [
                    Icon(Icons.delete_outline, size: 18),
                    SizedBox(width: 8),
                    Text('清空全部'),
                  ]),
                  onTap: _clearAll,
                ),
              ],
            ),
        ],
      ),
      body: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(12),
        itemCount: displayedEntries.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          if (i == displayedEntries.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final entry = displayedEntries[i];
          final word = entry['word'] ?? '';
          final reading = entry['reading'] ?? '';
          final meaningZh = entry['meaning_zh'] ?? '';
          final meaningEn = entry['meaning_en'] ?? '';
          final jlpt = entry['jlpt'] ?? '';
          final id = entry['id'] as int;

          return Card(
            elevation: 1,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                word,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              if (reading.isNotEmpty)
                                Text(
                                  reading,
                                  style: TextStyle(fontSize: 14, color: cs.primary),
                                ),
                              if (jlpt.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Chip(
                                  label: Text(jlpt, style: const TextStyle(fontSize: 12)),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除',
                          onPressed: () => _deleteEntry(id),
                          iconSize: 20,
                        ),
                      ],
                    ),
                    if (meaningZh.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(meaningZh, style: const TextStyle(fontSize: 13)),
                    ],
                    if (meaningEn.isNotEmpty && meaningEn != meaningZh) ...[
                      const SizedBox(height: 4),
                      Text(meaningEn, style: TextStyle(fontSize: 12, color: cs.outline)),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
