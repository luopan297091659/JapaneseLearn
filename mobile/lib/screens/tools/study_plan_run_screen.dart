import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';

class StudyPlanRunScreen extends StatefulWidget {
  final String planId;
  final String? stage;

  const StudyPlanRunScreen({
    super.key,
    required this.planId,
    this.stage,
  });

  @override
  State<StudyPlanRunScreen> createState() => _StudyPlanRunScreenState();
}

class _StudyPlanRunScreenState extends State<StudyPlanRunScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _plan;
  List<Map<String, dynamic>> _queue = [];
  int _index = 0;

  final Map<String, VocabularyModel> _vocabCache = {};
  final Map<String, GrammarLessonModel> _grammarCache = {};

  bool _submitting = false;

  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
    _init();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ja-JP');
    await _tts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  String _planType(Map<String, dynamic> plan) {
    if (plan['includeVocabulary'] == true) return 'vocabulary';
    if (plan['includeGrammar'] == true) return 'grammar';
    if (plan['includeAnki'] == true) return 'anki';
    return 'vocabulary';
  }

  String _planLevel(Map<String, dynamic> plan) {
    if (plan['includeVocabulary'] == true) return (plan['vocabularyLevel'] ?? 'N5').toString();
    if (plan['includeGrammar'] == true) return (plan['grammarLevel'] ?? 'N5').toString();
    return 'N5';
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('study_plans_v1') ?? '[]';
      final plans = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final plan = plans.firstWhere(
        (p) => p['id']?.toString() == widget.planId,
        orElse: () => <String, dynamic>{},
      );

      if (plan.isEmpty) {
        setState(() {
          _error = '学习计划不存在';
          _loading = false;
        });
        return;
      }

      _plan = plan;

      await apiService.getStudyPlanToday();
      await apiService.startStudyPlanDay();

      final level = _planLevel(plan);
      final queueRes = await apiService.getStudyPlanQueue(level: level);
      final rawQueue = (queueRes['queue'] as List<dynamic>? ?? const []).cast<dynamic>();
      final planType = _planType(plan);

      final filtered = rawQueue
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((item) {
            if (planType == 'anki') return false;
            if (item['card_type']?.toString() != planType) return false;
            final stage = widget.stage;
            if (stage == null || stage.isEmpty) return true;
            if (stage == 'new') return (item['source']?.toString() == 'new');
            if (stage == 'learning') {
              final source = item['source']?.toString() ?? '';
              return source == 'new' || source == 'review' || source == 'difficult';
            }
            return true;
          })
          .toList();

      _queue = filtered;
      _index = 0;
      if (_queue.isNotEmpty) {
        await _ensureCurrentLoaded();
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载学习队列失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _ensureCurrentLoaded() async {
    if (_index >= _queue.length) return;
    final item = _queue[_index];
    final cardType = item['card_type']?.toString() ?? '';
    final refId = item['ref_id']?.toString() ?? '';
    if (refId.isEmpty) return;

    if (cardType == 'vocabulary' && !_vocabCache.containsKey(refId)) {
      final model = await apiService.getVocabularyById(refId);
      _vocabCache[refId] = model;
    }
    if (cardType == 'grammar' && !_grammarCache.containsKey(refId)) {
      final model = await apiService.getGrammarLesson(refId);
      _grammarCache[refId] = model;
    }
  }

  Future<void> _submitAnswer(String answer) async {
    if (_submitting || _index >= _queue.length) return;
    setState(() => _submitting = true);

    try {
      final item = _queue[_index];
      final cardType = item['card_type']?.toString() ?? '';
      final refId = item['ref_id']?.toString() ?? '';
      if (cardType.isEmpty || refId.isEmpty) {
        setState(() => _submitting = false);
        return;
      }

      await apiService.submitStudyPlanAnswer(
        cardType: cardType,
        refId: refId,
        answer: answer,
      );

      _index += 1;
      if (_index < _queue.length) {
        await _ensureCurrentLoaded();
        // 切换到下一张词汇卡时自动播放音频
        final nextItem = _queue[_index];
        if (nextItem['card_type']?.toString() == 'vocabulary') {
          final nextRefId = nextItem['ref_id']?.toString() ?? '';
          final nextVocab = _vocabCache[nextRefId];
          if (nextVocab != null) _tts.speak(nextVocab.word);
        }
      }

      if (!mounted) return;
      setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('提交失败：$e'),
        ),
      );
    }
  }

  Future<void> _finishDay() async {
    try {
      await apiService.finishStudyPlanDay();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('今日学习已完成，干得漂亮！'),
        ),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final planName = _plan?['name']?.toString() ?? '学习计划';

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('计划学习中')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('计划学习中')),
        body: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
      );
    }

    if (_planType(_plan!) == 'anki') {
      return Scaffold(
        appBar: AppBar(title: const Text('计划学习中')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 56),
                const SizedBox(height: 12),
                const Text('Anki 计划请使用本地词库学习页继续执行'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go('/local-vocab?planId=${widget.planId}'),
                  child: const Text('前往 Anki 学习'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final completed = _index;
    final total = _queue.length;
    final done = completed >= total;

    return Scaffold(
      appBar: AppBar(
        title: Text('计划学习 · $planName'),
      ),
      body: done
          ? _buildDoneView(context)
          : _buildRunView(context, completed: completed, total: total),
    );
  }

  Widget _buildDoneView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 72, color: Colors.amber),
            const SizedBox(height: 12),
            const Text('本轮计划学习完成', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('继续保持每天一点点，记忆会越来越稳。'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _finishDay,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('完成今日任务'),
            ),
          ],
        ),
      ),
    );
  }

  String get _leftSwipeText {
    final stage = widget.stage ?? '';
    if (stage == 'review') return '不认识 / 没掌握';
    if (stage == 'mastered') return '未掌握';
    return '不认识 / 没掌握';
  }

  String get _rightSwipeText {
    final stage = widget.stage ?? '';
    if (stage == 'review') return '已掌握';
    if (stage == 'mastered') return '已掌握';
    return '认识 / 已完成';
  }

  double _dragOffset = 0;

  Widget _buildRunView(BuildContext context, {required int completed, required int total}) {
    final item = _queue[_index];
    final cardType = item['card_type']?.toString() ?? '';
    final refId = item['ref_id']?.toString() ?? '';
    final progress = total > 0 ? (completed / total) : 0.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final dragRatio = (_dragOffset / (screenWidth * 0.4)).clamp(-1.0, 1.0);

    Color? cardTint;
    IconData? overlayIcon;
    String? overlayText;
    Color overlayColor = Colors.transparent;
    if (dragRatio > 0.05) {
      cardTint = Colors.green.shade100.withValues(alpha: dragRatio.abs());
      overlayIcon = Icons.check_circle_rounded;
      overlayText = _rightSwipeText;
      overlayColor = Colors.green;
    } else if (dragRatio < -0.05) {
      cardTint = Colors.red.shade100.withValues(alpha: dragRatio.abs());
      overlayIcon = Icons.close_rounded;
      overlayText = _leftSwipeText;
      overlayColor = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('第 ${completed + 1} / $total 项', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: _submitting
                  ? null
                  : (details) {
                      setState(() => _dragOffset += details.delta.dx);
                    },
              onHorizontalDragEnd: _submitting
                  ? null
                  : (details) async {
                      final threshold = screenWidth * 0.5;
                      if (_dragOffset.abs() > threshold) {
                        final answer = _dragOffset > 0 ? 'known' : 'unknown';
                        setState(() => _dragOffset = 0);
                        await _submitAnswer(answer);
                      } else {
                        setState(() => _dragOffset = 0);
                      }
                    },
              onHorizontalDragCancel: () => setState(() => _dragOffset = 0),
              child: AnimatedContainer(
                duration: _dragOffset == 0 ? const Duration(milliseconds: 200) : Duration.zero,
                transform: Matrix4.translationValues(_dragOffset, 0, 0),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: cardTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: cardType == 'vocabulary'
                          ? _buildVocabCard(refId)
                          : _buildGrammarCard(refId),
                    ),
                    if (overlayText != null)
                      Positioned(
                        top: 16,
                        right: overlayColor == Colors.red ? null : 16,
                        left: overlayColor == Colors.red ? 16 : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: overlayColor.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(overlayText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(width: 4),
                              Icon(overlayIcon, color: Colors.white, size: 16),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swipe_left_rounded, size: 16, color: Colors.red.shade300),
              const SizedBox(width: 4),
              Text('左滑：$_leftSwipeText', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
              const SizedBox(width: 16),
              Icon(Icons.swipe_right_rounded, size: 16, color: Colors.green.shade400),
              const SizedBox(width: 4),
              Text('右滑：$_rightSwipeText', style: TextStyle(fontSize: 12, color: Colors.green.shade500)),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildVocabCard(String refId) {
    final vocab = _vocabCache[refId];
    if (vocab == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('单词学习', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  IconButton(
                    onPressed: () => _tts.speak(vocab.word),
                    icon: const Icon(Icons.volume_up_rounded),
                    tooltip: '朗读',
                    color: Colors.blue,
                  ),
                ],
              ),
              Text(vocab.word, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(vocab.reading, style: const TextStyle(fontSize: 18, color: Colors.black54)),
              const Divider(height: 24),
              Text(vocab.meaningZh, style: const TextStyle(fontSize: 22)),
              if ((vocab.exampleSentence ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('例句：${vocab.exampleSentence}', style: const TextStyle(fontSize: 14)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrammarCard(String refId) {
    final grammar = _grammarCache[refId];
    if (grammar == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final title = (grammar.titleZh ?? grammar.title).trim();
    final examples = grammar.examples;
    final exerciseCount = examples.where(_isValidExample).length.clamp(0, 3);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('语法学习', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(grammar.pattern, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(title, style: const TextStyle(fontSize: 18, color: Colors.black54)),
                    ],
                    const Divider(height: 24),
                    Text(grammar.explanationZh ?? grammar.explanation ?? '', style: const TextStyle(fontSize: 16)),
                    if (examples.where(_isValidExample).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('例句：${examples.where(_isValidExample).first.sentence}', style: const TextStyle(fontSize: 14)),
                    ],
                  ],
                ),
              ),
            ),
            if (examples.where(_isValidExample).isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showGrammarExercise(grammar, exerciseCount),
                  icon: const Icon(Icons.quiz_outlined),
                  label: Text('进入固定${exerciseCount}题练习'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 判断是否为有效例句（排除分类标签等非例句内容）
  bool _isValidExample(GrammarExampleModel ex) {
    final s = ex.sentence.trim();
    final m = ex.meaningZh.trim();
    if (s.length < 6 || m.length < 4) return false;
    // 排除纯分类标签（如 ②II类动词）
    if (RegExp(r'^[①②③④⑤⑥⑦⑧⑨⑩]').hasMatch(s) && s.length < 15) return false;
    // 排除纯列举（如 起[お]きる・食[た]べる...）
    if ('・'.allMatches(s).length >= 3 && !s.contains('。')) return false;
    return true;
  }

  /// 基于当前文法例句的练习（回忆模式）
  void _showGrammarExercise(GrammarLessonModel grammar, int count) {
    final examples = grammar.examples.where(_isValidExample).take(count).toList();
    if (examples.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(behavior: SnackBarBehavior.floating, content: Text('该语法暂无有效例句可练习')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GrammarExerciseSheet(grammar: grammar, examples: examples),
    );
  }
}

/// 文法例句练习 BottomSheet
class _GrammarExerciseSheet extends StatefulWidget {
  final GrammarLessonModel grammar;
  final List<GrammarExampleModel> examples;

  const _GrammarExerciseSheet({required this.grammar, required this.examples});

  @override
  State<_GrammarExerciseSheet> createState() => _GrammarExerciseSheetState();
}

class _GrammarExerciseSheetState extends State<_GrammarExerciseSheet> {
  int _current = 0;
  bool _revealed = false;
  int _correct = 0;
  bool _finished = false;

  GrammarExampleModel get _example => widget.examples[_current];

  void _reveal() => setState(() => _revealed = true);

  void _answer(bool gotIt) {
    if (gotIt) _correct++;
    if (_current + 1 >= widget.examples.length) {
      setState(() => _finished = true);
    } else {
      setState(() {
        _current++;
        _revealed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: _finished ? _buildResult(cs) : _buildQuestion(cs, scrollCtrl),
      ),
    );
  }

  Widget _buildQuestion(ColorScheme cs, ScrollController scrollCtrl) {
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '例句练习 ${_current + 1}/${widget.examples.length}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(widget.grammar.pattern, style: TextStyle(fontSize: 14, color: cs.primary)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (_current + 1) / widget.examples.length,
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('中文含义：', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(_example.meaningZh, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!_revealed) ...[
          const Text('请回忆对应的日语例句，然后点击下方按钮查看答案。',
            style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reveal,
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('显示答案'),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('日语例句：', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(_example.sentence, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (_example.reading != null && _example.reading!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_example.reading!, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _answer(false),
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: const Text('没想起来'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _answer(true),
                  icon: const Icon(Icons.check),
                  label: const Text('想起来了'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildResult(ColorScheme cs) {
    final total = widget.examples.length;
    final ratio = total > 0 ? _correct / total : 0.0;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ratio >= 0.8 ? Icons.emoji_events_rounded : Icons.thumb_up_rounded,
            size: 56,
            color: ratio >= 0.8 ? Colors.amber : cs.primary,
          ),
          const SizedBox(height: 12),
          Text('练习完成', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text('$_correct / $total 题回忆成功', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(widget.grammar.pattern, style: TextStyle(fontSize: 14, color: cs.outline)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回继续学习'),
            ),
          ),
        ],
      ),
    );
  }
}
