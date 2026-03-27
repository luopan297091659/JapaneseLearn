import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_service.dart';

enum AppAppearanceMode { classic, anime }

const _kAppearanceModeKey = 'app_appearance_mode';

class AppAppearanceNotifier extends Notifier<AppAppearanceMode> {
  @override
  AppAppearanceMode build() => AppAppearanceMode.classic;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kAppearanceModeKey);
    if (saved == 'anime') {
      state = AppAppearanceMode.anime;
      return;
    }
    state = AppAppearanceMode.classic;
  }

  Future<void> setMode(AppAppearanceMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    final value = mode == AppAppearanceMode.anime ? 'anime' : 'classic';
    await prefs.setString(_kAppearanceModeKey, value);
    try {
      await syncService.syncUserPreferences(appearanceMode: value);
    } catch (_) {}
  }
}

final appAppearanceProvider =
    NotifierProvider<AppAppearanceNotifier, AppAppearanceMode>(
      AppAppearanceNotifier.new,
    );

class AppVisualTheme extends ThemeExtension<AppVisualTheme> {
  final bool animeBackground;

  const AppVisualTheme({required this.animeBackground});

  @override
  AppVisualTheme copyWith({bool? animeBackground}) {
    return AppVisualTheme(
      animeBackground: animeBackground ?? this.animeBackground,
    );
  }

  @override
  AppVisualTheme lerp(ThemeExtension<AppVisualTheme>? other, double t) {
    if (other is! AppVisualTheme) return this;
    return t < 0.5 ? this : other;
  }
}
