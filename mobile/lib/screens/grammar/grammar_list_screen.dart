import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

// JLPT 级别色
const _grammarLevelColors = {
  'N5': Color(0xFF4CAF50),
  'N4': Color(0xFF2196F3),
  'N3': Color(0xFF9C27B0),
  'N2': Color(0xFFFF9800),
  'N1': Color(0xFFE53935),
};

class GrammarListScreen extends StatefulWidget {
  const GrammarListScreen({super.key});
  @override
  State<GrammarListScreen> createState() => _GrammarListScreenState();
}

class _GrammarListScreenState extends State<GrammarListScreen> {
  String _selectedLevel = 'N5';
  List<GrammarLessonModel> _lessons = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _restoreLevel(); }

  Future<void> _restoreLevel() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('grammar_selected_level');
    if (saved != null && ['N5','N4','N3','N2','N1'].contains(saved)) {
      _selectedLevel = saved;
    }
    _load();
  }

  Future<void> _saveLevel(String level) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('grammar_selected_level', level);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await apiService.getGrammarLessons(level: _selectedLevel);
      setState(() { _lessons = res['data'] as List<GrammarLessonModel>; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lvCol = _grammarLevelColors[_selectedLevel] ?? cs.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('文法課程'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: ['N5', 'N4', 'N3', 'N2', 'N1'].map((l) {
                final color = _grammarLevelColors[l] ?? cs.primary;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(l),
                    selected: _selectedLevel == l,
                    selectedColor: color.withValues(alpha: 0.18),
                    checkmarkColor: color,
                    labelStyle: TextStyle(
                      color: _selectedLevel == l ? color : null,
                      fontWeight: _selectedLevel == l ? FontWeight.bold : null,
                    ),
                    side: _selectedLevel == l
                        ? BorderSide(color: color, width: 1.5)
                        : null,
                    onSelected: (_) { setState(() => _selectedLevel = l); _saveLevel(l); _load(); },
                  ),
                );
              }).toList()),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _lessons.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_outlined, size: 64, color: cs.outlineVariant),
                          const SizedBox(height: 12),
                          Text('暂无 $_selectedLevel 语法条目', style: TextStyle(color: cs.outline)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      itemCount: _lessons.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final l = _lessons[i];
                        return _GrammarCard(
                          lesson: l,
                          index: i + 1,
                          levelColor: lvCol,
                        );
                      },
                    ),
            ),
    );
  }
}

// ─── 语法卡片 ─────────────────────────────────────────────────────────────────

class _GrammarCard extends StatelessWidget {
  final GrammarLessonModel lesson;
  final int index;
  final Color levelColor;
  const _GrammarCard({required this.lesson, required this.index, required this.levelColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final desc = lesson.explanationZh ?? lesson.explanation;
    final preview = desc.length > 60 ? '${desc.substring(0, 60)}…' : desc;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/grammar/${lesson.id}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Index circle
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: levelColor.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: levelColor, fontWeight: FontWeight.bold, fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lesson.pattern,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: levelColor,
                            ),
                          ),
                        ),
                        if (lesson.examples.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${lesson.examples.length} 例',
                              style: TextStyle(fontSize: 11, color: cs.outline),
                            ),
                          ),
                      ],
                    ),
                    if ((lesson.titleZh ?? lesson.title).isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        lesson.titleZh ?? lesson.title,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface),
                      ),
                    ],
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: cs.outlineVariant, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
