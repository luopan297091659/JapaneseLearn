import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../utils/japanese_text_utils.dart';
import '../../utils/tts_helper.dart';
import '../../utils/verb_conjugation.dart';
import '../../utils/audio_manager.dart';
import '../../widgets/furigana_text.dart';
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
  final bool _showAnswer = true;
  bool _loading = true;
  bool _loadError = false;
  bool _submitting = false;
  int _reviewed = 0;
  int _correct = 0;
  double _dragOffset = 0;
  final _startTime = DateTime.now();

  // ── 音频播放 ────────────────────────────────────────────────────
  FlutterTts? _tts;
  bool _wordPlaying = false;
  bool _wordLoading = false;
  bool _examplePlaying = false;
  bool _exampleLoading = false;

  SrsCardModel? get _currentCard =>
      _current >= 0 && _current < _cards.length ? _cards[_current] : null;

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
    AudioManager.instance.stopAll();
    _tts?.stop();
    super.dispose();
  }

  void _autoPlayCurrentCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final card = _currentCard;
      if (card == null) return;
      final content = card.content;
      if (content is VocabularyModel) {
        _speakWord(content.word, audioUrl: content.audioUrl);
      } else if (content is GrammarLessonModel) {
        _speakWord(content.pattern);
      }
    });
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
  Future<void> _speakWord(String text,
      {String? audioUrl, bool slow = false}) async {
    if (!mounted) return;
    setState(() => _wordLoading = true);
    try {
      final tts = await _getOrInitTts();
      await tts.stop();
      if (mounted) {
        setState(() {
          _wordLoading = false;
          _wordPlaying = true;
        });
      }
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
      if (mounted) {
        setState(() {
          _wordLoading = false;
          _wordPlaying = false;
        });
      }
    }
  }

  /// 朗读例句
  Future<void> _speakExample(String text,
      {String? audioUrl, bool slow = false}) async {
    if (!mounted) return;
    setState(() => _exampleLoading = true);
    try {
      final tts = await _getOrInitTts();
      await tts.stop();
      if (mounted) {
        setState(() {
          _exampleLoading = false;
          _examplePlaying = true;
        });
      }
      await TtsHelper.playJapaneseSmart(
        audioUrl: audioUrl,
        text: text,
        tts: tts,
        slow: slow,
        onComplete: () {
          if (mounted) setState(() => _examplePlaying = false);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _exampleLoading = false;
          _examplePlaying = false;
        });
      }
    }
  }

  Future<void> _loadCards() async {
    try {
      final res = await apiService.getDueCards(limit: 200);
      final cards = res['cards'] as List<SrsCardModel>;
      // Backend now filters orphaned cards; just use cards with content
      final enriched = cards.where((c) => c.content != null).toList();
      setState(() {
        _cards = enriched;
        _loading = false;
      });
      _autoPlayCurrentCard();
      // 后台预缓存所有词汇卡音频
      final audioUrls = enriched
          .where((c) => c.content is VocabularyModel)
          .map((c) => (c.content as VocabularyModel).audioUrl)
          .where((u) => u != null && u.isNotEmpty)
          .cast<String>();
      TtsHelper.precacheAudioUrls(audioUrls);
    } catch (_) {
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _submitReview(int quality) async {
    if (_submitting || _current >= _cards.length) return;
    setState(() => _submitting = true);
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
    if (!mounted) return;
    final isLast = _current + 1 >= _cards.length;
    setState(() {
      _submitting = false;
      if (!isLast) {
        _current++;
        _wordPlaying = false;
        _wordLoading = false;
        _examplePlaying = false;
        _exampleLoading = false;
      }
    });
    if (isLast) {
      _finishSession();
    } else {
      _autoPlayCurrentCard();
    }
  }

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
          const SizedBox(height: 8),
          const Text('继续保持，明天见！',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green)),
        ]),
        actions: [
          FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (mounted) context.go(_backTarget);
              },
              child: const Text('返回'))
        ],
      ),
    );
  }

  void _showWhiteboard(ColorScheme cs,
      {VocabularyModel? vocab, GrammarLessonModel? grammar}) {
    final refChar = vocab?.word ?? grammar?.pattern;
    final title = vocab?.word ?? grammar?.pattern ?? '';
    final subtitle = vocab != null
        ? vocab.reading
        : (grammar?.titleZh ?? grammar?.title ?? '');
    final meaning = vocab?.meaningZh ??
        grammar?.explanationZh ??
        grammar?.explanation ??
        '';
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
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.w400)),
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
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(meaning,
                      style:
                          TextStyle(fontSize: 14, color: cs.onPrimaryContainer),
                      textAlign: TextAlign.center),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
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
          SnackBar(
              content: Text('已清除 $count 条SRS记录'),
              behavior: SnackBarBehavior.floating),
        );
        setState(() {
          _cards = [];
          _loading = false;
          _loadError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('清除失败，请检查网络'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
            const Text('加载复习卡片失败',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('请检查网络连接后重试', style: TextStyle(color: cs.outline)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _loadError = false;
                });
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
            const Icon(Icons.check_circle_outline,
                color: Colors.green, size: 80),
            const SizedBox(height: 16),
            const Text('今日复习已完成！',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('明日再来继续学习'),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: () => context.go(_backTarget),
                child: const Text('返回')),
          ]),
        ),
      );
    }

    final card = _cards[_current];
    final vocab = card.content is VocabularyModel
        ? card.content as VocabularyModel
        : null;
    final grammar = card.content is GrammarLessonModel
        ? card.content as GrammarLessonModel
        : null;
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
            onPressed: () =>
                _showWhiteboard(cs, vocab: vocab, grammar: grammar),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') _confirmResetSrs();
            },
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: hasContent
                  ? _buildSwipeCard(vocab, grammar, cs)
                  : Card(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 48, color: cs.outline),
                            const SizedBox(height: 12),
                            Text('内容不可用',
                                style:
                                    TextStyle(fontSize: 18, color: cs.outline)),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed:
                                  _submitting ? null : () => _submitReview(3),
                              child: const Text('跳过此卡'),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (hasContent) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swipe_left_rounded,
                      size: 17, color: Colors.red.shade300),
                  const SizedBox(width: 4),
                  Text('左滑：不认识', style: TextStyle(color: Colors.red.shade400)),
                  const SizedBox(width: 20),
                  Icon(Icons.swipe_right_rounded,
                      size: 17, color: Colors.green.shade400),
                  const SizedBox(width: 4),
                  Text('右滑：认识', style: TextStyle(color: Colors.green.shade500)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeCard(
    VocabularyModel? vocab,
    GrammarLessonModel? grammar,
    ColorScheme cs,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dragRatio = (_dragOffset / (screenWidth * 0.4)).clamp(-1.0, 1.0);
    final swipingRight = dragRatio > 0.05;
    final swipingLeft = dragRatio < -0.05;
    final overlayColor = swipingRight
        ? Colors.green
        : swipingLeft
            ? Colors.red
            : Colors.transparent;
    final overlayText = swipingRight
        ? '认识'
        : swipingLeft
            ? '不认识'
            : null;

    return GestureDetector(
      onHorizontalDragUpdate: _submitting
          ? null
          : (details) => setState(() => _dragOffset += details.delta.dx),
      onHorizontalDragEnd: _submitting
          ? null
          : (_) async {
              if (_dragOffset.abs() > screenWidth * 0.5) {
                final quality = _dragOffset > 0 ? 4 : 0;
                setState(() => _dragOffset = 0);
                await _submitReview(quality);
              } else {
                setState(() => _dragOffset = 0);
              }
            },
      onHorizontalDragCancel: () {
        if (mounted) setState(() => _dragOffset = 0);
      },
      child: AnimatedContainer(
        duration: _dragOffset == 0
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        transform: Matrix4.translationValues(_dragOffset, 0, 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: swipingRight
                      ? Colors.green.shade100.withValues(alpha: dragRatio.abs())
                      : swipingLeft
                          ? Colors.red.shade100
                              .withValues(alpha: dragRatio.abs())
                          : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: vocab != null
                    ? _buildVocabContent(vocab, cs)
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: _buildGrammarContent(grammar!, cs),
                      ),
              ),
            ),
            if (overlayText != null)
              Positioned(
                top: 16,
                right: swipingLeft ? null : 16,
                left: swipingLeft ? 16 : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: overlayColor.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(overlayText,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      const SizedBox(width: 4),
                      Icon(
                        swipingLeft
                            ? Icons.close_rounded
                            : Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _posLabel(String pos) {
    const labels = {
      'noun': '名词',
      'verb': '动词',
      'adjective': '形容词',
      'adverb': '副词',
      'particle': '助词',
      'conjunction': '接续词',
      'interjection': '感叹词',
      'other': '其他',
    };
    return labels[pos] ?? pos;
  }

  static String _formatPosRaw(String raw) {
    return raw.replaceFirstMapped(
      RegExp(r'^(自他動|自動|他動|補動)(\d*)'),
      (m) => '${m[1]}詞${m[2] ?? ""}',
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _vocabSectionHeader({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(children: [
      Icon(icon, size: 17, color: color),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, color: color)),
    ]);
  }

  Widget _buildVocabAudioButton(
    VocabularyModel vocab, {
    required bool isExample,
    required bool playing,
    required bool loading,
    double size = 28,
  }) {
    final cs = Theme.of(context).colorScheme;
    final text = isExample
        ? (vocab.exampleSentence ?? '')
        : ttsText(vocab.word, vocab.reading);
    return GestureDetector(
      onTap: loading || text.isEmpty
          ? null
          : () => isExample
              ? _speakExample(text, audioUrl: vocab.exampleAudioUrl)
              : _speakWord(text, audioUrl: vocab.audioUrl),
      child: Container(
        width: size + 8,
        height: size + 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              playing ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: size * 0.6,
                  height: size * 0.6,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cs.primary),
                ),
              )
            : Icon(
                playing
                    ? Icons.volume_up_rounded
                    : Icons.play_circle_outline_rounded,
                color: cs.primary,
                size: size,
              ),
      ),
    );
  }

  Widget _buildVocabSlowButton(
    VocabularyModel vocab, {
    required bool isExample,
    double size = 24,
  }) {
    final text = isExample
        ? (vocab.exampleSentence ?? '')
        : ttsText(vocab.word, vocab.reading);
    return GestureDetector(
      onTap: text.isEmpty
          ? null
          : () => isExample
              ? _speakExample(text, audioUrl: vocab.exampleAudioUrl, slow: true)
              : _speakWord(text, audioUrl: vocab.audioUrl, slow: true),
      child: Container(
        width: size + 8,
        height: size + 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.orange.withValues(alpha: 0.1),
        ),
        child: Center(
          child:
              Text('🐌', style: TextStyle(fontSize: size * 0.55, height: 1.0)),
        ),
      ),
    );
  }

  Widget _buildVocabContent(VocabularyModel vocab, ColorScheme cs) {
    final posText = vocab.partOfSpeechRaw != null
        ? _formatPosRaw(vocab.partOfSpeechRaw!)
        : _posLabel(vocab.partOfSpeech);
    final conjugations = vocab.partOfSpeech == 'verb'
        ? conjugateVerb(vocab.word, vocab.reading)
        : <VerbConjugation>[];
    final reading = cleanReading(vocab.reading);
    final word = cleanWord(vocab.word);
    final showReading = reading.isNotEmpty && reading != word;

    // Layout and typography follow StudyPlanRunScreen._buildVocabCard.
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FuriganaText(
                      text: vocab.word,
                      fontSize: 32,
                      color: cs.onSurface,
                    ),
                    if (showReading) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          reading,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.1,
                            color: cs.primary.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _chip(vocab.jlptLevel, cs.primary),
                    if (posText.isNotEmpty) _chip(posText, cs.secondary),
                    _buildVocabAudioButton(
                      vocab,
                      isExample: false,
                      playing: _wordPlaying,
                      loading: _wordLoading,
                      size: 24,
                    ),
                    _buildVocabSlowButton(vocab, isExample: false, size: 22),
                  ],
                ),
              ),
              const Divider(height: 24),
              _vocabSectionHeader(
                icon: Icons.translate_rounded,
                label: '释义',
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                vocab.meaningZh,
                style:
                    TextStyle(fontSize: 18, height: 1.35, color: cs.onSurface),
              ),
              if (vocab.meaningEn != null) ...[
                const SizedBox(height: 4),
                Text(
                  vocab.meaningEn!,
                  style:
                      TextStyle(fontSize: 14, height: 1.35, color: cs.outline),
                ),
              ],
              if ((vocab.exampleSentence ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                _vocabSectionHeader(
                  icon: Icons.format_quote_rounded,
                  label: '例句',
                  color: cs.primary,
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (vocab.exampleReading != null &&
                              hasFurigana(vocab.exampleReading!))
                            FuriganaText(
                              text: vocab.exampleReading!,
                              fontSize: 15,
                              color: cs.onSurface,
                              fontWeight: FontWeight.normal,
                              textAlign: TextAlign.start,
                            )
                          else
                            Text(
                              vocab.exampleSentence!,
                              style: TextStyle(
                                  fontSize: 15,
                                  height: 1.5,
                                  color: cs.onSurface),
                            ),
                          if (vocab.exampleMeaningZh != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              vocab.exampleMeaningZh!,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: cs.outline),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      children: [
                        _buildVocabAudioButton(
                          vocab,
                          isExample: true,
                          playing: _examplePlaying,
                          loading: _exampleLoading,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        _buildVocabSlowButton(vocab, isExample: true, size: 20),
                      ],
                    ),
                  ],
                ),
              ],
              if (conjugations.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.swap_horiz_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 4),
                  Text('动词变形',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: cs.primary)),
                ]),
                const SizedBox(height: 4),
                ...conjugations.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        SizedBox(
                            width: 52,
                            child: Text(c.form,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(c.value,
                                style: const TextStyle(fontSize: 14))),
                      ]),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrammarContent(GrammarLessonModel grammar, ColorScheme cs) {
    final title = (grammar.titleZh ?? grammar.title).trim();
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(grammar.pattern,
              style:
                  const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_showAnswer) ...[
            if (title.isNotEmpty)
              Text(title, style: TextStyle(fontSize: 18, color: cs.primary)),
            const SizedBox(height: 8),
            Text(grammar.explanationZh ?? grammar.explanation ?? '',
                style: const TextStyle(fontSize: 15, height: 1.5),
                textAlign: TextAlign.center),
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
                    Text(grammar.examples.first.sentence,
                        textAlign: TextAlign.center),
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
