import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_service.dart';

enum AppAppearanceMode { classic, anime, sakura }

const _defaultAppearanceMode = AppAppearanceMode.sakura;

extension AppAppearanceModeX on AppAppearanceMode {
  String get value {
    switch (this) {
      case AppAppearanceMode.anime:
        return 'anime';
      case AppAppearanceMode.sakura:
        return 'sakura';
      case AppAppearanceMode.classic:
        return 'classic';
    }
  }

  String get label {
    switch (this) {
      case AppAppearanceMode.anime:
        return '蓝调模式';
      case AppAppearanceMode.sakura:
        return '樱花';
      case AppAppearanceMode.classic:
        return '经典模式';
    }
  }

  String get shortLabel {
    switch (this) {
      case AppAppearanceMode.anime:
        return '蓝调';
      case AppAppearanceMode.sakura:
        return '樱花';
      case AppAppearanceMode.classic:
        return '经典';
    }
  }

  static AppAppearanceMode fromValue(String? value) {
    switch (value) {
      case 'anime':
        return AppAppearanceMode.anime;
      case 'sakura':
        return AppAppearanceMode.sakura;
      default:
        return _defaultAppearanceMode;
    }
  }
}

const _kAppearanceModeKey = 'app_appearance_mode';
const _kPendingAppearanceModeSyncKey = 'pending_app_appearance_mode_sync';

class AppAppearanceNotifier extends Notifier<AppAppearanceMode> {
  @override
  AppAppearanceMode build() => _defaultAppearanceMode;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kAppearanceModeKey);
    state = AppAppearanceModeX.fromValue(saved);
    await retryPendingSync();
  }

  Future<void> setMode(AppAppearanceMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    final value = mode.value;
    await prefs.setString(_kAppearanceModeKey, value);
    await prefs.setString(_kPendingAppearanceModeSyncKey, value);
    await _syncAppearanceMode(value);
  }

  Future<void> applySavedValue(String? value) async {
    final mode = AppAppearanceModeX.fromValue(value);
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAppearanceModeKey, mode.value);
    await prefs.remove(_kPendingAppearanceModeSyncKey);
  }

  Future<void> syncCurrentModeToRemote() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kAppearanceModeKey) ?? state.value;
    await prefs.setString(_kPendingAppearanceModeSyncKey, value);
    await _syncAppearanceMode(value);
  }

  Future<void> retryPendingSync() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_kPendingAppearanceModeSyncKey) ??
        prefs.getString(_kAppearanceModeKey);
    if (pending == null || pending.isEmpty) return;
    await _syncAppearanceMode(pending);
  }

  Future<void> _syncAppearanceMode(String value) async {
    try {
      final remote =
          await syncService.syncUserPreferences(appearanceMode: value);
      final prefs = await SharedPreferences.getInstance();
      if (remote['appearance_mode'] == value) {
        await prefs.remove(_kPendingAppearanceModeSyncKey);
      } else {
        await prefs.setString(_kPendingAppearanceModeSyncKey, value);
      }
    } catch (_) {}
  }
}

final appAppearanceProvider =
    NotifierProvider<AppAppearanceNotifier, AppAppearanceMode>(
  AppAppearanceNotifier.new,
);

class AppVisualTheme extends ThemeExtension<AppVisualTheme> {
  final bool animeBackground;
  final bool sakuraBackground;

  const AppVisualTheme({
    required this.animeBackground,
    this.sakuraBackground = false,
  });

  @override
  AppVisualTheme copyWith({bool? animeBackground, bool? sakuraBackground}) {
    return AppVisualTheme(
      animeBackground: animeBackground ?? this.animeBackground,
      sakuraBackground: sakuraBackground ?? this.sakuraBackground,
    );
  }

  @override
  AppVisualTheme lerp(ThemeExtension<AppVisualTheme>? other, double t) {
    if (other is! AppVisualTheme) return this;
    return t < 0.5 ? this : other;
  }
}
