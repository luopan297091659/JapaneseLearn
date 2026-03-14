import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/audio_player_widget.dart';

class ListeningExerciseScreen extends StatefulWidget {
  const ListeningExerciseScreen({super.key});
  @override
  State<ListeningExerciseScreen> createState() => _ListeningExerciseScreenState();
}

class _ListeningExerciseScreenState extends State<ListeningExerciseScreen> {
  // ── 设置阶段 ──
  bool _started = false;
  String _level = 'N5';
  int _count = 10;

  // ── 练习阶段 ──
  List<ListeningExerciseQuestion> _questions = [];
  int _current = 0;
  bool _loading = false;
  bool _answered = false;
  String? _selectedAnswer;
  String? _error;
  bool _showSentence = false;
  DateTime? _startTime;

  // ── TTS ──
  late FlutterTts _tts;
  bool _ttsReady = false;
  bool _ttsPlaying = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    try {
      await _tts.setLanguage('ja-JP');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
      _tts.setStartHandler(() { if (mounted) setState(() => _ttsPlaying = true); });
      _tts.setCompletionHandler(() { if (mounted) setState(() => _ttsPlaying = false); });
      _tts.setCancelHandler(() { if (mounted) setState(() => _ttsPlaying = false); });
      _tts.setErrorHandler((_) { if (mounted) setState(() => _ttsPlaying = false); });
      setState(() => _ttsReady = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _startExercise() async {
    setState(() { _loading = true; _error = null; });
    try {
      final questions = await apiService.getListeningExercises(
        level: _level,
        count: _count,
      );
      if (questions.isEmpty) {
        setState(() { _loading = false; _error = '该级别暂无可用的听力练习题目'; });
        return;
      }
      setState(() {
        _questions = questions;
        _current = 0;
        _started = true;
        _loading = false;
        _answered = false;
        _selectedAnswer = null;
        _showSentence = false;
        _startTime = DateTime.now();
      });
      _playCurrentQuestion();
    } catch (e) {
      setState(() { _loading = false; _error = '获取题目失败: $e'; });
    }
  }

  void _playCurrentQuestion() {
    if (_current >= _questions.length) return;
    final q = _questions[_current];
    // 优先使用服务端音频，否则用 TTS
    if (q.audioUrl != null && q.audioUrl!.isNotEmpty) {
      // 音频由 AudioPlayerWidget 处理
    } else if (_ttsReady) {
      _tts.speak(q.sentence);
    }
  }

  void _speakSentence(String text, {double rate = 0.45}) async {
    await _tts.setSpeechRate(rate);
    await _tts.speak(text);
  }

  void _selectAnswer(String answer) {
    if (_answered) return;
    setState(() {
      _selectedAnswer = answer;
      _answered = true;
      _questions[_current].userAnswer = answer;
    });
  }

  void _nextQuestion() {
    if (_current < _questions.length - 1) {
      setState(() {
        _current++;
        _answered = false;
        _selectedAnswer = null;
        _showSentence = false;
      });
      _playCurrentQuestion();
    } else {
      _showResult();
    }
  }

  void _showResult() {
    final correctCount = _questions.where((q) => q.isCorrect).length;
    final total = _questions.length;
    final percent = (correctCount / total * 100).round();
    final duration = DateTime.now().difference(_startTime!).inSeconds;

    // 记录活动
    apiService.logActivity(
      activityType: 'listening',
      durationSeconds: duration,
      score: percent.toDouble(),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(
            percent >= 80 ? Icons.emoji_events : percent >= 60 ? Icons.thumb_up : Icons.school,
            color: percent >= 80 ? Colors.amber : percent >= 60 ? Colors.green : Colors.blue,
            size: 28,
          ),
          const SizedBox(width: 8),
          const Text('练习完成'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: percent >= 80 ? Colors.green : percent >= 60 ? Colors.orange : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text('$correctCount / $total 正确'),
            const SizedBox(height: 4),
            Text('用时 ${duration ~/ 60}分${duration % 60}秒', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Text(
              percent >= 80 ? '🎉 太棒了！听力能力很强！'
                : percent >= 60 ? '👍 不错，继续加油！'
                : '💪 多听多练，一定会进步！',
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() { _started = false; });
            },
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startExercise();
            },
            child: const Text('再练一次'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_started ? '听力测试 ($_level)' : '听力测试'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            if (_started) {
              _confirmExit();
            } else {
              context.canPop() ? context.pop() : context.go('/home');
            }
          },
        ),
        actions: _started ? [
          Center(child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              '${_current + 1} / ${_questions.length}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          )),
        ] : null,
      ),
      body: _started ? _buildExerciseBody(cs) : _buildSettingsBody(cs),
    );
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('当前练习进度将不会保存，确定退出吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('继续练习')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); setState(() => _started = false); },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  // ── 设置界面 ──────────────────────────────────────────────────────────────
  Widget _buildSettingsBody(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题图标
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primaryContainer, cs.tertiaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              Icon(Icons.hearing_rounded, size: 56, color: cs.primary),
              const SizedBox(height: 12),
              Text('听句选义', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
              const SizedBox(height: 4),
              Text('听日语例句，选出正确的中文翻译', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7))),
            ]),
          ),

          const SizedBox(height: 24),

          // 级别选择
          Text('选择级别', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['N5', 'N4', 'N3', 'N2', 'N1'].map((l) => ChoiceChip(
              label: Text(l, style: const TextStyle(fontWeight: FontWeight.bold)),
              selected: _level == l,
              onSelected: (_) => setState(() => _level = l),
              selectedColor: cs.primaryContainer,
            )).toList(),
          ),

          const SizedBox(height: 20),

          // 题目数量
          Text('题目数量', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [5, 10, 15, 20].map((n) => ChoiceChip(
              label: Text('$n题'),
              selected: _count == n,
              onSelected: (_) => setState(() => _count = n),
              selectedColor: cs.primaryContainer,
            )).toList(),
          ),

          const SizedBox(height: 32),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
            ),
            const SizedBox(height: 16),
          ],

          FilledButton.icon(
            onPressed: _loading ? null : _startExercise,
            icon: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_loading ? '加载中...' : '开始练习', style: const TextStyle(fontSize: 16)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 练习界面 ──────────────────────────────────────────────────────────────
  Widget _buildExerciseBody(ColorScheme cs) {
    final q = _questions[_current];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 进度条
          LinearProgressIndicator(
            value: (_current + 1) / _questions.length,
            backgroundColor: cs.surfaceContainerHighest,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 20),

          // 音频播放区域（紧凑两行）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Icon(Icons.headphones_rounded, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    '请仔细听这段日语',
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
                ]),
                const SizedBox(height: 10),
                // 服务端音频（如果有）
                if (q.audioUrl != null && q.audioUrl!.isNotEmpty) ...[
                  AudioPlayerWidget(audioUrl: q.audioUrl, compact: true),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 34,
                      child: FilledButton.icon(
                        onPressed: () => _speakSentence(q.sentence),
                        icon: Icon(_ttsPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                        label: Text(_ttsPlaying ? '播放中' : '播放', style: const TextStyle(fontSize: 13)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        onPressed: () => _speakSentence(q.sentence, rate: 0.25),
                        icon: const Icon(Icons.slow_motion_video_rounded, size: 18),
                        label: const Text('慢速', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 题目提示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.quiz_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '这段日语是什么意思？',
                style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
              )),
              // 来源标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: q.type == 'grammar' ? Colors.blue.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  q.type == 'grammar' ? '语法' : '词汇',
                  style: TextStyle(
                    fontSize: 11,
                    color: q.type == 'grammar' ? Colors.blue : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // 选项
          ...q.options.map((option) {
            final isSelected = _selectedAnswer == option;
            final isCorrect = option == q.correctAnswer;

            Color? bgColor;
            Color? borderColor;
            if (_answered) {
              if (isCorrect) {
                bgColor = Colors.green.withValues(alpha: 0.1);
                borderColor = Colors.green;
              } else if (isSelected && !isCorrect) {
                bgColor = Colors.red.withValues(alpha: 0.1);
                borderColor = Colors.red;
              }
            } else if (isSelected) {
              bgColor = cs.primaryContainer;
              borderColor = cs.primary;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => _selectAnswer(option),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor ?? cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor ?? cs.outlineVariant,
                      width: isSelected || (_answered && isCorrect) ? 2 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(
                      option,
                      style: TextStyle(
                        fontSize: option.length > 30 ? 13 : 15,
                        fontWeight: isSelected || (_answered && isCorrect) ? FontWeight.bold : FontWeight.normal,
                        height: 1.4,
                      ),
                    )),
                    if (_answered && isCorrect)
                      const Icon(Icons.check_circle, color: Colors.green, size: 22),
                    if (_answered && isSelected && !isCorrect)
                      const Icon(Icons.cancel, color: Colors.red, size: 22),
                  ]),
                ),
              ),
            );
          }),

          // 答错后显示原文解析
          if (_answered) ...[
            const SizedBox(height: 12),

            // 显示/隐藏原文按钮
            OutlinedButton.icon(
              onPressed: () => setState(() => _showSentence = !_showSentence),
              icon: Icon(_showSentence ? Icons.visibility_off : Icons.visibility),
              label: Text(_showSentence ? '隐藏原文' : '查看原文'),
            ),

            if (_showSentence) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 日语原文
                    Row(children: [
                      Icon(Icons.translate, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text('原文', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary, fontSize: 13)),
                    ]),
                    const SizedBox(height: 6),
                    Text(q.sentence, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),

                    if (q.reading != null && q.reading!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(q.reading!, style: TextStyle(color: cs.outline, fontSize: 14)),
                    ],

                    const Divider(height: 20),

                    // 中文翻译
                    Row(children: [
                      Icon(Icons.g_translate, size: 16, color: cs.tertiary),
                      const SizedBox(width: 6),
                      Text('翻译', style: TextStyle(fontWeight: FontWeight.bold, color: cs.tertiary, fontSize: 13)),
                    ]),
                    const SizedBox(height: 6),
                    Text(q.correctAnswer, style: const TextStyle(fontSize: 15)),

                    // 来源信息
                    if (q.grammarTitle != null || q.word != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        q.grammarTitle != null ? '语法: ${q.grammarTitle}' : '单词: ${q.word}',
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // 下一题按钮
            FilledButton.icon(
              onPressed: _nextQuestion,
              icon: Icon(_current < _questions.length - 1 ? Icons.skip_next_rounded : Icons.done_all_rounded),
              label: Text(
                _current < _questions.length - 1 ? '下一题' : '查看结果',
                style: const TextStyle(fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
