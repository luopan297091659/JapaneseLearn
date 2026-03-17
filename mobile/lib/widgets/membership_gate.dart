import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/membership_service.dart';

/// 会员功能锁定遮罩 — 当功能被锁定时显示升级提示
///
/// 用法:
/// ```dart
/// MembershipGate(
///   featureId: 'ai_features',
///   isMember: user.isMember,
///   child: TranslateWidget(),
/// )
/// ```
class MembershipGate extends StatelessWidget {
  final String featureId;
  final bool isMember;
  final Widget child;

  const MembershipGate({
    super.key,
    required this.featureId,
    required this.isMember,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (isMember || !membershipService.isBlocked(featureId, isMember: isMember)) {
      return child;
    }
    final info = membershipService.getTierInfo(featureId);
    return _LockedOverlay(info: info);
  }
}

class _LockedOverlay extends StatelessWidget {
  final TierInfo? info;

  const _LockedOverlay({this.info});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Text('🔒', style: TextStyle(fontSize: 36)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '${info?.icon ?? '⭐'} ${info?.name ?? '此功能'}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '此功能仅限会员使用',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            if (info != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '免费: ${info!.freeLabel}  ·  会员: ${info!.memberLabel}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showMembershipUpgradeDialog(context, featureName: info?.name),
              icon: const Text('👑', style: TextStyle(fontSize: 16)),
              label: const Text('升级会员'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 显示升级提示对话框 — 带功能对比入口
void showMembershipUpgradeDialog(BuildContext context, {String? featureName}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text('👑', style: TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            featureName != null ? '$featureName 需开通会员' : '开通会员',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '升级会员即可解锁全部功能，享受无限制的日语学习体验',
            style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Quick benefits list
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                _BenefitRow(icon: Icons.all_inclusive, text: '无限次数使用所有功能'),
                SizedBox(height: 6),
                _BenefitRow(icon: Icons.psychology, text: 'AI 发音纠正 & 翻译解析'),
                SizedBox(height: 6),
                _BenefitRow(icon: Icons.school, text: 'N5~N1 全等级内容'),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('稍后再说'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.push('/membership', extra: false);
          },
          icon: const Icon(Icons.compare_arrows, size: 18),
          label: const Text('查看权益对比'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
          ),
        ),
      ],
    ),
  );
}

/// 会员权益快速展示行
class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF92400E)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
          ),
        ),
      ],
    );
  }
}

/// 免费用户限额提示横幅 — 超限时自动弹出升级提示
class MembershipLimitBanner extends StatefulWidget {
  final String featureId;
  final bool isMember;
  final int currentUsage;

  const MembershipLimitBanner({
    super.key,
    required this.featureId,
    required this.isMember,
    this.currentUsage = 0,
  });

  @override
  State<MembershipLimitBanner> createState() => _MembershipLimitBannerState();
}

class _MembershipLimitBannerState extends State<MembershipLimitBanner> {
  bool _hasShownExhaustedDialog = false;

  @override
  void didUpdateWidget(covariant MembershipLimitBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当用量变化时重新检查是否需要弹窗
    if (widget.currentUsage != oldWidget.currentUsage) {
      _checkExhausted();
    }
  }

  @override
  void initState() {
    super.initState();
    // 延迟检查，避免在 build 中弹窗
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkExhausted());
  }

  void _checkExhausted() {
    if (widget.isMember || _hasShownExhaustedDialog) return;
    final limit = membershipService.getFreeLimit(widget.featureId);
    if (limit == null || limit <= 0) return;
    final remaining = limit - widget.currentUsage;
    if (remaining <= 0 && mounted) {
      _hasShownExhaustedDialog = true;
      final info = membershipService.getTierInfo(widget.featureId);
      showMembershipUpgradeDialog(context, featureName: info?.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMember) return const SizedBox.shrink();
    final limit = membershipService.getFreeLimit(widget.featureId);
    if (limit == null || limit <= 0) return const SizedBox.shrink();
    final info = membershipService.getTierInfo(widget.featureId);
    final remaining = limit - widget.currentUsage;
    if (remaining > limit ~/ 2) return const SizedBox.shrink(); // 超过一半才显示

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: remaining <= 0
              ? [const Color(0xFFFEE2E2), const Color(0xFFFECACA)]
              : [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            remaining <= 0 ? '🚫' : '⚠️',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  remaining <= 0
                      ? '今日${info?.name ?? '此功能'}免费次数已用完'
                      : '${info?.name ?? '此功能'}今日剩余 $remaining 次',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: remaining <= 0
                        ? const Color(0xFF991B1B)
                        : const Color(0xFF92400E),
                  ),
                ),
                if (remaining <= 0)
                  Text(
                    '开通会员可无限使用',
                    style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFF991B1B).withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => showMembershipUpgradeDialog(context, featureName: info?.name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: remaining <= 0
                    ? const Color(0xFFF59E0B)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                remaining <= 0 ? '开通会员' : '升级 👑',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: remaining <= 0 ? Colors.white : const Color(0xFF6366F1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 功能入口卡片上的会员锁定角标
class MembershipBadge extends StatelessWidget {
  final String featureId;
  final bool isMember;

  const MembershipBadge({
    super.key,
    required this.featureId,
    required this.isMember,
  });

  @override
  Widget build(BuildContext context) {
    if (isMember) return const SizedBox.shrink();
    final blocked = membershipService.isBlocked(featureId, isMember: isMember);
    if (!blocked) return const SizedBox.shrink();

    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: const Text(
          '👑',
          style: TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
