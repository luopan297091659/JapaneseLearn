import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import '../../data/kana_data.dart';
import '../../utils/tts_helper.dart';
import '../../widgets/kana_stroke_widget.dart';

class KanaWritingTestScreen extends StatefulWidget {
  const KanaWritingTestScreen({super.key});
  @override
  State<KanaWritingTestScreen> createState() => _KanaWritingTestScreenState();
}

class _KanaWritingTestScreenState extends State<KanaWritingTestScreen> {
  final FlutterTts _tts = FlutterTts();

  // ── 设置 ──
  bool _started = false;
  String _category = 'hiragana'; // hiragana, katakana, mixed
  String _range = 'seion'; // seion(清音), dakuon(浊音), all
  int _count = 10;

  // ── 测试 ──
  List<Map<String, String>> _questions = [];
  int _current = 0;
  final List<int> _scores = [];
  bool _scored = false;
  int? _currentScore;
  bool _finished = false;
  DateTime? _startTime;

  final _strokeController = KanaStrokeController();
  int _canvasKey = 0;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
    await TtsHelper.configureForJapanese(_tts);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _generateQuestions() {
    final rng = Random();
    final allKana = <Map<String, String>>[];

    void addFromData(List<List<List<String>>> data) {
      for (final row in data) {
        for (final kana in row) {
          if (kana.isEmpty) continue;
          // Only include single characters (skip multi-char yōon for writing test)
          if (kana[0].length > 1) continue;
          if (_category == 'hiragana' || _category == 'mixed') {
            allKana.add({'kana': kana[0], 'romaji': kana[2], 'isKatakana': 'false'});
          }
          if (_category == 'katakana' || _category == 'mixed') {
            allKana.add({'kana': kana[1], 'romaji': kana[2], 'isKatakana': 'true'});
          }
        }
      }
    }

    if (_range == 'seion' || _range == 'all') addFromData(gojuonData);
    if (_range == 'dakuon' || _range == 'all') addFromData(dakuonData);

    allKana.shuffle(rng);
    _questions = allKana.take(_count).toList();
  }

  void _startTest() {
    _generateQuestions();
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的题目')),
      );
      return;
    }
    setState(() {
      _started = true;
      _current = 0;
      _scores.clear();
      _scored = false;
      _currentScore = null;
      _finished = false;
      _canvasKey = 0;
      _startTime = DateTime.now();
    });
  }

  Future<void> _playPrompt() async {
    if (_questions.isEmpty) return;
    final q = _questions[_current];
    try {
      try { await _tts.setLanguage('ja-JP'); } catch (_) {}
      await _tts.setVolume(1.0);
      await _tts.speak(q['kana']!);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  void _submitAnswer() {
    if (!_strokeController.hasStrokes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先书写假名')),
      );
      return;
    }
    final score = _strokeController.calculateScore();
    setState(() {
      _currentScore = score;
      _scores.add(score);
      _scored = true;
    });
  }

  void _nextQuestion() {
    if (_current + 1 >= _questions.length) {
      setState(() => _finished = true);
    } else {
      setState(() {
        _current++;
        _scored = false;
        _currentScore = null;
        _canvasKey++;
      });
    }
  }

  void _restart() {
    setState(() {
      _started = false;
      _finished = false;
      _scores.clear();
    });
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    if (!_started) return _buildSetup(context);
    if (_finished) return _buildResult(context);
    return _buildTest(context);
  }

  // ── Setup ──

  Widget _buildSetup(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('五十音书写测试'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Category
            _SectionLabel(label: '假名类型', icon: Icons.translate_rounded),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _buildChip('平假名', 'hiragana', _category, (v) => setState(() => _category = v)),
              _buildChip('片假名', 'katakana', _category, (v) => setState(() => _category = v)),
              _buildChip('混合', 'mixed', _category, (v) => setState(() => _category = v)),
            ]),
            const SizedBox(height: 20),

            // Range
            _SectionLabel(label: '出题范围', icon: Icons.grid_view_rounded),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _buildChip('清音', 'seion', _range, (v) => setState(() => _range = v)),
              _buildChip('浊音/半浊音', 'dakuon', _range, (v) => setState(() => _range = v)),
              _buildChip('全部', 'all', _range, (v) => setState(() => _range = v)),
            ]),
            const SizedBox(height: 20),

            // Count
            _SectionLabel(label: '题目数量', icon: Icons.format_list_numbered_rounded),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [5, 10, 15, 20].map((n) => ChoiceChip(
              label: Text('$n 题'),
              selected: _count == n,
              onSelected: (_) => setState(() => _count = n),
            )).toList()),
            const SizedBox(height: 32),

            // Start button
            FilledButton.icon(
              onPressed: _startTest,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('开始测试', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, String value, String current, ValueChanged<String> onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: current == value,
      onSelected: (_) => onTap(value),
    );
  }

  // ── Test ──

  Widget _buildTest(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _questions[_current];
    final isKata = q['isKatakana'] == 'true';
    final kana = q['kana']!;
    final romaji = q['romaji']!;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('${_current + 1} / ${_questions.length}'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _showExitDialog(),
        ),
        actions: [
          if (_scores.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '平均 ${(_scores.reduce((a, b) => a + b) / _scores.length).round()}分',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (_current + (_scored ? 1 : 0)) / _questions.length,
            minHeight: 3,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Prompt
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '请写出以下假名${isKata ? "（片假名）" : "（平假名）"}',
                          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              romaji,
                              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: cs.primary),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: _playPrompt,
                              icon: Icon(Icons.volume_up_rounded, color: cs.primary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Canvas area
                  Expanded(
                    child: _scored
                        ? _buildScoreResult(cs, kana, isKata)
                        : KanaStrokeWidget(
                            key: ValueKey('test-$_canvasKey'),
                            kana: kana,
                            isKatakana: isKata,
                            testMode: true,
                            controller: _strokeController,
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Action buttons
                  if (!_scored)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _strokeController.clear();
                              setState(() => _canvasKey++);
                            },
                            icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                            label: const Text('清除'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _submitAnswer,
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: const Text('提交', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _nextQuestion,
                        icon: Icon(_current + 1 >= _questions.length
                            ? Icons.done_all_rounded
                            : Icons.arrow_forward_rounded, size: 20),
                        label: Text(
                          _current + 1 >= _questions.length ? '查看结果' : '下一题',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreResult(ColorScheme cs, String kana, bool isKata) {
    final score = _currentScore ?? 0;
    final Color scoreColor;
    final String emoji;
    if (score >= 80) {
      scoreColor = const Color(0xFF10b981);
      emoji = '🎉';
    } else if (score >= 50) {
      scoreColor = const Color(0xFFf59e0b);
      emoji = '👍';
    } else {
      scoreColor = Colors.red;
      emoji = '💪';
    }

    return Column(
      children: [
        // Score display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text('$emoji AI 评分', style: TextStyle(fontSize: 13, color: cs.outline)),
            const SizedBox(height: 4),
            Text(
              '$score',
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: scoreColor),
            ),
            Text(
              score >= 80 ? '完美书写！' : score >= 50 ? '不错，继续加油！' : '再多练习一下吧',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Show correct answer animation
        Expanded(
          child: Column(
            children: [
              Text('正确写法', style: TextStyle(fontSize: 13, color: cs.outline, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Expanded(
                child: KanaStrokeWidget(
                  key: ValueKey('answer-$kana-$isKata-$_current'),
                  kana: kana,
                  isKatakana: isKata,
                  animationOnly: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出测试'),
        content: const Text('确定要退出当前测试吗？进度将不会保存。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _restart();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  // ── Result ──

  Widget _buildResult(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _scores.length;
    final avg = total > 0 ? (_scores.reduce((a, b) => a + b) / total).round() : 0;
    final excellent = _scores.where((s) => s >= 80).length;
    final duration = DateTime.now().difference(_startTime ?? DateTime.now()).inSeconds;

    final Color mainColor;
    final String emoji;
    if (avg >= 80) {
      mainColor = const Color(0xFF10b981);
      emoji = '🎉';
    } else if (avg >= 60) {
      mainColor = const Color(0xFFf59e0b);
      emoji = '😊';
    } else {
      mainColor = Colors.red;
      emoji = '💪';
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('测试结果'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Main score
          Center(
            child: Column(children: [
              Text(emoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(
                '$avg',
                style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: mainColor),
              ),
              Text('平均得分', style: TextStyle(fontSize: 15, color: cs.outline)),
            ]),
          ),
          const SizedBox(height: 24),

          // Stats row
          Row(
            children: [
              Expanded(child: _statCard(cs, '$total', '总题数', cs.primary)),
              const SizedBox(width: 12),
              Expanded(child: _statCard(cs, '$excellent', '优秀 (≥80)', const Color(0xFF10b981))),
              const SizedBox(width: 12),
              Expanded(child: _statCard(cs, '${duration}s', '用时', cs.tertiary)),
            ],
          ),
          const SizedBox(height: 20),

          // Score list
          Text('各题得分', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 8),
          ...List.generate(_questions.length, (i) {
            final q = _questions[i];
            final score = i < _scores.length ? _scores[i] : 0;
            final isKata = q['isKatakana'] == 'true';
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Text(
                  '${i + 1}',
                  style: TextStyle(fontSize: 13, color: cs.outline, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Text(
                  q['kana']!,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  '${q['romaji']} ${isKata ? "片" : "平"}',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (score >= 80 ? const Color(0xFF10b981)
                        : score >= 50 ? const Color(0xFFf59e0b)
                        : Colors.red).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: score >= 80 ? const Color(0xFF10b981)
                          : score >= 50 ? const Color(0xFFf59e0b)
                          : Colors.red,
                    ),
                  ),
                ),
              ]),
            );
          }),
          const SizedBox(height: 20),

          // Action buttons
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                label: const Text('返回'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('再来一次'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _statCard(ColorScheme cs, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
      ]),
    );
  }
}

// ── 设置区域标题 ──

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
      Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface)),
    ]);
  }
}
