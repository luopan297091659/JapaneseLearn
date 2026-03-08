import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../utils/japanese_text_utils.dart';
import '../../utils/tts_helper.dart';
import '../../widgets/audio_player_widget.dart';
import 'vocab_whiteboard_screen.dart';

class VocabularyDetailScreen extends StatefulWidget {
  final String id;
  const VocabularyDetailScreen({super.key, required this.id});
  @override
  State<VocabularyDetailScreen> createState() => _VocabularyDetailScreenState();
}

class _VocabularyDetailScreenState extends State<VocabularyDetailScreen> {
  VocabularyModel? _vocab;
  bool _loading = true;
  String? _error;
  bool _addedToSrs = false;

  // 闪卡模式
  bool _showAnswer = false;

  // SRS 卡片信息
  String? _srsCardId;
  int    _srsRepetitions  = 0;
  double _srsEaseFactor   = 2.5;
  int    _srsIntervalDays = 0;
  bool   _srsSubmitting   = false;

  // ── TTS ──────────────────────────────────────────────────────────────────
  late final FlutterTts _tts;
  bool _ttsPlaying = false;
  bool _ttsReady   = false;  // 引擎初始化完成标志
  late final DateTime _screenOpenTime;

  @override
  void initState() {
    super.initState();
    _screenOpenTime = DateTime.now();
    _initTts();
    _load();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();

    _tts.setStartHandler(() {
      if (mounted) setState(() => _ttsPlaying = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _ttsPlaying = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _ttsPlaying = false);
    });
    _tts.setErrorHandler((err) {
      debugPrint('TTS error: $err');
      if (mounted) setState(() => _ttsPlaying = false);
    });

    try {
      await TtsHelper.configureForJapanese(_tts).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('TTS 初始化超时（15s）');
          return false;
        },
      );
      await _tts.setSpeechRate(0.5);
    } catch (e) {
      debugPrint('TTS 初始化失败: $e');
    }
    if (mounted) setState(() => _ttsReady = true);
  }

  Future<void> _speak() async {
    if (_vocab == null) return;

    // 引擎尚未就绪时提示用户
    if (!_ttsReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('语音引擎初始化中，请稍后再试…'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 已在播放 → 停止，并重置标志防止卡死
    if (_ttsPlaying) {
      await _tts.stop();
      setState(() => _ttsPlaying = false);
      return;
    }

    final text = ttsText(_vocab!.word, _vocab!.reading);
    try {
      setState(() => _ttsPlaying = true); // 乐观更新，按钮立即响应
      
      // 每次 speak 前设置语言和音量，防止 Android TTS 丢失设置
      await _tts.setLanguage('ja-JP');
      await _tts.setVolume(1.0);
      
      final result = await _tts.speak(text);
      // result == 1 表示成功启动，0 表示引擎拒绝
      if (result != 1 && mounted) {
        setState(() => _ttsPlaying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('语音引擎不可用，请在系统设置中安装日语 TTS 引擎'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _ttsPlaying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('朗读出错：$e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    final dur = DateTime.now().difference(_screenOpenTime).inSeconds;
    if (_vocab != null && dur > 2) {
      apiService.logActivity(activityType: 'vocabulary', refId: widget.id, durationSeconds: dur);
    }
    _tts.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final vocab = await apiService.getVocabularyById(widget.id);
      if (mounted) setState(() { _vocab = vocab; _loading = false; });
      // 异步查询 SRS 卡片状态
      _loadSrsCard();
    } catch (e) {
      if (mounted) setState(() { _error = '加载失败：$e'; _loading = false; });
    }
  }

  Future<void> _loadSrsCard() async {
    try {
      final card = await apiService.getSrsCardByRef(widget.id);
      if (mounted) setState(() {
        _srsCardId       = card?['id']?.toString();
        _addedToSrs      = card != null;
        _srsRepetitions  = (card?['repetitions']  as num?)?.toInt()    ?? 0;
        _srsEaseFactor   = (card?['ease_factor']  as num?)?.toDouble() ?? 2.5;
        _srsIntervalDays = (card?['interval_days'] as num?)?.toInt()   ?? 0;
      });
    } catch (_) {}
  }

  // 本地预算下次间隔（与后端 SM-2 保持一致）
  int _calcNext(int quality) {
    if (quality < 3) return 0;
    double ease = (_srsEaseFactor + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
        .clamp(1.3, 4.0);
    if (_srsRepetitions == 0) return 1;
    if (_srsRepetitions == 1) return 6;
    return (_srsIntervalDays * ease).round().clamp(1, 36500);
  }

  List<({String label, Color color, String interval, int quality})> get _srsIntervals => [
    (label: '重来', color: Colors.red.shade400,    interval: '<10分',                quality: 0),
    (label: '困难', color: Colors.orange.shade400, interval: _fmtDays(_calcNext(3)), quality: 3),
    (label: '良好', color: Colors.blue.shade400,   interval: _fmtDays(_calcNext(4)), quality: 4),
    (label: '简单', color: Colors.green.shade400,  interval: _fmtDays(_calcNext(5)), quality: 5),
  ];

  static String _fmtDays(int days) {
    if (days == 0)   return '<10分';
    if (days == 1)   return '1天';
    if (days < 30)   return '$days天';
    final m = days / 30.0;
    if (m < 12)      return '${m.toStringAsFixed(1)}月';
    return '${(days / 365.0).toStringAsFixed(1)}年';
  }

  Future<void> _submitSrsDifficulty(int quality) async {
    if (_srsCardId == null || _srsSubmitting) return;
    setState(() => _srsSubmitting = true);
    try {
      await apiService.submitSrsReview(_srsCardId!, quality);
      if (mounted) {
        final label = quality == 0 ? '重来' : quality <= 3 ? '困难' : quality == 4 ? '良好' : '简单';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已标记为「$label」，已更新复习计划'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _srsSubmitting = false);
    }
  }

  Future<void> _addToSrs() async {
    try {
      await apiService.addSrsCard(widget.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已加入间隔复习！'), backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating));
      }
      // 加入后立即获取 card_id，底部显示难度按钮
      _loadSrsCard();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/vocabulary'),
        ),
        title: Text(_vocab?.word ?? '単詞詳細'),
        actions: [
          // ── TTS 朗读按钮 ────────────────────────────────────────────
          if (_vocab != null)
            IconButton(
              tooltip: _ttsReady ? '朗读' : '语音引擎加载中…',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: !_ttsReady
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                        key: ValueKey('loading'),
                      )
                    : Icon(
                        _ttsPlaying ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                        key: ValueKey(_ttsPlaying),
                      ),
              ),
              onPressed: _speak,
            ),
          // ── 白板练习按钮 ────────────────────────────────────────────
          if (_vocab != null)
            IconButton(
              tooltip: '白板练习',
              icon: const Icon(Icons.draw_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VocabWhiteboardScreen(
                    word: _vocab!.word,
                    reading: _vocab!.reading,
                    meaningZh: _vocab!.meaningZh,
                  ),
                ),
              ),
            ),

          if (_vocab != null && !_addedToSrs)
            TextButton.icon(
              icon: const Icon(Icons.add_card),
              label: const Text('加入SRS'),
              onPressed: _addToSrs,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: cs.error),
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: cs.error)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); },
                        child: const Text('重试')),
                  ]))
              : Column(
                  children: [
                    Expanded(child: _buildContent(cs)),
                    // ── 底部闪卡控制栏 ────────────────────────────
                    if (_showAnswer && _srsCardId != null)
                      _AnkiRatingBar(
                        intervals: _srsIntervals,
                        submitting: _srsSubmitting,
                        onRate: _submitSrsDifficulty,
                      ),
                    if (!_showAnswer)
                      _ShowAnswerBar(onShow: () => setState(() => _showAnswer = true)),
                  ],
                ),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    final v = _vocab!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Word card ─────────────────────────────────────────────────
          GestureDetector(
            onTap: !_showAnswer ? () => setState(() => _showAnswer = true) : null,
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primaryContainer, cs.secondaryContainer],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: v.word));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制'), behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 1)));
                  },
                  child: Text(cleanWord(v.word),
                      style: TextStyle(fontSize: 52, fontWeight: FontWeight.bold,
                          color: cs.primary, height: 1.2)),
                ),
                if (_showAnswer) ...[  
                  const SizedBox(height: 8),
                  Text(cleanReading(v.reading).isNotEmpty ? cleanReading(v.reading) : ttsText(v.word, v.reading),
                      style: TextStyle(fontSize: 24, color: cs.secondary, fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _chip(v.jlptLevel, cs.primary),
                  const SizedBox(width: 8),
                  _chip(v.partOfSpeech, cs.tertiary),
                ]),
              ],
            ),
           ), // end GestureDetector
          ),

          const SizedBox(height: 20),

          // 未显示答案时提示点击
          if (!_showAnswer) ...[  
            const SizedBox(height: 40),
            Text('点击卡片或「显示答案」查看释义',
                style: TextStyle(color: cs.outline, fontSize: 14)),
            const SizedBox(height: 40),
          ],

          if (_showAnswer) ...[

          // ── Audio / TTS ───────────────────────────────────────────────
          // 有远程音频时显示播放卡片，TTS已在右上角AppBar提供
          if (v.audioUrl != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AudioPlayerWidget(audioUrl: v.audioUrl, compact: false),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Meanings ──────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.translate_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 6),
                    const Text('释义', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  const Divider(height: 16),
                  // Chinese meaning
                  _meaningRow('中文', v.meaningZh, cs),
                  if (v.meaningEn != null) _meaningRow('English', v.meaningEn!, cs),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Example sentence ──────────────────────────────────────────
          if (v.exampleSentence != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.format_quote_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      const Text('例文', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ]),
                    const Divider(height: 16),
                    Text(v.exampleSentence!, style: const TextStyle(fontSize: 18, height: 1.6)),
                    if (v.exampleReading != null)
                      Text(v.exampleReading!,
                          style: TextStyle(fontSize: 14, color: cs.primary, height: 1.4)),
                    if (v.exampleMeaningZh != null) ...[
                      const SizedBox(height: 4),
                      Text(v.exampleMeaningZh!,
                          style: const TextStyle(fontSize: 15, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),

          // ── SRS add button ────────────────────────────────────────────
          if (!_addedToSrs)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _addToSrs,
                icon: const Icon(Icons.add_card),
                label: const Text('加入间隔复习 (SRS)'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check),
                label: const Text('已加入SRS'),
              ),
            ),
          const SizedBox(height: 16),
          ], // end if (_showAnswer)
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _meaningRow(String lang, String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 60,
          child: Text(lang, style: TextStyle(fontSize: 12, color: cs.outline, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
      ]),
    );
  }
}

// ─── 显示答案栏 ──────────────────────────────────────────────────────────────────
class _ShowAnswerBar extends StatelessWidget {
  final VoidCallback onShow;
  const _ShowAnswerBar({required this.onShow});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: onShow,
          child: const Text('显示意思', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}

// ─── Anki 风格评分栏 ──────────────────────────────────────────────────────────
class _AnkiRatingBar extends StatelessWidget {
  final List<({String label, Color color, String interval, int quality})> intervals;
  final bool submitting;
  final Future<void> Function(int) onRate;

  const _AnkiRatingBar({
    required this.intervals,
    required this.submitting,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: intervals.map((item) => Expanded(
        child: GestureDetector(
          onTap: submitting ? null : () => onRate(item.quality),
          child: Container(
            color: item.color,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.interval,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                submitting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(item.label,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
        ),
      )).toList(),
    );
  }
}
