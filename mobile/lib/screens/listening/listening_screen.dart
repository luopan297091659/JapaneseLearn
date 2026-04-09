import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../services/api_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/furigana_text.dart';
import '../../utils/tts_helper.dart';

class ListeningScreen extends StatefulWidget {
  const ListeningScreen({super.key});
  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen> {
  static const bool _showSttDebug = kDebugMode;

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
  String? _speechLocaleId;

  // ── 评分 ──
  int? _score;
  String _recognized = '';
  String _feedback = '';
  final List<int> _scores = [];
  String _lastRecognized = '';
  bool _showSentence = false;
  bool _attemptFinalized = false;
  bool _aiScoring = false;
  Timer? _resultDebounce;
  Timer? _safetyTimeout;

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
      await TtsHelper.configureForJapanese(_tts);
    } catch (_) {}
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) {
        debugPrint('Speech init error: $error');
        if (mounted) {
          setState(() {
            _debugLastError = error.errorMsg;
          });
        }
      },
      onStatus: (status) {
        debugPrint('Speech init status: $status');
        if (mounted) {
          setState(() {
            _debugStatus = 'init:$status';
          });
        }
      },
    );
    if (_speechAvailable) {
      try {
        final locales = await _speech.locales();
        stt.LocaleName? jaLocale;
        for (final locale in locales) {
          final id = locale.localeId.toLowerCase();
          if (id == 'ja_jp' || id == 'ja-jp') {
            jaLocale = locale;
            break;
          }
        }
        jaLocale ??= locales.cast<stt.LocaleName?>().firstWhere(
              (locale) => locale != null && locale.localeId.toLowerCase().startsWith('ja'),
              orElse: () => null,
            );
        _speechLocaleId = jaLocale?.localeId ?? 'ja-JP';
        debugPrint('Speech locale selected: ${_speechLocaleId ?? 'system default'}');
        if (mounted) {
          setState(() {
            _debugStatus = 'ready';
          });
        }
      } catch (e) {
        debugPrint('Load speech locales failed: $e');
      }
    }
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
            'audio_url': q.audioUrl ?? '',
          };
        }).toList();
        _index = 0;
        _scores.clear();
        _loading = false;
      });
      // 后台预缓存所有例句音频
      final audioUrls = _sentences
          .map((s) => s['audio_url'] as String)
          .where((u) => u.isNotEmpty);
      TtsHelper.precacheAudioUrls(audioUrls);
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
    final audioUrl = s['audio_url'] as String?;
    await TtsHelper.playJapaneseSmart(
      audioUrl: (audioUrl != null && audioUrl.isNotEmpty) ? audioUrl : null,
      text: s['sentence'],
      tts: _tts,
      slow: rate < 0.4,
    );
  }


  bool _toggling = false;
  bool _preferOnDevice = true; // 优先本地识别，失败后回退到在线
  DateTime? _listenStartTime;
  String _debugStatus = 'idle';
  String _debugListenStarted = '-';
  String _debugLastError = '-';
  String _debugPartial = '-';

  bool _isOfflineSttError(String message) {
    final msg = message.toLowerCase();
    return msg.contains('error_network') || msg.contains('error_client');
  }

  /// 统一 finalize 入口 —— 所有路径（手动停止/statusListener/debounce/timeout）都走这里
  void _finalizeAttempt() {
    if (_attemptFinalized || !mounted) return;
    _attemptFinalized = true;
    _resultDebounce?.cancel();
    _safetyTimeout?.cancel();
    _speech.stop();
    if (_lastRecognized.trim().isNotEmpty) {
      _processResult(_lastRecognized);
    } else {
      if (mounted) setState(() { _listening = false; _feedback = '未检测到语音，请靠近麦克风重试'; });
    }
  }

  Future<void> _toggleRecord() async {
    if (_toggling) return;
    _toggling = true;
    try {
      await _doToggleRecord();
    } finally {
      _toggling = false;
    }
  }

  Future<void> _doToggleRecord() async {
    if (_listening) {
      _finalizeAttempt();
      return;
    }

    final micGranted = await PermissionService.requestMicrophonePermission();
    if (!micGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音，请在设置中允许')),
        );
      }
      return;
    }

    // 每次开始前先清理上一次会话状态
    if (!_speechAvailable) {
      await _initSpeech();
    }
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别不可用，请检查麦克风权限或系统设置')),
        );
      }
      return;
    }

    _lastRecognized = '';
    _attemptFinalized = false;
    _resultDebounce?.cancel();
    _safetyTimeout?.cancel();
    _listenStartTime = DateTime.now();
    setState(() {
      _listening = true;
      _score = null;
      _recognized = '';
      _feedback = '';
      _inputMode = false;
      _inputCtrl.clear();
      _debugListenStarted = 'starting';
      _debugLastError = '-';
      _debugPartial = '-';
    });
    try {
      // statusListener —— 启动后 2s 内忽略 notListening（Android STT 启动时会发一次瞬态回调）
      _speech.statusListener = (status) {
        debugPrint('STT status: $status');
        if (mounted) {
          setState(() {
            _debugStatus = status;
          });
        }
        final elapsed = _listenStartTime != null
            ? DateTime.now().difference(_listenStartTime!).inMilliseconds
            : 0;
        if ((status == 'done' || status == 'notListening') &&
            elapsed > 2000 &&
            mounted && _listening && !_attemptFinalized) {
          _finalizeAttempt();
        }
      };

      // onResult 回调（onDevice 回退共用）
      void onSttResult(SpeechRecognitionResult result) {
          _lastRecognized = result.recognizedWords;
          if (mounted) {
            setState(() {
              _debugPartial = result.recognizedWords.isEmpty ? '(empty)' : result.recognizedWords;
            });
          }
          if (result.finalResult && !_attemptFinalized) {
            _finalizeAttempt();
            return;
          }
          _resultDebounce?.cancel();
          if (_lastRecognized.trim().isNotEmpty) {
            _resultDebounce = Timer(const Duration(seconds: 2), () {
              if (!_attemptFinalized && _listening) {
                _finalizeAttempt();
              }
            });
          }
      }

      // 优先本地识别，失败后自动回退到在线模式（兼容不支持 onDevice 的设备）
      bool listenStarted = false;
      final modesToTry = _preferOnDevice ? [true, false] : [false];
      for (final tryOnDevice in modesToTry) {
        try {
          final dynamic listenResult = await _speech.listen(
            localeId: _speechLocaleId ?? 'ja-JP',
            onDevice: tryOnDevice,
            onResult: onSttResult,
            listenFor: const Duration(seconds: 15),
            pauseFor: const Duration(seconds: 3),
          );
          final started = listenResult is bool ? listenResult : true;
          debugPrint('listen(onDevice: $tryOnDevice) => $listenResult');
          if (started) {
            if (!tryOnDevice && _preferOnDevice) {
              _preferOnDevice = false;
              debugPrint('Falling back to online STT for this device');
            }
            listenStarted = true;
            if (mounted) setState(() => _debugListenStarted = 'ok(onDevice=$tryOnDevice)');
            break;
          }
          try { await _speech.stop(); } catch (_) {}
        } catch (e) {
          debugPrint('listen(onDevice: $tryOnDevice) error: $e');
          if (mounted) setState(() => _debugLastError = '$e');
          try { await _speech.stop(); } catch (_) {}
          continue;
        }
      }

      if (!listenStarted) {
        if (mounted) {
          setState(() {
            _listening = false;
            _feedback = '语音识别未启动，请检查系统语音服务';
            _debugListenStarted = 'failed';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('语音识别未启动，请检查麦克风权限和系统语音服务'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 安全超时：无论如何 18 秒后强制结束
      _safetyTimeout = Timer(const Duration(seconds: 18), () {
        if (!_attemptFinalized && _listening) {
          debugPrint('Safety timeout triggered');
          _finalizeAttempt();
        }
      });
    } catch (e) {
      debugPrint('Speech listen error: $e');
      if (mounted) {
        setState(() {
          _listening = false;
          _feedback = '录音启动失败，请重试';
          _debugLastError = '$e';
        });
      }
    }
  }

  Future<void> _processResult(String recognized) async {
    final s = _sentences[_index];
    final sentence = (s['sentence'] as String).trim();
    final reading = (s['reading'] as String).trim();
    final rec = recognized.trim();

    // 有 reading 时做本地快速评分；没有时只显示识别结果等 AI
    final hasReading = reading.isNotEmpty;
    int localScore;
    if (hasReading) {
      final scores = [
        _calcScore(sentence, rec),
        _calcScore(reading, rec),
      ];
      localScore = scores.reduce(max);
    } else {
      // 没有 reading，仅用 sentence 比较（可能不准，以 AI 为准）
      localScore = _calcScore(sentence, rec);
    }

    String feedback;
    if (localScore >= 90) {
      feedback = '🎉 完美！';
    } else if (localScore >= 70) {
      feedback = '👍 不错！识别:「$recognized」';
    } else if (localScore >= 40) {
      feedback = '💪 继续努力！识别:「$recognized」';
    } else {
      feedback = '🔄 再试一次！识别:「$recognized」';
    }

    setState(() { _score = localScore; _recognized = recognized; _feedback = feedback; _listening = false; _showSentence = true; _aiScoring = true; });

    try {
      final ai = await apiService.scoreSpeechRecognition(
        targetText: sentence,
        recognizedText: rec,
        referenceReading: hasReading ? reading : null,
        mode: 'listening',
      );
      if (mounted) {
        final aiScore = (ai['score'] as num?)?.toInt();
        final aiFeedback = (ai['feedback'] as String?)?.trim();
        if (aiScore != null) {
          final finalAiScore = aiScore.clamp(0, 100);
          _scores.add(finalAiScore);
          setState(() {
            _score = finalAiScore;
            _aiScoring = false;
            if (aiFeedback != null && aiFeedback.isNotEmpty) {
              _feedback = '🤖 $aiFeedback';
            }
          });
        } else {
          _scores.add(localScore);
          if (mounted) setState(() => _aiScoring = false);
        }
      }
    } catch (e) {
      debugPrint('AI scoring failed: $e');
      _scores.add(localScore);
      if (mounted) setState(() => _aiScoring = false);
    }

    final finalScore = _score ?? localScore;

    // 得分低于70分时保存到错题集
    if (finalScore < 70) {
      _saveWrongAnswer(
        question: sentence,
        yourAnswer: rec,
        correctAnswer: sentence,
        explanation: s['meaning'] as String? ?? '',
      );
    }
  }

  Future<void> _saveWrongAnswer({required String question, required String yourAnswer, required String correctAnswer, String explanation = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wrongAnswers') ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.add({
      'source': 'listening',
      'question': question,
      'yourAnswer': yourAnswer,
      'correctAnswer': correctAnswer,
      'explanation': explanation,
      'time': DateTime.now().toIso8601String(),
    });
    while (list.length > 500) { list.removeAt(0); }
    await prefs.setString('wrongAnswers', jsonEncode(list));
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
    _score = null; _recognized = ''; _feedback = ''; _showSentence = false; _inputCtrl.clear(); _inputMode = false; _aiScoring = false;
  }

  @override
  void dispose() {
    _resultDebounce?.cancel();
    _safetyTimeout?.cancel();
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
        title: const Text('🎧 听力学习', style: TextStyle(fontWeight: FontWeight.w800)),
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

        if (_showSttDebug) ...[
          _buildSttDebugBar(cs),
          const SizedBox(height: 12),
        ],

        // 录音按钮
          GestureDetector(
              onTap: _toggleRecord,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: _listening ? Colors.red : cs.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    if (_listening) BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)
                  ]
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(_listening ? '⏹ 点击 停止录音' : '🎙️ 点击 录音比对', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
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
          if (_aiScoring) ...[
            Text('AI 评分中…', style: TextStyle(fontSize: 13, color: cs.outline)),
            const SizedBox(height: 4),
            const SizedBox(height: 4, child: LinearProgressIndicator()),
            const SizedBox(height: 8),
          ],
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
                if (hasFurigana(s['reading']))
                  FuriganaText(text: s['reading'], fontSize: 13, color: cs.outline, fontWeight: FontWeight.normal, textAlign: TextAlign.left)
                else
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

  Widget _buildSttDebugBar(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('STT DEBUG', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('locale: ${_speechLocaleId ?? 'system-default'}, onDevice: $_preferOnDevice'),
            Text('available: $_speechAvailable, listening: $_listening, started: $_debugListenStarted'),
            Text('status: $_debugStatus'),
            Text('result: $_debugPartial'),
            Text('error: $_debugLastError'),
          ],
        ),
      ),
    );
  }
}
