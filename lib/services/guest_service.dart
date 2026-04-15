import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 游客模式管理：仅 iOS 生效（Apple 审核要求），Android 始终返回 false
class GuestService {
  static final GuestService _instance = GuestService._();
  factory GuestService() => _instance;
  GuestService._();

  static const _key = 'guest_mode';

  bool _isGuest = false;
  bool get isGuest => Platform.isIOS && _isGuest;

  Future<void> init() async {
    if (!Platform.isIOS) return;
    final prefs = await SharedPreferences.getInstance();
    _isGuest = prefs.getBool(_key) ?? false;
  }

  Future<void> enableGuestMode() async {
    if (!Platform.isIOS) return;
    _isGuest = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  Future<void> disableGuestMode() async {
    _isGuest = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 需要登录的功能路径
  static const _authRequiredPaths = {
    '/srs-review',
    '/study-plan',
    '/wrong-answers',
    '/profile',
    '/anki-import',
    '/local-vocab',
    '/membership',
    '/qr-payment',
    '/stripe-checkout',
  };

  /// 检查路径是否需要登录
  static bool isAuthRequired(String path) {
    return _authRequiredPaths.any((p) => path.startsWith(p));
  }

  /// 游客尝试访问需登录功能时弹出提示，返回 true 表示已拦截
  static bool guardRoute(BuildContext context, String path) {
    if (!GuestService().isGuest) return false;
    if (!isAuthRequired(path)) return false;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.login, color: Colors.orange, size: 28),
          SizedBox(width: 8),
          Expanded(child: Text('需要登录')),
        ]),
        content: const Text('此功能需要登录账号后使用。\n登录后可享受完整的学习体验！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              GuestService().disableGuestMode();
              GoRouter.of(context).go('/login');
            },
            child: const Text('去登录'),
          ),
        ],
      ),
    );
    return true;
  }
}

final guestService = GuestService();
