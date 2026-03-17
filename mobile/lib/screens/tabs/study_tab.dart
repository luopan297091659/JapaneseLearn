import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/membership_service.dart';

class StudyTab extends StatefulWidget {
  const StudyTab({super.key});
  @override
  State<StudyTab> createState() => _StudyTabState();
}

class _StudyTabState extends State<StudyTab> {
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
            title: '文法学习',
            subtitle: '规则掌握 · 系统学习日语文法',
            color: const Color(0xFF2196F3),
            onTap: () => context.push('/grammar'),
          ),
          const SizedBox(height: 12),
          _StudyCard(
            icon: Icons.headphones_rounded,
            title: '听力学习',
            subtitle: '听力提升 · 例句听写录音AI比对',
            color: const Color(0xFF9C27B0),
            onTap: () => context.push('/listening'),
          ),
          const SizedBox(height: 12),
          _StudyCard(
            icon: Icons.mic_rounded,
            title: 'AI 发音练习',
            subtitle: '智能纠正 · 对比原生发音',
            color: const Color(0xFF00BCD4),
            blocked: _isBlocked('pronunciation'),
            onTap: () {
              if (_isBlocked('pronunciation')) { _showMemberDialog('AI 发音练习'); return; }
              context.push('/pronunciation');
            },
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
  final bool blocked;

  const _StudyCard({
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
