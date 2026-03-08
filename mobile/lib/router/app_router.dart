import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../l10n/app_localizations.dart';

// Screens
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/vocabulary/vocabulary_list_screen.dart';
import '../screens/vocabulary/vocabulary_detail_screen.dart';
import '../screens/grammar/grammar_list_screen.dart';
import '../screens/grammar/grammar_detail_screen.dart';
import '../screens/listening/listening_screen.dart';
import '../screens/quiz/quiz_screen.dart';
import '../screens/quiz/quiz_result_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/srs_review_screen.dart';
import '../screens/vocabulary/dictionary_screen.dart';
import '../screens/vocabulary/anki_import_screen.dart';
import '../screens/vocabulary/local_vocab_screen.dart';
import '../screens/game/tetris_grammar_game.dart';
import '../screens/game/flashcard_screen.dart';
import '../screens/tabs/study_tab.dart';
import '../screens/tabs/game_tab.dart';
import '../screens/tabs/test_tab.dart';
import '../screens/tabs/tools_tab.dart';
import '../screens/study/gojuon_screen.dart';
import '../screens/study/pronunciation_screen.dart';
import '../screens/news/news_list_screen.dart';
import '../screens/news/news_detail_screen.dart';
import '../screens/news/nhk_detail_screen.dart';
import '../screens/tools/todofuken_quiz_screen.dart';
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
      final isOnAuthPage =
          state.matchedLocation == '/login' || state.matchedLocation == '/register';

      if (!isAuth && !isOnAuthPage) return '/login';
      if (isAuth && isOnAuthPage) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/study', builder: (_, __) => const StudyTab()),
          GoRoute(path: '/games', builder: (_, __) => const GameTab()),
          GoRoute(path: '/test', builder: (_, __) => const TestTab()),
          GoRoute(path: '/tools', builder: (_, __) => const ToolsTab()),
          GoRoute(path: '/vocabulary', builder: (_, __) => const VocabularyListScreen()),
          GoRoute(
            path: '/vocabulary/:id',
            builder: (_, state) => VocabularyDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(path: '/grammar', builder: (_, __) => const GrammarListScreen()),
          GoRoute(
            path: '/grammar/:id',
            builder: (_, state) => GrammarDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(path: '/listening', builder: (_, __) => const ListeningScreen()),
          GoRoute(path: '/quiz', builder: (_, __) => const QuizScreen()),
          GoRoute(
            path: '/quiz/result',
            builder: (_, state) => QuizResultScreen(
              result: state.extra as Map<String, dynamic>,
            ),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/srs-review', builder: (_, __) => const SrsReviewScreen()),
          GoRoute(
            path: '/dictionary',
            builder: (_, state) => DictionaryScreen(
              initialQuery: state.uri.queryParameters['q'],
            ),
          ),
          GoRoute(path: '/anki-import', builder: (_, __) => const AnkiImportScreen()),
          GoRoute(path: '/local-vocab',  builder: (_, __) => const LocalVocabScreen()),
          GoRoute(
            path: '/game',
            builder: (_, state) => TetrisGrammarGame(
              gameType: (state.extra as String?) ?? 'particles',
            ),
          ),
          GoRoute(path: '/flashcard', builder: (_, __) => const FlashcardScreen()),
          GoRoute(path: '/gojuon', builder: (_, __) => const GojuonScreen()),
          GoRoute(path: '/pronunciation', builder: (_, __) => const PronunciationScreen()),
          GoRoute(path: '/news', builder: (_, __) => const NewsListScreen()),
          GoRoute(
            path: '/news/:id',
            builder: (_, state) => NewsDetailScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/nhk-news/:id',
            builder: (_, state) => NhkDetailScreen(
              newsId: state.pathParameters['id']!,
              article: state.extra as NewsArticleModel?,
            ),
          ),
          GoRoute(path: '/todofuken-quiz', builder: (_, __) => const TodofukenQuizScreen()),
        ],
      ),
    ],
  );
});

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _tabRoutes = ['/home', '/study', '/games', '/test', '/tools'];

  void _onTabTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    context.go(_tabRoutes[index]);
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync tab index with current route
    final location = GoRouterState.of(context).matchedLocation;
    int idx = _tabRoutes.indexOf(location);
    if (idx == -1) {
      // Sub-page: determine parent tab
      if (location.startsWith('/vocabulary') ||
          location.startsWith('/grammar') ||
          location.startsWith('/listening') ||
          location.startsWith('/srs-review') ||
          location.startsWith('/gojuon') ||
          location.startsWith('/flashcard') ||
          location.startsWith('/news') ||
          location.startsWith('/nhk-news')) {
        idx = 1; // 学习
      } else if (location.startsWith('/game')) {
        idx = 2; // 游戏 (covers /game, /games)
      } else if (location.startsWith('/quiz')) {
        idx = 3; // 测试
      } else if (location.startsWith('/dictionary') ||
          location.startsWith('/anki') ||
          location.startsWith('/local-vocab') ||
          location.startsWith('/todofuken')) {
        idx = 4; // 工具
      } else {
        idx = 0; // 主页
      }
    }
    if (idx != _currentIndex) {
      setState(() => _currentIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTap,
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '主页'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: '学习'),
          NavigationDestination(icon: Icon(Icons.sports_esports_outlined), selectedIcon: Icon(Icons.sports_esports_rounded), label: '游戏'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment_rounded), label: '测试'),
          NavigationDestination(icon: Icon(Icons.build_outlined), selectedIcon: Icon(Icons.build_rounded), label: '工具'),
        ],
      ),
    );
  }
}
