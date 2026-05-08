import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/guest_service.dart';
import '../../models/models.dart';
import '../../widgets/furigana_text.dart';

// JLPT 级别色
const _grammarLevelColors = {
  'N5': Color(0xFF4CAF50),
  'N4': Color(0xFF2196F3),
  'N3': Color(0xFF9C27B0),
  'N2': Color(0xFFFF9800),
  'N1': Color(0xFFE53935),
};

class GrammarListScreen extends StatefulWidget {
  final String? initialLevel;
  final String? planStage;
  final String? planId;

  const GrammarListScreen({
    super.key,
    this.initialLevel,
    this.planStage,
    this.planId,
  });
  @override
  State<GrammarListScreen> createState() => _GrammarListScreenState();
}

class _GrammarListScreenState extends State<GrammarListScreen> {
  String _selectedLevel = 'N5';
  final List<GrammarLessonModel> _lessons = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _total = 0;
  static const _pageSize = 200;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final lv = widget.initialLevel;
    if (lv != null && ['N5', 'N4', 'N3', 'N2', 'N1'].contains(lv)) {
      _selectedLevel = lv;
    }
    _restoreLevel();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 420),
      () => _load(),
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _restoreLevel() async {
    if (widget.initialLevel != null && ['N5', 'N4', 'N3', 'N2', 'N1'].contains(widget.initialLevel)) {
      _selectedLevel = widget.initialLevel!;
      _load();
      return;
    }
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
    setState(() { _loading = true; _page = 1; _lessons.clear(); _hasMore = true; });
    try {
      final q = _searchCtrl.text.trim();
      final res = await apiService.getGrammarLessons(
        level: q.isNotEmpty ? null : _selectedLevel,
        query: q.isEmpty ? null : q,
        page: 1,
        limit: _pageSize,
      );
      _total = res['total'] as int? ?? 0;
      final data = res['data'] as List<GrammarLessonModel>;
      if (!mounted) return;
      setState(() {
        _lessons.addAll(_sortCommonFirst(data));
        // 游客模式限刖10条
        if (guestService.isGuest && _lessons.length > 10) {
          _lessons.removeRange(10, _lessons.length);
          _hasMore = false;
        } else {
          _hasMore = _lessons.length < _total;
        }
        _loading = false;
      });
      // 预加载第2页
      if (_hasMore) _prefetch(2);
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    _page++;
    try {
      final q = _searchCtrl.text.trim();
      final res = await apiService.getGrammarLessons(
        level: q.isNotEmpty ? null : _selectedLevel,
        query: q.isEmpty ? null : q,
        page: _page,
        limit: _pageSize,
      );
      final data = res['data'] as List<GrammarLessonModel>;
      if (!mounted) return;
      setState(() {
        _lessons.addAll(_sortCommonFirst(data));
        _hasMore = _lessons.length < _total;
        _loadingMore = false;
      });
      // 预加载下一页到缓存
      if (_hasMore) _prefetch(_page + 1);
    } catch (_) {
      _page--;
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _prefetch(int nextPage) {
    // 静默预加载，仅填充缓存，不影响UI
    apiService.getGrammarLessons(level: _selectedLevel, page: nextPage, limit: _pageSize);
  }

  List<GrammarLessonModel> _sortCommonFirst(List<GrammarLessonModel> input) {
    final indexed = <MapEntry<int, GrammarLessonModel>>[];
    for (var i = 0; i < input.length; i++) {
      indexed.add(MapEntry(i, input[i]));
    }

    int priority(GrammarLessonModel g) {
      if (g.isCommon == true) return 0;
      if (g.frequencyRank != null) {
        if (g.frequencyRank! <= 2000) return 0;
        if (g.frequencyRank! >= 10000) return 2;
        return 1;
      }
      final tags = '${g.category ?? ''} ${g.difficulty ?? ''} ${g.usageNotes ?? ''} ${g.titleZh ?? ''} ${g.title}'.toLowerCase();
      if (tags.contains('常用') || tags.contains('common') || tags.contains('core') || tags.contains('daily') || tags.contains('basic')) {
        return 0;
      }
      if (tags.contains('生僻') || tags.contains('rare') || tags.contains('uncommon') || tags.contains('hard')) {
        return 2;
      }
      return 1;
    }

    indexed.sort((a, b) {
      final pa = priority(a.value);
      final pb = priority(b.value);
      if (pa != pb) return pa.compareTo(pb);
      return a.key.compareTo(b.key);
    });

    return indexed.map((e) => e.value).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lvCol = _grammarLevelColors[_selectedLevel] ?? cs.primary;
    final inPlanMode = widget.planId != null && widget.planId!.isNotEmpty;
    final levels = inPlanMode ? <String>[_selectedLevel] : <String>['N5', 'N4', 'N3', 'N2', 'N1'];
    final isSearching = _searchCtrl.text.trim().isNotEmpty;
    final planStageText = switch (widget.planStage) {
      'new' => '新卡片',
      'learning' => '学习中',
      'review' => '待复习',
      'overdue' => '优先复习',
      _ => '全部',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(inPlanMode ? '学习计划 · 语法' : '语法課程'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/study'),
        ),
        actions: [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索语法、句型或释义…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () { _searchCtrl.clear(); _load(); },
                        )
                      : null,
                  isDense: true,
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (_) { _debounce?.cancel(); _load(); },
              ),
              const SizedBox(height: 8),
              if (!isSearching)
              SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: levels.map((l) {
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
                    onSelected: inPlanMode
                        ? null
                        : (_) { setState(() => _selectedLevel = l); _saveLevel(l); _searchCtrl.clear(); _load(); },
                  ),
                );
              }).toList()),
            ),
              if (isSearching)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Icon(Icons.travel_explore_rounded, size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Text('全局搜索中…', style: TextStyle(fontSize: 12, color: cs.primary)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
      body: _loading
          ? _buildSkeleton(cs)
          : RefreshIndicator(
              onRefresh: _load,
              child: _lessons.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                        Icon(Icons.menu_book_outlined, size: 64, color: cs.outlineVariant),
                        const SizedBox(height: 12),
                        Center(child: Text(
                          isSearching ? '未找到匹配的语法条目' : '暂无 $_selectedLevel 语法条目',
                          style: TextStyle(color: cs.outline),
                        )),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      itemCount: _lessons.length + 2, // header + footer
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          if (!inPlanMode) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Text('共 $_total 条', style: TextStyle(fontSize: 13, color: cs.outline, fontWeight: FontWeight.w500)),
                                  const Spacer(),
                                  Text('${_lessons.length}/$_total', style: TextStyle(fontSize: 12, color: cs.outlineVariant)),
                                ],
                              ),
                            );
                          }
                          return Column(
                            children: [
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '计划模式：等级 $_selectedLevel · 阶段 $planStageText',
                                  style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Text('共 $_total 条', style: TextStyle(fontSize: 13, color: cs.outline, fontWeight: FontWeight.w500)),
                                    const Spacer(),
                                    Text('${_lessons.length}/$_total', style: TextStyle(fontSize: 12, color: cs.outlineVariant)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                        final idx = i - 1;
                        if (idx >= _lessons.length) {
                          if (guestService.isGuest && !_hasMore) {
                            return _GuestLimitBanner();
                          }
                          if (_loadingMore) {
                            return const Padding(padding: EdgeInsets.all(20), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
                          }
                          return _hasMore
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(child: Text('— 已全部加载 —', style: TextStyle(fontSize: 12, color: cs.outlineVariant))),
                                );
                        }
                        final l = _lessons[idx];
                        final cardColor = isSearching
                            ? (_grammarLevelColors[l.jlptLevel] ?? lvCol)
                            : lvCol;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _GrammarCard(lesson: l, index: idx + 1, levelColor: cardColor, showLevel: isSearching, lessonIds: _lessons.map((e) => e.id).toList()),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _buildSkeleton(ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: 8,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 16, width: 140, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 8),
                    Container(height: 12, width: 200, decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 游客限制提示 ──────────────────────────────────────────────────────────────

class _GuestLimitBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Icon(Icons.lock_outline_rounded, color: cs.primary, size: 28),
        const SizedBox(height: 8),
        Text('游客仅可预览 10 条内容',
          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 4),
        Text('登录后可浏览全部内容并同步学习进度',
          style: TextStyle(fontSize: 12, color: cs.outline)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              guestService.disableGuestMode();
              GoRouter.of(context).go('/login');
            },
            child: const Text('登录 / 注册'),
          ),
        ),
      ]),
    );
  }
}

// ─── 语法卡片 ─────────────────────────────────────────────────────────────────

class _GrammarCard extends StatelessWidget {
  final GrammarLessonModel lesson;
  final int index;
  final Color levelColor;
  final bool showLevel;
  final List<String>? lessonIds;
  const _GrammarCard({required this.lesson, required this.index, required this.levelColor, this.showLevel = false, this.lessonIds});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final desc = lesson.explanationZh ?? lesson.explanation ?? '';
    final pattern = stripFuriganaMarkup(lesson.pattern);
    final title = stripFuriganaMarkup(lesson.titleZh ?? lesson.title);
    final showTitle = title.isNotEmpty &&
        title.replaceAll(RegExp(r'\s+'), '') !=
            pattern.replaceAll(RegExp(r'\s+'), '');
    final preview = desc.length > 60 ? '${desc.substring(0, 60)}…' : desc;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/grammar/${lesson.id}', extra: lessonIds),
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
                            pattern,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: levelColor,
                            ),
                          ),
                        ),
                        if (showLevel && lesson.jlptLevel.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: levelColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: levelColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              lesson.jlptLevel,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: levelColor),
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
                    if (showTitle) ...[
                      const SizedBox(height: 3),
                      Text(
                        title,
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
