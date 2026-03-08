import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/local_db.dart';
import '../../models/models.dart';

// ─── 测验来源 ──────────────────────────────────────────────────────────────────
enum _QuizSource { server, local }

// ─── 测验题型 ──────────────────────────────────────────────────────────────────
enum _QuizType { meaning, reading }

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // ── 设置阶段 ─────────────────────────────────────────────────────────────
  bool _started = false;
  String       _level      = 'N5';
  _QuizSource  _source     = _QuizSource.server;
  _QuizType    _quizType   = _QuizType.meaning;
  int          _count      = 10;

  // ── 测验阶段 ─────────────────────────────────────────────────────────────
  List<QuizQuestionModel> _questions = [];
  int     _current  = 0;
  String? _selectedAnswer;
  bool    _answered = false;
  bool    _loading  = false;
  String? _error;
  DateTime? _startTime;

  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _startQuiz() async {
    setState(() { _loading = true; _error = null; });
    try {
      List<QuizQuestionModel> qs;
      if (_source == _QuizSource.server) {
        // 服务端 quiz_type：meaning→vocabulary  reading→reading
        final typeStr = _quizType == _QuizType.meaning ? 'vocabulary' : 'reading';
        // level='ALL' 对服务端无效，降级为 N5
        final effectiveLevel = (_level == 'ALL') ? 'N5' : _level;
        qs = await apiService.generateQuiz(level: effectiveLevel, quizType: typeStr, count: _count);
      } else {
        qs = await _buildLocalQuiz();
      }
      if (qs.isEmpty) {
        setState(() { _loading = false; _error = _source == _QuizSource.local
            ? '本地词库没有足够的单词（至少需要 4 个），请先导入 Anki 词卡'
            : '暂无题目，服务端可能尚无当前级别的题库，请换一个级别重试'; });
        return;
      }
      setState(() {
        _questions = qs; _current = 0;
        _selectedAnswer = null; _answered = false;
        _loading = false; _started = true;
        _startTime = DateTime.now();
      });
    } catch (e) {
      setState(() { _loading = false; _error = '加载失败：${_friendlyError(e)}'; });
    }
  }

  /// 把技术性异常描述转换为用户友好的文案
  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) return '网络连接失败，请检查网络';
    if (msg.contains('TimeoutException')) return '请求超时，请稍候重试';
    if (msg.contains('401')) return '登录已过期，请重新登录';
    if (msg.contains('500')) return '服务器内部错误，请稍候重试';
    return msg.length > 80 ? '${msg.substring(0, 80)}…' : msg;
  }

  /// 从本地 Anki 词库随机生成选择题
  Future<List<QuizQuestionModel>> _buildLocalQuiz() async {
    // 多取一些以便构造去重干扰项
    final pool = await localDb.listByDeck(
      level: _level == 'ALL' ? null : _level,
      limit: max(_count * 6, 60),  // 加大池子确保去重后仍有足够干扰项
    );
    if (pool.length < 4) return [];

    final rng = Random();
    pool.shuffle(rng);

    final questions = <QuizQuestionModel>[];
    final take = min(_count, pool.length);

    for (int i = 0; i < take; i++) {
      final word = pool[i];
      final distractors = pool.where((w) => w.id != word.id).toList()..shuffle(rng);

      if (_quizType == _QuizType.meaning) {
        // 看单词 → 选中文意思（去重）
        final correctDef = word.meaningZh.trim();
        if (correctDef.isEmpty) continue; // 无中文释义跳过
        final wrongOpts = distractors
            .map((w) => w.meaningZh.trim())
            .where((m) => m.isNotEmpty && m != correctDef)
            .toSet()  // 去重
            .take(3)
            .toList();
        if (wrongOpts.length < 3) continue; // 干扰项不足则跳过该词
        final opts = [correctDef, ...wrongOpts]..shuffle(rng);
        questions.add(QuizQuestionModel(
          id:            word.id,
          questionType:  'vocabulary',
          question:      word.reading.isNotEmpty
              ? '${word.word}【${word.reading}】'
              : word.word,
          correctAnswer: correctDef,
          options:       opts,
          explanation:   '${word.word} → $correctDef',
          jlptLevel:     word.jlptLevel,
        ));
      } else {
        // 看汉字+意思 → 选假名读音（去重）
        final correctReading = word.reading.trim();
        if (correctReading.isEmpty) continue;
        final wrongOpts = distractors
            .map((w) => w.reading.trim())
            .where((r) => r.isNotEmpty && r != correctReading)
            .toSet()
            .take(3)
            .toList();
        if (wrongOpts.length < 3) continue;
        final opts = [correctReading, ...wrongOpts]..shuffle(rng);
        questions.add(QuizQuestionModel(
          id:            word.id,
          questionType:  'reading',
          question:      '${word.word}\n${word.meaningZh}',
          correctAnswer: correctReading,
          options:       opts,
          explanation:   '${word.word} 的读音是 $correctReading',
          jlptLevel:     word.jlptLevel,
        ));
      }
      if (questions.length >= _count) break;
    }

    // 若生成题目不足（词库去重后干扰项不够），如实提示
    if (questions.isEmpty) return [];
    return questions;
  }

  void _selectAnswer(String answer) {
    if (_answered) return;
    setState(() { _selectedAnswer = answer; _answered = true;
      _questions[_current].userAnswer = answer; });
  }

  void _nextQuestion() {
    if (_current + 1 >= _questions.length) {
      _submitQuiz();
    } else {
      setState(() { _current++; _selectedAnswer = null; _answered = false; });
    }
  }

  Future<void> _submitQuiz() async {
    final duration = DateTime.now().difference(_startTime ?? DateTime.now()).inSeconds;
    final correct = _questions.where((q) => q.isCorrect).length;
    final total   = _questions.length;
    final score   = total > 0 ? ((correct / total) * 100).round() : 0;

    // 记录测验学习活动
    apiService.logActivity(activityType: 'quiz', durationSeconds: duration, score: score.toDouble());

    if (_source == _QuizSource.server) {
      final typeStr = _quizType == _QuizType.meaning ? 'vocabulary' : 'reading';
      final effectiveLevel = (_level == 'ALL') ? 'N5' : _level;
      final answers = _questions.map((q) => {
        'question_id': q.id, 'user_answer': q.userAnswer ?? '', 'correct_answer': q.correctAnswer,
      }).toList();
      try {
        final result = await apiService.submitQuiz(
          level: effectiveLevel, quizType: typeStr,
          answers: answers, timeSpentSeconds: duration,
        );
        if (mounted) context.go('/quiz/result', extra: result);
        return;
      } catch (_) { /* 提交失败则降级展示本地结果 */ }
    }

    // 本地结果直接展示
    if (mounted) {
      context.go('/quiz/result', extra: {
        'score': score, 'correct': correct, 'total': total,
        'time_spent_seconds': duration,
      });
    }
  }

  // ─── 设置界面 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_started) return _buildSetupScreen(context);
    return _buildQuizScreen(context);
  }

  Widget _buildSetupScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('随机测验'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 来源选择 ─────────────────────────────────────────
                  _SectionLabel(label: '词库来源', icon: Icons.storage_rounded),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _SourceTile(
                      selected: _source == _QuizSource.server,
                      icon: Icons.cloud_rounded,
                      label: '服务器词库',
                      sub: '按JLPT级别出题',
                      onTap: () => setState(() {
                        _source = _QuizSource.server;
                        // 服务端不支持 'ALL'，自动重置为 N5
                        if (_level == 'ALL') _level = 'N5';
                      }),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _SourceTile(
                      selected: _source == _QuizSource.local,
                      icon: Icons.folder_rounded,
                      label: '我的Anki词库',
                      sub: '本地导入的词卡',
                      onTap: () => setState(() => _source = _QuizSource.local),
                    )),
                  ]),

                  const SizedBox(height: 24),

                  // ── JLPT 级别 ────────────────────────────────────────
                  _SectionLabel(label: 'JLPT 级别', icon: Icons.bar_chart_rounded),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_source == _QuizSource.local)
                      _LevelChip(label: '全部', value: 'ALL', selected: _level == 'ALL',
                          onTap: () => setState(() => _level = 'ALL')),
                    ...['N5','N4','N3','N2','N1'].map((l) => _LevelChip(
                      label: l, value: l, selected: _level == l,
                      onTap: () => setState(() => _level = l),
                    )),
                  ]),

                  const SizedBox(height: 24),

                  // ── 题型选择 ─────────────────────────────────────────
                  _SectionLabel(label: '题目类型', icon: Icons.quiz_rounded),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _TypeTile(
                      selected: _quizType == _QuizType.meaning,
                      icon: Icons.translate_rounded,
                      label: '单词意思',
                      sub: '看单词→选中文',
                      onTap: () => setState(() => _quizType = _QuizType.meaning),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _TypeTile(
                      selected: _quizType == _QuizType.reading,
                      icon: Icons.record_voice_over_rounded,
                      label: '假名读音',
                      sub: '看汉字→选假名',
                      onTap: () => setState(() => _quizType = _QuizType.reading),
                    )),
                  ]),

                  const SizedBox(height: 24),

                  // ── 题目数量 ─────────────────────────────────────────
                  _SectionLabel(label: '题目数量', icon: Icons.format_list_numbered_rounded),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [10, 20, 30].map((n) => ChoiceChip(
                    label: Text('$n 题'),
                    selected: _count == n,
                    onSelected: (_) => setState(() => _count = n),
                  )).toList()),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(Icons.warning_rounded, color: cs.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: TextStyle(color: cs.onErrorContainer))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _startQuiz,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('开始测验', style: TextStyle(fontSize: 17)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ─── 答题界面 ──────────────────────────────────────────────────────────────

  Widget _buildQuizScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('测验')),
        body: const Center(child: Text('暂无题目')),
      );
    }

    final q = _questions[_current];
    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${_current + 1} / ${_questions.length} 题'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '退出测验',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('退出测验'),
              content: const Text('确定要退出当前测验吗？进度不会保存。'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('继续测验')),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() { _started = false; _questions = []; _error = null; });
                  },
                  child: const Text('退出'),
                ),
              ],
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_current + 1) / _questions.length),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 题目卡片 ─────────────────────────────────────────────
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Text(
                  q.question,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: q.question.length > 20 ? 18 : 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ── 选项列表 ─────────────────────────────────────────────
            ...?q.options?.map((opt) {
              Color? bg;
              Color borderColor = cs.outlineVariant;
              double borderWidth = 1;
              if (_answered) {
                if (opt == q.correctAnswer) {
                  bg = Colors.green.withValues(alpha: 0.15);
                  borderColor = Colors.green;
                  borderWidth = 2;
                } else if (opt == _selectedAnswer) {
                  bg = Colors.red.withValues(alpha: 0.15);
                  borderColor = Colors.red;
                  borderWidth = 2;
                }
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: bg ?? cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _selectAnswer(opt),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor, width: borderWidth),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(opt, style: const TextStyle(fontSize: 15))),
                        if (_answered && opt == q.correctAnswer)
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        if (_answered && opt == _selectedAnswer && opt != q.correctAnswer)
                          const Icon(Icons.cancel, color: Colors.red, size: 20),
                      ]),
                    ),
                  ),
                ),
              );
            }),
            // ── 说明 ─────────────────────────────────────────────────
            if (_answered && q.explanation != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('💡 ${q.explanation!}', style: TextStyle(fontSize: 14, color: cs.onSecondaryContainer)),
              ),
            ],
            const Spacer(),
            if (_answered)
              FilledButton(
                onPressed: _nextQuestion,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(
                  _current + 1 < _questions.length ? '下一题 →' : '查看结果',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 辅助小组件 ─────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 18, color: cs.primary),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.primary)),
    ]);
  }
}

class _SourceTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _SourceTile({required this.selected, required this.icon,
      required this.label, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant, size: 26),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? cs.primary : cs.onSurface,
          )),
          Text(sub, style: TextStyle(fontSize: 11, color: cs.outline)),
        ]),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _TypeTile({required this.selected, required this.icon,
      required this.label, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.secondary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: selected ? cs.secondary : cs.onSurfaceVariant, size: 26),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? cs.secondary : cs.onSurface,
          )),
          Text(sub, style: TextStyle(fontSize: 11, color: cs.outline)),
        ]),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  const _LevelChip({required this.label, required this.value,
      required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
