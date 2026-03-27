import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:dio/dio.dart' as dio;
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
  bool _attemptFinalized = false;

  // ── 文字输入 ──
  final TextEditingController _inputCtrl = TextEditingController();
  bool _inputMode = false;

  // ── 录音文件（用于保存/回放）──
  final AudioRecorder _recorder = AudioRecorder();
  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();
  bool _concurrentRecording = false;
  String? _recordingPath;
  bool _uploading = false;
  String? _lastUploadedRecordingPath;

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
      onError: (error) => debugPrint('Speech init error: $error'),
      onStatus: (status) => debugPrint('Speech init status: $status'),
    );
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
      await _stopConcurrentRecording();
      if (!_attemptFinalized && _score == null && _lastRecognized.isNotEmpty) {
        _attemptFinalized = true;
        _processResult(_lastRecognized);
      } else {
        setState(() => _listening = false);
      }
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
    await _speech.stop();
    await _speech.cancel();

    _speechAvailable = await _speech.initialize(
      onError: (error) => debugPrint('Speech init error: $error'),
      onStatus: (status) => debugPrint('Speech init status: $status'),
    );
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
    setState(() {
      _listening = true;
      _score = null;
      _recognized = '';
      _feedback = '';
      _inputMode = false;
      _inputCtrl.clear();
      _recordingPath = null;
      _lastUploadedRecordingPath = null;
    });
    try {
      _speech.statusListener = (status) {
        if ((status == 'done' || status == 'notListening') && mounted && _listening && !_attemptFinalized) {
          _attemptFinalized = true;
          _stopConcurrentRecording().then((_) {
            if (_score == null && _lastRecognized.isNotEmpty) {
              _processResult(_lastRecognized);
            } else {
              setState(() { _listening = false; _feedback = '未检测到语音，请靠近麦克风重试'; });
            }
          });
        }
      };

      await _speech.listen(
        localeId: 'ja_JP',
        onResult: (result) {
          _lastRecognized = result.recognizedWords;
          if (result.finalResult && !_attemptFinalized) {
            _attemptFinalized = true;
            _processResult(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
      );

      await _startConcurrentRecording();
    } catch (e) {
      debugPrint('Speech listen error: $e');
      await _stopConcurrentRecording();
      if (mounted) {
        setState(() { _listening = false; _feedback = '录音启动失败，请重试'; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('录音启动失败：$e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _processResult(String recognized) async {
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

    try {
      final ai = await apiService.scoreSpeechRecognition(
        targetText: sentence,
        recognizedText: rec,
        referenceReading: reading.isNotEmpty ? reading : null,
        mode: 'listening',
      );
      if (mounted) {
        final aiScore = (ai['score'] as num?)?.toInt();
        final aiFeedback = (ai['feedback'] as String?)?.trim();
        if (aiScore != null) {
          setState(() {
            _score = aiScore.clamp(0, 100);
            if (aiFeedback != null && aiFeedback.isNotEmpty) {
              _feedback = '🤖 $aiFeedback';
            }
          });
        }
      }
    } catch (_) {
      // ignore AI failures and keep local score
    }

    final finalScore = _score ?? score;

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

  Future<void> _startConcurrentRecording() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recDir = Directory('${dir.path}/recordings');
      if (!await recDir.exists()) await recDir.create(recursive: true);
      final filePath = '${recDir.path}/listening_${DateTime.now().millisecondsSinceEpoch}.m4a';
      if (await _recorder.hasPermission()) {
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
          path: filePath,
        );
        _concurrentRecording = true;
      }
    } catch (_) {
      _concurrentRecording = false;
    }
  }

  Future<void> _stopConcurrentRecording() async {
    if (!_concurrentRecording) return;
    try {
      if (await _recorder.isRecording()) {
        final path = await _recorder.stop();
        if (path != null && await File(path).exists()) {
          final fileSize = await File(path).length();
          if (fileSize > 1024 && mounted) {
            setState(() {
              _recordingPath = path;
              _lastUploadedRecordingPath = null;
            });
          }
        }
      }
    } catch (_) {
      // ignore
    } finally {
      _concurrentRecording = false;
    }
  }

  Future<void> _playRecording() async {
    if (_recordingPath == null) return;
    try {
      final file = File(_recordingPath!);
      if (!await file.exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('录音文件不存在')));
        return;
      }
      await _audioPlayer.stop();
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
    if (_recordingPath == null) return;
    if (_lastUploadedRecordingPath == _recordingPath) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该录音已保存'), duration: Duration(seconds: 1)),
        );
      }
      return;
    }

    setState(() => _uploading = true);
    try {
      final s = _sentences[_index];
      final file = File(_recordingPath!);
      if (!await file.exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('录音文件不存在')));
        return;
      }
      final formData = dio.FormData.fromMap({
        'audio': await dio.MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
        'sentence': (s['sentence'] as String?) ?? '',
        'reading': (s['reading'] as String?) ?? '',
        if (_score != null) 'score': _score.toString(),
      });
      final res = await apiService.dio.post('/pronunciation/listening-recording', data: formData);
      if (mounted) {
        final success = res.data is Map && res.data['success'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '✅ 录音已保存' : '保存失败'), duration: const Duration(seconds: 2)),
        );
        if (success) {
          _lastUploadedRecordingPath = _recordingPath;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
    if (_concurrentRecording) {
      _recorder.stop().catchError((_) => null);
    }
    _recorder.dispose();
    _audioPlayer.dispose();
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
          if (_recordingPath != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _playRecording,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('回放录音'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _uploading ? null : _uploadRecording,
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: const Text('保存录音'),
                ),
                if (_uploading)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ],
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
}
