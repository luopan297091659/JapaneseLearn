import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class QuizResultScreen extends StatelessWidget {
  final Map<String, dynamic> result;
  const QuizResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = (result['score'] ?? 0) as num;
    final correct = result['correct'] ?? 0;
    final total = result['total'] ?? 0;

    Color scoreColor = score >= 80 ? Colors.green : score >= 60 ? Colors.orange : Colors.red;
    String emoji = score >= 80 ? '🎉' : score >= 60 ? '😊' : '💪';

    return Scaffold(
      appBar: AppBar(title: const Text('测验结果'), automaticallyImplyLeading: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text('$score%',
                  style: TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: scoreColor)),
              Text('$correct / $total 道题答对了',
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 32),
              // Score bar
              LinearProgressIndicator(
                value: score / 100,
                minHeight: 12,
                backgroundColor: cs.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scoreColor),
              ),
              const SizedBox(height: 8),
              Text(
                score >= 80 ? '优秀！继续保持👏' : score >= 60 ? '良好！还有提升空间' : '加油！多复习一下基础知识',
                style: TextStyle(color: cs.outline),
              ),
              const SizedBox(height: 40),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.go('/quiz'),
                    child: const Text('再来一次'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    child: const Text('返回'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
