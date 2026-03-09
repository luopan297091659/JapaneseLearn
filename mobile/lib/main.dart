import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'router/app_router.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'utils/tts_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  apiService.init();
  apiService.setOnSessionReplaced(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      GoRouter.of(ctx).go('/login');
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
        const SnackBar(
          content: Text('你的账号已在其他设备登录，请重新登录'),
          duration: Duration(seconds: 5),
        ),
      );
    });
  });
  // 启动时读取持久化语言设置
  final container = ProviderContainer();
  await container.read(localeProvider.notifier).init();
  // 后台检测服务端内容版本，有更新则清除缓存
  syncService.checkContentVersion();
  // 后台拉取功能开关
  syncService.fetchFeatureToggles();
  // 预初始化 TTS 引擎诊断
  TtsHelper.instance.init();
  runApp(UncontrolledProviderScope(container: container, child: const JapaneseLearnApp()));
}

class JapaneseLearnApp extends ConsumerWidget {
  const JapaneseLearnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: '言旅 Kotabi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      // ── 国际化配置 ──
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class AppTheme {
  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFE63946), // Japanese red
      brightness: Brightness.light,
    ),
    fontFamily: 'NotoSansJP',
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFE63946),
      brightness: Brightness.dark,
    ),
    fontFamily: 'NotoSansJP',
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
