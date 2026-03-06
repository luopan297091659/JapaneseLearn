import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ToolsTab extends StatelessWidget {
  const ToolsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('工具', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ToolCard(
            icon: Icons.manage_search_rounded,
            title: '辞书检索',
            subtitle: '词典查询 · 日中双向搜索',
            color: const Color(0xFF607D8B),
            onTap: () => context.push('/dictionary'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.upload_file_rounded,
            title: 'Anki 导入',
            subtitle: '导入词库 · 兼容 Anki 格式',
            color: const Color(0xFF795548),
            onTap: () => context.push('/anki-import'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.folder_copy_rounded,
            title: 'Anki 词库',
            subtitle: '本地卡片 · 离线浏览复习',
            color: const Color(0xFF00897B),
            onTap: () => context.push('/local-vocab'),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ToolCard({
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
