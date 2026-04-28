import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/membership_service.dart';
import '../../services/guest_service.dart';
import '../../config/app_config.dart';
import '../../providers/app_appearance_provider.dart';
import '../../widgets/mode_background.dart';

class StudyTab extends StatefulWidget {
  const StudyTab({super.key});
  @override
  State<StudyTab> createState() => _StudyTabState();
}

class _StudyTabState extends State<StudyTab> {
  bool _isMember = false;
  bool _tiersReady = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    // 同步读取缓存，避免页面闪烁
    if (membershipService.hasCachedStatus) {
      _isMember = membershipService.cachedIsMember;
      _avatarUrl = membershipService.cachedAvatarUrl;
      _tiersReady = true;
    }
    _loadMembership();
  }

  Future<void> _loadMembership() async {
    try {
      final status = await membershipService.getCachedStatus();
      if (mounted) {
        setState(() {
          _isMember = status.isMember;
          _avatarUrl = status.avatarUrl;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final animeVisual = Theme.of(context).extension<AppVisualTheme>()?.animeBackground ?? false;
    Widget body = ListView(
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
          icon: Icons.mic_rounded,
          title: '发音训练',
          subtitle: '智能纠正 · 对比原生发音',
          color: const Color(0xFF00BCD4),
          blocked: _isBlocked('pronunciation'),
          onTap: () {
            if (_isBlocked('pronunciation')) { _showMemberDialog('发音训练'); return; }
            context.push('/pronunciation');
          },
        ),
        const SizedBox(height: 12),
        _StudyCard(
          icon: Icons.headphones_rounded,
          title: '听力训练',
          subtitle: '听力提升 · 例句听写录音AI比对',
          color: const Color(0xFF9C27B0),
          blocked: _isBlocked('listening_daily'),
          onTap: () {
            if (_isBlocked('listening_daily')) { _showMemberDialog('听力训练'); return; }
            context.push('/listening');
          },
        ),
        const SizedBox(height: 12),
        _StudyCard(
          icon: Icons.folder_copy_rounded,
          title: '我的词库',
          subtitle: '个人词库 · Anki/CSV/TXT 导入浏览',
          color: const Color(0xFF00897B),
          blocked: _isBlocked('anki_quiz'),
          onTap: () {
            if (GuestService.guardRoute(context, '/local-vocab')) return;
            if (_isBlocked('anki_quiz')) { _showMemberDialog('我的词库'); return; }
            context.push('/local-vocab');
          },
        ),
        const SizedBox(height: 12),
        _StudyCard(
          icon: Icons.layers_rounded,
          title: 'SRS 复习',
          subtitle: '间隔记忆 · 科学记忆曲线',
          color: const Color(0xFFFF9800),
          blocked: _isBlocked('srs_daily'),
          onTap: () {
            if (GuestService.guardRoute(context, '/srs-review')) return;
            if (_isBlocked('srs_daily')) { _showMemberDialog('SRS 复习'); return; }
            context.push('/srs-review?from=study');
          },
        ),
      ],
    );

    if (animeVisual) {
      body = AnimeModeBackground(child: body);
    }

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('学习', style: TextStyle(fontWeight: FontWeight.w800)),
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
              child: SizedBox(
                height: 52,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                              GuestService().isGuest ? '游客' : _isMember ? '会员' : '免费',
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
          ),
        ],
      ),
      body: body,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimeCardDecoration(
        color: color,
        borderRadius: 16,
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
