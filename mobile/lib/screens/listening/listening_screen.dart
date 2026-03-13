import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../services/api_service.dart';

class ListeningScreen extends StatefulWidget {
  const ListeningScreen({super.key});
  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen> {
  // ── 基础状态 ──
  String _level = 'N5';
  List<Map<String, dynamic>> _sentences = [];
  int _index = 0;
  bool _loading = true;

  // ── 语音 ──
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  // ── 评分 ──
  int? _score;
  String _recognized = '';
  String _feedback = '';
  final List<int> _scores = [];
  String _lastRecognized = '';
  bool _showSentence = false;

  // ── 文字输入 ──
  final TextEditingController _inputCtrl = TextEditingController();
  bool _inputMode = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
    _loadSentences();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('ja-JP');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
    } catch (_) {}
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _loadSentences() async {
    setState(() { _loading = true; _score = null; _recognized = ''; _feedback = ''; _showSentence = false; _inputCtrl.clear(); });
    try {
      final res = await apiService.getListeningExercises(level: _level, count: 20, source: 'all');
      if (mounted) setState(() {
        _sentences = res.map((q) {
          return {
            'sentence': q.sentence,
            'reading': q.reading ?? '',
            'meaning': q.correctAnswer,
            'type': q.type,
            'title': q.grammarTitle ?? q.word ?? '',
          };
        }).toList();
        _index = 0;
        _scores.clear();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectLevel(String level) {
    if (_level == level) return;
    _level = level;
    _loadSentences();
  }

  Future<void> _play({double rate = 0.45}) async {
    if (_sentences.isEmpty) return;
    final s = _sentences[_index];
    await _tts.setSpeechRate(rate);
    await _tts.speak(s['sentence']);
    await _tts.setSpeechRate(0.45);
  }

  Future<void> _toggleRecord() async {
    if (_listening) {
      await _speech.stop();
      if (_score == null && _lastRecognized.isNotEmpty) {
        _processResult(_lastRecognized);
      } else {
        setState(() => _listening = false);
      }
      return;
    }
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别不可用，请检查权限')),
        );
      }
      return;
    }
    _lastRecognized = '';
    setState(() { _listening = true; _score = null; _recognized = ''; _feedback = ''; _inputMode = false; _inputCtrl.clear(); });
    await _speech.listen(
      localeId: 'ja_JP',
      onResult: (result) {
        _lastRecognized = result.recognizedWords;
        if (result.finalResult) _processResult(result.recognizedWords);
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
    );
    _speech.statusListener = (status) {
      if (status == 'done' || status == 'notListening') {
        if (mounted && _listening && _score == null && _lastRecognized.isNotEmpty) {
          _processResult(_lastRecognized);
        } else if (mounted && _listening) {
          setState(() => _listening = false);
        }
      }
    };
  }

  void _processResult(String recognized) {
    final s = _sentences[_index];
    final sentence = (s['sentence'] as String).trim();
    final reading = (s['reading'] as String).trim();
    final rec = recognized.trim();

    final scores = [
      _calcScore(sentence, rec),
      if (reading.isNotEmpty) _calcScore(reading, rec),
    ];
    final score = scores.reduce(max);
    _scores.add(score);

    String feedback;
    if (score >= 90) {
      feedback = '🎉 完美！';
    } else if (score >= 70) {
      feedback = '👍 不错！识别:「$recognized」';
    } else if (score >= 40) {
      feedback = '💪 继续努力！识别:「$recognized」';
    } else {
      feedback = '🔄 再试一次！识别:「$recognized」';
    }

    setState(() { _score = score; _recognized = recognized; _feedback = feedback; _listening = false; _showSentence = true; });
  }

  void _submitText() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _processResult(text);
    FocusScope.of(context).unfocus();
  }

  int _calcScore(String target, String recognized) {
    if (target == recognized) return 100;
    final t = target.runes.toList();
    final r = recognized.runes.toList();
    final maxLen = max(t.length, r.length);
    if (maxLen == 0) return 0;
    int matches = 0;
    for (int i = 0; i < min(t.length, r.length); i++) {
      if (t[i] == r[i]) matches++;
    }
    return (matches / maxLen * 100).round();
  }

  void _prev() {
    if (_index > 0) setState(() { _index--; _resetState(); });
  }

  void _next() {
    if (_index < _sentences.length - 1) setState(() { _index++; _resetState(); });
  }

  void _resetState() {
    _score = null; _recognized = ''; _feedback = ''; _showSentence = false; _inputCtrl.clear(); _inputMode = false;
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _inputCtrl.dispose();
    if (_scores.isNotEmpty) {
      final avg = (_scores.reduce((a, b) => a + b) / _scores.length).round();
      apiService.logActivity(activityType: 'listening', durationSeconds: _scores.length * 10, score: avg.toDouble());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avgScore = _scores.isNotEmpty ? (_scores.reduce((a, b) => a + b) / _scores.length).round() : null;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('🎧 听力练习', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sentences.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.headphones_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('暂无例句数据', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _loadSentences, child: const Text('重试')),
                  ],
                ))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildLevelChips(cs),
                    const SizedBox(height: 20),
                    _buildSentenceCard(cs),
                    const SizedBox(height: 20),
                    _buildSessionStats(cs, avgScore),
                  ],
                ),
    );
  }

  Widget _buildLevelChips(ColorScheme cs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['N5', 'N4', 'N3', 'N2', 'N1'].map((l) {
          final active = l == _level;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(l),
              selected: active,
              selectedColor: cs.primary,
              labelStyle: TextStyle(color: active ? Colors.white : cs.onSurface, fontWeight: FontWeight.bold),
              onSelected: (_) => _selectLevel(l),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSentenceCard(ColorScheme cs) {
    final s = _sentences[_index];
    final typeLabel = s['type'] == 'grammar' ? '语法例句' : '词汇例句';
    final title = s['title'] as String;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        // 进度
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${_index + 1} / ${_sentences.length}', style: TextStyle(color: cs.outline, fontSize: 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
            child: Text(typeLabel, style: TextStyle(fontSize: 11, color: cs.primary)),
          ),
        ]),
        if (title.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: cs.outline)),
        ],
        const SizedBox(height: 16),

        // 听力区域
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [cs.primaryContainer.withValues(alpha: 0.5), cs.tertiaryContainer.withValues(alpha: 0.3)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Icon(Icons.headphones_rounded, size: 48, color: cs.primary),
            const SizedBox(height: 8),
            Text('请仔细听这段日语', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7), fontSize: 14)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: () => _play(),
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('播放'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _play(rate: 0.25),
                icon: const Text('🐌', style: TextStyle(fontSize: 16)),
                label: const Text('慢速'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),

        // 录音按钮
        FilledButton.icon(
          onPressed: _toggleRecord,
          icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(_listening ? '停止录音' : '🎙️ 录音比对'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: _listening ? Colors.red : cs.primary,
          ),
        ),
        if (_listening)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('正在聆听...请用日语说出你听到的内容', style: TextStyle(color: cs.primary, fontSize: 12))),

        const SizedBox(height: 8),

        // 文字输入按钮/输入框
        if (!_listening && _score == null) ...[
          OutlinedButton.icon(
            onPressed: () => setState(() => _inputMode = !_inputMode),
            icon: Icon(_inputMode ? Icons.close : Icons.keyboard_rounded),
            label: Text(_inputMode ? '收起键盘' : '✍️ 文字输入'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (_inputMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _inputCtrl,
              decoration: InputDecoration(
                hintText: '输入你听到的日语...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(icon: const Icon(Icons.send_rounded), onPressed: _submitText),
              ),
              onSubmitted: (_) => _submitText(),
            ),
          ],
        ],

        // 评分结果
        if (_score != null) ...[
          const SizedBox(height: 20),
          Text('$_score', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: _score! >= 80 ? Colors.green : _score! >= 50 ? Colors.orange : Colors.red)),
          const SizedBox(height: 4),
          Text(_feedback, style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.7)), textAlign: TextAlign.center),
        ],

        // 原文显示
        if (_showSentence) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📝 原文', style: TextStyle(fontSize: 12, color: cs.outline)),
              const SizedBox(height: 6),
              Text(s['sentence'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
              if ((s['reading'] as String).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(s['reading'], style: TextStyle(fontSize: 13, color: cs.outline)),
              ],
              const SizedBox(height: 8),
              Text('💬 ${s['meaning']}', style: TextStyle(fontSize: 14, color: cs.primary)),
            ]),
          ),
        ],

        if (!_showSentence && _score == null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _showSentence = true),
            child: Text('👁 显示原文', style: TextStyle(color: cs.outline)),
          ),
        ],

        const SizedBox(height: 20),

        // 导航按钮
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          OutlinedButton.icon(
            onPressed: _index > 0 ? _prev : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('上一句'),
          ),
          OutlinedButton.icon(
            onPressed: _index < _sentences.length - 1 ? _next : null,
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('下一句'),
          ),
        ]),
      ]),
    );
  }

  Widget _buildSessionStats(ColorScheme cs, int? avgScore) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        Column(children: [
          Text('${_scores.length}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
          Text('已练习', style: TextStyle(fontSize: 12, color: cs.outline)),
        ]),
        Container(width: 1, height: 30, color: cs.outlineVariant),
        Column(children: [
          Text(avgScore != null ? '$avgScore' : '-', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: avgScore != null && avgScore >= 70 ? Colors.green : Colors.orange)),
          Text('平均分', style: TextStyle(fontSize: 12, color: cs.outline)),
        ]),
        Container(width: 1, height: 30, color: cs.outlineVariant),
        Column(children: [
          Text('$_level', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
          Text('当前级别', style: TextStyle(fontSize: 12, color: cs.outline)),
        ]),
      ]),
    );
  }
}
