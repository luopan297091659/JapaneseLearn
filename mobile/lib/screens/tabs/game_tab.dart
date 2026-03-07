import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class GameTab extends StatelessWidget {
  const GameTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('游戏', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GameCard(
            icon: Icons.sports_esports_rounded,
            title: '助词方块',
            subtitle: '趣味闯关 · 助词填空',
            gradient: const [Color(0xFFE91E63), Color(0xFFFF5252)],
            onTap: () => context.push('/game', extra: 'particles'),
          ),
          const SizedBox(height: 12),
          _GameCard(
            icon: Icons.sports_esports_rounded,
            title: '动词方块',
            subtitle: '趣味闯关 · 动词变形',
            gradient: const [Color(0xFF9C27B0), Color(0xFF7E57C2)],
            onTap: () => context.push('/game', extra: 'verbs'),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _GameCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('开始', style: TextStyle(color: gradient[0], fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ]),
      ),
    );
  }
}
