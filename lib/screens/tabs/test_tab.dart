import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/membership_service.dart';
import '../../services/guest_service.dart';
import '../../services/sync_service.dart';
import '../../config/app_config.dart';
import '../../providers/app_appearance_provider.dart';
import '../../widgets/mode_background.dart';

class TestTab extends StatefulWidget {
  const TestTab({super.key});
  @override
  State<TestTab> createState() => _TestTabState();
}

class _TestTabState extends State<TestTab> {
  bool _isMember = false;
  bool _tiersReady = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadMembership();
  }

  Future<void> _loadMembership() async {
    try {
      final user = await apiService.getMe();
      await syncService.fetchFeatureTiers();
      if (mounted) {
        setState(() {
          _isMember = user.isMember;
          _avatarUrl = user.avatarUrl;
          _tiersReady = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _tiersReady = true);
    }
  }

  bool _isBlocked(String tierId) {
    if (_isMember) return false;
    if (!_tiersReady) return true;
    return membershipService.isBlocked(tierId, isMember: _isMember);
  }

  String? _resolvedAvatarUrl() {
    final avatar = _avatarUrl;
    if (avatar == null || avatar.isEmpty) return null;
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) return avatar;
    return '${AppConfig.serverRoot}$avatar';
  }

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
    final animeVisual = Theme.of(context).extension<AppVisualTheme>()?.animeBackground ?? false;
    final wrongBlocked = _isBlocked('wrong_answers');
    Widget body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TestCard(
            icon: Icons.assignment_late_rounded,
            title: '错题集',
            subtitle: '查阅测试中的错题 · 随时复习',
            color: const Color(0xFFE53935),
            blocked: wrongBlocked,
            onTap: () {
              if (GuestService.guardRoute(context, '/wrong-answers')) return;
              if (wrongBlocked) { _showMemberDialog('错题集'); return; }
              context.push('/wrong-answers');
            },
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.draw_rounded,
            title: '五十音读写',
            subtitle: '读写测试 · 练习假名书写与识读',
            color: const Color(0xFF2196F3),
            blocked: _isBlocked('kana_writing_modes'),
            onTap: () {
              if (_isBlocked('kana_writing_modes')) { _showMemberDialog('五十音读写'); return; }
              context.push('/kana-writing-test');
            },
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.quiz_rounded,
            title: '单词测验',
            subtitle: '检验水平 · 随机出题巩固知识',
            color: const Color(0xFFFF5722),
            blocked: _isBlocked('quiz_meaning_daily'),
            onTap: () {
              if (_isBlocked('quiz_meaning_daily')) { _showMemberDialog('单词测验'); return; }
              context.push('/quiz');
            },
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.menu_book_rounded,
            title: '语法测验',
            subtitle: '检验水平 · 随机出题巩固语法',
            color: const Color(0xFF7B1FA2),
            blocked: _isBlocked('grammar_quiz_daily'),
            onTap: () {
              if (_isBlocked('grammar_quiz_daily')) { _showMemberDialog('语法测验'); return; }
              context.push('/grammar-quiz');
            },
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.hearing_rounded,
            title: '听力测验',
            subtitle: '听句选义 · N5-N1 例句听力测验',
            color: const Color(0xFFE040FB),
            blocked: _isBlocked('listening_exercise_daily'),
            onTap: () {
              if (_isBlocked('listening_exercise_daily')) { _showMemberDialog('听力测验'); return; }
              context.push('/listening-exercise');
            },
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.sports_esports_rounded,
            title: '闯关游戏',
            subtitle: '助词方块 · 动词方块 · 闯关挑战',
            color: const Color(0xFF4CAF50),
            blocked: _isBlocked('game_levels'),
            onTap: () {
              if (_isBlocked('game_levels')) { _showMemberDialog('闯关游戏'); return; }
              _showGameTypeSelection(context);
            },
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.map_rounded,
            title: '都道府県测验',
            subtitle: '地理测验 · 学习 47 个都道府県读音',
            color: const Color(0xFFE65100),
            onTap: () => context.push('/todofuken-quiz'),
          ),
        ],
      );

    if (animeVisual) {
      body = AnimeModeBackground(child: body);
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('测试', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          GestureDetector(
            onTap: () {
              if (GuestService.guardRoute(context, '/profile')) return;
              context.push('/profile');
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.4),
                    ),
                    child: ClipOval(
                      child: _resolvedAvatarUrl() != null
                          ? Image.network(
                              _resolvedAvatarUrl()!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.person_outline, color: Colors.white, size: 20),
                            )
                          : const Icon(Icons.person_outline, color: Colors.white, size: 20),
                    ),
                  ),
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
      body: body,
    );
  }
}

class _TestCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool blocked;

  const _TestCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimeCardDecoration(
        color: color,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: blocked ? (isDark ? 0.12 : 0.04) : (isDark ? 0.22 : 0.08)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: blocked ? (isDark ? 0.25 : 0.1) : (isDark ? 0.45 : 0.2))),
          ),
          child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: blocked ? (isDark ? 0.18 : 0.08) : (isDark ? 0.35 : 0.18)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: blocked ? color.withValues(alpha: isDark ? 0.6 : 0.4) : color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16,
                  color: blocked ? color.withValues(alpha: isDark ? 0.6 : 0.4) : color)),
                const SizedBox(height: 4),
                Text(blocked ? '会员专属功能' : subtitle,
                  style: TextStyle(fontSize: 13,
                    color: blocked ? Colors.grey : color.withValues(alpha: isDark ? 0.85 : 0.7))),
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
      ),
    );
  }
}
