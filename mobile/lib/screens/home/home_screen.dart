import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/sync_service.dart';
import '../../models/models.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/japanese_text_utils.dart';

// ── 全部可选功能（ID → 元数据） ──
const _allFeatures = <String, ({IconData icon, String label, String sub, String path, Color color})>{
  'gojuon':        (icon: Icons.grid_view_rounded,      label: '五十音',     sub: '基础入门', path: '/gojuon',          color: Color(0xFFE91E63)),
  'vocabulary':    (icon: Icons.menu_book_rounded,      label: '单词学习',   sub: '词汇积累', path: '/vocabulary',      color: Color(0xFF4CAF50)),
  'grammar':       (icon: Icons.school_rounded,         label: '文法学习',   sub: '规则掌握', path: '/grammar',         color: Color(0xFF2196F3)),
  'listening':     (icon: Icons.headphones_rounded,     label: '听力练习',   sub: '提升听力', path: '/listening',       color: Color(0xFF9C27B0)),
  'pronunciation': (icon: Icons.mic_rounded,            label: '发音练习',   sub: 'AI智能纠正', path: '/pronunciation',  color: Color(0xFF00BCD4)),
  'srs':           (icon: Icons.layers_rounded,         label: 'SRS复习',    sub: '间隔记忆', path: '/srs-review',     color: Color(0xFFFF9800)),
  'flashcard':     (icon: Icons.style_rounded,          label: '闪卡练习',   sub: '翻转记忆', path: '/flashcard',      color: Color(0xFF3F51B5)),
  'dictionary':    (icon: Icons.manage_search_rounded,  label: '辞书检索',   sub: '词典查询', path: '/dictionary',     color: Color(0xFF607D8B)),
  'translate':     (icon: Icons.translate_rounded,      label: '翻译解析',   sub: 'AI句子分析', path: '/translate',    color: Color(0xFF3949AB)),
  'quiz':          (icon: Icons.quiz_rounded,           label: '单词随机测验',   sub: '检验水平', path: '/quiz',           color: Color(0xFFFF5722)),
  'news':          (icon: Icons.article_rounded,        label: 'NHK新闻',   sub: '阅读训练', path: '/news',           color: Color(0xFF00897B)),
  'game':          (icon: Icons.sports_esports_rounded, label: '闯关游戏',   sub: '趣味闯关', path: '/game',           color: Color(0xFFE91E63)),
  'todofuken':     (icon: Icons.map_rounded,            label: '都道府県',   sub: '地理测验', path: '/todofuken-quiz', color: Color(0xFFE65100)),
  'wrong-answers': (icon: Icons.assignment_late_rounded, label: '错题集',    sub: '错题复习', path: '/wrong-answers', color: Color(0xFFE53935)),
  'anki':          (icon: Icons.upload_file_rounded,    label: 'Anki导入',  sub: '导入词库', path: '/anki-import',    color: Color(0xFF795548)),
  'localvocab':    (icon: Icons.folder_copy_rounded,    label: 'Anki词库',  sub: '本地浏览', path: '/local-vocab',    color: Color(0xFF00897B)),
};
const _defaultFeatureIds = ['vocabulary', 'grammar', 'srs', 'flashcard', 'listening', 'dictionary'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  UserModel? _user;
  Map<String, dynamic>? _srsStats;
  Map<String, dynamic>? _dailyGoals;
  List<VocabularyModel> _wordPool = [];
  int _wordIndex = 0;

  // 各区域独立加载状态，不再阻塞整页显示
  bool _userLoading   = true;
  bool _srsLoading    = true;
  bool _wordLoading   = true;
  bool _goalsLoading  = true;
  bool _wordRevealed  = false;

  // 是否正在刷新（下拉刷新时用）
  bool _refreshing = false;

  // 常用功能自定义列表（最多6个）
  List<String> _favFeatureIds = List.from(_defaultFeatureIds);

  // 可用功能（经服务端开关过滤后）
  Map<String, ({IconData icon, String label, String sub, String path, Color color})> _enabledFeatures = Map.from(_allFeatures);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFavFeatures();
    _loadFeatureToggles();
    _loadAll(fromCache: true);
    // 后台检测服务端内容版本是否有更新
    Future.microtask(() async {
      final updated = await syncService.checkContentVersion();
      if (updated && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✨ 词库/语法已更新，重新打开列表即可看到新内容'),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: '查看词汇',
              onPressed: () => context.push('/vocabulary'),
            ),
          ),
        );
      }
    });
  }

  /// [fromCache] true = 先用缓存立即渲染，后台同步刷新；false = 强制刷新
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台回来时清除缓存、同步最新数据
      apiService.invalidateCache();
      _loadAll(fromCache: false);
    }
  }

  /// [fromCache] true = 先用缓存立即渲染，后台同步刷新；false = 强制刷新
  Future<void> _loadAll({bool fromCache = false}) async {
    if (!fromCache) {
      setState(() => _refreshing = true);
    }
    // 先加载用户信息，获取 JLPT 等级后再加载今日一词
    // SRS 和每日目标不依赖用户等级，可与用户加载并行
    await Future.wait([
      _loadUser(),
      _loadSrs(),
      _loadDailyGoals(),
    ]);
    await _loadWordOfDay();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _loadUser() async {
    setState(() => _userLoading = true);
    try {
      final user = await apiService.getMe();
      if (mounted) setState(() { _user = user; _userLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _userLoading = false);
    }
  }

  Future<void> _loadSrs() async {
    setState(() => _srsLoading = true);
    try {
      final stats = await apiService.getSrsStats();
      if (mounted) setState(() { _srsStats = stats; _srsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _srsLoading = false);
    }
  }

  Future<void> _loadDailyGoals() async {
    setState(() => _goalsLoading = true);
    try {
      final data = await apiService.getDailyGoals();
      if (mounted) setState(() { _dailyGoals = data; _goalsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _goalsLoading = false);
    }
  }

  Future<void> _loadWordOfDay() async {
    setState(() => _wordLoading = true);
    try {
      // 使用用户的 JLPT 等级过滤单词
      final level = _user?.level ?? 'N5';
      final res = await apiService.getVocabulary(level: level, limit: 20, page: 1);
      final words = res['data'] as List<VocabularyModel>;
      if (words.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final todayStr = DateTime.now().toIso8601String().substring(0, 10);
        final savedDate = prefs.getString('wod_date');
        final savedIdx = prefs.getInt('wod_index');
        final savedLevel = prefs.getString('wod_level');

        int startIdx;
        if (savedDate == todayStr && savedIdx != null && savedLevel == level) {
          // 同一天且同等级，复用已保存的索引（包括用户换过词后的索引）
          startIdx = savedIdx % words.length;
        } else {
          // 新的一天或等级变化，按日期种子生成初始索引
          final seed = DateTime.now().year * 10000 +
              DateTime.now().month * 100 +
              DateTime.now().day;
          startIdx = Random(seed).nextInt(words.length);
          await prefs.setString('wod_date', todayStr);
          await prefs.setInt('wod_index', startIdx);
          await prefs.setString('wod_level', level);
        }
        if (mounted) setState(() {
          _wordPool  = words;
          _wordIndex = startIdx;
          _wordRevealed = false;
          _wordLoading = false;
        });
      } else {
        if (mounted) setState(() => _wordLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _wordLoading = false);
    }
  }

  void _nextWord() async {
    if (_wordPool.isEmpty) return;
    final newIdx = (_wordIndex + 1) % _wordPool.length;
    // 持久化索引，杀掉进程重新进仍显示换过的词
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wod_index', newIdx);
    if (mounted) setState(() {
      _wordIndex = newIdx;
      _wordRevealed = false;
    });
  }

  // ── 常用功能持久化 ──
  Future<void> _loadFavFeatures() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList('home_fav_features');
    if (saved != null && saved.isNotEmpty) {
      setState(() => _favFeatureIds = saved.where((id) => _allFeatures.containsKey(id)).toList());
    }
  }

  Future<void> _saveFavFeatures() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('home_fav_features', _favFeatureIds);
  }

  Future<void> _loadFeatureToggles() async {
    final toggles = await syncService.fetchFeatureToggles();
    if (!mounted) return;
    setState(() {
      _enabledFeatures = Map.fromEntries(
        _allFeatures.entries.where((e) => toggles[e.key] ?? true),
      );
      // 移除被关闭的收藏功能
      _favFeatureIds = _favFeatureIds.where((id) => _enabledFeatures.containsKey(id)).toList();
    });
  }

  void _editFavFeatures() {
    // 临时副本
    final selected = List<String>.from(_favFeatureIds);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('编辑常用功能', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${selected.length}/6', style: TextStyle(fontSize: 13, color: selected.length > 6 ? Colors.red : Colors.grey)),
              ]),
              const SizedBox(height: 4),
              const Text('点击添加或移除，最多保留 6 个', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: _enabledFeatures.entries.map((e) {
                  final on = selected.contains(e.key);
                  return FilterChip(
                    avatar: Icon(e.value.icon, size: 18, color: on ? Colors.white : e.value.color),
                    label: Text(e.value.label),
                    selected: on,
                    selectedColor: e.value.color,
                    labelStyle: TextStyle(color: on ? Colors.white : null, fontWeight: FontWeight.w600, fontSize: 12),
                    onSelected: (v) {
                      setSheetState(() {
                        if (v) { if (selected.length < 6) selected.add(e.key); }
                        else { selected.remove(e.key); }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                )),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(
                  onPressed: () {
                    setState(() => _favFeatureIds = selected);
                    _saveFavFeatures();
                    Navigator.pop(ctx);
                  },
                  child: const Text('保存'),
                )),
              ]),
            ]),
          );
        },
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6)  return 'こんばんは 🌙';
    if (h < 12) return 'おはようございます ☀️';
    if (h < 18) return 'こんにちは 🌤️';
    return 'こんばんは 🌙';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 从 dailyGoals 提取数据
    final totalXp = _dailyGoals?['total_xp'] ?? 0;
    final streakDays = _dailyGoals?['streak_days'] ?? _user?.streakDays ?? 0;
    final todayXp = _dailyGoals?['today']?['xp_earned'] ?? 0;
    final todaySeconds = _dailyGoals?['today']?['study_seconds'] ?? 0;
    final todayMinutes = (todaySeconds as int) ~/ 60;
    final goals = _dailyGoals?['goals'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: RefreshIndicator(
        onRefresh: () => _loadAll(fromCache: false),
        child: CustomScrollView(
          slivers: [
            // ── App Bar ────────────────────────────────────────────
            _buildSliverHeader(cs, totalXp, streakDays, todayXp, todayMinutes),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 16),
                  // ── 今日目标 ────────────────────────────────────────
                  if (!_goalsLoading && goals != null) ...[
                    _SectionTitle(title: '今日目标', icon: Icons.flag_rounded),
                    const SizedBox(height: 10),
                    _DailyGoalsCard(goals: goals),
                    const SizedBox(height: 20),
                  ],
                  // ── 搜索栏 ──────────────────────────────────────
                  _SearchBar(),
                  const SizedBox(height: 20),
                  // ── SRS 提醒（加载完才判断）──────────────────────
                  if (!_srsLoading && (_srsStats?['due_today'] ?? 0) > 0) ...[
                    _SrsReviewBanner(dueCount: _srsStats!['due_today']),
                    const SizedBox(height: 20),
                  ],
                  // ── 今日一词 ────────────────────────────────────
                  _SectionTitle(title: '今日一词', icon: Icons.auto_awesome_rounded),
                  const SizedBox(height: 10),
                  if (_wordLoading)
                    _WordOfDayShimmer(cs: cs)
                  else if (_wordPool.isNotEmpty)
                    _WordOfDayCard(
                      word: _wordPool[_wordIndex],
                      revealed: _wordRevealed,
                      onReveal: () => setState(() => _wordRevealed = true),
                      onNext: _nextWord,
                    ),
                  const SizedBox(height: 20),
                  // ── 常用功能（可自定义，最多6个）────────────────
                  Row(children: [
                    const Expanded(child: _SectionTitle(title: '常用功能', icon: Icons.apps_rounded)),
                    GestureDetector(
                      onTap: _editFavFeatures,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.edit_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 2),
                        Text('编辑', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _CategoryGrid(items: _favFeatureIds
                      .where((id) => _enabledFeatures.containsKey(id))
                      .map((id) { final f = _enabledFeatures[id]!; return (icon: f.icon, label: f.label, sub: f.sub, path: f.path, color: f.color); })
                      .toList()),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sliver App Bar ─────────────────────────────────────────────────────────
  Widget _buildSliverHeader(ColorScheme cs, int totalXp, int streakDays, int todayXp, int todayMinutes) {
    return SliverAppBar(
      expandedHeight: 130,
      floating: false,
      pinned: true,
      backgroundColor: cs.primary,
      // title 仅在折叠后显示，展开时由 background 自绘内容
      title: Text(S.of(context).appTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          )),
      actions: [
        IconButton(
          icon: const Icon(Icons.person_outline, color: Colors.white),
          onPressed: () => context.push('/profile'),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        // ⚠️ 不设 title，避免与 background 中文字重叠
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, cs.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 时间问候 + 用户名 + 等级（一行）
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _user != null
                              ? '${_greeting()}　${_user!.username}さん'
                              : '${_greeting()}　学生',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.star,
                        color: Colors.amber,
                        label: _user?.level ?? 'N5',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _StatBadge(
                        icon: Icons.local_fire_department,
                        color: Colors.orange,
                        label: '$streakDays 天连续',
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.diamond_rounded,
                        color: Colors.amberAccent,
                        label: '$totalXp XP',
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.trending_up_rounded,
                        color: Colors.greenAccent,
                        label: '+$todayXp 今日',
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.timer_outlined,
                        color: Colors.lightBlueAccent,
                        label: '$todayMinutes分',
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Word of Day Shimmer ──────────────────────────────────────────────────────

class _WordOfDayShimmer extends StatelessWidget {
  final ColorScheme cs;
  const _WordOfDayShimmer({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer.withValues(alpha: 0.4),
                   cs.secondaryContainer.withValues(alpha: 0.4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _shimmerBox(cs, 40, 20, radius: 8),
            const SizedBox(width: 8),
            _shimmerBox(cs, 60, 20, radius: 8),
          ]),
          const SizedBox(height: 16),
          _shimmerBox(cs, 120, 36, radius: 6),
          const SizedBox(height: 8),
          _shimmerBox(cs, 80, 20, radius: 6),
          const Spacer(),
          _shimmerBox(cs, double.infinity, 14, radius: 4),
        ],
      ),
    );
  }

  Widget _shimmerBox(ColorScheme cs, double w, double h, {double radius = 4}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─── Stat Badge ──────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatBadge({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    );
  }
}

// ─── Search Bar ──────────────────────────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _ctrl = TextEditingController();

  void _doSearch() {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    context.push('/dictionary?q=${Uri.encodeComponent(q)}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Icon(Icons.search_rounded, color: cs.primary, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Color(0xFF333333), fontSize: 15),
            decoration: const InputDecoration(
              hintText: '输入日语、中文或罗马字搜索…',
              hintStyle: TextStyle(color: Color(0xFF999999), fontSize: 13),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _doSearch(),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 34,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: _doSearch,
            child: const Text('搜索', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

// ─── SRS Banner ──────────────────────────────────────────────────────────────

class _SrsReviewBanner extends StatelessWidget {
  final int dueCount;
  const _SrsReviewBanner({required this.dueCount});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/srs-review'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange.shade400, Colors.deepOrange.shade400],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const Icon(Icons.layers_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$dueCount 张卡片待复习',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const Text('趁热打铁，强化记忆！',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('开始复习',
                style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

// ─── Word of Day ─────────────────────────────────────────────────────────────

class _WordOfDayCard extends StatelessWidget {
  final VocabularyModel word;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onNext;
  const _WordOfDayCard({required this.word, required this.revealed, required this.onReveal, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push('/vocabulary/${word.id}'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primaryContainer, cs.secondaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(word.jlptLevel,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.tertiary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(word.partOfSpeechRaw != null ? _formatPosRaw(word.partOfSpeechRaw!) : _posLabel(word.partOfSpeech),
                  style: TextStyle(color: cs.tertiary, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onNext,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Text('换一词', style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Text(word.word,
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: cs.primary, height: 1.1)),
          const SizedBox(height: 4),
          Text(cleanReading(word.reading),
              style: TextStyle(fontSize: 18, color: cs.secondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 14),
          // 意思遮挡翻转
          GestureDetector(
            onTap: () {
              if (!revealed) onReveal();
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: revealed
                  ? Column(
                      key: const ValueKey('revealed'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(word.meaningZh,
                            style: TextStyle(fontSize: 16, color: cs.onSurface, fontWeight: FontWeight.w500)),
                        if (word.exampleSentence != null) ...[
                          const SizedBox(height: 8),
                          Text(word.exampleSentence!,
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
                        ],
                      ],
                    )
                  : Container(
                      key: const ValueKey('hidden'),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.visibility_off_rounded, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text('点击查看释义',
                              style: TextStyle(color: cs.primary, fontSize: 13)),
                        ]),
                      ),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  static String _posLabel(String pos) {
    const map = {
      'noun': '名词',
      'verb': '动词',
      'adjective': '形容词',
      'adverb': '副词',
      'particle': '助词',
      'conjunction': '接续词',
      'interjection': '感叹词',
      'other': '其他',
    };
    return map[pos] ?? pos;
  }

  static String _formatPosRaw(String raw) {
    return raw.replaceFirstMapped(
      RegExp(r'^(自他動|自動|他動|補動)(\d*)'),
      (m) => '${m[1]}詞${m[2] ?? ""}',
    );
  }
}

// ─── Section Title ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 18, color: cs.primary),
      const SizedBox(width: 6),
      Text(title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
    ]);
  }
}

// ─── XP & 今日统计行 ──────────────────────────────────────────────────────────

class _XpStatsRow extends StatelessWidget {
  final int totalXp, todayXp, todayMinutes, streakDays;
  const _XpStatsRow({required this.totalXp, required this.todayXp, required this.todayMinutes, required this.streakDays});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: _MiniStatCard(icon: Icons.diamond_rounded, color: const Color(0xFF7C3AED), label: '总经验', value: '$totalXp XP')),
        const SizedBox(width: 8),
        Expanded(child: _MiniStatCard(icon: Icons.trending_up_rounded, color: const Color(0xFF059669), label: '今日XP', value: '+$todayXp')),
        const SizedBox(width: 8),
        Expanded(child: _MiniStatCard(icon: Icons.local_fire_department, color: const Color(0xFFEA580C), label: '连续打卡', value: '$streakDays天')),
        const SizedBox(width: 8),
        Expanded(child: _MiniStatCard(icon: Icons.schedule_rounded, color: const Color(0xFF2563EB), label: '今日学习', value: '$todayMinutes分')),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _MiniStatCard({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ─── 今日目标卡片 ──────────────────────────────────────────────────────────────

class _DailyGoalsCard extends StatelessWidget {
  final Map<String, dynamic> goals;
  const _DailyGoalsCard({required this.goals});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final studyGoal = goals['study_minutes'] as Map<String, dynamic>?;
    final lessonGoal = goals['lessons'] as Map<String, dynamic>?;
    final reviewGoal = goals['reviews'] as Map<String, dynamic>?;

    final items = <Widget>[];
    if (studyGoal != null) {
      items.add(_CompactGoalItem(
        icon: Icons.schedule_rounded,
        color: const Color(0xFF2563EB),
        label: '学习',
        current: (studyGoal['current'] as int),
        target: (studyGoal['target'] as int),
        unit: '分钟',
      ));
    }
    if (lessonGoal != null) {
      items.add(_CompactGoalItem(
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF059669),
        label: '活动',
        current: (lessonGoal['current'] as int),
        target: (lessonGoal['target'] as int),
        unit: '项',
      ));
    }
    if (reviewGoal != null) {
      items.add(_CompactGoalItem(
        icon: Icons.layers_rounded,
        color: const Color(0xFFEA580C),
        label: '复习',
        current: (reviewGoal['current'] as int),
        target: (reviewGoal['target'] as int),
        unit: '张',
      ));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) Container(
              width: 1, height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: cs.outlineVariant,
            ),
            Expanded(child: items[i]),
          ],
        ],
      ),
    );
  }
}

class _CompactGoalItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int current, target;
  final String unit;
  const _CompactGoalItem({required this.icon, required this.color, required this.label, required this.current, required this.target, required this.unit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final done = progress >= 1.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(done ? Icons.check_circle_rounded : icon, size: 14, color: done ? const Color(0xFF059669) : color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
      ]),
      const SizedBox(height: 4),
      Text('$current/$target$unit', style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      SizedBox(
        width: 60,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: cs.surfaceContainerHighest,
            color: done ? const Color(0xFF059669) : color,
          ),
        ),
      ),
    ]);
  }
}

// ─── 快速入口 ──────────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final int srsCount;
  const _QuickActions({required this.srsCount});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _QuickActionBtn(
        icon: Icons.layers_rounded,
        label: 'SRS复习${srsCount > 0 ? ' ($srsCount)' : ''}',
        color: const Color(0xFFFF9800),
        onTap: () => context.push('/srs-review'),
      )),
      const SizedBox(width: 10),
      Expanded(child: _QuickActionBtn(
        icon: Icons.style_rounded,
        label: '闪卡练习',
        color: const Color(0xFF3F51B5),
        onTap: () => context.push('/flashcard'),
      )),
    ]);
  }
}

class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ─── Category Grid (可复用的 3 列宫格) ──────────────────────────────────────────

typedef _CatItem = ({IconData icon, String label, String sub, String path, Color color});

class _CategoryGrid extends StatelessWidget {
  final List<_CatItem> items;
  const _CategoryGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final f = items[i];
        return _FeatureTile(icon: f.icon, label: f.label, sub: f.sub, path: f.path, color: f.color);
      },
    );
  }
}

// ─── Game Banner (游戏区横幅) ─────────────────────────────────────────────────

class _GameBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _GameCard(
        title: '助词方块',
        subtitle: '趣味闯关 · 助词填空',
        icon: Icons.extension_rounded,
        color: const Color(0xFFE91E63),
        onTap: () => context.push('/game', extra: 'particles'),
      ),
      const SizedBox(height: 12),
      _GameCard(
        title: '动词方块',
        subtitle: '趣味闯关 · 动词变形',
        icon: Icons.translate_rounded,
        color: const Color(0xFF9C27B0),
        onTap: () => context.push('/game', extra: 'verbs'),
      ),
      const SizedBox(height: 12),
      _GameCard(
        title: '闪卡练习',
        subtitle: '翻转记忆 · 四级评价',
        icon: Icons.style_rounded,
        color: const Color(0xFF3F51B5),
        onTap: () => context.push('/flashcard'),
      ),
    ]);
  }
}

class _GameCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GameCard({
    required this.title,
    required this.subtitle,
    this.icon = Icons.sports_esports_rounded,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('开始',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final String path;
  final Color color;
  const _FeatureTile({required this.icon, required this.label, required this.sub, required this.path, required this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(path),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
        ]),
      ),
    );
  }
}


