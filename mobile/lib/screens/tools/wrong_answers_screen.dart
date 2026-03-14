import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

class WrongAnswersScreen extends StatefulWidget {
  const WrongAnswersScreen({super.key});

  @override
  State<WrongAnswersScreen> createState() => _WrongAnswersScreenState();
}

class _WrongAnswersScreenState extends State<WrongAnswersScreen> {
  List<Map<String, dynamic>> _items = [];
  String _filter = 'all';
  bool _loading = true;
  bool _syncing = false;

  static const _sourceLabels = {
    'quiz': '单词测验',
    'listening': '听力测试',
    'game': '闯关游戏',
  };

  @override
  void initState() {
    super.initState();
    _loadAndSync();
  }

  /// 先加载本地，再与服务端同步
  Future<void> _loadAndSync() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wrongAnswers') ?? '[]';
    final List<dynamic> list = jsonDecode(raw);
    final local = list.cast<Map<String, dynamic>>().reversed.toList();
    setState(() { _items = local; _loading = false; });
    // 后台同步
    _syncWithServer(prefs, local);
  }

  Future<void> _syncWithServer(SharedPreferences prefs, List<Map<String, dynamic>> local) async {
    if (_syncing) return;
    _syncing = true;
    try {
      // 找出未同步的（没有 id 字段的是本地新增的）
      final unsyncedItems = local.where((w) => w['id'] == null).toList();
      final res = await apiService.dio.post('/wrong-answers/sync', data: {
        'items': unsyncedItems,
      });
      if (res.data['ok'] == true) {
        final serverList = (res.data['data'] as List).cast<Map<String, dynamic>>();
        // 服务端返回的是全量数据，直接替换本地
        await prefs.setString('wrongAnswers', jsonEncode(serverList));
        if (mounted) setState(() => _items = serverList);
      }
    } catch (_) {
      // 离线或未登录，保持本地数据不变
    }
    _syncing = false;
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _items;
    return _items.where((w) => w['source'] == _filter).toList();
  }

  Future<void> _deleteOne(Map<String, dynamic> item) async {
    // 从本地列表移除
    setState(() => _items.remove(item));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wrongAnswers', jsonEncode(_items));
    // 如果有服务端 id，也从服务端删除
    final serverId = item['id'];
    if (serverId != null) {
      try { await apiService.dio.delete('/wrong-answers/$serverId'); } catch (_) {}
    }
  }

  Future<void> _clearFiltered() async {
    final label = _filter == 'all' ? '所有' : (_sourceLabels[_filter] ?? _filter);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空错题'),
        content: Text('确定要清空「$label」的错题记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) return;
    if (_filter == 'all') {
      setState(() => _items = []);
    } else {
      setState(() => _items.removeWhere((w) => w['source'] == _filter));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wrongAnswers', jsonEncode(_items));
    // 服务端同步删除
    try {
      await apiService.dio.delete('/wrong-answers', queryParameters: {'source': _filter});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题集', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_filtered.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空当前分类',
              onPressed: _clearFiltered,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    _buildChip('全部', 'all'), const SizedBox(width: 8),
                    _buildChip('单词测验', 'quiz'), const SizedBox(width: 8),
                    _buildChip('听力测试', 'listening'), const SizedBox(width: 8),
                    _buildChip('闯关游戏', 'game'),
                  ]),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('✅', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text('暂无错题记录', style: TextStyle(color: cs.outline, fontSize: 15)),
                        ]))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _buildItem(filtered[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildChip(String label, String value) {
    final selected = _filter == value;
    return FilterChip(label: Text(label), selected: selected, onSelected: (_) => setState(() => _filter = value));
  }

  Widget _buildItem(Map<String, dynamic> w) {
    final cs = Theme.of(context).colorScheme;
    final source = _sourceLabels[w['source']] ?? w['source']?.toString() ?? '';
    final gameType = w['gameType'] == 'verbs' ? ' · 动词方块' : (w['gameType'] == 'particles' ? ' · 助词方块' : '');
    final time = w['time'] != null ? DateTime.tryParse(w['time'].toString()) : null;
    final timeStr = time != null ? '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : '';

    return Dismissible(
      key: ValueKey(w['id']?.toString() ?? '${w['question']}_${w['time']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      onDismissed: (_) => _deleteOne(w),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Text('$source$gameType', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary)),
                  ),
                  const Spacer(),
                  Text(timeStr, style: TextStyle(fontSize: 10, color: cs.outline)),
                ]),
                const SizedBox(height: 8),
                Text(w['question']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text('❌ ${w['yourAnswer'] ?? ''}', style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
                Text('✅ ${w['correctAnswer'] ?? ''}', style: const TextStyle(color: Color(0xFF43A047), fontSize: 13)),
                if (w['explanation'] != null && w['explanation'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(w['explanation'].toString(), style: TextStyle(fontSize: 12, color: cs.outline)),
                ],
              ]),
            ),
            // 单条删除按钮
            IconButton(
              icon: Icon(Icons.close, size: 18, color: cs.outline),
              onPressed: () => _deleteOne(w),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
