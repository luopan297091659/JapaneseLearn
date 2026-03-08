import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../utils/tts_helper.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/audio_player_widget.dart';

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
  const GrammarDetailScreen({super.key, required this.id});
  @override
  State<GrammarDetailScreen> createState() => _GrammarDetailScreenState();
}

class _GrammarDetailScreenState extends State<GrammarDetailScreen> {
  final FlutterTts _tts = FlutterTts();
  GrammarLessonModel? _lesson;
  bool _loading = true;
  bool _ttsReady = false;
  late final DateTime _screenOpenTime;

  @override
  void initState() {
    super.initState();
    _screenOpenTime = DateTime.now();
    _initTts();
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

  Future<void> _speakJa(String text) async {
    if (!_ttsReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音引擎初始化中，请稍后再试…'), duration: Duration(seconds: 2)),
      );
      return;
    }
    try {
      try { await _tts.setLanguage('ja-JP'); } catch (_) {}
      await _tts.setVolume(1.0);
      final result = await _tts.speak(text);
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
  }

  @override
  void dispose() {
    final dur = DateTime.now().difference(_screenOpenTime).inSeconds;
    if (_lesson != null && dur > 2) {
      apiService.logActivity(activityType: 'grammar', refId: widget.id, durationSeconds: dur);
    }
    _tts.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lesson = await apiService.getGrammarLesson(widget.id);
      setState(() { _lesson = lesson; _loading = false; });
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
        actions: [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lesson == null
              ? const Center(child: Text('加载失败'))
              : ListView(
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
                      child: Text(_lesson!.explanationZh ?? _lesson!.explanation,
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
                                      Expanded(child: Text(e.sentence, style: const TextStyle(fontSize: 15, height: 1.4))),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () => _speakJa(e.sentence),
                                        borderRadius: BorderRadius.circular(14),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(Icons.volume_up_rounded, size: 20, color: cs.primary),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (e.reading != null) ...[const SizedBox(height: 2),
                                    Text(e.reading!, style: TextStyle(color: cs.primary, fontSize: 12))],
                                  const SizedBox(height: 4),
                                  Text(e.meaningZh, style: TextStyle(fontSize: 13, color: cs.outline)),
                                  if (e.audioUrl != null) ...[
                                    const SizedBox(height: 6),
                                    AudioPlayerWidget(
                                      audioUrl: e.audioUrl,
                                      compact: true,
                                    ),
                                  ],
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
    );
  }
}
