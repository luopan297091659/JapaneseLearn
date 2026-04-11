import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/japanese_text_utils.dart';

class VocabularyListScreen extends StatefulWidget {
  final String? initialLevel;
  final String? planStage;
  final String? planId;

  const VocabularyListScreen({
    super.key,
    this.initialLevel,
    this.planStage,
    this.planId,
  });
  @override
  State<VocabularyListScreen> createState() => _VocabularyListScreenState();
}

class _VocabularyListScreenState extends State<VocabularyListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  String _selectedLevel = 'N5';
  List<VocabularyModel> _words = [];
  bool _loading     = true;
  bool _loadingMore = false;
  bool _hasMore     = true;
  int  _total       = 0;
  int  _page        = 1;
  static const _limit = 30;

  /// 当前级别的全部单词 ID（用于详情页上一个/下一个导航）
  List<String> _allWordIds = [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    final lv = widget.initialLevel;
    if (lv != null && ['N5', 'N4', 'N3', 'N2', 'N1'].contains(lv)) {
      _selectedLevel = lv;
    }
    _restoreLevel();
  }

  Future<void> _restoreLevel() async {
    if (widget.initialLevel != null && ['N5', 'N4', 'N3', 'N2', 'N1'].contains(widget.initialLevel)) {
      _selectedLevel = widget.initialLevel!;
      _loadWords(reset: true);
      return;
    }
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('vocab_selected_level');
    if (saved != null && ['N5','N4','N3','N2','N1'].contains(saved)) {
      _selectedLevel = saved;
    }
    _loadWords();
  }

  Future<void> _saveLevel(String level) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('vocab_selected_level', level);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 420),
      () => _loadWords(reset: true),
    );
  }

  Future<void> _loadWords({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _hasMore = true;
    }
    setState(() => _loading = true);
    try {
      final futures = <Future>[
        apiService.getVocabulary(
          level: _searchCtrl.text.isNotEmpty ? null : _selectedLevel,
          query: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
          page: _page,
          limit: _limit,
        ),
      ];
      // 搜索模式下不加载全部 ID，仅在常规浏览时加载
      if (_searchCtrl.text.isEmpty && reset) {
        futures.add(apiService.getVocabularyIdsByLevel(_selectedLevel));
      }
      final results = await Future.wait(futures);
      final res = results[0] as Map<String, dynamic>;
      final newWords = res['data'] as List<VocabularyModel>;
      if (results.length > 1) {
        _allWordIds = results[1] as List<String>;
      }
      setState(() {
        final merged = reset ? newWords : [..._words, ...newWords];
        _words = _sortCommonFirst(merged);
        _total   = res['total'] as int;
        _hasMore = _words.length < _total;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    _page++;
    try {
      final res = await apiService.getVocabulary(
        level: _searchCtrl.text.isNotEmpty ? null : _selectedLevel,
        query: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
        page: _page,
        limit: _limit,
      );
      final newWords = res['data'] as List<VocabularyModel>;
      setState(() {
        _words = _sortCommonFirst([..._words, ...newWords]);
        _hasMore = _words.length < _total;
        _loadingMore = false;
      });
    } catch (_) {
      _page--;
      setState(() => _loadingMore = false);
    }
  }

  List<VocabularyModel> _sortCommonFirst(List<VocabularyModel> input) {
    final indexed = <MapEntry<int, VocabularyModel>>[];
    for (var i = 0; i < input.length; i++) {
      indexed.add(MapEntry(i, input[i]));
    }

    int priority(VocabularyModel w) {
      if (w.isCommon == true) return 0;
      if (w.frequencyRank != null) {
        if (w.frequencyRank! <= 3000) return 0;
        if (w.frequencyRank! >= 15000) return 2;
        return 1;
      }
      final tags = '${w.category ?? ''} ${w.difficulty ?? ''}'.toLowerCase();
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
    final inPlanMode = widget.planId != null && widget.planId!.isNotEmpty;
    final levels = inPlanMode ? <String>[_selectedLevel] : <String>['N5', 'N4', 'N3', 'N2', 'N1'];
    final planStageText = switch (widget.planStage) {
      'new' => '新卡片',
      'learning' => '学习中',
      'review' => '待复习',
      'overdue' => '优先复习',
      _ => '全部',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(inPlanMode ? '学习计划 · 单词' : '単語学習'),
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
                  hintText: '搜索单词、读音或意思…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () { _searchCtrl.clear(); _loadWords(reset: true); },
                        )
                      : null,
                  isDense: true,
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (_) { _debounce?.cancel(); _loadWords(reset: true); },
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: levels.map((l) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(l),
                      selected: _selectedLevel == l,
                      onSelected: inPlanMode
                          ? null
                          : (_) {
                              setState(() => _selectedLevel = l);
                              _saveLevel(l);
                              _loadWords(reset: true);
                            },
                    ),
                  )).toList(),
                ),
              ),
            ]),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadWords(reset: true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inPlanMode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                      child: Container(
                        width: double.infinity,
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
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      '共 $_total 个单词，已加载 ${_words.length} 个',
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                  ),
                  Expanded(
                    child: _words.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 64, color: cs.outlineVariant),
                                const SizedBox(height: 12),
                                Text('没有找到相关单词', style: TextStyle(color: cs.outline)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                            itemCount: _words.length + (_hasMore ? 1 : 0),
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              if (i == _words.length) {
                                return _loadingMore
                                    ? const Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                      )
                                    : const SizedBox.shrink();
                              }
                              return _VocabCard(word: _words[i], wordIds: _allWordIds.isNotEmpty ? _allWordIds : _words.map((w) => w.id).toList());
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── 词汇卡片 ─────────────────────────────────────────────────────────────────

/// 格式化原始词性：自動1→自動詞1, 他動3→他動詞3, 自他動2→自他動詞2
/// 同时支持英文词性→中文映射（用于N4等只有英文词性的数据）
String _formatPosRaw(String raw) {
  const enZhMap = {
    'noun': '名词',
    'verb': '动词',
    'adjective': '形容词',
    'adverb': '副词',
    'particle': '助词',
    'conjunction': '接续词',
    'interjection': '感叹词',
    'other': '其他',
  };
  final mapped = enZhMap[raw.toLowerCase()];
  if (mapped != null) return mapped;
  return raw.replaceFirstMapped(
    RegExp(r'^(自他動|自動|他動|補動)(\d*)'),
    (m) => '${m[1]}詞${m[2] ?? ""}',
  );
}

const _levelColors = {
  'N5': Color(0xFF4CAF50),
  'N4': Color(0xFF2196F3),
  'N3': Color(0xFF9C27B0),
  'N2': Color(0xFFFF9800),
  'N1': Color(0xFFE53935),
};

class _VocabCard extends StatelessWidget {
  final VocabularyModel word;
  final List<String>? wordIds;
  const _VocabCard({required this.word, this.wordIds});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final lvCol = _levelColors[word.jlptLevel] ?? cs.primary;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/vocabulary/${word.id}', extra: wordIds),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              // Level badge
              Container(
                width: 38,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: lvCol.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: lvCol.withValues(alpha: 0.3)),
                ),
                child: Text(
                  word.jlptLevel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: lvCol, fontWeight: FontWeight.bold, fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Word info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            word.word,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (word.reading.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              cleanReading(word.reading),
                              style: TextStyle(fontSize: 12, color: cs.primary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      word.meaningZh,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((word.partOfSpeechRaw ?? word.partOfSpeech).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatPosRaw(word.partOfSpeechRaw ?? word.partOfSpeech),
                            style: TextStyle(fontSize: 10, color: cs.outline),
                          ),
                        ),
                      ),
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
