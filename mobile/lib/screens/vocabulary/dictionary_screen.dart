import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

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
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  // 释义语言：'zh'=中文 / 'en'=英文
  String _lang = 'zh';

  // Recent search history (in-memory)
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadLangPref();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchCtrl.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
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
    setState(() { _loading = true; _error = null; if (reset) _results = []; });

    // Add to history
    if (!_history.contains(q)) {
      _history.insert(0, q);
      if (_history.length > 20) _history.removeLast();
    }

    try {
      final result = await apiService.searchDictionary(q, page: _page, lang: _lang);
      setState(() {
        if (reset) {
          _results = result.data;
        } else {
          _results.addAll(result.data);
        }
        _hasMore = result.data.length >= 20;
        _loading = false;
        _hasSearched = true;
      });
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
                              setState(() { _results = []; _hasSearched = false; });
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
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Text('最近搜索', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _history.clear()),
              child: const Text('清空'),
            ),
          ]),
          Wrap(
            spacing: 8, runSpacing: 4,
            children: _history.map((h) => ActionChip(
              label: Text(h),
              onPressed: () => _searchWord(h),
            )).toList(),
          ),
        ],
        const SizedBox(height: 24),
        const _SearchTipsCard(),
      ]);
    }

    if (_loading && _results.isEmpty) {
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

    if (_results.isEmpty && _hasSearched) {
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

    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: _results.length + (_loading || _hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == _results.length) {
          return _loading
              ? const Padding(padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : const SizedBox.shrink();
        }
        return _DictionaryEntryCard(
          entry: _results[i],
          lang: _lang,
          onWordTap: _searchWord,
        );
      },
    );
  }
}

// ─── Quick search bar ──────────────────────────────────────────────────────
class _QuickSearchBar extends StatelessWidget {
  final void Function(String) onSearch;
  const _QuickSearchBar({required this.onSearch});

  static const _examples = ['食べる', '勉強する', '日本語', 'N5', '時間', '友達', '電車', '美しい'];

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
              ('#kanji 字', '搜索指定漢字的詳細信息'),
              ('#jlpt-n5', '搜索指定 JLPT 等級單詞'),
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
  final void Function(String) onWordTap;
  const _DictionaryEntryCard({required this.entry, required this.lang, required this.onWordTap});

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
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
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
                  // Jisho link icon
                  Icon(Icons.open_in_new, size: 16, color: cs.outline),
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
                    GestureDetector(
                      onTap: () => widget.onWordTap(entry.displayWord),
                      child: Text('via Jisho ⇗',
                          style: TextStyle(fontSize: 11, color: cs.primary,
                              decoration: TextDecoration.underline)),
                    ),
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
    final defs = meaning.definitions(lang);

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
