import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:dio/dio.dart';
import '../../utils/tts_helper.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

class NhkDetailScreen extends StatefulWidget {
  final String newsId;
  final NewsArticleModel? article;
  const NhkDetailScreen({super.key, required this.newsId, this.article});
  @override
  State<NhkDetailScreen> createState() => _NhkDetailScreenState();
}

class _NhkDetailScreenState extends State<NhkDetailScreen> {
  String _body = '';
  bool _loading = true;
  bool _showRuby = true;
  double _fontSize = 18;
  bool _isFav = false;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
    _load();
    _checkFav();
  }

  Future<void> _initTts() async {
    _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
    await TtsHelper.configureForJapanese(_tts);
    await _tts.setSpeechRate(0.4);
  }

  @override
  void dispose() { _tts.stop(); super.dispose(); }

  Future<void> _load() async {
    try {
      final body = await apiService.getNhkArticleBody(widget.newsId);
      setState(() { _body = body; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _checkFav() async {
    try {
      final fav = await apiService.checkNewsFavorite('nhk', widget.newsId);
      setState(() => _isFav = fav);
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    try {
      if (_isFav) {
        await apiService.removeNewsFavorite('nhk', widget.newsId);
        setState(() => _isFav = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)));
      } else {
        final title = widget.article?.title ?? _plainText(_body);
        await apiService.addNewsFavorite(
          newsType: 'nhk', newsId: widget.newsId,
          title: title.isNotEmpty ? title : 'NHK Easy News',
          description: widget.article?.body ?? _plainText(_body),
          source: 'NHK', publishedAt: widget.article?.publishedAt,
        );
        setState(() => _isFav = true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已收藏'), duration: Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  // 从 HTML 中提取纯文本，保留 ruby 标注
  List<InlineSpan> _parseHtml(String html) {
    final spans = <InlineSpan>[];
    final rubyReg = RegExp(r'<ruby[^>]*>(.*?)<rt>(.*?)</rt>.*?</ruby>', dotAll: true);
    final tagReg = RegExp(r'<[^>]+>');
    
    int lastEnd = 0;
    for (final match in rubyReg.allMatches(html)) {
      if (match.start > lastEnd) {
        final plain = html.substring(lastEnd, match.start).replaceAll(tagReg, '').replaceAll('&nbsp;', ' ');
        if (plain.isNotEmpty) spans.add(TextSpan(text: plain));
      }
      final kanji = match.group(1)!.replaceAll(tagReg, '');
      final reading = match.group(2)!.replaceAll(tagReg, '');
      if (_showRuby) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _RubyText(kanji: kanji, reading: reading, fontSize: _fontSize),
        ));
      } else {
        spans.add(TextSpan(text: kanji));
      }
      lastEnd = match.end;
    }
    if (lastEnd < html.length) {
      final plain = html.substring(lastEnd).replaceAll(tagReg, '').replaceAll('&nbsp;', ' ');
      if (plain.isNotEmpty) spans.add(TextSpan(text: plain));
    }
    return spans;
  }

  String _plainText(String html) {
    return html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
  }

  /// 将 HTML 正文按 <p> 段落拆分
  List<String> _splitParagraphs(String html) {
    final pReg = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true);
    final matches = pReg.allMatches(html);
    if (matches.isEmpty) return [html];
    return matches.map((m) => m.group(1) ?? '').where((p) {
      final t = p.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      return t.isNotEmpty && t.length > 3;
    }).toList();
  }

  /// 长按段落触发 AI 分析
  void _onParagraphTap(String paragraphHtml) {
    final sentence = _plainText(paragraphHtml);
    if (sentence.isEmpty) return;
    _showAnalysisSheet(sentence);
  }

  void _showAnalysisSheet(String sentence) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiAnalysisSheet(sentence: sentence, tts: _tts),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.article?.title ?? 'NHK Easy News';
    return Scaffold(
      appBar: AppBar(
        title: const Text('NHK Easy News'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/news'),
        ),
        actions: [
          IconButton(
            icon: Icon(_isFav ? Icons.star_rounded : Icons.star_border_rounded, size: 20),
            tooltip: _isFav ? '取消收藏' : '收藏',
            color: _isFav ? Colors.amber : null,
            onPressed: _toggleFav,
          ),
          IconButton(
            icon: Icon(_showRuby ? Icons.text_fields : Icons.translate, size: 20),
            tooltip: _showRuby ? '隐藏读音' : '显示读音',
            onPressed: () => setState(() => _showRuby = !_showRuby),
          ),
          IconButton(
            icon: const Icon(Icons.volume_up, size: 20),
            tooltip: '朗读',
            onPressed: () async {
              final text = _plainText(_body);
              if (text.isEmpty) return;
              try {
                try { await _tts.setLanguage('ja-JP'); } catch (_) {}
                await _tts.setVolume(1.0);
                final result = await _tts.speak(text.substring(0, text.length.clamp(0, 500)));
                if (result != 1 && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('语音引擎不可用，请检查系统TTS设置'), duration: Duration(seconds: 3)),
                  );
                }
              } catch (e) {
                debugPrint('TTS speak error: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('朗读出错：$e'), duration: const Duration(seconds: 3)),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _body.isEmpty
              ? const Center(child: Text('文章加载失败'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 图片
                    if (widget.article?.imageUrl != null && widget.article!.imageUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(widget.article!.imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox()),
                      ),
                    const SizedBox(height: 12),
                    // 来源 + 日期
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('NHK Easy', style: TextStyle(fontSize: 12, color: Color(0xFF0077B6), fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatDate(widget.article?.publishedAt), style: TextStyle(fontSize: 12, color: cs.outline)),
                    ]),
                    const SizedBox(height: 10),
                    // 标题
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4)),
                    const SizedBox(height: 16),
                    // 字号调节
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('字号', style: TextStyle(fontSize: 12, color: cs.outline)),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.text_decrease, size: 18),
                          onPressed: () => setState(() => _fontSize = (_fontSize - 2).clamp(14, 28)),
                          visualDensity: VisualDensity.compact,
                        ),
                        Text('${_fontSize.toInt()}', style: TextStyle(fontSize: 13, color: cs.outline)),
                        IconButton(
                          icon: const Icon(Icons.text_increase, size: 18),
                          onPressed: () => setState(() => _fontSize = (_fontSize + 2).clamp(14, 28)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    // AI 分析提示
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app, size: 14, color: cs.outline),
                          const SizedBox(width: 4),
                          Text('点击段落可进行AI分析', style: TextStyle(fontSize: 11, color: cs.outline, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    // 正文（按段落渲染，支持点击分析）
                    ..._splitParagraphs(_body).map((pHtml) => GestureDetector(
                      onTap: () => _onParagraphTap(pHtml),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.transparent,
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: _fontSize, height: 2.0, color: cs.onSurface),
                            children: _parseHtml(pHtml),
                          ),
                        ),
                      ),
                    )),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  String _formatDate(String? dt) {
    if (dt == null) return '';
    try {
      final d = DateTime.parse(dt);
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) { return dt.length > 10 ? dt.substring(0, 10) : dt; }
  }
}

// ── Ruby 注音组件 ──────────────────────────────────────────────────────────────
class _RubyText extends StatelessWidget {
  final String kanji;
  final String reading;
  final double fontSize;
  const _RubyText({required this.kanji, required this.reading, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(reading, style: TextStyle(fontSize: fontSize * 0.45, color: cs.primary, height: 1.0)),
        Text(kanji, style: TextStyle(fontSize: fontSize, height: 1.0)),
      ],
    );
  }
}

// ── AI 分析 Bottom Sheet ───────────────────────────────────────────────────────
class _AiAnalysisSheet extends StatefulWidget {
  final String sentence;
  final FlutterTts tts;
  const _AiAnalysisSheet({required this.sentence, required this.tts});
  @override
  State<_AiAnalysisSheet> createState() => _AiAnalysisSheetState();
}

class _AiAnalysisSheetState extends State<_AiAnalysisSheet> {
  String _translation = '';
  List<Map<String, dynamic>> _tokens = [];
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _wordDetail;
  bool _wordLoading = false;
  int _selectedTokenIdx = -1;

  @override
  void initState() {
    super.initState();
    _fetchAiData();
  }

  Future<void> _fetchAiData() async {
    try {
      final results = await Future.wait([
        apiService.aiTranslate(widget.sentence),
        apiService.aiAnalyze(widget.sentence),
      ]);
      if (mounted) {
        setState(() {
          _translation = results[0] as String;
          _tokens = results[1] as List<Map<String, dynamic>>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String msg = 'AI 分析失败';
        if (e is DioException && e.response?.data is Map) {
          msg = (e.response?.data as Map)['error']?.toString() ?? msg;
        }
        setState(() { _loading = false; _error = msg; });
      }
    }
  }

  Future<void> _fetchWordDetail(int idx) async {
    final token = _tokens[idx];
    if (_selectedTokenIdx == idx) {
      setState(() { _selectedTokenIdx = -1; _wordDetail = null; });
      return;
    }
    setState(() { _selectedTokenIdx = idx; _wordLoading = true; _wordDetail = null; });
    try {
      final detail = await apiService.aiWordDetail(
        token['word'] ?? '',
        pos: token['pos'],
        sentence: widget.sentence,
      );
      if (mounted) setState(() => _wordDetail = detail);
    } catch (_) {}
    if (mounted) setState(() => _wordLoading = false);
  }

  void _speak(String text) async {
    if (text.isEmpty) return;
    try { await widget.tts.speak(text.substring(0, text.length.clamp(0, 500))); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.auto_fix_high, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('AI 句子分析', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.primary)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.volume_up, size: 20), onPressed: () => _speak(widget.sentence), tooltip: '朗读'),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.sentence));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
                    },
                    tooltip: '复制原文',
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [CircularProgressIndicator(), SizedBox(height: 12), Text('AI 正在分析...')],
                    ))
                  : _error.isNotEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.error_outline, size: 48, color: cs.error),
                        const SizedBox(height: 12),
                        Text(_error, style: TextStyle(color: cs.error, fontSize: 15), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () { setState(() { _loading = true; _error = ''; }); _fetchAiData(); },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('重试'),
                        ),
                      ]),
                    ))
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        // 原文
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(widget.sentence, style: const TextStyle(fontSize: 16, height: 1.8)),
                        ),
                        const SizedBox(height: 12),
                        // 翻译
                        if (_translation.isNotEmpty) ...[
                          Row(children: [
                            Icon(Icons.translate, size: 16, color: cs.primary),
                            const SizedBox(width: 6),
                            Text('翻译', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary)),
                          ]),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SelectableText(_translation, style: const TextStyle(fontSize: 15, height: 1.6)),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // 词法分析
                        if (_tokens.isNotEmpty) ...[
                          Row(children: [
                            Icon(Icons.auto_fix_high, size: 16, color: cs.primary),
                            const SizedBox(width: 6),
                            Text('词法分析', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary)),
                            const SizedBox(width: 8),
                            Text('(点击单词查看详解)', style: TextStyle(fontSize: 11, color: cs.outline)),
                          ]),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 8,
                              children: List.generate(_tokens.length, (i) {
                                final t = _tokens[i];
                                if (t['word'] == '\n') return const SizedBox(width: double.infinity, height: 4);
                                final isSelected = i == _selectedTokenIdx;
                                final color = _posColor(t['pos'] ?? '');
                                return GestureDetector(
                                  onTap: () => _fetchWordDetail(i),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected ? color.withValues(alpha: 0.25) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border(bottom: BorderSide(color: color, width: 2.5)),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (t['furigana'] != null && t['furigana'].toString().isNotEmpty && t['furigana'] != t['word'])
                                          Text(t['furigana'], style: TextStyle(fontSize: 10, color: cs.primary, height: 1.0)),
                                        Text(t['word'] ?? '', style: const TextStyle(fontSize: 16, height: 1.3)),
                                        if (t['meaning'] != null && t['meaning'].toString().isNotEmpty)
                                          Text(t['meaning'], style: TextStyle(fontSize: 9, color: cs.outline, height: 1.2)),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildPosLegend(cs),
                        ],
                        if (_wordLoading) ...[
                          const SizedBox(height: 16),
                          const Center(child: CircularProgressIndicator()),
                        ],
                        if (_wordDetail != null && !_wordLoading) ...[
                          const SizedBox(height: 16),
                          _buildWordDetailCard(cs, _wordDetail!),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosLegend(ColorScheme cs) {
    const items = [
      ('名詞', '名词'), ('動詞', '动词'), ('形容詞', '形容词'),
      ('副詞', '副词'), ('助詞', '助词'), ('助動詞', '助动词'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: items.map((e) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: _posColor(e.$1), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(e.$2, style: TextStyle(fontSize: 11, color: cs.outline)),
        ],
      )).toList(),
    );
  }

  Widget _buildWordDetailCard(ColorScheme cs, Map<String, dynamic> d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('词汇详解', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.primary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.volume_up, size: 18),
              onPressed: () => _speak(d['word'] ?? ''),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Text(d['word'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            if (d['furigana'] != null && d['furigana'].toString().isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('【${d['furigana']}】', style: TextStyle(fontSize: 14, color: cs.primary)),
            ],
          ]),
          if (d['romaji'] != null && d['romaji'].toString().isNotEmpty)
            Text(d['romaji'], style: TextStyle(fontSize: 12, color: cs.outline)),
          const SizedBox(height: 6),
          if (d['dictionaryForm'] != null && d['dictionaryForm'] != d['word'])
            _detailRow('辞书形', d['dictionaryForm']),
          if (d['pos'] != null)
            Wrap(children: [
              const Text('词性  ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _posColor(d['pos']).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(d['pos'], style: TextStyle(fontSize: 13, color: _posColor(d['pos']), fontWeight: FontWeight.w600)),
              ),
            ]),
          const SizedBox(height: 4),
          _detailRow('释义', d['meaning'] ?? ''),
          if (d['explanation'] != null) ...[
            const Divider(height: 16),
            Text(d['explanation'], style: TextStyle(fontSize: 13, height: 1.7, color: cs.onSurface)),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label  ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  static Color _posColor(String pos) {
    final p = pos.split('-').first;
    switch (p) {
      case '名詞': return const Color(0xFF2196F3);
      case '動詞': return const Color(0xFFE53935);
      case '形容詞': return const Color(0xFFFF9800);
      case '形容動詞': return const Color(0xFFFF9800);
      case '副詞': return const Color(0xFF9C27B0);
      case '助詞': return const Color(0xFF4CAF50);
      case '助動詞': return const Color(0xFF00BCD4);
      case '接続詞': return const Color(0xFF795548);
      case '連体詞': return const Color(0xFF607D8B);
      case '感動詞': return const Color(0xFFE91E63);
      case '記号': return const Color(0xFF9E9E9E);
      default: return const Color(0xFF757575);
    }
  }
}
