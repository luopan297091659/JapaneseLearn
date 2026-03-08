import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../utils/japanese_text_utils.dart';
import '../../utils/tts_helper.dart';

class PronunciationScreen extends StatefulWidget {
  const PronunciationScreen({super.key});
  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen> {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  List<VocabularyModel> _words = [];
  int _index = 0;
  String _level = 'N5';
  bool _loading = true;
  bool _listening = false;
  bool _speechAvailable = false;

  // scoring
  int? _score;
  String _recognized = '';
  String _feedback = '';
  final List<int> _scores = [];

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
    _loadWords();
  }

  Future<void> _initTts() async {
    _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
    await TtsHelper.configureForJapanese(_tts);
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _loadWords() async {
    setState(() { _loading = true; _score = null; _recognized = ''; _feedback = ''; });
    try {
      final res = await apiService.getVocabularyByLevel(_level);
      final words = List<VocabularyModel>.from(res);
      // shuffle
      for (int i = words.length - 1; i > 0; i--) {
        final j = Random().nextInt(i + 1);
        final tmp = words[i]; words[i] = words[j]; words[j] = tmp;
      }
      if (mounted) setState(() {
        _words = words.take(10).toList();
        _index = 0;
        _scores.clear();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  void _selectLevel(String level) {
    if (_level == level) return;
    _level = level;
    _loadWords();
  }

  String _ttsText(VocabularyModel w) => ttsText(w.word, w.reading);

  Future<void> _playAudio() async {
    if (_words.isEmpty) return;
    try {
      try { await _tts.setLanguage('ja-JP'); } catch (_) {}
      await _tts.setVolume(1.0);
      final result = await _tts.speak(_ttsText(_words[_index]));
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

  String _lastRecognized = '';

  Future<void> _toggleRecord() async {
    if (_listening) {
      await _speech.stop();
      // Process whatever was recognized so far (stop() may not trigger finalResult on Android)
      if (_score == null && _lastRecognized.isNotEmpty) {
        _processResult(_lastRecognized);
      } else {
        setState(() => _listening = false);
      }
      return;
    }
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音识别不可用，请检查权限')),
      );
      return;
    }
    _lastRecognized = '';
    setState(() { _listening = true; _score = null; _recognized = ''; _feedback = ''; });
    await _speech.listen(
      localeId: 'ja_JP',
      onResult: (result) {
        _lastRecognized = result.recognizedWords;
        if (result.finalResult) {
          _processResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 5),
      pauseFor: const Duration(seconds: 2),
      onSoundLevelChange: null,
    );
    // Handle speech recognition ending without finalResult (timeout etc.)
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
    final w = _words[_index];
    final reading = cleanReading(w.reading);
    final word = cleanWord(w.word);
    final tts = _ttsText(w);
    final rec = recognized.trim();

    // Compare against cleaned reading, cleaned word, and TTS text
    final scores = [
      if (reading.isNotEmpty) _calcScore(reading, rec),
      _calcScore(word, rec),
      _calcScore(tts, rec),
    ];
    final score = scores.reduce(max);

    final target = reading.isNotEmpty ? reading : word;
    _scores.add(score);

    String feedback;
    if (score >= 90) {
      feedback = '🎉 完美发音！';
    } else if (score >= 70) {
      feedback = '👍 不错！识别: 「$recognized」';
    } else if (score >= 40) {
      feedback = '💪 继续努力！识别: 「$recognized」，目标: 「$target」';
    } else {
      feedback = '🔄 再试一次！识别: 「$recognized」，目标: 「$target」';
    }

    setState(() {
      _score = score;
      _recognized = recognized;
      _feedback = feedback;
      _listening = false;
    });
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
    if (_index > 0) setState(() { _index--; _score = null; _recognized = ''; _feedback = ''; });
  }

  void _next() {
    if (_index < _words.length - 1) setState(() { _index++; _score = null; _recognized = ''; _feedback = ''; });
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avgScore = _scores.isNotEmpty
        ? (_scores.reduce((a, b) => a + b) / _scores.length).round()
        : null;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('🎤 AI 発音練習', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Level chips
                _buildLevelChips(cs),
                const SizedBox(height: 20),
                // Word card
                if (_words.isNotEmpty) _buildWordCard(cs),
                const SizedBox(height: 20),
                // Session stats
                _buildSessionStats(cs, avgScore),
              ],
            ),
    );
  }

  Widget _buildLevelChips(ColorScheme cs) {
    return Row(
      children: ['N5', 'N4', 'N3'].map((l) {
        final active = l == _level;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(l),
            selected: active,
            selectedColor: cs.primary,
            labelStyle: TextStyle(
              color: active ? Colors.white : cs.onSurface,
              fontWeight: FontWeight.bold,
            ),
            onSelected: (_) => _selectLevel(l),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWordCard(ColorScheme cs) {
    final w = _words[_index];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: cs.shadow.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: [
        // Word
        Text(cleanWord(w.word), style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: cs.primary)),
        const SizedBox(height: 4),
        Text(cleanReading(w.reading).isNotEmpty ? cleanReading(w.reading) : _ttsText(w), style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(w.meaningZh, style: TextStyle(fontSize: 14, color: cs.outline)),
        const SizedBox(height: 24),

        // Play button
        OutlinedButton.icon(
          onPressed: _playAudio,
          icon: const Icon(Icons.volume_up_rounded),
          label: const Text('听原生发音'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 12),

        // Record button
        FilledButton.icon(
          onPressed: _toggleRecord,
          icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(_listening ? '停止录音' : '🎙️ 按住录音'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: _listening ? Colors.red : cs.primary,
          ),
        ),
        if (_listening)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('🔴 正在录音…', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
          ),

        // Score result
        if (_score != null) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Text('AI 评分', style: TextStyle(fontSize: 13, color: cs.outline)),
              const SizedBox(height: 4),
              Text(
                '$_score',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: _score! >= 80
                      ? const Color(0xFF10b981)
                      : _score! >= 50
                          ? const Color(0xFFf59e0b)
                          : Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Text(_feedback, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
            ]),
          ),
        ],

        // Nav
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton(
            onPressed: _index > 0 ? _prev : null,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('← 上一个'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${_index + 1} / ${_words.length}',
                style: TextStyle(fontSize: 13, color: cs.outline)),
          ),
          OutlinedButton(
            onPressed: _index < _words.length - 1 ? _next : null,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('下一个 →'),
          ),
        ]),
      ]),
    );
  }

  Widget _buildSessionStats(ColorScheme cs, int? avgScore) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: cs.shadow.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📈 本次练习统计', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _miniStat(cs, '${_scores.length}', '已练习', cs.primary)),
          const SizedBox(width: 12),
          Expanded(child: _miniStat(cs, avgScore != null ? '$avgScore' : '-', '平均得分', const Color(0xFF10b981))),
        ]),
      ]),
    );
  }

  Widget _miniStat(ColorScheme cs, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
      ]),
    );
  }
}
