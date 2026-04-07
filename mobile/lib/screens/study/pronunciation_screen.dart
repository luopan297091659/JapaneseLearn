import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../utils/japanese_text_utils.dart';
import '../../widgets/furigana_text.dart';
import '../../utils/tts_helper.dart';
import '../../services/permission_service.dart';
import '../../widgets/membership_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PronunciationScreen extends StatefulWidget {
  const PronunciationScreen({super.key});
  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen> {
  static const bool _showSttDebug = kDebugMode;

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  List<VocabularyModel> _words = [];
  int _index = 0;
  String _level = 'N5';
  bool _loading = true;
  bool _listening = false;
  bool _speechAvailable = false;
  String? _speechLocaleId;
  bool _isMember = true; // optimistic default
  bool _attemptFinalized = false;
  Timer? _resultDebounce;
  Timer? _safetyTimeout;
  Timer? _earlySilenceTimer;

  // scoring
  int? _score;
  String _recognized = '';
  String _feedback = '';
  final List<int> _scores = [];
  bool _aiScoring = false;

  @override
  void initState() {
    super.initState();
    _checkMembership();
    _initTts();
    _initSpeech();
    _loadWords();
  }

  Future<void> _checkMembership() async {
    try {
      final user = await apiService.getMe();
      if (mounted) setState(() => _isMember = user.isMember);
    } catch (_) {}
  }

  Future<void> _initTts() async {
    _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
    await TtsHelper.configureForJapanese(_tts);
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

  Future<bool> _prepareSpeechSession() async {
    _resultDebounce?.cancel();
    _safetyTimeout?.cancel();
    _earlySilenceTimer?.cancel();

    // Cancel / stop any ongoing session (with timeout to avoid hangs on Samsung etc.)
    try { await _speech.cancel().timeout(const Duration(seconds: 2)); } catch (_) {}
    try { await _speech.stop().timeout(const Duration(seconds: 2)); } catch (_) {}

    // If already initialised, reuse — avoids the expensive re-init that hangs on some devices
    if (_speechAvailable && _speechLocaleId != null) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (mounted) setState(() { _debugStatus = 'ready(reused)'; });
      return true;
    }

    // Full (re)initialisation with timeout protection
    if (mounted) setState(() { _debugStatus = 'reinit'; });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await _initSpeech().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Speech init timeout/error: $e');
      _speechAvailable = false;
    }
    return _speechAvailable;
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
      // 后台预缓存所有单词音频
      final audioUrls = _words
          .where((w) => w.audioUrl != null && w.audioUrl!.isNotEmpty)
          .map((w) => w.audioUrl!);
      TtsHelper.precacheAudioUrls(audioUrls);
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
    final w = _words[_index];
    await TtsHelper.playJapaneseSmart(
      audioUrl: w.audioUrl,
      text: _ttsText(w),
      tts: _tts,
    );
  }

  Future<void> _playAudioSlow() async {
    if (_words.isEmpty) return;
    final w = _words[_index];
    await TtsHelper.playJapaneseSmart(
      audioUrl: w.audioUrl,
      text: _ttsText(w),
      tts: _tts,
      slow: true,
    );
  }

  String _lastRecognized = '';
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

  String _sttUnavailableMessage() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return '当前设备未检测到可用的系统语音识别服务。\n\n很多国内安卓手机因未安装或无法使用 Google 语音服务，点击开始识别后无法进行本地 STT 评分。\n\n建议：\n1. 检查系统是否支持语音识别\n2. 安装并启用 Google 语音服务\n3. 确认麦克风权限已开启';
      case TargetPlatform.iOS:
        return '当前设备未检测到可用的系统语音识别能力。\n\n这通常是因为系统语音识别权限未开启，或 Siri 与听写功能不可用。\n\n建议：\n1. 在系统设置中开启麦克风权限\n2. 开启语音识别权限\n3. 确认 Siri 与系统听写可正常使用';
      default:
        return '当前设备未检测到可用的系统语音识别服务，请检查麦克风权限和系统语音识别设置。';
    }
  }

  Future<void> _showSttUnavailableDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('本机语音识别不可用'),
        content: Text(_sttUnavailableMessage()),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await PermissionService.openPermissionSettings();
            },
            child: const Text('打开设置'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 统一 finalize 入口 —— 所有路径都走这里
  void _finalizeAttempt() {
    if (_attemptFinalized || !mounted) return;
    _attemptFinalized = true;
    _resultDebounce?.cancel();
    _safetyTimeout?.cancel();
    _earlySilenceTimer?.cancel();
    _speech.stop();
    if (_lastRecognized.trim().isNotEmpty) {
      _processResult(_lastRecognized);
    } else {
      if (mounted) setState(() { _listening = false; _recognized = ''; _feedback = '未检测到语音，请靠近麦克风重试'; });
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

    // 请求麦克风权限
    final micGranted = await PermissionService.requestMicrophonePermission();
    if (!micGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音，请在设置中允许')),
        );
      }
      return;
    }

    final speechReady = await _prepareSpeechSession();
    if (!speechReady) {
      if (mounted) {
        await _showSttUnavailableDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别不可用，请检查系统设置或安装 Google 语音服务')),
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
      _listening = false;
      _score = null;
      _recognized = '';
      _feedback = '';
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
            _listening &&
            !_attemptFinalized) {
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
          // 给 listen() 加超时，避免在三星等设备上挂起
          final dynamic listenResult = await _speech.listen(
            localeId: _speechLocaleId ?? 'ja-JP',
            onDevice: tryOnDevice,
            onResult: onSttResult,
            listenFor: const Duration(seconds: 10),
            pauseFor: const Duration(seconds: 3),
            onSoundLevelChange: null,
          ).timeout(const Duration(seconds: 4), onTimeout: () => false);
          final started = listenResult is bool ? listenResult : true;
          debugPrint('listen(onDevice: $tryOnDevice) => $listenResult');
          if (started) {
            // 验证 STT 是否真正启动（部分安卓设备 listen 返回成功但实际未启动）
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (!_speech.isListening && !_attemptFinalized) {
              debugPrint('Phantom listen: isListening=false after 500ms (onDevice=$tryOnDevice)');
              if (mounted) setState(() => _debugListenStarted = 'phantom(onDevice=$tryOnDevice)');
              try { await _speech.stop(); } catch (_) {}
              continue; // 尝试下一个模式
            }
            if (!tryOnDevice && _preferOnDevice) {
              _preferOnDevice = false;
              debugPrint('Falling back to online STT for this device');
            }
            listenStarted = true;
            if (mounted) {
              setState(() {
                _listening = true;
                _debugListenStarted = 'ok(onDevice=$tryOnDevice)';
              });
            }
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
        // 所有模式都失败，强制重置 _speechAvailable 以便下次重新 initialize
        _speechAvailable = false;
        _speechLocaleId = null;
        if (mounted) {
          setState(() {
            _listening = false;
            _feedback = '语音识别未启动，请检查系统语音服务';
            _debugListenStarted = 'failed';
          });
          await _showSttUnavailableDialog();
        }
        return;
      }

      // 3 秒早期静默检测：没收到任何 partial result 且 STT 已停止 → 立即报错
      _earlySilenceTimer = Timer(const Duration(seconds: 3), () {
        if (_listening && _lastRecognized.isEmpty && !_attemptFinalized && mounted) {
          if (!_speech.isListening) {
            debugPrint('Early silence: STT stopped with no results after 3s');
            _finalizeAttempt();
          }
        }
      });

      // 安全超时：无论如何 13 秒后强制结束
      _safetyTimeout = Timer(const Duration(seconds: 13), () {
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
    final w = _words[_index];
    final reading = cleanReading(w.reading);
    final word = cleanWord(w.word);
    final tts = _ttsText(w);
    final rec = recognized.trim();

    // 有 reading 时做本地快速评分；没有 reading 时直接等 AI 评分
    final hasReading = reading.isNotEmpty;
    int? localScore;
    if (hasReading) {
      final scores = [
        _calcScore(reading, rec),
        _calcScore(word, rec),
        _calcScore(tts, rec),
      ];
      localScore = scores.reduce(max);
    }

    final target = hasReading ? reading : word;

    String feedback;
    if (localScore != null) {
      if (localScore >= 90) {
        feedback = '🎉 完美发音！';
      } else if (localScore >= 70) {
        feedback = '👍 不错！识别: 「$recognized」';
      } else if (localScore >= 40) {
        feedback = '💪 继续努力！识别: 「$recognized」，目标: 「$target」';
      } else {
        feedback = '🔄 再试一次！识别: 「$recognized」，目标: 「$target」';
      }
    } else {
      // 没有 reading，只显示识别结果，等 AI 评分
      feedback = '识别结果：「$recognized」';
    }

    setState(() {
      _score = localScore;
      _recognized = recognized;
      _feedback = feedback;
      _listening = false;
      _aiScoring = true;
    });

    try {
      final ai = await apiService.scoreSpeechRecognition(
        targetText: word,
        recognizedText: rec,
        referenceReading: hasReading ? reading : null,
        mode: 'pronunciation',
      );
      if (!mounted) return;
      final aiScore = (ai['score'] as num?)?.toInt();
      final aiFeedback = (ai['feedback'] as String?)?.trim();
      if (aiScore != null) {
        final finalScore = aiScore.clamp(0, 100);
        // 用 AI 分数更新 _scores 列表
        if (localScore != null) {
          _scores.add(localScore);
        } else {
          _scores.add(finalScore);
        }
        setState(() {
          _score = finalScore;
          _aiScoring = false;
          if (aiFeedback != null && aiFeedback.isNotEmpty) {
            _feedback = '🤖 $aiFeedback';
          }
        });
      } else {
        _scores.add(localScore ?? 0);
        if (mounted) setState(() => _aiScoring = false);
      }
    } catch (e) {
      debugPrint('AI scoring failed: $e');
      _scores.add(localScore ?? 0);
      if (mounted) {
        setState(() {
          _aiScoring = false;
          if (localScore == null) {
            _feedback = '识别结果：「$recognized」（AI评分暂不可用）';
          }
        });
      }
    }
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
    if (_index > 0) {
      setState(() {
        _index--;
        _score = null;
        _recognized = '';
        _feedback = '';
      });
    }
  }

  void _next() {
    if (_index < _words.length - 1) {
      setState(() {
        _index++;
        _score = null;
        _recognized = '';
        _feedback = '';
      });
    }
  }

  @override
  void dispose() {
    _resultDebounce?.cancel();
    _safetyTimeout?.cancel();
    _earlySilenceTimer?.cancel();
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
      body: MembershipGate(
        featureId: 'pronunciation',
        isMember: _isMember,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildLevelChips(cs),
                  const SizedBox(height: 20),
                  if (_words.isNotEmpty) _buildWordCard(cs),
                  const SizedBox(height: 20),
                  _buildSessionStats(cs, avgScore),
                ],
              ),
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
            labelStyle: TextStyle(
              color: active ? Colors.white : cs.onSurface,
              fontWeight: FontWeight.bold,
            ),
            onSelected: (_) => _selectLevel(l),
          ),
        );
      }).toList(),
    ));
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
        FuriganaText(text: w.word, fontSize: 48, color: cs.primary),
        const SizedBox(height: 2),
        Text(w.meaningZh, style: TextStyle(fontSize: 14, color: cs.outline)),
        const SizedBox(height: 24),

        // Play button
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: _playAudio,
            icon: const Icon(Icons.volume_up_rounded),
            label: const Text('发音'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _playAudioSlow,
            icon: const Text('🐌', style: TextStyle(fontSize: 16)),
            label: const Text('慢速'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        if (_showSttDebug) ...[
          _buildSttDebugBar(cs),
          const SizedBox(height: 12),
        ],

        // Record button
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
                    Text(_listening ? '⏹ 点击 停止识别' : '🎙️ 点击 开始识别', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          if (_listening)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('🔴 正在聆听…请朗读', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
          ),
        // Score result
        if (_score != null || _feedback.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Text(_score != null ? (_aiScoring ? 'AI 评分中…' : 'AI 评分') : '识别结果', style: TextStyle(fontSize: 13, color: cs.outline)),
              if (_aiScoring) ...[
                const SizedBox(height: 4),
                const SizedBox(height: 4, child: LinearProgressIndicator()),
              ],
              if (_score != null) ...[
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
              ],
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
