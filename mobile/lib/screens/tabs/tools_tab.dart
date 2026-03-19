import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/membership_service.dart';

class ToolsTab extends StatefulWidget {
  const ToolsTab({super.key});
  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  bool _isMember = false;

  @override
  void initState() {
    super.initState();
    _loadMembership();
  }

  Future<void> _loadMembership() async {
    try {
      final user = await apiService.getMe();
      if (mounted) setState(() => _isMember = user.isMember);
    } catch (_) {}
  }

  bool _isBlocked(String tierId) =>
    !_isMember && membershipService.isBlocked(tierId, isMember: _isMember);

  void _showMemberDialog(String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(child: Text('👑', style: TextStyle(fontSize: 28))),
            ),
            const SizedBox(height: 14),
            Text('$name 需开通会员',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('升级会员即可解锁全部功能',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.push('/membership', extra: false);
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            child: const Text('查看权益'),
          ),
        ],
      ),
    );
  }

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
        actions: [
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline, color: Colors.white, size: 24),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: _isMember
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isMember ? Icons.workspace_premium : Icons.lock_open_rounded,
                          size: 10,
                          color: _isMember ? const Color(0xFFFCD34D) : Colors.white70,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _isMember ? '会员' : '免费',
                          style: TextStyle(
                            color: _isMember ? const Color(0xFFFCD34D) : Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ToolCard(
            icon: Icons.manage_search_rounded,
            title: '辞书检索',
            subtitle: '词典查询 · 日中双向搜索',
            color: const Color(0xFF607D8B),
            blocked: _isBlocked('dictionary_daily'),
            onTap: () {
              if (_isBlocked('dictionary_daily')) { _showMemberDialog('辞书检索'); return; }
              context.push('/dictionary');
            },
          ),
          const SizedBox(height: 12),
            _ToolCard(
              icon: Icons.translate_rounded,
              title: '翻译/解析',
              subtitle: 'AI翻译 · 句子分析 · TTS朗读',
              color: const Color(0xFF3949AB),
              blocked: _isBlocked('ai_features'),
              onTap: () {
                if (_isBlocked('ai_features')) { _showMemberDialog('翻译/解析'); return; }
                context.push('/translate');
              },
            ),
            const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.folder_copy_rounded,
            title: 'Anki 词库',
            subtitle: '本地卡片 · 离线浏览复习',
            color: const Color(0xFF00897B),
            blocked: _isBlocked('anki_quiz'),
            onTap: () {
              if (_isBlocked('anki_quiz')) { _showMemberDialog('Anki 词库'); return; }
              context.push('/local-vocab');
            },
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.newspaper_rounded,
            title: 'NHK 新闻阅读',
            subtitle: '实战阅读 · NHK Easy News + 注音',
            color: const Color(0xFF0077B6),
            blocked: _isBlocked('news_limit'),
            onTap: () {
              if (_isBlocked('news_limit')) { _showMemberDialog('NHK 新闻阅读'); return; }
              context.push('/news');
            },
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.headphones_rounded,
            title: '磨耳朵',
            subtitle: '沉浸式听力 · 日语频道视频',
            color: const Color(0xFFE65100),
            blocked: _isBlocked('immersion_daily'),
            onTap: () {
              if (_isBlocked('immersion_daily')) { _showMemberDialog('磨耳朵'); return; }
              context.push('/immersion');
            },
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
  final bool blocked;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: blocked ? 0.04 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: blocked ? 0.1 : 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: blocked ? 0.08 : 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: blocked ? color.withValues(alpha: 0.4) : color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16,
                  color: blocked ? color.withValues(alpha: 0.4) : color)),
                const SizedBox(height: 4),
                Text(blocked ? '会员专属功能' : subtitle,
                  style: TextStyle(fontSize: 13,
                    color: blocked ? Colors.grey : color.withValues(alpha: 0.7))),
              ],
            ),
          ),
          if (blocked)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.workspace_premium, size: 16, color: Colors.white),
            )
          else
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }
}
