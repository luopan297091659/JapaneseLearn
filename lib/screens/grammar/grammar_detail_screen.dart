import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/tts_helper.dart';
import '../../utils/audio_manager.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../config/app_config.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/furigana_text.dart';

// ─── 段落标题 ──────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 18, color: cs.primary),
      const SizedBox(width: 6),
      Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurface)),
    ]);
  }
}

class GrammarDetailScreen extends StatefulWidget {
  final String id;
  final List<String>? lessonIds;
  const GrammarDetailScreen({super.key, required this.id, this.lessonIds});
  @override
  State<GrammarDetailScreen> createState() => _GrammarDetailScreenState();
}

class _GrammarDetailScreenState extends State<GrammarDetailScreen> {
  final FlutterTts _tts = FlutterTts();
  AudioPlayer? _examplePlayer;
  GrammarLessonModel? _lesson;
  bool _loading = true;
  bool _ttsReady = false;
  late final DateTime _screenOpenTime;

  // 每条例句独立的播放/加载状态 (key = example index)
  int _playingExampleIdx = -1;
  bool _exampleLoading = false;

  late String _currentId;

  @override
  void initState() {
    super.initState();
    _currentId = widget.id;
    _screenOpenTime = DateTime.now();
    _initTts();
    _load();
  }

  // ── 上一个 / 下一个 ─────────────────────────────────────────────
  int get _currentIndex => widget.lessonIds?.indexOf(_currentId) ?? -1;
  bool get _hasPrev => widget.lessonIds != null && _currentIndex > 0;
  bool get _hasNext => widget.lessonIds != null && _currentIndex >= 0 && _currentIndex < widget.lessonIds!.length - 1;

  void _goToLesson(String id) {
    AudioManager.instance.stopAll();
    _tts.stop();
    _examplePlayer?.stop();
    setState(() {
      _currentId = id;
      _loading = true;
      _playingExampleIdx = -1;
      _exampleLoading = false;
    });
    _load();
  }

  Future<void> _initTts() async {
    _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
    _tts.setStartHandler(() { if (mounted) setState(() {}); });
    _tts.setCompletionHandler(() { if (mounted) setState(() {}); });
    _tts.setCancelHandler(() { if (mounted) setState(() {}); });
    await TtsHelper.configureForJapanese(_tts);
    if (mounted) setState(() => _ttsReady = true);
  }

  /// 播放例句音频：有 audio_url 用 just_audio，否则回退到 TTS
  Future<void> _playExampleAudio(int idx, String text, String? audioUrl, {bool slow = false}) async {
    if (mounted) setState(() { _playingExampleIdx = idx; _exampleLoading = true; });
    try {
      await AudioManager.instance.requestTts(_tts);
      await TtsHelper.playJapaneseSmart(
        audioUrl: audioUrl,
        text: text,
        tts: _tts,
        slow: slow,
        onComplete: () {
          if (mounted) setState(() { _playingExampleIdx = -1; _exampleLoading = false; });
        },
      );
      // 音频已开始播放，取消 loading 状态，保留 playing 状态
      if (mounted) setState(() => _exampleLoading = false);
    } catch (e) {
      debugPrint('Grammar audio error: $e');
      if (mounted) setState(() { _playingExampleIdx = -1; _exampleLoading = false; });
    }
  }

  @override
  void dispose() {
    final dur = DateTime.now().difference(_screenOpenTime).inSeconds;
    if (_lesson != null && dur > 2) {
      apiService.logActivity(activityType: 'grammar', refId: _currentId, durationSeconds: dur);
    }
    AudioManager.instance.stopAll();
    _tts.stop();
    _examplePlayer?.stop();
    _examplePlayer?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lesson = await apiService.getGrammarLesson(_currentId);
      setState(() { _lesson = lesson; _loading = false; });
      // 后台预缓存所有例句音频
      final audioUrls = lesson.examples
          .where((e) => e.audioUrl != null && e.audioUrl!.isNotEmpty)
          .map((e) => e.audioUrl!);
      TtsHelper.precacheAudioUrls(audioUrls);
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/grammar'),
        ),
        title: Text(_lesson?.pattern ?? '文法'),
        actions: [
          if (_lesson != null)
            IconButton(
              tooltip: '问题反馈',
              icon: const Icon(Icons.info_outline_rounded, size: 22),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => ReportDialog(
                  refType: 'grammar',
                  refId: _lesson!.id,
                  refTitle: _lesson!.pattern,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lesson == null
              ? const Center(child: Text('加载失败'))
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Pattern header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_lesson!.pattern, style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold, color: cs.primary)),
                          Text(_lesson!.titleZh ?? _lesson!.title,
                              style: TextStyle(color: cs.onPrimaryContainer)),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary, borderRadius: BorderRadius.circular(4)),
                            child: Text(_lesson!.jlptLevel,
                                style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Explanation
                    _SectionHeader(icon: Icons.description_outlined, title: '说明'),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(_lesson!.explanationZh ?? _lesson!.explanation ?? '',
                          style: TextStyle(fontSize: 14.5, height: 1.6, color: cs.onSurface)),
                    ),
                    if (_lesson!.usageNotes != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline, color: cs.tertiary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_lesson!.usageNotes!, style: TextStyle(color: cs.onTertiaryContainer))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Examples
                    _SectionHeader(icon: Icons.format_list_numbered_rounded, title: '例文 (${_lesson!.examples.length})'),
                    const SizedBox(height: 8),
                    ..._lesson!.examples.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final e = entry.value;
                      final isPlaying = _playingExampleIdx == idx;
                      final isLoading = isPlaying && _exampleLoading;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 26, height: 26,
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text('${idx + 1}',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                                        color: cs.primary)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: (e.reading != null && hasFurigana(e.reading!))
                                            ? FuriganaText(
                                                text: e.reading!,
                                                fontSize: 16,
                                                color: cs.onSurface,
                                                fontWeight: FontWeight.normal,
                                                textAlign: TextAlign.start,
                                              )
                                            : Text(e.sentence, style: const TextStyle(fontSize: 15, height: 1.4)),
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: isLoading ? null : () => _playExampleAudio(idx, e.sentence, e.audioUrl),
                                        child: Container(
                                          width: 30, height: 30,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isPlaying && !isLoading ? cs.primary.withValues(alpha: 0.15) : Colors.transparent,
                                          ),
                                          child: isLoading
                                              ? Center(child: SizedBox(
                                                  width: 16, height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                                ))
                                              : Icon(
                                                  isPlaying ? Icons.volume_up_rounded : Icons.play_circle_outline_rounded,
                                                  size: 20, color: cs.primary,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      GestureDetector(
                                        onTap: () => _playExampleAudio(idx, e.sentence, e.audioUrl, slow: true),
                                        child: Container(
                                          width: 30, height: 30,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.orange.withValues(alpha: 0.1),
                                          ),
                                          child: const Center(child: Text('🐌', style: TextStyle(fontSize: 14))),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(e.meaningZh, style: TextStyle(fontSize: 13, color: cs.outline)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
                    ),
                    // ── 上一个 / 下一个 导航栏 ────────────────────
                    if (widget.lessonIds != null && widget.lessonIds!.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        ),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: _hasPrev
                                  ? () => _goToLesson(widget.lessonIds![_currentIndex - 1])
                                  : null,
                              icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
                              label: const Text('上一个'),
                            ),
                            const Spacer(),
                            Text('${_currentIndex + 1} / ${widget.lessonIds!.length}',
                                style: TextStyle(color: cs.outline, fontSize: 13)),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _hasNext
                                  ? () => _goToLesson(widget.lessonIds![_currentIndex + 1])
                                  : null,
                              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                              label: const Text('下一个'),
                              iconAlignment: IconAlignment.end,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
