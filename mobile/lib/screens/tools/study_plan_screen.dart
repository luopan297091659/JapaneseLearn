import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/local_db.dart';

class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  static const _storageKey = 'study_plans_v1';
  static const _activePlanKey = 'study_plans_active_id_v1';

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

  Map<String, dynamic>? get _activePlan {
    for (final plan in _plans) {
      if (plan['id'] == _activePlanId) return plan;
    }
    return null;
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

  Future<void> _startPlan(Map<String, dynamic> plan) async {
    await _setActivePlan(plan['id']?.toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已开启「${plan['name'] ?? '学习计划'}」'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openPlanModule(String module, Map<String, dynamic> plan) async {
    switch (module) {
      case 'vocabulary':
        await context.push('/vocabulary');
        break;
      case 'grammar':
        await context.push('/grammar');
        break;
      case 'anki':
        await context.push('/local-vocab');
        break;
      default:
        break;
    }
  }

  Future<void> _showPlanEditor({int? editIndex}) async {
    final editing = editIndex != null;
    final original = editing ? _plans[editIndex] : <String, dynamic>{};

    final nameCtrl = TextEditingController(text: (original['name'] as String?) ?? '');
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
                  onChanged: (v) => setSt(() => selectedType = v ?? 'anki'),
                  title: const Text('Anki词库'),
                  subtitle: const Text('按词库加入本地 Anki 复习'),
                ),
                if (selectedType == 'anki') ...[
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: ankiDeckRoot.isEmpty ? null : ankiDeckRoot,
                    decoration: const InputDecoration(
                      labelText: '选择词牌',
                      prefixIcon: Icon(Icons.folder_copy_rounded),
                    ),
                    items: [
                      const DropdownMenuItem(value: '__all__', child: Text('全部词牌')),
                      ..._ankiDeckRoots.map((name) => DropdownMenuItem(value: name, child: Text(name))),
                    ],
                    onChanged: (v) => setSt(() => ankiDeckRoot = v ?? ''),
                  ),
                ],
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
                if (selectedType == 'anki' && ankiDeckRoot.isEmpty) {
                  setSt(() => error = '请选择 Anki 词牌');
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
      };

      setState(() {
        if (editing) {
          _plans[editIndex] = item;
        } else {
          _plans.add(item);
        }
      });
      await _savePlans();
    }

    nameCtrl.dispose();
  }

  String _planSummary(Map<String, dynamic> plan) {
    if (plan['includeVocabulary'] == true) {
      return '学习类型：单词 · 等级 ${plan['vocabularyLevel'] ?? 'N5'}';
    }
    if (plan['includeGrammar'] == true) {
      return '学习类型：语法 · 等级 ${plan['grammarLevel'] ?? 'N5'}';
    }
    if (plan['includeAnki'] == true) {
      final deckRoot = (plan['ankiDeckRoot'] ?? plan['ankiDeck'] ?? '').toString();
      final deck = deckRoot == '__all__' ? '全部词牌' : (deckRoot.isEmpty ? '词牌' : deckRoot);
      return '学习类型：Anki · 词牌 $deck';
    }
    return '学习类型：未设置';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习计划'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/tools'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPlanEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建计划'),
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
                  itemCount: _plans.length + (_activePlan != null ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (_activePlan != null && index == 0) {
                      return _buildActivePlanCard(cs, _activePlan!);
                    }
                    final realIndex = _activePlan != null ? index - 1 : index;
                    final plan = _plans[realIndex];
                    final summary = _planSummary(plan);

                    final isActive = plan['id']?.toString() == _activePlanId;

                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: cs.primaryContainer,
                                  child: Icon(Icons.route_rounded, color: cs.primary),
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
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: isActive ? null : () => _startPlan(plan),
                                icon: Icon(isActive ? Icons.check_circle_rounded : Icons.play_arrow_rounded),
                                label: Text(isActive ? '已开启' : '开启计划'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildActivePlanCard(ColorScheme cs, Map<String, dynamic> plan) {
    final chips = <Widget>[];
    if (plan['includeVocabulary'] == true) {
      chips.add(ActionChip(
        avatar: const Icon(Icons.menu_book_rounded, size: 16),
        label: Text('单词 ${plan['vocabularyLevel'] ?? 'N5'}'),
        onPressed: () => _openPlanModule('vocabulary', plan),
      ));
    }
    if (plan['includeGrammar'] == true) {
      chips.add(ActionChip(
        avatar: const Icon(Icons.school_rounded, size: 16),
        label: Text('语法 ${plan['grammarLevel'] ?? 'N5'}'),
        onPressed: () => _openPlanModule('grammar', plan),
      ));
    }
    if (plan['includeAnki'] == true) {
      final deckRoot = (plan['ankiDeckRoot'] ?? plan['ankiDeck'] ?? '').toString();
      final deckLabel = deckRoot == '__all__' ? '全部词牌' : (deckRoot.isEmpty ? '词牌' : deckRoot);
      chips.add(ActionChip(
        avatar: const Icon(Icons.folder_copy_rounded, size: 16),
        label: Text('Anki $deckLabel'),
        onPressed: () => _openPlanModule('anki', plan),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_circle_fill_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('进行中：${plan['name'] ?? '学习计划'}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
                    const SizedBox(height: 2),
                    Text(
                      _planSummary(plan),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _setActivePlan(null),
                child: const Text('结束'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
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
