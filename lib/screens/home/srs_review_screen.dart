import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../utils/tts_helper.dart';
import '../../widgets/whiteboard_widget.dart';

class SrsReviewScreen extends StatefulWidget {
  final String from;

  const SrsReviewScreen({super.key, this.from = 'home'});
  @override
  State<SrsReviewScreen> createState() => _SrsReviewScreenState();
}

class _SrsReviewScreenState extends State<SrsReviewScreen> {
  List<SrsCardModel> _cards = [];
  int _current = 0;
  bool _showAnswer = false;
  bool _loading = true;
  bool _loadError = false;
  int _reviewed = 0;
  int _correct = 0;
  final _startTime = DateTime.now();

  // ── 音频播放 ────────────────────────────────────────────────────
  FlutterTts? _tts;
  bool _wordPlaying = false;
  bool _wordLoading = false;
  bool _examplePlaying = false;
  bool _exampleLoading = false;

  String get _backTarget {
    switch (widget.from) {
      case 'study':
        return '/study';
      case 'test':
        return '/test';
      case 'tools':
        return '/tools';
      default:
        return '/home';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void dispose() {
    _tts?.stop();
    super.dispose();
  }

  /// 获取或初始化 TTS 实例
  Future<FlutterTts> _getOrInitTts() async {
    if (_tts == null) {
      _tts = FlutterTts();
      await TtsHelper.configureForJapanese(_tts!);
    }
    return _tts!;
  }

  /// 朗读单词：系统音频优先，TTS兜底
  Future<void> _speakWord(String text, {String? audioUrl, bool slow = false}) async {
    if (!mounted) return;
    setState(() => _wordLoading = true);
    try {
      final tts = await _getOrInitTts();
      await tts.stop();
      if (mounted) setState(() { _wordLoading = false; _wordPlaying = true; });
      await TtsHelper.playJapaneseSmart(
        audioUrl: audioUrl,
        text: text,
        tts: tts,
        slow: slow,
        onComplete: () {
          if (mounted) setState(() => _wordPlaying = false);
        },
      );
    } catch (e) {
      if (mounted) setState(() { _wordLoading = false; _wordPlaying = false; });
    }
  }

  /// 朗读例句
  Future<void> _speakExample(String text, {String? audioUrl}) async {
    if (!mounted) return;
    setState(() => _exampleLoading = true);
    try {
      final tts = await _getOrInitTts();
      await tts.stop();
      if (mounted) setState(() { _exampleLoading = false; _examplePlaying = true; });
      await TtsHelper.playJapaneseSmart(
        audioUrl: audioUrl,
        text: text,
        tts: tts,
        onComplete: () {
          if (mounted) setState(() => _examplePlaying = false);
        },
      );
    } catch (e) {
      if (mounted) setState(() { _exampleLoading = false; _examplePlaying = false; });
    }
  }

  Future<void> _loadCards() async {
    try {
      final res = await apiService.getDueCards(limit: 200);
      final cards = res['cards'] as List<SrsCardModel>;
      // Backend now filters orphaned cards; just use cards with content
      final enriched = cards.where((c) => c.content != null).toList();
      setState(() { _cards = enriched; _loading = false; });
      // 后台预缓存所有词汇卡音频
      final audioUrls = enriched
          .where((c) => c.content is VocabularyModel)
          .map((c) => (c.content as VocabularyModel).audioUrl)
          .where((u) => u != null && u.isNotEmpty)
          .cast<String>();
      TtsHelper.precacheAudioUrls(audioUrls);
    } catch (_) {
      setState(() { _loading = false; _loadError = true; });
    }
  }

  Future<void> _submitReview(int quality) async {
    final card = _cards[_current];
    if (quality >= 3) _correct++;
    _reviewed++;
    try {
      await apiService.submitSrsReview(card.id, quality);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('复习数据保存失败，请检查网络'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
    if (mounted) {
      final label = quality == 0 ? '重来' : quality <= 3 ? '困难' : quality == 4 ? '良好' : '简单';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已标记为「$label」，已更新复习计划'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          duration: const Duration(seconds: 1),
        ),
      );
    }
    if (_current + 1 >= _cards.length) {
      _finishSession();
    } else {
      setState(() { _current++; _showAnswer = false; });
    }
  }

  // ─── SM-2 间隔预算（与后端保持一致） ──────────────────────────────
  int _calcNextInterval(int quality) {
    final card = _cards[_current];
    if (quality < 3) return 0;
    double ease = (card.easeFactor + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
        .clamp(1.3, 4.0);
    if (card.repetitions == 0) return 1;
    if (card.repetitions == 1) return 6;
    return (card.intervalDays * ease).round().clamp(1, 36500);
  }

  static String _fmtDays(int days) {
    if (days == 0) return '<10分';
    if (days < 30) return '$days天';
    if (days < 365) return '${(days / 30).round()}月';
    return '${(days / 365).round()}年';
  }

  List<({String label, Color color, String interval, int quality})> _buildSrsIntervals() => [
    (label: '重来', color: Colors.red.shade400,    interval: '<10分',                         quality: 0),
    (label: '困难', color: Colors.orange.shade400, interval: _fmtDays(_calcNextInterval(3)),  quality: 3),
    (label: '良好', color: Colors.blue.shade400,   interval: _fmtDays(_calcNextInterval(4)),  quality: 4),
    (label: '简单', color: Colors.green.shade400,  interval: _fmtDays(_calcNextInterval(5)),  quality: 5),
  ];

  void _finishSession() {
    final duration = DateTime.now().difference(_startTime).inSeconds;
    apiService.logActivity(
      activityType: 'srs_review',
      durationSeconds: duration,
      score: _reviewed > 0 ? (_correct / _reviewed * 100) : 0,
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('复习完成！'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('共复习 $_reviewed 张卡片', style: const TextStyle(fontSize: 16)),
          Text('正确率 ${_reviewed > 0 ? (_correct / _reviewed * 100).round() : 0}%',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
        ]),
        actions: [FilledButton(
          onPressed: () { 
            Navigator.pop(dialogContext);
            if (mounted) context.go(_backTarget); 
          }, 
          child: const Text('返回')
        )],
      ),
    );
  }

  void _showWhiteboard(ColorScheme cs, {VocabularyModel? vocab, GrammarLessonModel? grammar}) {
    final refChar = vocab?.word ?? grammar?.pattern;
    final title = vocab?.word ?? grammar?.pattern ?? '';
    final subtitle = vocab != null ? vocab.reading : (grammar?.titleZh ?? grammar?.title ?? '');
    final meaning = vocab?.meaningZh ?? grammar?.explanationZh ?? grammar?.explanation ?? '';
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(ctx),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w400)),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              if (meaning.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(meaning, style: TextStyle(fontSize: 14, color: cs.onPrimaryContainer), textAlign: TextAlign.center),
                ),
              Expanded(child: WhiteboardWidget(referenceChar: refChar)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmResetSrs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除所有SRS记录'),
        content: const Text('将删除你的所有间隔复习卡片和进度，此操作不可撤销。\n\n确定要清除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await apiService.resetSrsCards();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 $count 条SRS记录'), behavior: SnackBarBehavior.floating),
        );
        setState(() { _cards = []; _loading = false; _loadError = false; });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('清除失败，请检查网络'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_loadError) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('间隔复习'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            tooltip: '返回',
            onPressed: () => context.go(_backTarget),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: '清除SRS记录',
              onPressed: _confirmResetSrs,
            ),
          ],
        ),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.cloud_off_rounded, color: cs.error, size: 64),
            const SizedBox(height: 16),
            const Text('加载复习卡片失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('请检查网络连接后重试', style: TextStyle(color: cs.outline)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() { _loading = true; _loadError = false; });
                _loadCards();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ]),
        ),
      );
    }
    if (_cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('间隔复习'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            tooltip: '返回',
            onPressed: () => context.go(_backTarget),
          ),
        ),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            const Text('今日复习已完成！', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('明日再来继续学习'),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.go(_backTarget), child: const Text('返回')),
          ]),
        ),
      );
    }

    final card = _cards[_current];
    final vocab = card.content is VocabularyModel ? card.content as VocabularyModel : null;
    final grammar = card.content is GrammarLessonModel ? card.content as GrammarLessonModel : null;
    final hasContent = vocab != null || grammar != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('复习 ${_current + 1}/${_cards.length}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.go(_backTarget),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.draw_rounded),
            tooltip: '白板',
            onPressed: () => _showWhiteboard(cs, vocab: vocab, grammar: grammar),
          ),
          PopupMenuButton<String>(
            onSelected: (v) { if (v == 'reset') _confirmResetSrs(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'reset', child: Text('清除所有SRS记录')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_current + 1) / _cards.length),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Card(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: !hasContent
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 48, color: cs.outline),
                            const SizedBox(height: 12),
                            Text('内容不可用', style: TextStyle(fontSize: 18, color: cs.outline)),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () => _submitReview(3),
                              child: const Text('跳过此卡'),
                            ),
                          ],
                        )
                      : vocab != null
                          ? _buildVocabContent(vocab, cs)
                          : _buildGrammarContent(grammar!, cs),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (hasContent) ...[
              if (!_showAnswer) ...[
                FilledButton.icon(
                  onPressed: () => setState(() => _showAnswer = true),
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('显示答案'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ] else ...[
                const Text('你记住了吗？', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Row(children: _buildSrsIntervals().map((item) => Expanded(
                    child: GestureDetector(
                      onTap: () => _submitReview(item.quality),
                      child: Container(
                        color: item.color,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.interval, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(item.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ),
                    ),
                  )).toList()),
                ),
              ],
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildVocabContent(VocabularyModel vocab, ColorScheme cs) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── 单词 + 发音按钮 ───────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(vocab.word, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _wordLoading ? null : () => _speakWord(vocab.word, audioUrl: vocab.audioUrl),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _wordPlaying ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
                  ),
                  child: _wordLoading
                      ? Center(child: SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                        ))
                      : Icon(
                          _wordPlaying ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded,
                          color: cs.primary,
                          size: 28,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showAnswer) ...[
            // ── 假名 ──────────────────────────────────────────────────
            Text(vocab.reading, style: TextStyle(fontSize: 22, color: cs.primary, fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            
            // ── 释义 ──────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.translate_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 6),
                    Text('释义', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurfaceVariant)),
                  ]),
                  const SizedBox(height: 8),
                  Text(vocab.meaningZh, style: const TextStyle(fontSize: 18, height: 1.6)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 例文 ──────────────────────────────────────────────────
            if (vocab.exampleSentence != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.format_quote_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Text('例文', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(vocab.exampleSentence!, textAlign: TextAlign.start, style: const TextStyle(fontSize: 16, height: 1.6)),
                              if (vocab.exampleMeaningZh != null) ...[
                                const SizedBox(height: 4),
                                Text(vocab.exampleMeaningZh!, style: TextStyle(color: cs.outline, fontSize: 14)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: GestureDetector(
                            onTap: _exampleLoading ? null : () => _speakExample(vocab.exampleSentence!, audioUrl: vocab.exampleAudioUrl),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _examplePlaying ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
                              ),
                              child: _exampleLoading
                                  ? Center(child: SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                    ))
                                  : Icon(
                                      _examplePlaying ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded,
                                      color: cs.primary,
                                      size: 24,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ] else ...[
            const SizedBox(height: 12),
            Text('点击"显示答案"查看释义和例文', style: TextStyle(color: cs.outline, fontSize: 16)),
          ],
        ],
      ),
    );
  }

  Widget _buildGrammarContent(GrammarLessonModel grammar, ColorScheme cs) {
    final title = (grammar.titleZh ?? grammar.title).trim();
    return SingleChildScrollView(
      child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(grammar.pattern, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_showAnswer) ...[
          if (title.isNotEmpty)
            Text(title, style: TextStyle(fontSize: 18, color: cs.primary)),
          const SizedBox(height: 8),
          Text(grammar.explanationZh ?? grammar.explanation ?? '',
              style: const TextStyle(fontSize: 15, height: 1.5), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (grammar.examples.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(grammar.examples.first.sentence, textAlign: TextAlign.center),
                  Text(grammar.examples.first.meaningZh,
                      style: TextStyle(color: cs.outline, fontSize: 12)),
                ],
              ),
            ),
        ] else ...[
          const SizedBox(height: 8),
          Text('点击"显示答案"查看释义', style: TextStyle(color: cs.outline)),
        ],
      ],
      ),
    );
  }
}

// _QualityButton 已替换为内联 Anki 风格评分栏
