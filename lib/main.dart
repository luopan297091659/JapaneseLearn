import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'services/guest_service.dart';
import 'router/app_router.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'utils/tts_helper.dart';
import 'services/plan_reminder_service.dart';
import 'providers/app_appearance_provider.dart';

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
  apiService.setOnMembershipLimit((data) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      final error = data['error'] as String? ?? '';
      final msg = data['message'] as String? ?? '此功能需要会员';
      showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(error == 'DAILY_LIMIT_REACHED' ? Icons.hourglass_empty : Icons.lock,
                color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('会员功能')),
          ]),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                GoRouter.of(ctx).push('/membership', extra: false);
              },
              child: const Text('查看会员'),
            ),
          ],
        ),
      );
    });
  });
  // 启动时读取持久化语言设置
  final container = ProviderContainer();
  await container.read(localeProvider.notifier).init();
  await container.read(appAppearanceProvider.notifier).init();
  // 初始化游客模式状态
  await guestService.init();
  // 后台检测服务端内容版本，有更新则清除缓存
  syncService.checkContentVersion();
  // 后台拉取功能开关
  syncService.fetchFeatureToggles();
  // 后台拉取功能分级配置
  syncService.fetchFeatureTiers();
  // 预初始化 TTS 引擎诊断
  TtsHelper.instance.init();
  // 初始化学习计划提醒服务
  await PlanReminderService.instance.init();
  runApp(UncontrolledProviderScope(container: container, child: const JapaneseLearnApp()));
}

class JapaneseLearnApp extends ConsumerWidget {
  const JapaneseLearnApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    final appearance = ref.watch(appAppearanceProvider);
    final isAnime = appearance == AppAppearanceMode.anime;
    return MaterialApp.router(
      title: '言旅 Kotabi',
      debugShowCheckedModeBanner: false,
      theme: isAnime ? AppTheme.animeLight : AppTheme.light,
      darkTheme: isAnime ? AppTheme.animeDark : AppTheme.dark,
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
    extensions: const [
      AppVisualTheme(animeBackground: false),
    ],
  );

  static final dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFE63946),
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF1C1B1F),
      surfaceContainerLowest: const Color(0xFF1C1B1F),
      surfaceContainerLow: const Color(0xFF211F23),
      surfaceContainer: const Color(0xFF262428),
      surfaceContainerHigh: const Color(0xFF2B292D),
      surfaceContainerHighest: const Color(0xFF312F33),
    ),
    scaffoldBackgroundColor: const Color(0xFF1C1B1F),
    fontFamily: 'NotoSansJP',
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    extensions: const [
      AppVisualTheme(animeBackground: false),
    ],
  );

  static final animeLight = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF29B6F6),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF039BE5),
      secondary: const Color(0xFF9575CD),
      tertiary: const Color(0xFF4DD0E1),
      surface: const Color(0xFFFFFFFF),
      surfaceContainerLowest: const Color(0xFFFCFEFF),
      surfaceContainerLow: const Color(0xFFF7FBFF),
      surfaceContainer: const Color(0xFFF2F9FF),
      surfaceContainerHigh: const Color(0xFFEFF7FF),
      onSurface: const Color(0xFF0F2940),
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
    extensions: const [
      AppVisualTheme(animeBackground: true),
    ],
  );

  static final animeDark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E88E5),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF42A5F5),
      secondary: const Color(0xFFB39DDB),
      tertiary: const Color(0xFF4DD0E1),
      surface: const Color(0xFF151B2E),
      surfaceContainerLowest: const Color(0xFF151B2E),
      surfaceContainerLow: const Color(0xFF1A2035),
      surfaceContainer: const Color(0xFF1E253C),
      surfaceContainerHigh: const Color(0xFF242B42),
      surfaceContainerHighest: const Color(0xFF2A3148),
    ),
    scaffoldBackgroundColor: const Color(0xFF151B2E),
    fontFamily: 'NotoSansJP',
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    extensions: const [
      AppVisualTheme(animeBackground: true),
    ],
  );
}
