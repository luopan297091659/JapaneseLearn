import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/sync_service.dart';
import '../../services/membership_service.dart';

/// 会员功能对比页面 — 展示免费用户与会员用户的功能差异
class MembershipComparisonPage extends StatefulWidget {
  final bool isMember;
  const MembershipComparisonPage({super.key, required this.isMember});

  @override
  State<MembershipComparisonPage> createState() => _MembershipComparisonPageState();
}

class _MembershipComparisonPageState extends State<MembershipComparisonPage> {
  List<Map<String, dynamic>> _tiers = [];
  bool _loading = true;
  bool _isMember = false;
  bool _isTrial = false;
  bool _trialActivated = false;
  int? _daysLeft;
  bool _trialEnabled = false;
  int _trialDays = 3;
  String _trialDesc = '';
  bool _activating = false;

  @override
  void initState() {
    super.initState();
    _isMember = widget.isMember;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        syncService.fetchFeatureTiers(force: true),
        apiService.getMe(force: true),
        apiService.getTrialConfig(),
      ]);
      final tiers = results[0] as List<Map<String, dynamic>>;
      final user = results[1] as dynamic;
      final trialCfg = results[2] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _tiers = tiers;
          _isMember = user.isMember;
          _isTrial = user.isTrial;
          _trialActivated = user.trialActivated;
          _daysLeft = user.membershipDaysLeft;
          _trialEnabled = trialCfg['enabled'] == true;
          _trialDays = trialCfg['days'] as int? ?? 3;
          _trialDesc = trialCfg['description'] as String? ?? '';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('会员权益对比'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header banner
                _buildHeaderBanner(cs),
                const SizedBox(height: 16),
                // Trial section
                _buildTrialSection(cs),
                const SizedBox(height: 20),
                // Comparison table
                _buildComparisonTable(cs),
                const SizedBox(height: 24),
                // Membership plans
                _buildPlansSection(cs),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildHeaderBanner(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFF59E0B), const Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('👑', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text(
            '升级会员，解锁全部功能',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isMember ? '您已是尊贵会员' : '享受无限制的日语学习体验',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
          if (_isMember && _daysLeft != null) ...[
            const SizedBox(height: 6),
            Text(
              _isTrial ? '体验剩余 $_daysLeft 天' : '会员剩余 $_daysLeft 天',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
          ],
          if (_isMember) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(_isTrial ? '体验中' : '已开通', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrialSection(ColorScheme cs) {
    // Already a member — no trial needed
    if (_isMember) return const SizedBox.shrink();

    // Trial already used
    if (_trialActivated) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: cs.outline, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text('您已使用过会员体验，每个账号仅限一次',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
          ],
        ),
      );
    }

    // Trial not enabled by admin
    if (!_trialEnabled) return const SizedBox.shrink();

    // Show trial activation card
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('🎁', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 10),
          const Text('免费体验会员',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(_trialDesc.isNotEmpty ? _trialDesc : '免费体验全部会员功能',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 4),
          Text('体验时长：$_trialDays 天，每个账号仅限一次',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _activating ? null : _activateTrial,
              icon: _activating
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(_activating ? '开通中...' : '立即开通体验'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activateTrial() async {
    setState(() => _activating = true);
    try {
      final result = await apiService.activateTrial();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? '已成功开通会员体验！'),
            backgroundColor: Colors.green,
          ),
        );
        // Reload data to reflect new state
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('已使用过') ? '您已使用过会员体验，每个账号仅限一次'
            : e.toString().contains('已经是会员') ? '您已经是会员，无需开通体验'
            : '开通失败，请稍后重试';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Widget _buildComparisonTable(ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('功能', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text('免费用户', style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13, color: cs.outline,
                    )),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('👑 会员',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Table rows from tiers
          ..._tiers.asMap().entries.map((entry) {
            final i = entry.key;
            final tier = entry.value;
            final isLast = i == _tiers.length - 1;
            return _buildComparisonRow(
              cs: cs,
              icon: tier['icon'] ?? '⭐',
              name: tier['name'] ?? '',
              freeLabel: tier['free_label'] ?? '',
              memberLabel: tier['member_label'] ?? '',
              type: tier['type'] ?? 'blocked',
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildComparisonRow({
    required ColorScheme cs,
    required String icon,
    required String name,
    required String freeLabel,
    required String memberLabel,
    required String type,
    required bool isLast,
  }) {
    // Determine free status icon/color
    Widget freeWidget;
    if (type == 'blocked') {
      freeWidget = const Icon(Icons.close_rounded, color: Colors.red, size: 20);
    } else {
      freeWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, color: Colors.green, size: 16),
          const SizedBox(width: 2),
          Flexible(
            child: Text(freeLabel,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(child: freeWidget),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check, color: Colors.green, size: 16),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(memberLabel,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlansSection(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.card_membership_rounded, size: 20, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('会员方案', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        _PlanCard(
          name: '月度会员',
          price: '¥18',
          period: '/月',
          features: const ['全部功能解锁', '按月计费', '随时取消'],
          color: cs.primary,
          highlighted: false,
        ),
        const SizedBox(height: 12),
        _PlanCard(
          name: '年度会员',
          price: '¥128',
          period: '/年',
          features: const ['全部功能解锁', '比月付省41%', '优先更新体验'],
          color: const Color(0xFFF59E0B),
          highlighted: true,
          badge: '最受欢迎',
        ),
        const SizedBox(height: 12),
        _PlanCard(
          name: '终身会员',
          price: '¥398',
          period: '',
          features: const ['一次购买永久使用', '含未来所有新功能', '专属徽章'],
          color: const Color(0xFF7C3AED),
          highlighted: false,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '会员付费功能即将上线，敬请期待！\n目前可免费体验全部会员功能',
            style: TextStyle(fontSize: 13, color: cs.outline),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String price;
  final String period;
  final List<String> features;
  final Color color;
  final bool highlighted;
  final String? badge;

  const _PlanCard({
    required this.name,
    required this.price,
    required this.period,
    required this.features,
    required this.color,
    this.highlighted = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? color : cs.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
        color: highlighted ? color.withValues(alpha: 0.05) : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: color,
                      )),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(price, style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w900, color: color,
                          )),
                          if (period.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(period, style: TextStyle(
                                fontSize: 14, color: color.withValues(alpha: 0.7),
                              )),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...features.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 14, color: color),
                            const SizedBox(width: 6),
                            Text(f, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (badge != null)
            Positioned(
              top: 0,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: Text(badge!,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}
