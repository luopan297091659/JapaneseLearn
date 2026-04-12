import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/local_db.dart';
import '../../utils/tts_helper.dart';

const _kLangPrefKey = 'dict_lang';

class DictionaryScreen extends StatefulWidget {
  final String? initialQuery;
  const DictionaryScreen({super.key, this.initialQuery});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<DictionaryEntry> _results = [];
  List<VocabularyModel> _vocabResults = [];
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  // 释义语言：'zh'=中文 / 'en'=英文
  String _lang = 'zh';

  // Recent search history (from local DB, with details)
  List<Map<String, dynamic>> _historyRecords = [];

  final FlutterTts _tts = FlutterTts();
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadLangPref();
    _initTts();
    _loadHistory();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchCtrl.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  Future<void> _loadHistory() async {
    try {
      final records = await localDb.getDictHistory(limit: 30);
      if (mounted) setState(() => _historyRecords = records);
    } catch (_) {}
  }

  Future<void> _initTts() async {
    await TtsHelper.configureForJapanese(_tts);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _playingId = null);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _playingId = null);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _playingId = null);
    });
  }

  void _playWord(String word, {String? id, String? audioUrl}) {
    setState(() => _playingId = id ?? word);
    TtsHelper.playJapaneseSmart(
      audioUrl: audioUrl,
      text: word,
      tts: _tts,
      onComplete: () {
        if (mounted) setState(() => _playingId = null);
      },
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLangPref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLangPrefKey) ?? 'zh';
    if (mounted) setState(() => _lang = saved);
  }

  Future<void> _setLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangPrefKey, lang);
    setState(() => _lang = lang);
    if (_hasSearched && _searchCtrl.text.trim().isNotEmpty) _search();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      if (!_loading && _hasMore) _loadMore();
    }
  }

  Future<void> _search({bool reset = true}) async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    if (reset) {
      _page = 1;
      _hasMore = true;
    }
    setState(() { _loading = true; _error = null; if (reset) { _results = []; _vocabResults = []; } });

    // 先返回本地缓存词库结果，减少首屏等待
    if (reset) {
      try {
        final localQuick = await localDb.searchCachedVocabularyQuick(query: q, limit: 8);
        if (!mounted) return;
        setState(() {
          _vocabResults = localQuick;
          _hasSearched = true;
        });
      } catch (_) {}
    }

    try {
      if (reset) {
        final dictFuture = apiService.searchDictionary(q, page: _page, lang: _lang);
        final vocabFuture = apiService
            .getVocabulary(query: q, page: 1, limit: 8)
            .catchError((_) => <String, dynamic>{'data': <VocabularyModel>[]});
        final responses = await Future.wait<dynamic>([dictFuture, vocabFuture]);
        final dictResult = responses[0] as DictionarySearchResult;
        final vocabRes = responses[1] as Map<String, dynamic>;
        final remoteVocab = (vocabRes['data'] as List<dynamic>? ?? const [])
            .whereType<VocabularyModel>()
            .toList();

        setState(() {
          _results = dictResult.data;
          if (remoteVocab.isNotEmpty) {
            _vocabResults = remoteVocab;
          }
          _hasMore = dictResult.data.length >= 20;
          _loading = false;
          _hasSearched = true;
        });
      } else {
        final result = await apiService.searchDictionary(q, page: _page, lang: _lang);
        setState(() {
          _results.addAll(result.data);
          _hasMore = result.data.length >= 20;
          _loading = false;
          _hasSearched = true;
        });
      }

      if (reset) {
        apiService.logActivity(activityType: 'dictionary', durationSeconds: 0);
        // 保存搜索历史（取第一个结果的详细信息）
        _saveDictHistory(q);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '查询失败，请检查网络连接';
        _hasSearched = true;
      });
    }
  }

  Future<void> _loadMore() async {
    _page++;
    await _search(reset: false);
  }

  void _saveDictHistory(String query) {
    // 从搜索结果中取第一个匹配项的详细信息
    String word = query, reading = '', pos = '', meaning = '', jlpt = '';
    if (_results.isNotEmpty) {
      final first = _results.first;
      word = first.displayWord;
      reading = first.displayReading;
      if (first.meanings.isNotEmpty) {
        final m = first.meanings.first;
        pos = m.partsOfSpeech.isNotEmpty ? m.partsOfSpeech.first : '';
        final defs = m.chineseDefinitions.isNotEmpty ? m.chineseDefinitions : m.englishDefinitions;
        meaning = defs.join('；');
      }
      jlpt = first.jlpt.isNotEmpty ? first.jlpt.first.toUpperCase().replaceAll('JLPT-', '') : '';
    } else if (_vocabResults.isNotEmpty) {
      final first = _vocabResults.first;
      word = first.word;
      reading = first.reading;
      pos = first.partOfSpeech;
      meaning = first.meaningZh;
      jlpt = first.jlptLevel;
    }
    localDb.insertDictHistory(word: word, reading: reading, pos: pos, meaning: meaning, jlpt: jlpt).then((_) => _loadHistory());
  }

  void _searchWord(String word) {
    _searchCtrl.text = word;
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日語辞書'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          // 语言切换按钮
          _LangToggle(lang: _lang, onChanged: _setLang),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: widget.initialQuery == null,
                  decoration: InputDecoration(
                    hintText: '輸入日語、中文或羅馬字...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() { _results = []; _vocabResults = []; _hasSearched = false; });
                            })
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _search,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(60, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('検索'),
              ),
            ]),
          ),
        ),
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    // Initial state: show history + quick search tips
    if (!_hasSearched && !_loading) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _QuickSearchBar(onSearch: _searchWord),
        if (_historyRecords.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Text('最近搜索', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await localDb.clearDictHistory();
                _loadHistory();
              },
              child: const Text('清空'),
            ),
          ]),
          ...(_historyRecords.map((r) => _DictHistoryTile(
            record: r,
            onTap: () => _searchWord(r['word'] as String),
            onDelete: () async {
              await localDb.deleteDictHistory(r['id'] as int);
              _loadHistory();
            },
          ))),
        ],
        const SizedBox(height: 24),
        const _SearchTipsCard(),
      ]);
    }

    if (_loading && _results.isEmpty && _vocabResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.signal_wifi_off_rounded, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: cs.outline)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _search, child: const Text('重試')),
        ]),
      );
    }

    if (_results.isEmpty && _vocabResults.isEmpty && _hasSearched) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off_rounded, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('未找到「${_searchCtrl.text}」的結果', style: TextStyle(color: cs.outline)),
          const SizedBox(height: 8),
          const Text('換個詞試試？'),
        ]),
      );
    }

    final vocabCount = _vocabResults.length;
    final totalCount = vocabCount + _results.length + (_loading || _hasMore ? 1 : 0);

    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: totalCount,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        // 系统词库结果优先展示
        if (i < vocabCount) {
          final vocab = _vocabResults[i];
          final id = 'vocab_$i';
          return _VocabResultCard(vocab: vocab, onWordTap: _searchWord, playingId: _playingId, itemId: id, onPlay: (word) => _playWord(word, id: id, audioUrl: vocab.audioUrl));
        }
        final dictIndex = i - vocabCount;
        if (dictIndex == _results.length) {
          return _loading
              ? const Padding(padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : const SizedBox.shrink();
        }
        final dictId = 'dict_$dictIndex';
        return _DictionaryEntryCard(
          entry: _results[dictIndex],
          lang: _lang,
          onWordTap: _searchWord,
          playingId: _playingId,
          itemId: dictId,
          onPlay: (word) => _playWord(word, id: dictId),
        );
      },
    );
  }
}

// ─── Quick search bar ──────────────────────────────────────────────────────
class _QuickSearchBar extends StatelessWidget {
  final void Function(String) onSearch;
  const _QuickSearchBar({required this.onSearch});

  static const _examples = ['食べる', '勉強', '日本語', '時間', '友達', '電車', '美しい'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('快速搜索示例', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 6,
          children: _examples.map((w) => InputChip(
            label: Text(w),
            onPressed: () => onSearch(w),
          )).toList(),
        ),
      ],
    );
  }
}

// ─── Search tips card ──────────────────────────────────────────────────────
class _SearchTipsCard extends StatelessWidget {
  const _SearchTipsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              const Text('搜索技巧', style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            ...[
              ('🔤 日語文字', '輸入漢字、假名（平假名/片假名）'),
              ('🌐 中文', '輸入中文含義搜索相關單詞'),
              ('🔠 羅馬字', '輸入 romaji，例如 taberu'),
              // ('#kanji 字', '搜索指定漢字的詳細信息'),
              // ('#jlpt-n5', '搜索指定 JLPT 等級單詞'),
            ].map((tip) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 90, child: Text(tip.$1, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
                  Expanded(child: Text(tip.$2, style: const TextStyle(fontSize: 13, color: Colors.grey))),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// ─── Language Toggle ──────────────────────────────────────────────────────
class _LangToggle extends StatelessWidget {
  final String lang;
  final ValueChanged<String> onChanged;
  const _LangToggle({required this.lang, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(lang == 'zh' ? 'en' : 'zh'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: lang == 'zh' ? cs.primaryContainer : cs.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: lang == 'zh' ? cs.primary : cs.secondary,
            width: 1.2,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            Icons.translate_rounded,
            size: 14,
            color: lang == 'zh' ? cs.primary : cs.secondary,
          ),
          const SizedBox(width: 4),
          Text(
            lang == 'zh' ? '中文' : 'EN',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: lang == 'zh' ? cs.primary : cs.secondary,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Dictionary Entry Card ─────────────────────────────────────────────────
class _DictionaryEntryCard extends StatefulWidget {
  final DictionaryEntry entry;
  final String lang;
  final String? playingId;
  final String itemId;
  final void Function(String) onPlay;
  final void Function(String) onWordTap;
  const _DictionaryEntryCard({required this.entry, required this.lang, required this.playingId, required this.itemId, required this.onPlay, required this.onWordTap});

  @override
  State<_DictionaryEntryCard> createState() => __DictionaryEntryCardState();
}

class __DictionaryEntryCardState extends State<_DictionaryEntryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entry = widget.entry;

    return Card(
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Word + badges
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            // Word (clickable for sub-search)
                            GestureDetector(
                              onLongPress: () {
                                Clipboard.setData(ClipboardData(text: entry.displayWord));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制到剪贴板'),
                                      behavior: SnackBarBehavior.floating, duration: Duration(seconds: 1)));
                              },
                              child: Text(
                                entry.displayWord,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Common badge
                            if (entry.isCommon)
                              const _Badge('常用', Colors.green),
                          ],
                        ),
                        // Reading
                        if (entry.displayReading.isNotEmpty &&
                            entry.displayReading != entry.displayWord)
                          GestureDetector(
                            onTap: () => widget.onWordTap(entry.displayReading),
                            child: Text(
                              entry.displayReading,
                              style: TextStyle(fontSize: 18, color: cs.primary, height: 1.4),
                            ),
                          ),
                        // JLPT badges
                        if (entry.jlpt.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            ...entry.jlpt.map((j) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _Badge(j.toUpperCase().replaceAll('JLPT-', ''), cs.primary),
                            )),
                            ...entry.tags.take(2).map((t) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _Badge(t, Colors.orange),
                            )),
                          ]),
                        ],
                      ],
                    ),
                  ),
                  // Voice button
                  _circleAudioBtn(
                    playing: widget.playingId == widget.itemId,
                    onTap: () => widget.onPlay(entry.displayWord),
                    cs: cs,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // ── First meaning (always visible) ─────────────────────────
              if (entry.meanings.isNotEmpty)
                _MeaningRow(meaning: entry.meanings[0], index: 0, showPos: true, lang: widget.lang),
              // ── Expand button ───────────────────────────────────────────
              if (entry.meanings.length > 1 || entry.japanese.length > 1)
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Text(
                        _expanded ? '收起' : '展開更多 (${entry.meanings.length} 個義項)',
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                          size: 16, color: cs.primary),
                    ]),
                  ),
                ),
              // ── Expanded content ────────────────────────────────────────
              if (_expanded) ...[
                const Divider(height: 16),
                // All meanings
                ...entry.meanings.asMap().entries.skip(1).map((e) =>
                    _MeaningRow(meaning: e.value, index: e.key, showPos: true, lang: widget.lang)),
                // All Japanese forms
                if (entry.japanese.length > 1) ...[
                  const SizedBox(height: 8),
                  Text('其他形式', style: TextStyle(fontWeight: FontWeight.bold, color: cs.outline, fontSize: 13)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: entry.japanese.skip(1).map((j) => ActionChip(
                      label: Text(j.word != null
                          ? '${j.word}【${j.reading ?? ''}】'
                          : j.reading ?? ''),
                      onPressed: () => widget.onWordTap(j.word ?? j.reading ?? ''),
                    )).toList(),
                  ),
                ],
                // Actions
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: entry.displayWord));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 1)));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (entry.url != null) ...[
                    const SizedBox(width: 8),

                  ],
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 系统词库结果卡片 ────────────────────────────────────────────────────────
class _VocabResultCard extends StatelessWidget {
  final VocabularyModel vocab;
  final String? playingId;
  final String itemId;
  final void Function(String) onPlay;
  final void Function(String) onWordTap;
  const _VocabResultCard({required this.vocab, required this.onWordTap, required this.playingId, required this.itemId, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onWordTap(vocab.word),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(vocab.word, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            _Badge('常用', Colors.green),
                            const SizedBox(width: 4),
                            if (vocab.jlptLevel.isNotEmpty)
                              _Badge(vocab.jlptLevel, cs.primary),
                          ],
                        ),
                        if (vocab.reading.isNotEmpty && vocab.reading != vocab.word)
                          Text(vocab.reading, style: TextStyle(fontSize: 18, color: cs.primary, height: 1.4)),
                      ],
                    ),
                  ),
                  _circleAudioBtn(
                    playing: playingId == itemId,
                    onTap: () => onPlay(vocab.word),
                    cs: cs,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(vocab.partOfSpeech,
                        style: TextStyle(fontSize: 12, color: cs.primary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(vocab.meaningZh, style: const TextStyle(fontSize: 15))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Meaning Row ──────────────────────────────────────────────────────────
class _MeaningRow extends StatelessWidget {
  final DictionaryMeaning meaning;
  final int index;
  final bool showPos;
  final String lang;
  const _MeaningRow({required this.meaning, required this.index, this.showPos = true, this.lang = 'zh'});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final defs = meaning.definitions(lang).toSet().toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Index circle
          Container(
            width: 20, height: 20,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // POS
                if (showPos && meaning.posZh.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(meaning.posZh,
                        style: TextStyle(fontSize: 11, color: cs.outline,
                            fontStyle: FontStyle.italic)),
                  ),
                // Definitions
                Text(defs.join(lang == 'zh' ? '；' : '; '), style: const TextStyle(fontSize: 15)),
                // Additional info
                if (meaning.info.isNotEmpty)
                  Text(meaning.info.join(', '),
                      style: TextStyle(fontSize: 11, color: cs.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Circular audio button (shared) ───────────────────────────────────────
Widget _circleAudioBtn({
  required bool playing,
  required VoidCallback onTap,
  required ColorScheme cs,
  double size = 24,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: size + 8,
      height: size + 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: playing ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
      ),
      child: Icon(
        playing ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded,
        color: cs.primary,
        size: size,
      ),
    ),
  );
}

// ─── Badge widget ─────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Dict History Tile ────────────────────────────────────────────────────
class _DictHistoryTile extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _DictHistoryTile({required this.record, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final word = record['word'] as String? ?? '';
    final reading = record['reading'] as String? ?? '';
    final pos = record['pos'] as String? ?? '';
    final meaning = record['meaning'] as String? ?? '';
    final jlpt = record['jlpt'] as String? ?? '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 4),
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(word, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      if (reading.isNotEmpty && reading != word) ...[
                        const SizedBox(width: 6),
                        Text(reading, style: TextStyle(fontSize: 13, color: cs.primary)),
                      ],
                      if (jlpt.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _Badge(jlpt, cs.primary),
                      ],
                    ]),
                    if (pos.isNotEmpty || meaning.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          if (pos.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(pos, style: TextStyle(fontSize: 10, color: cs.primary)),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              meaning,
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.close, size: 16, color: cs.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
