import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../utils/tts_helper.dart';

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
  int _reviewed = 0;
  int _correct = 0;
  final _startTime = DateTime.now();

  // ── 音频播放 ────────────────────────────────────────────────────
  FlutterTts? _tts;
  bool _wordPlaying = false;
  bool _wordLoading = false;

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

  /// 朗读单词
  Future<void> _speakWord(String text, {bool slow = false}) async {
    if (!mounted) return;
    setState(() => _wordLoading = true);
    try {
      final tts = await _getOrInitTts();
      await tts.stop();
      final rate = slow ? 0.25 : 0.45;
      await tts.setSpeechRate(rate);
      if (mounted) setState(() { _wordLoading = false; _wordPlaying = true; });
      tts.setCompletionHandler(() {
        if (mounted) setState(() => _wordPlaying = false);
      });
      await TtsHelper.speakJapanese(tts, text);
    } catch (e) {
      if (mounted) setState(() => _wordLoading = false);
    }
  }

  Future<void> _loadCards() async {
    try {
      final res = await apiService.getDueCards(limit: 200);
      final cards = res['cards'] as List<SrsCardModel>;
      // Fetch missing content for cards without it
      final enriched = <SrsCardModel>[];
      for (final card in cards) {
        if (card.content != null) {
          enriched.add(card);
          continue;
        }
        try {
          dynamic content;
          if (card.cardType == 'vocabulary') {
            content = await apiService.getVocabularyById(card.refId);
          } else if (card.cardType == 'grammar') {
            content = await apiService.getGrammarLesson(card.refId);
          }
          enriched.add(SrsCardModel(
            id: card.id,
            cardType: card.cardType,
            refId: card.refId,
            repetitions: card.repetitions,
            easeFactor: card.easeFactor,
            intervalDays: card.intervalDays,
            dueDate: card.dueDate,
            isGraduated: card.isGraduated,
            content: content,
          ));
        } catch (_) {
          enriched.add(card);
        }
      }
      setState(() { _cards = enriched; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('加载复习卡片失败，请检查网络'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
              if (!_wordLoading && !_wordPlaying)
                IconButton(
                  icon: Icon(Icons.volume_up_rounded, color: cs.primary, size: 28),
                  onPressed: () => _speakWord(vocab.word),
                  tooltip: '朗读单词',
                )
              else if (_wordLoading)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(cs.primary),
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: Icon(Icons.volume_down_rounded, color: cs.primary, size: 28),
                  onPressed: () async => await _tts?.stop(),
                  tooltip: '停止播放',
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
                    Text(vocab.exampleSentence!, textAlign: TextAlign.start, style: const TextStyle(fontSize: 16, height: 1.6)),
                    if (vocab.exampleMeaningZh != null) ...[
                      const SizedBox(height: 4),
                      Text(vocab.exampleMeaningZh!, style: TextStyle(color: cs.outline, fontSize: 14)),
                    ],
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
