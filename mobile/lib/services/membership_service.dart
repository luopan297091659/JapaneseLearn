import '../models/models.dart';
import 'sync_service.dart';

/// 会员功能分级检查服务
///
/// 集中判断免费用户 vs 会员用户的功能访问权限。
/// 依赖 [SyncService] 中缓存的分级配置和 [UserModel.isMember]。
class MembershipService {
  static final MembershipService _instance = MembershipService._internal();
  factory MembershipService() => _instance;
  MembershipService._internal();

  /// 检查某功能对当前用户是否完全锁定
  bool isBlocked(String featureId, {required bool isMember}) {
    if (isMember) return false;
    final tier = syncService.getFeatureTier(featureId);
    // tier 未加载或未配置时，对已知 blocked 功能仍做拦截
    if (tier == null) {
      return _defaultBlockedFeatures.contains(featureId);
    }
    return tier['type'] == 'blocked';
  }

  static const _defaultBlockedFeatures = {
    'ai_features', 'pronunciation', 'anki_import', 'anki_quiz', 'wrong_answers',
  };

  /// 获取免费用户的每日/数量限额，null 表示无限制
  int? getFreeLimit(String featureId) {
    final tier = syncService.getFeatureTier(featureId);
    if (tier == null) return null;
    final type = tier['type'];
    if (type == 'daily_limit' || type == 'limit') {
      return (tier['free_limit'] as num?)?.toInt();
    }
    return null;
  }

  /// 获取免费用户的枚举可用值（如级别列表），null 表示无限制
  List<String>? getFreeValues(String featureId) {
    final tier = syncService.getFeatureTier(featureId);
    if (tier == null) return null;
    if (tier['type'] != 'enum') return null;
    final values = tier['free_values'];
    if (values is List) return values.cast<String>();
    return null;
  }

  /// 获取功能的分级描述信息（用于 UI 展示升级提示）
  TierInfo? getTierInfo(String featureId) {
    final tier = syncService.getFeatureTier(featureId);
    if (tier == null) return null;
    return TierInfo(
      id: tier['id'] as String? ?? featureId,
      name: tier['name'] as String? ?? featureId,
      icon: tier['icon'] as String? ?? '⭐',
      type: tier['type'] as String? ?? 'blocked',
      freeLabel: tier['free_label'] as String? ?? '',
      memberLabel: tier['member_label'] as String? ?? '无限制',
    );
  }
}

class TierInfo {
  final String id;
  final String name;
  final String icon;
  final String type;
  final String freeLabel;
  final String memberLabel;

  const TierInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.type,
    required this.freeLabel,
    required this.memberLabel,
  });
}

// ─── 全局单例 ──────────────────────────────────────────────────────────────────
final membershipService = MembershipService();
