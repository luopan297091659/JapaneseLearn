import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/local_db.dart';
import '../../services/api_service.dart';

class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  static const _storageKey = 'study_plans_v1';
  static const _activePlanKey = 'study_plans_active_id_v1';
  static const _planCardsKeyPrefix = 'study_plan_new_cards_v1_';

  List<Map<String, dynamic>> _plans = [];
  List<String> _ankiDeckRoots = [];
  String? _activePlanId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final activePlanId = prefs.getString(_activePlanKey);
    final decks = await localDb.listDecks();

    List<Map<String, dynamic>> plans = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        plans = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        plans = [];
      }
    }

    final hasActive = plans.any((p) => (p['status'] ?? 'not_started').toString() == 'in_progress');

    if (!mounted) return;
    final deckNames = decks.map((d) => d.deckName).toSet().toList()..sort();
    final deckRoots = deckNames
        .map((name) => name.split('::').first.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    setState(() {
      _plans = plans;
      _ankiDeckRoots = deckRoots;
      _activePlanId = activePlanId;
      _loading = false;
    });

    if (!hasActive && activePlanId != null) {
      final prefs2 = await SharedPreferences.getInstance();
      await prefs2.remove(_activePlanKey);
      await _savePlans();
    }
  }

  Future<void> _savePlans() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_plans));
  }

  Future<void> _setActivePlan(String? planId) async {
    final prefs = await SharedPreferences.getInstance();
    if (planId == null) {
      await prefs.remove(_activePlanKey);
    } else {
      await prefs.setString(_activePlanKey, planId);
    }
    if (mounted) setState(() => _activePlanId = planId);
  }

  String _planCardsStorageKey(String planId) => '$_planCardsKeyPrefix$planId';

  String _planStatus(Map<String, dynamic> plan) => (plan['status'] ?? 'not_started').toString();

  int _planPriority(Map<String, dynamic> plan) {
    final status = _planStatus(plan);
    if (status == 'in_progress') return 0;
    if (status == 'not_started') return 1;
    return 2;
  }

  String _planStatusText(String status) {
    switch (status) {
      case 'in_progress':
        return '进行中';
      case 'ended':
        return '已结束';
      default:
        return '未开始';
    }
  }

  Color _planStatusColor(ColorScheme cs, String status) {
    switch (status) {
      case 'in_progress':
        return cs.primary;
      case 'ended':
        return cs.outline;
      default:
        return Colors.orange;
    }
  }

  Future<List<String>> _fetchAllGrammarIds(String level) async {
    const limit = 100;
    var page = 1;
    final ids = <String>[];

    while (true) {
      final res = await apiService.getGrammarLessons(level: level, page: page, limit: limit);
      final lessons = (res['data'] as List).cast<dynamic>();
      for (final lesson in lessons) {
        final id = lesson.id?.toString() ?? '';
        if (id.isNotEmpty) ids.add(id);
      }

      final total = (res['total'] as int?) ?? ids.length;
      if (lessons.isEmpty || ids.length >= total) break;
      page += 1;
      if (page > 100) break;
    }

    return ids;
  }

  Future<List<String>> _fetchAnkiIds(String deckRoot) async {
    const limit = 200;
    var page = 1;
    final ids = <String>[];
    final useDeckFilter = deckRoot != '__all__' && deckRoot.isNotEmpty;

    while (true) {
      final rows = await localDb.listByDeck(
        deckName: useDeckFilter ? deckRoot : null,
        prefixMatch: useDeckFilter,
        page: page,
        limit: limit,
      );
      if (rows.isEmpty) break;
      ids.addAll(rows.map((e) => e.id));
      if (rows.length < limit) break;
      page += 1;
      if (page > 200) break;
    }

    return ids;
  }

  Future<Map<String, dynamic>> _enrichPlanWithImportedCards(Map<String, dynamic> base) async {
    final planId = base['id'].toString();
    final includeVocab = base['includeVocabulary'] == true;
    final includeGrammar = base['includeGrammar'] == true;
    final includeAnki = base['includeAnki'] == true;
    final dailyTarget = ((base['dailyTarget'] as int?) ?? 20).clamp(1, 999);

    List<String> ids = const [];
    String type = 'vocabulary';

    if (includeVocab) {
      type = 'vocabulary';
      final level = (base['vocabularyLevel'] ?? 'N5').toString();
      ids = await apiService.getVocabularyIdsByLevel(level);
    } else if (includeGrammar) {
      type = 'grammar';
      final level = (base['grammarLevel'] ?? 'N5').toString();
      ids = await _fetchAllGrammarIds(level);
    } else if (includeAnki) {
      type = 'anki';
      final deckRoot = (base['ankiDeckRoot'] ?? '').toString();
      ids = await _fetchAnkiIds(deckRoot);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _planCardsStorageKey(planId),
      jsonEncode({
        'planId': planId,
        'type': type,
        'ids': ids,
        'importedAt': DateTime.now().toIso8601String(),
      }),
    );

    final total = ids.length;
    final estimatedDays = total == 0 ? 0 : ((total + dailyTarget - 1) ~/ dailyTarget);

    return {
      ...base,
      'totalCardCount': total,
      'importedCount': total,
      'estimatedDays': estimatedDays,
      'status': (base['status'] ?? 'not_started').toString(),
      'dailyTarget': dailyTarget,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _deletePlan(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除学习计划'),
        content: Text('确定删除「${_plans[index]['name'] ?? '未命名计划'}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleting = _plans[index];
      setState(() => _plans.removeAt(index));
      await _savePlans();
      if (_activePlanId == deleting['id']) {
        await _setActivePlan(null);
      }
    }
  }

  Future<void> _openPlanDetail(Map<String, dynamic> plan) async {
    await context.push('/study-plan/${plan['id']}');
  }

  Future<void> _pausePlan(Map<String, dynamic> plan) async {
    final planId = plan['id']?.toString();
    if (planId == null || planId.isEmpty) return;

    for (final p in _plans) {
      if (p['id']?.toString() == planId) {
        p['status'] = 'not_started';
      }
    }
    await _savePlans();
    if (_activePlanId == planId) {
      await _setActivePlan(null);
    }
    if (mounted) setState(() {});
  }

  Future<void> _startPlanAndOpen(Map<String, dynamic> plan) async {
    final planId = plan['id']?.toString();
    if (planId == null || planId.isEmpty) return;

    for (final p in _plans) {
      if (p['id']?.toString() == planId) {
        p['status'] = 'in_progress';
      }
    }
    await _savePlans();
    await _setActivePlan(planId);
    try {
      await apiService.getStudyPlanToday();
      await apiService.startStudyPlanDay();
    } catch (_) {
      // 后端接口失败不阻断本地计划
    }
    if (!mounted) return;
    setState(() {});
    await _openPlanDetail(plan);
  }

  Future<void> _showPlanEditor({int? editIndex}) async {
    final editing = editIndex != null;
    final original = editing ? _plans[editIndex] : <String, dynamic>{};

    final nameCtrl = TextEditingController(text: (original['name'] as String?) ?? '');
    final dailyTargetCtrl = TextEditingController(
      text: ((original['dailyTarget'] as int?) ?? 20).toString(),
    );
    var vocabLevel = (original['vocabularyLevel'] as String?) ?? 'N5';
    var grammarLevel = (original['grammarLevel'] as String?) ?? 'N5';
    var selectedType = 'vocabulary';
    if ((original['includeAnki'] as bool?) == true) {
      selectedType = 'anki';
    } else if ((original['includeGrammar'] as bool?) == true) {
      selectedType = 'grammar';
    } else if ((original['includeVocabulary'] as bool?) == true) {
      selectedType = 'vocabulary';
    }
    var ankiDeckRoot = (original['ankiDeckRoot'] as String?) ?? '';
    if (ankiDeckRoot.isEmpty) {
      final legacyDeck = (original['ankiDeck'] as String?) ?? '';
      if (legacyDeck.isNotEmpty && legacyDeck != '__all__') {
        ankiDeckRoot = legacyDeck.split('::').first.trim();
      } else if (legacyDeck == '__all__') {
        ankiDeckRoot = '__all__';
      }
    }
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(editing ? '编辑学习计划' : '新建学习计划'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '计划名称',
                    hintText: '例如：N3冲刺计划',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dailyTargetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每日学习数目',
                    hintText: '默认 20',
                    prefixIcon: Icon(Icons.today_rounded),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                const Text('学习内容（单选）', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 6),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'vocabulary',
                  groupValue: selectedType,
                  onChanged: (v) => setSt(() => selectedType = v ?? 'vocabulary'),
                  title: const Text('单词学习'),
                  subtitle: const Text('按 JLPT 等级加入单词学习'),
                ),
                if (selectedType == 'vocabulary')
                  _LevelSelector(
                    title: '单词等级',
                    value: vocabLevel,
                    onChanged: (v) => setSt(() => vocabLevel = v),
                  ),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'grammar',
                  groupValue: selectedType,
                  onChanged: (v) => setSt(() => selectedType = v ?? 'grammar'),
                  title: const Text('语法学习'),
                  subtitle: const Text('按 JLPT 等级加入语法学习'),
                ),
                if (selectedType == 'grammar')
                  _LevelSelector(
                    title: '语法等级',
                    value: grammarLevel,
                    onChanged: (v) => setSt(() => grammarLevel = v),
                  ),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'anki',
                  groupValue: selectedType,
                  onChanged: (v) => setSt(() {
                    selectedType = v ?? 'anki';
                    if (ankiDeckRoot.isEmpty) ankiDeckRoot = '__all__';
                  }),
                  title: const Text('我的词库'),
                  subtitle: const Text('使用已导入的词库学习'),
                ),
                if (selectedType == 'anki')
                  _ankiDeckRoots.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(left: 16, top: 4),
                          child: Text('暂无已导入的牌组，请先在「Anki导入」中导入', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16),
                          child: DropdownButtonFormField<String>(
                            value: ankiDeckRoot.isEmpty || (!_ankiDeckRoots.contains(ankiDeckRoot) && ankiDeckRoot != '__all__')
                                ? '__all__'
                                : ankiDeckRoot,
                            decoration: const InputDecoration(
                              labelText: '选择牌组',
                              prefixIcon: Icon(Icons.folder_rounded),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(value: '__all__', child: Text('全部牌组')),
                              ..._ankiDeckRoots.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                            ],
                            onChanged: (v) => setSt(() => ankiDeckRoot = v ?? '__all__'),
                          ),
                        ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setSt(() => error = '计划名称不能为空');
                  return;
                }
                final dailyTarget = int.tryParse(dailyTargetCtrl.text.trim()) ?? 20;
                if (dailyTarget <= 0) {
                  setSt(() => error = '每日学习数目必须大于 0');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final includeVocab = selectedType == 'vocabulary';
      final includeGrammar = selectedType == 'grammar';
      final includeAnki = selectedType == 'anki';
      final dailyTarget = int.tryParse(dailyTargetCtrl.text.trim()) ?? 20;

      final item = <String, dynamic>{
        'id': (original['id']?.toString().isNotEmpty == true)
            ? original['id'].toString()
            : DateTime.now().microsecondsSinceEpoch.toString(),
        'name': nameCtrl.text.trim(),
        'includeVocabulary': includeVocab,
        'vocabularyLevel': vocabLevel,
        'includeGrammar': includeGrammar,
        'grammarLevel': grammarLevel,
        'includeAnki': includeAnki,
        'ankiDeckRoot': ankiDeckRoot,
        'ankiDeck': ankiDeckRoot,
        'dailyTarget': dailyTarget,
        'status': (original['status'] ?? 'not_started').toString(),
      };

      setState(() => _loading = true);
      try {
        final enriched = await _enrichPlanWithImportedCards(item);

        setState(() {
          if (editing) {
            _plans[editIndex] = enriched;
          } else {
            _plans.add(enriched);
          }
        });
        await _savePlans();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('已导入 ${enriched['importedCount'] ?? 0} 张新卡片到计划'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('导入新卡片失败：$e'),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    nameCtrl.dispose();
    dailyTargetCtrl.dispose();
  }

  String _planSummary(Map<String, dynamic> plan) {
    final daily = (plan['dailyTarget'] ?? 20).toString();
    final estimatedDays = (plan['estimatedDays'] ?? 0).toString();
    if (plan['includeVocabulary'] == true) {
      return '学习类型：单词 · 等级 ${plan['vocabularyLevel'] ?? 'N5'} · 每日$daily · 预计$estimatedDays天';
    }
    if (plan['includeGrammar'] == true) {
      return '学习类型：语法 · 等级 ${plan['grammarLevel'] ?? 'N5'} · 每日$daily · 预计$estimatedDays天';
    }
    if (plan['includeAnki'] == true) {
      final deckRoot = (plan['ankiDeckRoot'] ?? plan['ankiDeck'] ?? '').toString();
      final deck = deckRoot == '__all__' ? '全部词牌' : (deckRoot.isEmpty ? '词牌' : deckRoot);
      return '学习类型：Anki · 词牌 $deck · 每日$daily · 预计$estimatedDays天';
    }
    return '学习类型：未设置';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayPlans = [..._plans]
      ..sort((a, b) {
        final pa = _planPriority(a);
        final pb = _planPriority(b);
        if (pa != pb) return pa.compareTo(pb);
        final ta = a['updatedAt']?.toString() ?? '';
        final tb = b['updatedAt']?.toString() ?? '';
        return tb.compareTo(ta);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习计划'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/tools'),
        ),
        actions: [
          IconButton(
            tooltip: '新建计划',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showPlanEditor(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.route_rounded, size: 72, color: cs.outline),
                        const SizedBox(height: 14),
                        const Text('还没有学习计划', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          '每个计划仅选择一种学习内容，再设置对应等级或词牌。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: displayPlans.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final plan = displayPlans[index];
                    final realIndex = _plans.indexWhere((p) => p['id']?.toString() == plan['id']?.toString());
                    if (realIndex < 0) return const SizedBox.shrink();
                    final summary = _planSummary(plan);

                    final status = _planStatus(plan);
                    final isActive = status == 'in_progress';
                    final statusText = _planStatusText(status);
                    final statusColor = _planStatusColor(cs, status);

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: isActive
                            ? const BorderSide(color: Colors.pinkAccent, width: 1.5)
                            : BorderSide.none,
                      ),
                      color: isActive ? Colors.pink.shade50 : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isActive ? Colors.pinkAccent : cs.primaryContainer,
                                  child: Icon(
                                    isActive ? Icons.play_circle_fill_rounded : Icons.route_rounded,
                                    color: isActive ? Colors.white : cs.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(plan['name'] ?? '未命名计划', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                                      const SizedBox(height: 4),
                                      Text(summary, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: '编辑',
                                  icon: const Icon(Icons.edit_rounded, size: 20),
                                  onPressed: () => _showPlanEditor(editIndex: realIndex),
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                  onPressed: () => _deletePlan(realIndex),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (isActive) ...[
                                  Expanded(
                                    flex: 1,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _pausePlan(plan),
                                      icon: const Icon(Icons.pause_rounded, size: 18),
                                      label: const Text('暂停'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  flex: 2,
                                  child: FilledButton.icon(
                                    onPressed: isActive ? () => _openPlanDetail(plan) : () => _startPlanAndOpen(plan),
                                    icon: Icon(isActive ? Icons.check_circle_rounded : Icons.play_arrow_rounded),
                                    label: Text(isActive ? '继续学习' : (status == 'ended' ? '重新开始' : '开始计划')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _LevelSelector extends StatelessWidget {
  final String title;
  final String value;
  final ValueChanged<String> onChanged;

  const _LevelSelector({required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: ['N5', 'N4', 'N3', 'N2', 'N1'].map((level) {
            return ChoiceChip(
              label: Text(level),
              selected: value == level,
              onSelected: (_) => onChanged(level),
            );
          }).toList(),
        ),
      ],
    );
  }
}
