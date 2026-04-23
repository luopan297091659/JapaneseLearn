import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/membership_service.dart';
import '../../models/models.dart';
import '../../widgets/membership_gate.dart';

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
  bool _isMember = true;
  List<String> _freeJlptLevels = [];
  List<int> _freeCountOptions = [];

  @override
  void initState() {
    super.initState();
    _checkMembership();
  }

  Future<void> _checkMembership() async {
    try {
      final user = await apiService.getMe();
      final jlpt = membershipService.getFreeValues('quiz_jlpt_levels');
      final counts = membershipService.getFreeValues('quiz_count_options');
      if (mounted) {
        setState(() {
          _isMember = user.isMember;
          _freeJlptLevels = jlpt ?? [];
          _freeCountOptions = counts?.map((s) => int.tryParse(s) ?? 0).toList() ?? [];
        });
      }
    } catch (_) {}
  }

  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _startQuiz() async {
    setState(() { _loading = true; _error = null; });
    try {
      final qs = await _buildDynamicQuizFromServer();
      if (qs.isEmpty) {
        setState(() {
          _loading = false;
          _error = '暂无足够题目，请切换级别后重试';
        });
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

  /// 判断字符串是否全部由假名/符号组成（即纯假名词，无汉字）
  bool _isPureKana(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^[\u3040-\u30ff\u30fc\uff70ー々〆〇\s]+$').hasMatch(t);
  }

  /// 去除振假名标注，保留汉字：噂[うわさ] → 噂
  String _stripFurigana(String text) => text.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();

  bool _isValidReadingOption(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    // 读音选项必须包含假名，且不应混入英文字母。
    if (!RegExp(r'[\u3040-\u30ff]').hasMatch(value)) return false;
    if (RegExp(r'[A-Za-z]').hasMatch(value)) return false;
    return true;
  }

  bool _isValidMeaningOption(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    // 释义题优先展示中文释义，过滤纯英文项。
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(value);
    return hasCjk || !hasLatin;
  }

  Future<List<QuizQuestionModel>> _buildDynamicQuizFromServer() async {
    final rng = Random();
    final levels = _level == 'ALL' ? const ['N5', 'N4', 'N3', 'N2', 'N1'] : [_level];
    final pool = <VocabularyModel>[];

    for (final lv in levels) {
      try {
        final meta = await apiService.getVocabulary(level: lv, page: 1, limit: 1);
        final total = (meta['total'] as int?) ?? 0;
        final pageSize = max(_count * 8, 80);
        final maxPage = total > 0 ? max(1, (total / pageSize).ceil()) : 1;
        final randomPage = maxPage > 1 ? rng.nextInt(maxPage) + 1 : 1;

        final pageSet = <int>{1, randomPage};
        for (final p in pageSet) {
          final res = await apiService.getVocabulary(level: lv, page: p, limit: pageSize);
          final data = (res['data'] as List<VocabularyModel>?) ?? [];
          pool.addAll(data);
        }
      } catch (_) {
        // Ignore a single level failure and continue with others.
      }
    }

    // 去重并打乱，确保每次题目不同
    final byId = <String, VocabularyModel>{};
    for (final w in pool) {
      byId[w.id] = w;
    }
    final uniquePool = byId.values.toList()..shuffle(rng);
    if (uniquePool.length < 4) return [];

    final questions = <QuizQuestionModel>[];
    for (final word in uniquePool) {
      final distractors = uniquePool.where((w) => w.id != word.id).toList()..shuffle(rng);

      if (_quizType == _QuizType.meaning) {
        final correctDef = word.meaningZh.trim();
        if (!_isValidMeaningOption(correctDef)) continue;
        final wrongOpts = distractors
            .map((w) => w.meaningZh.trim())
            .where((m) => m != correctDef && _isValidMeaningOption(m))
            .toSet()
            .take(3)
            .toList();
        if (wrongOpts.length < 3) continue;
        final opts = [correctDef, ...wrongOpts]..shuffle(rng);
        questions.add(QuizQuestionModel(
          id: word.id,
          questionType: 'vocabulary',
          question: word.reading.isNotEmpty ? '${_stripFurigana(word.word)}【${word.reading}】' : _stripFurigana(word.word),
          correctAnswer: correctDef,
          options: opts,
          explanation: '${word.word} → $correctDef',
          jlptLevel: word.jlptLevel,
        ));
      } else {
        // 词条本身已是纯假名，问读音毫无意义，跳过
        if (_isPureKana(word.word)) continue;
        final correctReading = word.reading.trim();
        if (!_isValidReadingOption(correctReading)) continue;
        final wrongOpts = distractors
            .map((w) => w.reading.trim())
            .where((r) => r != correctReading && _isValidReadingOption(r))
            .toSet()
            .take(3)
            .toList();
        if (wrongOpts.length < 3) continue;
        final opts = [correctReading, ...wrongOpts]..shuffle(rng);
        questions.add(QuizQuestionModel(
          id: word.id,
          questionType: 'reading',
          question: _stripFurigana(word.word),
          correctAnswer: correctReading,
          options: opts,
          explanation: '${word.word} 的读音是 $correctReading',
          jlptLevel: word.jlptLevel,
        ));
      }

      if (questions.length >= _count) break;
    }

    return questions;
  }

  void _selectAnswer(String answer) {
    if (_answered) return;
    setState(() { _selectedAnswer = answer; _answered = true;
      _questions[_current].userAnswer = answer; });
    final q = _questions[_current];
    if (answer != q.correctAnswer) {
      _saveWrongAnswer(
        source: 'quiz',
        question: q.question,
        yourAnswer: answer,
        correctAnswer: q.correctAnswer,
        explanation: q.explanation ?? '',
      );
    }
  }

  Future<void> _saveWrongAnswer({
    required String source,
    required String question,
    required String yourAnswer,
    required String correctAnswer,
    String explanation = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wrongAnswers') ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.add({
      'source': source,
      'question': question,
      'yourAnswer': yourAnswer,
      'correctAnswer': correctAnswer,
      'explanation': explanation,
      'time': DateTime.now().toIso8601String(),
    });
    // 最多保留500条
    while (list.length > 500) { list.removeAt(0); }
    await prefs.setString('wrongAnswers', jsonEncode(list));
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
        title: const Text('单词测验'),
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
                  // ── JLPT 级别 ────────────────────────────────────────
                  _SectionLabel(label: 'JLPT 级别', icon: Icons.bar_chart_rounded),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _LevelChip(label: '全部', value: 'ALL', selected: _level == 'ALL',
                        onTap: () => setState(() => _level = 'ALL')),
                    ...['N5','N4','N3','N2','N1'].map((l) {
                      final locked = !_isMember && _freeJlptLevels.isNotEmpty && !_freeJlptLevels.contains(l);
                      return _LevelChip(
                        label: locked ? '$l 🔒' : l,
                        value: l,
                        selected: _level == l,
                        onTap: () {
                          if (locked) {
                            showMembershipUpgradeDialog(context, featureName: 'JLPT等级筛选');
                          } else {
                            setState(() => _level = l);
                          }
                        },
                      );
                    }),
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
                  Wrap(spacing: 8, runSpacing: 8, children: [10, 20, 30].map((n) {
                    final locked = !_isMember && _freeCountOptions.isNotEmpty && !_freeCountOptions.contains(n);
                    return ChoiceChip(
                      label: Text(locked ? '$n 题 🔒' : '$n 题'),
                      selected: _count == n,
                      onSelected: (_) {
                        if (locked) {
                          showMembershipUpgradeDialog(context, featureName: '题目数量选择');
                        } else {
                          setState(() => _count = n);
                        }
                      },
                    );
                  }).toList()),

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
            builder: (dialogCtx) => AlertDialog(
              title: const Text('退出测验'),
              content: const Text('确定要退出当前测验吗？进度不会保存。'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('继续测验')),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
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
      bottomNavigationBar: _answered
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _nextQuestion,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(
                    _current + 1 < _questions.length ? '下一题 →' : '查看结果',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            )
          : null,
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
