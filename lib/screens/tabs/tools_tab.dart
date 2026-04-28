import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/membership_service.dart';
import '../../services/guest_service.dart';
import '../../config/app_config.dart';
import '../../providers/app_appearance_provider.dart';
import '../../widgets/mode_background.dart';

class ToolsTab extends StatefulWidget {
  const ToolsTab({super.key});
  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  bool _isMember = false;
  bool _tiersReady = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
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
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return avatar;
    }
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
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                  child: Text('👑', style: TextStyle(fontSize: 28))),
            ),
            const SizedBox(height: 14),
            Text('$name 需开通会员',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B)),
            child: const Text('查看权益'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final animeVisual =
        Theme.of(context).extension<AppVisualTheme>()?.animeBackground ?? false;
    Widget body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ToolCard(
          icon: Icons.route_rounded,
          title: '学习计划',
          subtitle: '自定义组合：单词/语法复习',
          color: const Color(0xFF6D28D9),
          blocked: _isBlocked('study_plan_daily'),
          onTap: () {
            if (GuestService.guardRoute(context, '/study-plan')) return;
            if (_isBlocked('study_plan_daily')) {
              _showMemberDialog('学习计划');
              return;
            }
            context.push('/study-plan');
          },
        ),
        const SizedBox(height: 12),
        _ToolCard(
          icon: Icons.manage_search_rounded,
          title: '辞书检索',
          subtitle: '词典查询 · 日中双向搜索',
          color: const Color(0xFF607D8B),
          blocked: _isBlocked('dictionary_daily'),
          onTap: () {
            if (_isBlocked('dictionary_daily')) {
              _showMemberDialog('辞书检索');
              return;
            }
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
            if (_isBlocked('ai_features')) {
              _showMemberDialog('翻译/解析');
              return;
            }
            context.push('/translate');
          },
        ),
        // 磨耳朵暂时隐藏
        const SizedBox(height: 12),
        _ToolCard(
          icon: Icons.headphones_rounded,
          title: '磨耳朵',
          subtitle: '沉浸式听力 · 日语频道视频',
          color: const Color(0xFFE65100),
          blocked: _isBlocked('immersion_daily'),
          onTap: () {
            if (_isBlocked('immersion_daily')) {
              _showMemberDialog('磨耳朵');
              return;
            }
            context.push('/immersion');
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
            if (_isBlocked('news_limit')) {
              _showMemberDialog('NHK 新闻阅读');
              return;
            }
            context.push('/news');
          },
        ),
      ],
    );

    if (animeVisual) {
      body = AnimeModeBackground(child: body);
    }
    return Scaffold(
      backgroundColor:
          isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('工具', style: TextStyle(fontWeight: FontWeight.w800)),
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
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                          width: 1.4),
                    ),
                    child: ClipOval(
                      child: _resolvedAvatarUrl() != null
                          ? Image.network(
                              _resolvedAvatarUrl()!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_outline,
                                  color: Colors.white,
                                  size: 20),
                            )
                          : const Icon(Icons.person_outline,
                              color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                          _isMember
                              ? Icons.workspace_premium
                              : Icons.lock_open_rounded,
                          size: 10,
                          color: _isMember
                              ? const Color(0xFFFCD34D)
                              : Colors.white70,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          GuestService().isGuest
                              ? '游客'
                              : _isMember
                                  ? '会员'
                                  : '免费',
                          style: TextStyle(
                            color: _isMember
                                ? const Color(0xFFFCD34D)
                                : Colors.white70,
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? Color.alphaBlend(color.withValues(alpha: blocked ? 0.08 : 0.16),
            cs.surfaceContainerHigh)
        : color.withValues(alpha: blocked ? 0.04 : 0.08);
    final iconBg = isDark
        ? Color.alphaBlend(color.withValues(alpha: blocked ? 0.14 : 0.24),
            cs.surfaceContainerHighest)
        : color.withValues(alpha: blocked ? 0.08 : 0.18);
    final titleColor = blocked
        ? (isDark ? cs.onSurfaceVariant : color.withValues(alpha: 0.4))
        : (isDark
            ? Color.alphaBlend(color.withValues(alpha: 0.45), Colors.white)
            : color);
    final subtitleColor = blocked
        ? (isDark ? cs.outline : Colors.grey)
        : (isDark ? cs.onSurfaceVariant : color.withValues(alpha: 0.7));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimeCardDecoration(
        color: color,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: color.withValues(
                    alpha: blocked
                        ? (isDark ? 0.22 : 0.1)
                        : (isDark ? 0.52 : 0.2))),
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon,
                  color: blocked
                      ? color.withValues(alpha: isDark ? 0.7 : 0.4)
                      : titleColor,
                  size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: titleColor)),
                  const SizedBox(height: 4),
                  Text(blocked ? '会员专属功能' : subtitle,
                      style: TextStyle(fontSize: 13, color: subtitleColor)),
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
                child: const Icon(Icons.workspace_premium,
                    size: 16, color: Colors.white),
              )
            else
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: color.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }
}
