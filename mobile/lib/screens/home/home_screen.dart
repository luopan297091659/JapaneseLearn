import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/sync_service.dart';
import '../../models/models.dart';
import '../../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UserModel? _user;
  Map<String, dynamic>? _srsStats;
  List<VocabularyModel> _wordPool = [];
  int _wordIndex = 0;

  // 各区域独立加载状态，不再阻塞整页显示
  bool _userLoading   = true;
  bool _srsLoading    = true;
  bool _wordLoading   = true;
  bool _wordRevealed  = false;

  // 是否正在刷新（下拉刷新时用）
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
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
              onPressed: () => context.go('/vocabulary'),
            ),
          ),
        );
      }
    });
  }

  /// [fromCache] true = 先用缓存立即渲染，后台同步刷新；false = 强制刷新
  Future<void> _loadAll({bool fromCache = false}) async {
    if (!fromCache) {
      setState(() => _refreshing = true);
    }
    // 三个请求独立进行，任意一个完成立刻更新对应区域
    await Future.wait([
      _loadUser(),
      _loadSrs(),
      _loadWordOfDay(),
    ]);
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

  Future<void> _loadWordOfDay() async {
    setState(() => _wordLoading = true);
    try {
      final res = await apiService.getVocabulary(limit: 20, page: 1);
      final words = res['data'] as List<VocabularyModel>;
      if (words.isNotEmpty) {
        // 按当天日期固定起始索引，保证同一天首词一致
        final seed = DateTime.now().year * 10000 +
            DateTime.now().month * 100 +
            DateTime.now().day;
        final start = Random(seed).nextInt(words.length);
        if (mounted) setState(() {
          _wordPool  = words;
          _wordIndex = start;
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

  void _nextWord() {
    if (_wordPool.isEmpty) return;
    setState(() {
      _wordIndex = (_wordIndex + 1) % _wordPool.length;
      _wordRevealed = false;
    });
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
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: RefreshIndicator(
        onRefresh: () => _loadAll(fromCache: false),
        child: CustomScrollView(
          slivers: [
            // ── App Bar ────────────────────────────────────────────
            _buildSliverHeader(cs),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 16),
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
                  // ── 📚 学习 ────────────────────────────────────
                  _SectionTitle(title: '学习', icon: Icons.menu_book_rounded),
                  const SizedBox(height: 10),
                  _CategoryGrid(items: const [
                    (icon: Icons.grid_view_rounded,  label: '五十音',   sub: '基础入门', path: '/gojuon',       color: Color(0xFFE91E63)),
                    (icon: Icons.menu_book_rounded,  label: '单词学习', sub: '词汇积累', path: '/vocabulary', color: Color(0xFF4CAF50)),
                    (icon: Icons.school_rounded,     label: '语法学习', sub: '规则掌握', path: '/grammar',    color: Color(0xFF2196F3)),
                    (icon: Icons.headphones_rounded, label: '听力练习', sub: '提升听力', path: '/listening',  color: Color(0xFF9C27B0)),
                    (icon: Icons.layers_rounded,     label: 'SRS复习',  sub: '间隔记忆', path: '/srs-review', color: Color(0xFFFF9800)),
                    (icon: Icons.folder_copy_rounded, label: 'Anki词库', sub: '本地卡片', path: '/local-vocab', color: Color(0xFF00897B)),
                  ]),
                  const SizedBox(height: 20),
                  // ── 🎮 游戏 ────────────────────────────────────
                  _SectionTitle(title: '游戏', icon: Icons.sports_esports_rounded),
                  const SizedBox(height: 10),
                  _GameBanner(),
                  const SizedBox(height: 20),
                  // ── 🔧 工具 ────────────────────────────────────
                  _SectionTitle(title: '工具', icon: Icons.build_rounded),
                  const SizedBox(height: 10),
                  _CategoryGrid(items: const [
                    (icon: Icons.manage_search_rounded, label: '辞书检索', sub: '词典查询', path: '/dictionary',  color: Color(0xFF607D8B)),
                    (icon: Icons.upload_file_rounded,   label: 'Anki导入', sub: '导入词库', path: '/anki-import', color: Color(0xFF795548)),
                  ]),
                  const SizedBox(height: 20),
                  // ── ✏️ 测试 ────────────────────────────────────
                  _SectionTitle(title: '测试', icon: Icons.assignment_rounded),
                  const SizedBox(height: 10),
                  _CategoryGrid(items: const [
                    (icon: Icons.quiz_rounded, label: '随机测验', sub: '检验水平', path: '/quiz', color: Color(0xFFFF5722)),
                    (icon: Icons.map_rounded,  label: '都道府県', sub: '地理测验', path: '/todofuken-quiz', color: Color(0xFFE65100)),
                  ]),
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
  Widget _buildSliverHeader(ColorScheme cs) {
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
          onPressed: () => context.go('/profile'),
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
              padding: const EdgeInsets.fromLTRB(20, 4, 60, 8),
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
                        label: '${_user?.streakDays ?? 0} 天连续',
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.timer_outlined,
                        color: Colors.lightBlueAccent,
                        label: '${_user?.totalStudyMinutes ?? 0} 分钟',
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

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push('/dictionary'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(children: [
          Icon(Icons.search_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Text(
            '输入日语、中文或罗马字搜索…',
            style: TextStyle(color: cs.outline, fontSize: 14),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('辞书', style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
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
      onTap: () => context.go('/srs-review'),
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
              child: Text(word.partOfSpeech,
                  style: TextStyle(color: cs.tertiary, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
          ]),
          const SizedBox(height: 14),
          Text(word.word,
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: cs.primary, height: 1.1)),
          const SizedBox(height: 4),
          Text(word.reading,
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
          // 换一词按钮（揭开后显示）
          if (revealed) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onNext,
                icon: Icon(Icons.refresh_rounded, size: 16, color: cs.primary),
                label: Text('换一词', style: TextStyle(color: cs.primary, fontSize: 13)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  backgroundColor: cs.primary.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ]),
      ),
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
        color: const Color(0xFFE91E63),
        onTap: () => context.push('/game', extra: 'particles'),
      ),
      const SizedBox(height: 12),
      _GameCard(
        title: '动词方块',
        subtitle: '趣味闯关 · 动词变形',
        color: const Color(0xFF9C27B0),
        onTap: () => context.push('/game', extra: 'verbs'),
      ),
    ]);
  }
}

class _GameCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GameCard({
    required this.title,
    required this.subtitle,
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
            child: const Icon(Icons.sports_esports_rounded, color: Colors.white, size: 28),
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
            child: const Text('开始',
                style: TextStyle(color: Color(0xFFE91E63), fontWeight: FontWeight.bold, fontSize: 13)),
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


