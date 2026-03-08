import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});
  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<VocabularyModel> _cards = [];
  bool _loading = true;
  int _currentIndex = 0;
  bool _isFlipped = false;
  String _selectedLevel = 'N5'; // 当前词库等级
  bool _levelChosen = false; // 是否已选择等级

  // 学习统计
  int _totalReviewed = 0;
  int _correctCount = 0; // good + easy 算正确
  final Map<String, int> _difficultyStats = {'again': 0, 'hard': 0, 'good': 0, 'easy': 0};
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 不自动加载，等用户选级别
  }

  Future<void> _loadCards() async {
    setState(() => _loading = true);
    try {
      final res = await apiService.getVocabulary(level: _selectedLevel, limit: 50, page: 1);
      final words = res['data'] as List<VocabularyModel>;
      // 随机打乱
      words.shuffle(Random());
      if (mounted) setState(() { _cards = words; _loading = false; _levelChosen = true; _currentIndex = 0; _isFlipped = false; _totalReviewed = 0; _correctCount = 0; _difficultyStats.updateAll((k, v) => 0); });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _flipCard() {
    setState(() => _isFlipped = !_isFlipped);
  }

  void _handleDifficulty(String difficulty) {
    _totalReviewed++;
    _difficultyStats[difficulty] = (_difficultyStats[difficulty] ?? 0) + 1;
    if (difficulty == 'good' || difficulty == 'easy') _correctCount++;

    if (_currentIndex + 1 >= _cards.length) {
      _finishSession();
    } else {
      setState(() {
        _currentIndex++;
        _isFlipped = false;
      });
    }
  }

  void _finishSession() {
    final duration = DateTime.now().difference(_startTime).inSeconds;
    final accuracy = _totalReviewed > 0 ? (_correctCount / _totalReviewed * 100) : 0.0;
    // 记录学习活动
    apiService.logActivity(
      activityType: 'vocabulary',
      durationSeconds: duration,
      score: accuracy,
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.celebration_rounded, color: Color(0xFFFF9800), size: 28),
          SizedBox(width: 8),
          Text('练习完成！'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _ResultStatRow(label: '总复习', value: '$_totalReviewed 张'),
          _ResultStatRow(label: '正确率', value: '${accuracy.round()}%', color: Colors.green),
          const Divider(height: 20),
          _ResultStatRow(label: '重来', value: '${_difficultyStats['again']}', color: Colors.red),
          _ResultStatRow(label: '困难', value: '${_difficultyStats['hard']}', color: Colors.orange),
          _ResultStatRow(label: '良好', value: '${_difficultyStats['good']}', color: Colors.blue),
          _ResultStatRow(label: '简单', value: '${_difficultyStats['easy']}', color: Colors.green),
        ]),
        actions: [
          FilledButton(
            onPressed: () { Navigator.pop(ctx); if (mounted) context.go('/home'); },
            child: const Text('返回首页'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 等级选择页
    if (!_levelChosen) {
      return Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        appBar: AppBar(
          title: const Text('闪卡练习'),
          backgroundColor: cs.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.style_rounded, size: 64, color: cs.primary),
                const SizedBox(height: 16),
                const Text('选择词库等级', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('将同步对应等级的词汇进行练习', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 24),
                ...['N5', 'N4', 'N3', 'N2', 'N1'].map((level) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () { _selectedLevel = level; _loadCards(); },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: cs.primary.withOpacity(0.3)),
                      ),
                      child: Text(level, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary)),
                    ),
                  ),
                )),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('闪卡练习')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('闪卡练习')),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.inbox_rounded, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('暂无词汇可练习', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => context.go('/home'), child: const Text('返回首页')),
          ]),
        ),
      );
    }

    final card = _cards[_currentIndex];
    final progress = (_currentIndex + 1) / _cards.length;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('闪卡 ${_currentIndex + 1}/${_cards.length}'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _confirmExit(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: progress, backgroundColor: cs.primary.withOpacity(0.3)),
        ),
      ),
      body: Column(
        children: [
          // 学习统计栏
          _StatsBar(reviewed: _totalReviewed, correct: _correctCount, total: _cards.length),
          // 主卡片区域
          Expanded(
            child: GestureDetector(
              onTap: _flipCard,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: _FlipCard(
                  word: card,
                  isFlipped: _isFlipped,
                ),
              ),
            ),
          ),
          // 操作按钮区域
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: _isFlipped
                ? _DifficultyButtons(onSelect: _handleDifficulty)
                : Column(children: [
                    FilledButton.icon(
                      onPressed: _flipCard,
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('显示答案'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                    const SizedBox(height: 8),
                    Text('点击卡片或按钮翻转', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
          ),
        ],
      ),
    );
  }

  void _confirmExit() {
    if (_totalReviewed == 0) {
      context.go('/home');
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出练习'),
        content: Text('已复习 $_totalReviewed 张卡片，确定退出吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('继续')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _finishSession();
            },
            child: const Text('结束并保存'),
          ),
        ],
      ),
    );
  }
}

// ─── 翻转卡片 ────────────────────────────────────────────────────────────────

class _FlipCard extends StatelessWidget {
  final VocabularyModel word;
  final bool isFlipped;
  const _FlipCard({required this.word, required this.isFlipped});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: isFlipped ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      builder: (context, value, _) {
        // 0→0.5 正面翻到侧面，0.5→1 侧面翻到背面
        final angle = value * pi;
        final showBack = value >= 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // 透视
            ..rotateY(angle),
          child: showBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(pi), // 镜像翻转文字
                  child: _CardBack(word: word),
                )
              : _CardFront(word: word),
        );
      },
    );
  }
}

class _CardFront extends StatelessWidget {
  final VocabularyModel word;
  const _CardFront({required this.word});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // JLPT 等级
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(word.jlptLevel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
          // 日文大字
          Text(word.word, style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: cs.primary)),
          const SizedBox(height: 8),
          // 假名
          Text(word.reading, style: TextStyle(fontSize: 22, color: cs.secondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          // 词性标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.tertiary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(word.partOfSpeech, style: TextStyle(color: cs.tertiary, fontSize: 12)),
          ),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.touch_app_rounded, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('点击翻转', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ]),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final VocabularyModel word;
  const _CardBack({required this.word});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.primary.withOpacity(0.3), width: 2),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 日文 + 假名（小号）
          Text(word.word, style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: cs.primary)),
          const SizedBox(height: 4),
          Text(word.reading, style: TextStyle(fontSize: 18, color: cs.secondary)),
          const SizedBox(height: 20),
          // 释义
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(word.meaningZh,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: cs.onSurface),
                textAlign: TextAlign.center),
          ),
          // 例句
          if (word.exampleSentence != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.format_quote_rounded, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('例句', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 6),
                Text(word.exampleSentence!, style: TextStyle(fontSize: 15, color: cs.onSurface, height: 1.5)),
                if (word.exampleMeaningZh != null) ...[
                  const SizedBox(height: 4),
                  Text(word.exampleMeaningZh!, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 统计栏 ──────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int reviewed, correct, total;
  const _StatsBar({required this.reviewed, required this.correct, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accuracy = reviewed > 0 ? (correct / reviewed * 100).round() : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: cs.surfaceContainerHigh,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _StatChip(label: '已复习', value: '$reviewed', color: cs.primary),
        _StatChip(label: '正确率', value: '$accuracy%', color: const Color(0xFF059669)),
        _StatChip(label: '剩余', value: '${total - reviewed}', color: cs.onSurfaceVariant),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

// ─── 四级难度按钮 ────────────────────────────────────────────────────────────

class _DifficultyButtons extends StatelessWidget {
  final void Function(String difficulty) onSelect;
  const _DifficultyButtons({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('你记住了吗？', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _DiffButton(label: '重来', sub: '<1分', color: Colors.red, onTap: () => onSelect('again'))),
          const SizedBox(width: 8),
          Expanded(child: _DiffButton(label: '困难', sub: '<6分', color: Colors.orange, onTap: () => onSelect('hard'))),
          const SizedBox(width: 8),
          Expanded(child: _DiffButton(label: '良好', sub: '<10分', color: Colors.blue, onTap: () => onSelect('good'))),
          const SizedBox(width: 8),
          Expanded(child: _DiffButton(label: '简单', sub: '4天', color: Colors.green, onTap: () => onSelect('easy'))),
        ]),
      ],
    );
  }
}

class _DiffButton extends StatelessWidget {
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  const _DiffButton({required this.label, required this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
        ]),
      ),
    );
  }
}

// ─── 结果展示行 ──────────────────────────────────────────────────────────────

class _ResultStatRow extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _ResultStatRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}
