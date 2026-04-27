import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/guest_service.dart';

// Screens
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/vocabulary/vocabulary_list_screen.dart';
import '../screens/vocabulary/vocabulary_detail_screen.dart';
import '../screens/grammar/grammar_list_screen.dart';
import '../screens/grammar/grammar_detail_screen.dart';
import '../screens/listening/listening_screen.dart';
import '../screens/listening/listening_exercise_screen.dart';
import '../screens/quiz/quiz_screen.dart';
import '../screens/quiz/quiz_result_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/srs_review_screen.dart';
import '../screens/vocabulary/dictionary_screen.dart';
import '../screens/vocabulary/anki_import_screen.dart';
import '../screens/vocabulary/local_vocab_screen.dart';
import '../screens/vocabulary/local_vocab_detail_screen.dart';
import '../screens/game/tetris_grammar_game.dart';
import '../screens/game/flashcard_screen.dart';
import '../screens/tabs/study_tab.dart';
import '../screens/tabs/test_tab.dart';
import '../screens/tabs/tools_tab.dart';
import '../screens/study/gojuon_screen.dart';
import '../screens/study/pronunciation_screen.dart';
import '../screens/news/news_list_screen.dart';
import '../screens/news/news_detail_screen.dart';
import '../screens/news/nhk_detail_screen.dart';
import '../screens/tools/todofuken_quiz_screen.dart';
import '../screens/tools/translate_screen.dart';
import '../screens/tools/study_plan_screen.dart';
import '../screens/tools/study_plan_detail_screen.dart';
import '../screens/tools/study_plan_run_screen.dart';
import '../screens/quiz/kana_writing_test_screen.dart';
import '../screens/quiz/grammar_quiz_screen.dart';
import '../screens/tools/wrong_answers_screen.dart';
import '../screens/listening/immersion_screen.dart';
import '../screens/membership/membership_comparison_page.dart';
import '../screens/membership/qr_payment_page.dart';
import '../screens/membership/stripe_checkout_page.dart';
import '../screens/notifications/notifications_page.dart';
import '../models/models.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    redirect: (context, state) async {
      const storage = FlutterSecureStorage();
      String? token;
      try {
        token = await storage.read(key: 'access_token');
      } catch (_) {
        // Keystore mismatch or corrupted data — clear and treat as unauthenticated
        await storage.deleteAll();
        token = null;
      }
      final isAuth = token != null;
      final isGuest = guestService.isGuest;
      final isOnAuthPage = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password';

      // 游客模式：允许访问非账户功能，拦截需要登录的路径
      if (!isAuth && isGuest) {
        if (isOnAuthPage) return '/home';
        if (GuestService.isAuthRequired(state.matchedLocation)) return '/home';
        return null;
      }

      if (!isAuth && !isOnAuthPage) return '/login';
      if (isAuth && isOnAuthPage) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) => MainShell(
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/study', builder: (_, __) => const StudyTab()),
          GoRoute(path: '/test', builder: (_, __) => const TestTab()),
          GoRoute(path: '/tools', builder: (_, __) => const ToolsTab()),
          GoRoute(
            path: '/vocabulary',
            builder: (_, state) => VocabularyListScreen(
              initialLevel: state.uri.queryParameters['level'],
              planStage: state.uri.queryParameters['stage'],
              planId: state.uri.queryParameters['planId'],
            ),
          ),
          GoRoute(
            path: '/vocabulary/:id',
            builder: (_, state) {
              final ids = state.extra as List<String>?;
              return VocabularyDetailScreen(
                  id: state.pathParameters['id']!, wordIds: ids);
            },
          ),
          GoRoute(
            path: '/grammar',
            builder: (_, state) => GrammarListScreen(
              initialLevel: state.uri.queryParameters['level'],
              planStage: state.uri.queryParameters['stage'],
              planId: state.uri.queryParameters['planId'],
            ),
          ),
          GoRoute(
            path: '/grammar/:id',
            builder: (_, state) {
              final ids = state.extra as List<String>?;
              return GrammarDetailScreen(
                  id: state.pathParameters['id']!, lessonIds: ids);
            },
          ),
          GoRoute(
              path: '/listening', builder: (_, __) => const ListeningScreen()),
          GoRoute(
              path: '/listening-exercise',
              builder: (_, __) => const ListeningExerciseScreen()),
          GoRoute(path: '/quiz', builder: (_, __) => const QuizScreen()),
          GoRoute(
            path: '/grammar-quiz',
            builder: (_, state) => GrammarQuizScreen(
              initialLevel: state.uri.queryParameters['level'],
              initialCount:
                  int.tryParse(state.uri.queryParameters['count'] ?? ''),
              autoStart: state.uri.queryParameters['autostart'] == '1',
            ),
          ),
          GoRoute(
            path: '/quiz/result',
            builder: (_, state) => QuizResultScreen(
              result: state.extra as Map<String, dynamic>,
            ),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(
            path: '/srs-review',
            builder: (_, state) => SrsReviewScreen(
              from: state.uri.queryParameters['from'] ?? 'home',
            ),
          ),
          GoRoute(
            path: '/dictionary',
            builder: (_, state) => DictionaryScreen(
              initialQuery: state.uri.queryParameters['q'],
            ),
          ),
          GoRoute(
              path: '/anki-import',
              builder: (_, __) => const AnkiImportScreen()),
          GoRoute(
            path: '/local-vocab',
            builder: (_, state) => LocalVocabScreen(
              initialDeckRoot: state.uri.queryParameters['deck'],
              initialStage:
                  int.tryParse(state.uri.queryParameters['stage'] ?? ''),
              planId: state.uri.queryParameters['planId'],
            ),
          ),
          GoRoute(
            path: '/local-vocab/:id',
            builder: (_, state) => LocalVocabDetailScreen(
              cardId: state.pathParameters['id']!,
              args: state.extra as LocalVocabDetailArgs?,
            ),
          ),
          GoRoute(
            path: '/game',
            builder: (_, state) => TetrisGrammarGame(
              gameType: (state.extra as String?) ?? 'verbs',
            ),
          ),
          GoRoute(
              path: '/flashcard', builder: (_, __) => const FlashcardScreen()),
          GoRoute(path: '/gojuon', builder: (_, __) => const GojuonScreen()),
          GoRoute(
              path: '/pronunciation',
              builder: (_, __) => const PronunciationScreen()),
          GoRoute(path: '/news', builder: (_, __) => const NewsListScreen()),
          GoRoute(
            path: '/news/:id',
            builder: (_, state) =>
                NewsDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/nhk-news/:id',
            builder: (_, state) => NhkDetailScreen(
              newsId: state.pathParameters['id']!,
              article: state.extra as NewsArticleModel?,
            ),
          ),
          GoRoute(
              path: '/todofuken-quiz',
              builder: (_, __) => const TodofukenQuizScreen()),
          GoRoute(
              path: '/translate', builder: (_, __) => const TranslateScreen()),
          GoRoute(
              path: '/study-plan', builder: (_, __) => const StudyPlanScreen()),
          GoRoute(
            path: '/study-plan/:id',
            builder: (_, state) => StudyPlanDetailScreen(
              planId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/study-plan/:id/run',
            builder: (_, state) => StudyPlanRunScreen(
              planId: state.pathParameters['id']!,
              stage: state.uri.queryParameters['stage'],
            ),
          ),
          GoRoute(
              path: '/kana-writing-test',
              builder: (_, __) => const KanaWritingTestScreen()),
          GoRoute(
              path: '/wrong-answers',
              builder: (_, __) => const WrongAnswersScreen()),
          GoRoute(
              path: '/immersion', builder: (_, __) => const ImmersionScreen()),
          GoRoute(
            path: '/membership',
            builder: (_, state) => MembershipComparisonPage(
              isMember: (state.extra as bool?) ?? false,
            ),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsPage(),
          ),
          GoRoute(
            path: '/qr-payment',
            redirect: (_, __) => Platform.isIOS ? '/membership' : null,
            builder: (_, state) => QrPaymentPage(
              plan: (state.extra as Map<String, dynamic>?) ?? {},
            ),
          ),
          GoRoute(
            path: '/stripe-checkout',
            redirect: (_, __) => Platform.isIOS ? '/membership' : null,
            builder: (_, state) {
              final extra = (state.extra as Map<String, dynamic>?) ?? {};
              return StripeCheckoutPage(
                planId: extra['planId'] as String? ?? '',
                planName: extra['planName'] as String? ?? '',
              );
            },
          ),
        ],
      ),
    ],
  );
});

class MainShell extends StatefulWidget {
  final Widget child;
  final String location;
  const MainShell({super.key, required this.child, required this.location});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _tabRoutes = ['/home', '/study', '/test', '/tools'];
  late final List<Widget> _tabPages = const [
    HomeScreen(),
    StudyTab(),
    TestTab(),
    ToolsTab(),
  ];

  void _onTabTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    context.go(_tabRoutes[index]);
  }

  int _resolveTabIndex(String location) {
    int idx = _tabRoutes.indexOf(location);
    if (idx != -1) return idx;

    if (location.startsWith('/vocabulary') ||
        location.startsWith('/grammar') ||
        location.startsWith('/listening') ||
        location.startsWith('/srs-review') ||
        location.startsWith('/gojuon') ||
        location.startsWith('/flashcard') ||
        location.startsWith('/news') ||
        location.startsWith('/nhk-news') ||
        location.startsWith('/pronunciation')) {
      return 1;
    }
    if (location.startsWith('/quiz') ||
        location.startsWith('/grammar-quiz') ||
        location.startsWith('/game') ||
        location.startsWith('/listening-exercise') ||
        location.startsWith('/kana-writing-test')) {
      return 2;
    }
    if (location.startsWith('/dictionary') ||
        location.startsWith('/anki') ||
        location.startsWith('/local-vocab') ||
        location.startsWith('/todofuken') ||
        location.startsWith('/translate') ||
        location.startsWith('/study-plan') ||
        location.startsWith('/wrong-answers') ||
        location.startsWith('/immersion')) {
      return 3;
    }
    return 0;
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idx = _resolveTabIndex(widget.location);
    if (idx != _currentIndex) {
      setState(() => _currentIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTabRoot = _tabRoutes.contains(widget.location);
    return Scaffold(
      body: isTabRoot
          ? IndexedStack(
              index: _currentIndex,
              children: _tabPages,
            )
          : widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTap,
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined, size: 28),
              selectedIcon: Icon(Icons.home_rounded, size: 30),
              label: '主页'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined, size: 28),
              selectedIcon: Icon(Icons.menu_book_rounded, size: 30),
              label: '学习'),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined, size: 28),
              selectedIcon: Icon(Icons.assignment_rounded, size: 30),
              label: '测试'),
          NavigationDestination(
              icon: Icon(Icons.build_outlined, size: 28),
              selectedIcon: Icon(Icons.build_rounded, size: 30),
              label: '工具'),
        ],
      ),
    );
  }
}
