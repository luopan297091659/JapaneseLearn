import '../models/models.dart';
import 'api_service.dart';
import 'sync_service.dart';

/// 会员功能分级检查服务
///
/// 集中判断免费用户 vs 会员用户的功能访问权限。
/// 依赖 [SyncService] 中缓存的分级配置和 [UserModel.isMember]。
class MembershipService {
  static final MembershipService _instance = MembershipService._internal();
  factory MembershipService() => _instance;
  MembershipService._internal();

  // ── 会员状态本地缓存 ──────────────────────────────────────────────
  bool _cachedIsMember = false;
  String? _cachedAvatarUrl;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// 是否有有效缓存（供同步读取，避免页面闪烁）
  bool get hasCachedStatus => _cacheTime != null;
  bool get cachedIsMember => _cachedIsMember;
  String? get cachedAvatarUrl => _cachedAvatarUrl;

  /// 获取缓存的会员状态，如未缓存则自动加载
  Future<({bool isMember, String? avatarUrl})> getCachedStatus() async {
    if (_cacheTime != null && DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return (isMember: _cachedIsMember, avatarUrl: _cachedAvatarUrl);
    }
    try {
      final user = await apiService.getMe();
      await syncService.fetchFeatureTiers();
      updateCache(isMember: user.isMember, avatarUrl: user.avatarUrl);
      return (isMember: _cachedIsMember, avatarUrl: _cachedAvatarUrl);
    } catch (_) {
      return (isMember: _cachedIsMember, avatarUrl: _cachedAvatarUrl);
    }
  }

  /// 外部更新缓存（如 home 页面已加载用户信息后同步过来）
  void updateCache({required bool isMember, String? avatarUrl}) {
    _cachedIsMember = isMember;
    _cachedAvatarUrl = avatarUrl;
    _cacheTime = DateTime.now();
  }

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
