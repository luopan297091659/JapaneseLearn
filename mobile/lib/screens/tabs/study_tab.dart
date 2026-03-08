import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StudyTab extends StatelessWidget {
  const StudyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('学习', style: TextStyle(fontWeight: FontWeight.w800)),
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
          _StudyCard(
            icon: Icons.grid_view_rounded,
            title: '五十音',
            subtitle: '基础入门 · 平假名/片假名/浊音/拗音',
            color: const Color(0xFFE91E63),
            onTap: () => context.push('/gojuon'),
          ),
          const SizedBox(height: 12),
          _StudyCard(
            icon: Icons.menu_book_rounded,
            title: '单词学习',
            subtitle: '词汇积累 · N5 - N1 全级别覆盖',
            color: const Color(0xFF4CAF50),
            onTap: () => context.push('/vocabulary'),
          ),
          const SizedBox(height: 12),
          _StudyCard(
            icon: Icons.school_rounded,
            title: '语法学习',
            subtitle: '规则掌握 · 系统学习日语语法',
            color: const Color(0xFF2196F3),
            onTap: () => context.push('/grammar'),
          ),
          const SizedBox(height: 12),
          _StudyCard(
            icon: Icons.headphones_rounded,
            title: '听力练习',
            subtitle: '提升听力 · 磨耳朵训练',
            color: const Color(0xFF9C27B0),
            onTap: () => context.push('/listening'),
          ),
          const SizedBox(height: 12),
          _StudyCard(
            icon: Icons.mic_rounded,
            title: 'AI 发音练习',
            subtitle: '智能纠正 · 对比原生发音',
            color: const Color(0xFF00BCD4),
            onTap: () => context.push('/pronunciation'),
          ),
          const SizedBox(height: 12),
          _StudyCard(
            icon: Icons.style_rounded,
            title: '闪卡练习',
            subtitle: '翻转记忆 · 四级评价·支持等级词库',
            color: const Color(0xFF3F51B5),
            onTap: () => context.push('/flashcard'),
          ),
          const SizedBox(height: 12),
          _StudyCard(
            icon: Icons.layers_rounded,
            title: 'SRS 复习',
            subtitle: '间隔记忆 · 科学记忆曲线',
            color: const Color(0xFFFF9800),
            onTap: () => context.push('/srs-review'),
          ),
        ],
      ),
    );
  }
}

class _StudyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _StudyCard({
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
