import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLangKey = 'app_language';

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('zh'); // 默认中文

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLangKey);
    if (saved != null) state = Locale(saved);
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, locale.languageCode);
  }

  Future<void> toggle() async {
    await setLocale(state.languageCode == 'zh' ? const Locale('en') : const Locale('zh'));
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
