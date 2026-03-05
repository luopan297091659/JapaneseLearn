import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

class SrsReviewScreen extends StatefulWidget {
  const SrsReviewScreen({super.key});
  @override
  State<SrsReviewScreen> createState() => _SrsReviewScreenState();
}

class _SrsReviewScreenState extends State<SrsReviewScreen> {
  List<SrsCardModel> _cards = [];
  int _current = 0;
  bool _showAnswer = false;
  bool _loading = true;
  int _reviewed = 0;
  int _correct = 0;
  final _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    try {
      final res = await apiService.getDueCards(limit: 20);
      setState(() { _cards = res['cards'] as List<SrsCardModel>; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _submitReview(int quality) async {
    final card = _cards[_current];
    if (quality >= 3) _correct++;
    _reviewed++;
    await apiService.submitSrsReview(card.id, quality);
    if (mounted) {
      final label = quality == 0 ? '重来' : quality <= 3 ? '困难' : quality == 4 ? '良好' : '简单';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已标记为「$label」，已更新复习计划'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
    }
    if (_current + 1 >= _cards.length) {
      _finishSession();
    } else {
      setState(() { _current++; _showAnswer = false; });
    }
  }

  void _finishSession() {
    final duration = DateTime.now().difference(_startTime).inSeconds;
    apiService.logActivity(
      activityType: 'srs_review',
      durationSeconds: duration,
      score: _reviewed > 0 ? (_correct / _reviewed * 100) : 0,
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('复习完成！'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('共复习 $_reviewed 张卡片', style: const TextStyle(fontSize: 16)),
          Text('正确率 ${_reviewed > 0 ? (_correct / _reviewed * 100).round() : 0}%',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
        ]),
        actions: [FilledButton(onPressed: () { Navigator.of(context).pop(); context.go('/home'); }, child: const Text('返回首页'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('间隔复习'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            tooltip: '返回首页',
            onPressed: () => context.go('/home'),
          ),
        ),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            const Text('今日复习已完成！', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('明日再来继续学习'),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.go('/home'), child: const Text('返回首页')),
          ]),
        ),
      );
    }

    final card = _cards[_current];
    final vocab = card.content is VocabularyModel ? card.content as VocabularyModel : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('复习 ${_current + 1}/${_cards.length}'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '退出复习',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('退出复习'),
              content: const Text('确定要退出当前复习吗？'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('继续复习')),
                FilledButton(onPressed: () { Navigator.of(context).pop(); context.go('/home'); }, child: const Text('退出')),
              ],
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_current + 1) / _cards.length),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Card(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Word
                      Text(
                        vocab?.word ?? card.refId,
                        style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (_showAnswer) ...[
                        Text(vocab?.reading ?? '', style: TextStyle(fontSize: 24, color: cs.primary)),
                        const SizedBox(height: 8),
                        Text(vocab?.meaningZh ?? '', style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 16),
                        if (vocab?.exampleSentence != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(vocab!.exampleSentence!, textAlign: TextAlign.center),
                                Text(vocab.exampleMeaningZh ?? '',
                                    style: TextStyle(color: cs.outline, fontSize: 12)),
                              ],
                            ),
                          ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text('点击"显示答案"查看释义',
                            style: TextStyle(color: cs.outline)),
                      ]
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!_showAnswer) ...[
              FilledButton.icon(
                onPressed: () => setState(() => _showAnswer = true),
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('显示答案'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ] else ...[
              const Text('你记住了吗？', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _QualityButton(label: '重来', quality: 0, color: Colors.red, onTap: _submitReview)),
                const SizedBox(width: 8),
                Expanded(child: _QualityButton(label: '困难', quality: 3, color: Colors.orange, onTap: _submitReview)),
                const SizedBox(width: 8),
                Expanded(child: _QualityButton(label: '良好', quality: 4, color: Colors.blue, onTap: _submitReview)),
                const SizedBox(width: 8),
                Expanded(child: _QualityButton(label: '简单', quality: 5, color: Colors.green, onTap: _submitReview)),
              ]),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  final String label;
  final int quality;
  final Color color;
  final Future<void> Function(int) onTap;

  const _QualityButton({
    required this.label, required this.quality,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => onTap(quality),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
    );
  }
}
