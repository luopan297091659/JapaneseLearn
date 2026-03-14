import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TestTab extends StatelessWidget {
  const TestTab({super.key});

  void _showGameTypeSelection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('选择游戏', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Text('🧩', style: TextStyle(fontSize: 28)),
              title: const Text('助词方块', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('填入正确助词，消行闯关'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: const Color(0xFFF0FDF4),
              onTap: () { Navigator.pop(ctx); context.push('/game', extra: 'particles'); },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Text('🔤', style: TextStyle(fontSize: 28)),
              title: const Text('动词方块', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('选择正确动词活用形'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: const Color(0xFFEFF6FF),
              onTap: () { Navigator.pop(ctx); context.push('/game', extra: 'verbs'); },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('测试', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TestCard(
            icon: Icons.quiz_rounded,
            title: '单词随机测验',
            subtitle: '检验水平 · 随机出题巩固知识',
            color: const Color(0xFFFF5722),
            onTap: () => context.push('/quiz'),
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.draw_rounded,
            title: '五十音书写',
            subtitle: '书写测试 · 练习假名书写与笔顺',
            color: const Color(0xFF2196F3),
            onTap: () => context.push('/kana-writing-test'),
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.map_rounded,
            title: '都道府県竞答',
            subtitle: '地理测验 · 学习 47 个都道府県读音',
            color: const Color(0xFFE65100),
            onTap: () => context.push('/todofuken-quiz'),
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.hearing_rounded,
            title: '听力测试',
            subtitle: '听句选义 · N5-N1 例句听力测试',
            color: const Color(0xFFE040FB),
            onTap: () => context.push('/listening-exercise'),
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.sports_esports_rounded,
            title: '闯关游戏',
            subtitle: '助词方块 · 动词方块 · 闯关挑战',
            color: const Color(0xFF4CAF50),
            onTap: () => _showGameTypeSelection(context),
          ),
        ],
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _TestCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.7))),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }
}
