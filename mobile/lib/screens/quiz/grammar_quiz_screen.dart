import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/furigana_text.dart';

class GrammarQuizScreen extends StatefulWidget {
  final String? initialLevel;
  final int? initialCount;
  final bool autoStart;

  const GrammarQuizScreen({
    super.key,
    this.initialLevel,
    this.initialCount,
    this.autoStart = false,
  });
  @override
  State<GrammarQuizScreen> createState() => _GrammarQuizScreenState();
}

class _GrammarQuizScreenState extends State<GrammarQuizScreen> {
  // ── 设置阶段 ─────────────────────────────────────────
  bool _started = false;
  bool _finished = false;
  String _level = 'N5';
  int _count = 10;

  // ── 测验阶段 ─────────────────────────────────────────
  List<QuizQuestionModel> _questions = [];
  int _current = 0;
  String? _selectedAnswer;
  bool _answered = false;
  bool _loading = false;
  String? _error;
  DateTime? _startTime;
  int _durationSeconds = 0;

  static const _labels = ['A', 'B', 'C', 'D'];

  Future<void> _startQuiz() async {
    setState(() { _loading = true; _error = null; });
    try {
      final qs = await apiService.generateQuiz(
        level: _level,
        quizType: 'grammar',
        count: _count,
      );
      if (qs.isEmpty) {
        setState(() { _loading = false; _error = '当前级别暂无足够的文法题目，请换一个级别试试'; });
        return;
      }
      setState(() {
        _questions = qs;
        _current = 0;
        _selectedAnswer = null;
        _answered = false;
        _loading = false;
        _started = true;
        _startTime = DateTime.now();
      });
    } catch (e) {
      // 会员限制错误由全局拦截器弹窗处理，这里只更新UI状态
      if (e is DioException && e.response?.statusCode == 403) {
        setState(() { _loading = false; _error = e.response?.data?['message'] ?? '今日免费额度已用完，升级会员可无限使用'; });
        return;
      }
      setState(() { _loading = false; _error = '加载失败: $e'; });
    }
  }

  void _selectAnswer(String answer) {
    if (_answered) return;
    setState(() { _selectedAnswer = answer; _answered = true; _questions[_current].userAnswer = answer; });
    final q = _questions[_current];
    if (answer != q.correctAnswer) {
      _saveWrongAnswer(question: q.question, yourAnswer: answer, correctAnswer: q.correctAnswer, explanation: q.explanation ?? '');
    }
  }

  Future<void> _saveWrongAnswer({required String question, required String yourAnswer, required String correctAnswer, String explanation = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wrongAnswers') ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.add({
      'source': 'grammar_quiz',
      'question': question,
      'yourAnswer': yourAnswer,
      'correctAnswer': correctAnswer,
      'explanation': explanation,
      'time': DateTime.now().toIso8601String(),
    });
    while (list.length > 500) { list.removeAt(0); }
    await prefs.setString('wrongAnswers', jsonEncode(list));
  }

  void _nextQuestion() {
    if (_current + 1 >= _questions.length) {
      _finishQuiz();
    } else {
      setState(() { _current++; _selectedAnswer = null; _answered = false; });
    }
  }

  Future<void> _finishQuiz() async {
    _durationSeconds = DateTime.now().difference(_startTime ?? DateTime.now()).inSeconds;
    final correct = _questions.where((q) => q.isCorrect).length;
    final total = _questions.length;
    final score = total > 0 ? ((correct / total) * 100).round() : 0;

    apiService.logActivity(activityType: 'grammar_quiz', durationSeconds: _durationSeconds, score: score.toDouble());

    final answers = _questions.map((q) => {
      'question_id': q.id,
      'user_answer': q.userAnswer ?? '',
      'correct_answer': q.correctAnswer,
    }).toList();

    try {
      await apiService.submitQuiz(
        level: _level,
        quizType: 'grammar',
        answers: answers,
        timeSpentSeconds: _durationSeconds,
      );
    } catch (_) {}

    if (mounted) setState(() => _finished = true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialLevel != null && ['N5', 'N4', 'N3', 'N2', 'N1'].contains(widget.initialLevel)) {
      _level = widget.initialLevel!;
    }
    if (widget.initialCount != null && widget.initialCount! > 0) {
      _count = widget.initialCount!;
    }
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_started && !_loading) {
          _startQuiz();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return _buildResultScreen(context);
    if (!_started) return _buildSetupScreen(context);
    return _buildQuizScreen(context);
  }

  // ─── 设置界面 ──────────────────────────────────────────

  Widget _buildSetupScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('文法测验'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 头图区域
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
                      const Text('📖', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 8),
                      Text('文法选词填空', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
                      const SizedBox(height: 4),
                      Text('阅读日语例句，判断使用了哪个语法点', style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer.withValues(alpha: 0.7))),
                    ]),
                  ),

                  const SizedBox(height: 28),

                  // JLPT 级别
                  _sectionTitle(cs, Icons.bar_chart_rounded, 'JLPT 级别'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10, children: ['N5', 'N4', 'N3', 'N2', 'N1'].map((l) {
                    final selected = _level == l;
                    return ChoiceChip(
                      label: Text(l, style: TextStyle(fontWeight: FontWeight.bold, color: selected ? Colors.white : cs.onSurface)),
                      selected: selected,
                      selectedColor: cs.primary,
                      onSelected: (_) => setState(() => _level = l),
                    );
                  }).toList()),

                  const SizedBox(height: 28),

                  // 题目数量
                  _sectionTitle(cs, Icons.format_list_numbered_rounded, '题目数量'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10, children: [10, 20, 30].map((n) {
                    return ChoiceChip(
                      label: Text('$n 题'),
                      selected: _count == n,
                      onSelected: (_) => setState(() => _count = n),
                    );
                  }).toList()),

                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.warning_rounded, color: cs.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: TextStyle(color: cs.onErrorContainer, fontSize: 13))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 36),
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

  Widget _sectionTitle(ColorScheme cs, IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 18, color: cs.primary),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.primary)),
    ]);
  }

  // ─── 答题界面 ──────────────────────────────────────────

  Widget _buildQuizScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_questions.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('文法测验')), body: const Center(child: Text('暂无题目')));
    }

    final q = _questions[_current];
    final opts = q.options ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text('第 ${_current + 1} / ${_questions.length} 题'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '退出测验',
          onPressed: () => _showExitDialog(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_current + 1) / _questions.length),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 题目卡片：日语例句 ──
                  Card(
                    color: cs.primaryContainer,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(children: [
                        Text('请选择正确的词语填入空白处', style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer.withValues(alpha: 0.6))),
                        const SizedBox(height: 12),
                        if (hasFurigana(q.question))
                          FuriganaText(text: q.question, fontSize: q.question.length > 30 ? 18 : 22, color: cs.onPrimaryContainer)
                        else
                          Text(
                            q.question,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: q.question.length > 30 ? 18 : 22,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer,
                              height: 1.5,
                            ),
                          ),
                        // 中文翻译提示（答题后才显示）
                        if (_answered && q.meaningZh != null && q.meaningZh!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(q.meaningZh!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: cs.onPrimaryContainer.withValues(alpha: 0.7), height: 1.4)),
                        ],
                      ]),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── 选项列表（A/B/C/D） ──
                  ...List.generate(opts.length, (i) {
                    final opt = opts[i];
                    final label = i < _labels.length ? _labels[i] : '${i + 1}';
                    Color? bg;
                    Color borderColor = cs.outlineVariant;
                    double borderWidth = 1;
                    Color labelBg = cs.surfaceContainerHighest;
                    Color labelColor = cs.onSurface;

                    if (_answered) {
                      if (opt == q.correctAnswer) {
                        bg = Colors.green.withValues(alpha: 0.12);
                        borderColor = Colors.green;
                        borderWidth = 2;
                        labelBg = Colors.green;
                        labelColor = Colors.white;
                      } else if (opt == _selectedAnswer) {
                        bg = Colors.red.withValues(alpha: 0.12);
                        borderColor = Colors.red;
                        borderWidth = 2;
                        labelBg = Colors.red;
                        labelColor = Colors.white;
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor, width: borderWidth),
                            ),
                            child: Row(children: [
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: labelBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: labelColor, fontSize: 15)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(opt, style: const TextStyle(fontSize: 15, height: 1.4))),
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

                  // ── 解释 ──
                  if (_answered && q.explanation != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Text('💡 ${q.explanation!}', style: TextStyle(fontSize: 14, color: cs.onSecondaryContainer)),
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── 下一题按钮（固定底部） ──
          if (_answered)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: _nextQuestion,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(
                  _current + 1 < _questions.length ? '下一题 →' : '查看结果',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── 结果界面（含每题解析） ──────────────────────────

  Widget _buildResultScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final correct = _questions.where((q) => q.isCorrect).length;
    final total = _questions.length;
    final score = total > 0 ? ((correct / total) * 100).round() : 0;

    Color scoreColor = score >= 80 ? Colors.green : score >= 60 ? Colors.orange : Colors.red;
    String emoji = score >= 90 ? '🎉' : score >= 70 ? '😊' : score >= 50 ? '💪' : '📚';

    return Scaffold(
      appBar: AppBar(title: const Text('文法测验结果'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 分数概览 ──
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scoreColor.withValues(alpha: 0.15), scoreColor.withValues(alpha: 0.05)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              Text(emoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text('$score%', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: scoreColor)),
              Text('$correct / $total 道题答对', style: TextStyle(fontSize: 16, color: cs.onSurface)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: score / 100,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scoreColor),
              ),
              const SizedBox(height: 6),
              Text(
                score >= 80 ? '优秀！继续保持' : score >= 60 ? '良好！多加练习' : '加油！建议复习相关语法',
                style: TextStyle(fontSize: 13, color: cs.outline),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // ── 题目详解列表 ──
          Text('📋 题目详解', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 12),

          ...List.generate(_questions.length, (i) {
            final q = _questions[i];
            final isCorrect = q.isCorrect;
            final statusColor = isCorrect ? Colors.green : Colors.red;
            final statusIcon = isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: statusColor.withValues(alpha: 0.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 题号 + 状态
                Row(children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 6),
                  Text('第 ${i + 1} 题', style: TextStyle(fontWeight: FontWeight.bold, color: statusColor)),
                  const Spacer(),
                  Text(isCorrect ? '正确' : '错误', style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 10),

                // 日语例句
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: hasFurigana(q.question)
                      ? FuriganaText(text: q.question, fontSize: 16, color: cs.onSurface, textAlign: TextAlign.left)
                      : Text(q.question, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface, height: 1.5)),
                ),
                const SizedBox(height: 10),

                // 正确答案
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('✅ ', style: TextStyle(fontSize: 14)),
                  Expanded(child: Text.rich(TextSpan(children: [
                    TextSpan(text: '正确答案: ', style: TextStyle(fontSize: 13, color: cs.outline)),
                    TextSpan(text: q.correctAnswer, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                  ]))),
                ]),

                // 用户答案（如果答错）
                if (!isCorrect && q.userAnswer != null) ...[
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('❌ ', style: TextStyle(fontSize: 14)),
                    Expanded(child: Text.rich(TextSpan(children: [
                      TextSpan(text: '你的答案: ', style: TextStyle(fontSize: 13, color: cs.outline)),
                      TextSpan(text: q.userAnswer!, style: TextStyle(fontSize: 14, color: Colors.red.shade700, decoration: TextDecoration.lineThrough)),
                    ]))),
                  ]),
                ],

                // 文法解释
                if (q.explanation != null && q.explanation!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('💡 ', style: TextStyle(fontSize: 14)),
                      Expanded(child: Text(q.explanation!, style: TextStyle(fontSize: 13, color: cs.onSecondaryContainer, height: 1.4))),
                    ]),
                  ),
                ],
              ]),
            );
          }),

          const SizedBox(height: 16),

          // ── 操作按钮 ──
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _started = false; _finished = false; _questions = []; _error = null;
                }),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('再来一次'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => context.canPop() ? context.pop() : context.go('/test'),
                icon: const Icon(Icons.arrow_back_ios_rounded),
                label: const Text('返回'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出测验'),
        content: const Text('确定要退出当前测验吗？进度不会保存。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('继续测验')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() { _started = false; _questions = []; _error = null; });
            },
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}
