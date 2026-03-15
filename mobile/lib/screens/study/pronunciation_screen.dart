import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:dio/dio.dart' as dio;
import '../../services/api_service.dart';
import '../../config/app_config.dart';
import '../../models/models.dart';
import '../../utils/japanese_text_utils.dart';
import '../../utils/tts_helper.dart';
import '../../services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PronunciationScreen extends StatefulWidget {
  const PronunciationScreen({super.key});
  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen> {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();

  List<VocabularyModel> _words = [];
  int _index = 0;
  String _level = 'N5';
  bool _loading = true;
  bool _listening = false;
  bool _speechAvailable = false;
  String? _recordingPath;
  bool _uploading = false;

  // scoring
  int? _score;
  String _recognized = '';
  String _feedback = '';
  final List<int> _scores = [];

  // recording history
  List<Map<String, dynamic>> _recordingHistory = [];
  bool _historyLoading = false;

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

  Future<void> _playAudioSlow() async {
    if (_words.isEmpty) return;
    try {
      try { await _tts.setLanguage('ja-JP'); } catch (_) {}
      await _tts.setVolume(1.0);
      final prefs = await SharedPreferences.getInstance();
      final slowRate = prefs.getDouble('slow_speed') ?? 0.5;
      await _tts.setSpeechRate(slowRate * 0.5);
      final result = await _tts.speak(_ttsText(_words[_index]));
      await _tts.setSpeechRate(0.5);
      if (result != 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音引擎不可用，请检查系统TTS设置'), duration: Duration(seconds: 3)),
        );
      }
    } catch (e) {
      await _tts.setSpeechRate(0.5);
      debugPrint('TTS speak error: $e');
    }
  }

  String _lastRecognized = '';

  Future<void> _toggleRecord() async {
    if (_listening) {
      await _speech.stop();
      // Process whatever was recognized so far
      if (_score == null && _lastRecognized.isNotEmpty) {
        _processResult(_lastRecognized);
      } else {
        setState(() => _listening = false);
      }
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

    // 初始化语音识别（每次都重试，因为权限状态可能改变）
    if (!_speechAvailable) {
      _speechAvailable = await _speech.initialize(
        onError: (error) => debugPrint('Speech init error: $error'),
        onStatus: (status) => debugPrint('Speech status: $status'),
      );
    }
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别不可用，请检查系统设置或安装 Google 语音服务')),
        );
      }
      return;
    }
    _lastRecognized = '';
    setState(() { _listening = true; _score = null; _recognized = ''; _feedback = ''; _recordingPath = null; });

    // 注意：不再同时开启 AudioRecorder，避免与 speech_to_text 争抢麦克风
    // 语音识别结束后可通过「录制回放」按钮单独录音

    try {
      // 设置状态监听器（在 listen 之前注册）
      _speech.statusListener = (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted && _listening && _score == null && _lastRecognized.isNotEmpty) {
            _processResult(_lastRecognized);
          } else if (mounted && _listening) {
            setState(() { _listening = false; _feedback = '未检测到语音，请靠近麦克风重试'; });
          }
        }
      };

      await _speech.listen(
        localeId: 'ja_JP',
        onResult: (result) {
          _lastRecognized = result.recognizedWords;
          if (result.finalResult) {
            _processResult(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        onSoundLevelChange: null,
      );
    } catch (e) {
      debugPrint('Speech listen error: $e');
      if (mounted) {
        setState(() { _listening = false; _feedback = '录音启动失败，请重试'; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('录音启动失败：$e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  /// 单独录制回放音频（在语音识别完成后调用，不会与 speech_to_text 冲突）
  bool _isRecordingPlayback = false;
  Future<void> _recordPlayback() async {
    if (_isRecordingPlayback) {
      // 停止录制
      try {
        if (await _recorder.isRecording()) {
          final path = await _recorder.stop();
          if (path != null && await File(path).exists()) {
            setState(() { _recordingPath = path; _isRecordingPlayback = false; });
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 录音完成'), duration: Duration(seconds: 1)));
            return;
          }
        }
      } catch (e) {
        debugPrint('Stop recording error: $e');
      }
      setState(() => _isRecordingPlayback = false);
      return;
    }

    final micGranted = await PermissionService.requestMicrophonePermission();
    if (!micGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要麦克风权限')));
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final recDir = Directory('${dir.path}/recordings');
      if (!await recDir.exists()) await recDir.create(recursive: true);
      final w = _words[_index];
      final name = cleanWord(w.word).replaceAll(RegExp(r'[^\w\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]'), '');
      final filePath = '${recDir.path}/pron_${name}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      if (await _recorder.hasPermission()) {
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
          path: filePath,
        );
        setState(() => _isRecordingPlayback = true);
        // 自动 3 秒后停止
        Future.delayed(const Duration(seconds: 3), () {
          if (_isRecordingPlayback && mounted) _recordPlayback();
        });
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('录音权限不可用')));
      }
    } catch (e) {
      debugPrint('Audio recorder start error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('录音失败：$e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _playRecording() async {
    if (_recordingPath == null) return;
    try {
      final file = File(_recordingPath!);
      if (!await file.exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('录音文件不存在')));
        setState(() => _recordingPath = null);
        return;
      }
      await _audioPlayer.setFilePath(_recordingPath!);
      await _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('回放失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _uploadRecording() async {
    if (_recordingPath == null || _score == null) return;
    setState(() => _uploading = true);
    try {
      final w = _words[_index];
      final file = File(_recordingPath!);
      if (!await file.exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('录音文件不存在')));
        return;
      }
      final formData = dio.FormData.fromMap({
        'audio': await dio.MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
        'word': cleanWord(w.word),
        'reading': cleanReading(w.reading),
        'score': _score.toString(),
      });
      final res = await apiService.dio.post('/pronunciation/recording', data: formData);
      if (mounted) {
        final success = res.data is Map && res.data['success'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '✅ 录音已保存到云端' : '上传失败'), duration: const Duration(seconds: 2)),
        );
        if (success) _loadRecordingHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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

  Future<void> _loadRecordingHistory() async {
    setState(() => _historyLoading = true);
    try {
      final res = await apiService.dio.get('/pronunciation/recordings');
      final data = res.data;
      if (data is Map && data['recordings'] is List) {
        setState(() => _recordingHistory = List<Map<String, dynamic>>.from(data['recordings']));
      }
    } catch (e) {
      debugPrint('Load recording history error: $e');
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _playHistoryRecording(String audioUrl) async {
    try {
      final fullUrl = AppConfig.serverRoot + audioUrl;
      final localPath = await apiService.downloadToTempFile(fullUrl);
      await _audioPlayer.setFilePath(localPath);
      await _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _deleteHistoryRecording(String id) async {
    try {
      await apiService.dio.delete('/pronunciation/recording/$id');
      setState(() => _recordingHistory.removeWhere((r) => r['id'] == id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已删除'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _prev() {
    if (_index > 0) setState(() { _index--; _score = null; _recognized = ''; _feedback = ''; _recordingPath = null; });
  }

  void _next() {
    if (_index < _words.length - 1) setState(() { _index++; _score = null; _recognized = ''; _feedback = ''; _recordingPath = null; });
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _recorder.dispose();
    _audioPlayer.dispose();
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
                const SizedBox(height: 20),
                // Recording history
                _buildRecordingHistory(cs),
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
        Text(cleanWord(w.word), style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: cs.primary)),
        const SizedBox(height: 4),
        Text(cleanReading(w.reading).isNotEmpty ? cleanReading(w.reading) : _ttsText(w), style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant)),
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

        // Record button
        FilledButton.icon(
          onPressed: _toggleRecord,
          icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(_listening ? '停止识别' : '🎙️ 语音识别'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: _listening ? Colors.red : cs.primary,
          ),
        ),
        if (_listening)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('🔴 正在聆听…请朗读', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
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
              const SizedBox(height: 12),
              // 录制回放按钮（在语音识别结束后单独录音，避免麦克风冲突）
              if (_recordingPath == null)
                OutlinedButton.icon(
                  onPressed: _isRecordingPlayback ? _recordPlayback : _recordPlayback,
                  icon: Icon(_isRecordingPlayback ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                      size: 18, color: _isRecordingPlayback ? Colors.red : Colors.deepOrange),
                  label: Text(_isRecordingPlayback ? '停止录制 (3s)' : '🎤 录制回放'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    foregroundColor: Colors.deepOrange,
                    side: BorderSide(color: _isRecordingPlayback ? Colors.red : Colors.deepOrange),
                  ),
                ),
              if (_recordingPath != null) ...[
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  OutlinedButton.icon(
                    onPressed: _playRecording,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('回放录音'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _uploadRecording,
                    icon: _uploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: Text(_uploading ? '上传中…' : '保存录音'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      foregroundColor: Colors.teal,
                      side: const BorderSide(color: Colors.teal),
                    ),
                  ),
                ]),
              ],
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

  Widget _buildRecordingHistory(ColorScheme cs) {
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
        Row(children: [
          Expanded(child: Text('🎧 录音历史', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface))),
          SizedBox(
            height: 30,
            child: OutlinedButton(
              onPressed: _historyLoading ? null : _loadRecordingHistory,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _historyLoading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('刷新', style: TextStyle(fontSize: 12)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (_recordingHistory.isEmpty && !_historyLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('点击"刷新"加载录音历史', style: TextStyle(fontSize: 13, color: cs.outline)),
            ),
          ),
        if (_recordingHistory.isNotEmpty)
          ...List.generate(min(_recordingHistory.length, 20), (i) {
            final r = _recordingHistory[i];
            final score = r['score'] as num?;
            final scoreColor = (score ?? 0) >= 80
                ? const Color(0xFF10b981)
                : (score ?? 0) >= 50
                    ? const Color(0xFFf59e0b)
                    : Colors.red;
            final createdAt = DateTime.tryParse(r['created_at'] ?? '');
            final timeStr = createdAt != null
                ? '${createdAt.month}/${createdAt.day} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
                : '';
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: i < min(_recordingHistory.length, 20) - 1
                    ? Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)))
                    : null,
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['word'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    Text('${r['reading'] ?? ''} · $timeStr', style: TextStyle(fontSize: 11, color: cs.outline)),
                  ]),
                ),
                Text(
                  score != null ? '$score' : '-',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scoreColor),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 32, height: 32,
                  child: IconButton(
                    onPressed: () => _playHistoryRecording(r['audio_url'] ?? ''),
                    icon: Icon(Icons.play_arrow_rounded, size: 18, color: cs.primary),
                    padding: EdgeInsets.zero,
                  ),
                ),
                SizedBox(
                  width: 32, height: 32,
                  child: IconButton(
                    onPressed: () => _deleteHistoryRecording(r['id'] ?? ''),
                    icon: const Icon(Icons.close_rounded, size: 16, color: Colors.red),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ]),
            );
          }),
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
