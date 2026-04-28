import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/local_db.dart';
import '../../services/api_service.dart';
import '../../widgets/membership_gate.dart';
import '../../widgets/furigana_text.dart';
import 'local_vocab_detail_screen.dart';

// ── 智能显示辅助 ──────────────────────────────────────────────────────────────
// 部分 Anki 词库字段顺序颠倒：中文意思存入了 word，振假名日语存入了 reading
// 通过检测振假名格式 (漢字[よみ]) 自动纠正显示
final _furiganaRe = RegExp(
    r'[\u4e00-\u9fff\uff10-\uff19\u3041-\u30ff]+\[[^\]]*[\u3040-\u30ff][^\]]*\]');
bool _hasKana(String s) => RegExp(r'[\u3040-\u30ff]').hasMatch(s);
bool _isSwapped(LocalVocabModel c) =>
    !_hasKana(c.word) && _furiganaRe.hasMatch(c.reading);

/// 列表/闪卡显示的「主词」：若字段颠倒则用 reading（含振假名的日语），否则用 word
String _displayWord(LocalVocabModel c) => _isSwapped(c) ? c.reading : c.word;

/// 列表副标题：若字段颠倒则只显示释义，否则显示「读音　释义」
String _displaySub(LocalVocabModel c) =>
    _isSwapped(c) ? c.meaningZh : '${c.reading}　${c.meaningZh}'.trim();

/// 本地词汇列表（Anki 导入后保存在设备 SQLite 中的卡片）
class LocalVocabScreen extends StatefulWidget {
  final String? initialDeckRoot;
  final int? initialStage;
  final String? planId;

  const LocalVocabScreen({
    super.key,
    this.initialDeckRoot,
    this.initialStage,
    this.planId,
  });
  @override
  State<LocalVocabScreen> createState() => _LocalVocabScreenState();
}

class _LocalVocabScreenState extends State<LocalVocabScreen> {
  static const _pageSize = 200;

  List<({String deckName, int total, int pending})> _decks = [];
  Map<String, LocalDeckMeta> _deckMetas = const {};
  bool _loading = true;

  // 当前展开的牌组
  String? _selectedDeck;
  String? _deckFilterRoot;
  List<LocalVocabModel> _cards = [];
  bool _loadingCards = false;
  int _cardTotal = 0;
  int _stageTotal = 0;
  int _cardPage  = 1;
  int _selectedStage = 0; // 0: 新词, 1: 复习, 2: 掌握
  Map<int, int> _stageCounts = const {0: 0, 1: 0, 2: 0};

  // 搜索
  final _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();



  // 牌组树展开状态
  final Set<String> _expandedNodes = {};
  bool _isMember = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    final st = widget.initialStage;
    if (st != null && st >= 0 && st <= 2) {
      _selectedStage = st;
    }
    _checkMembership();
    _loadDecks();
  }

  Future<void> _checkMembership() async {
    try {
      final user = await apiService.getMe();
      if (mounted) setState(() => _isMember = user.isMember);
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _loadingCards) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200 && _cards.length < _stageTotal) {
      _cardPage++;
      _fetchCards();
    }
  }

  String? get _searchQuery {
    final query = _searchCtrl.text.trim();
    return query.isEmpty ? null : query;
  }

  Future<void> _loadDecks() async {
    setState(() => _loading = true);
    final decks   = await localDb.listDecks();
    final deckMetas = await localDb.deckMetas();
    if (!mounted) return;
    String? toOpenDeck;
    final initialDeck = widget.initialDeckRoot;
    if (initialDeck != null && initialDeck.isNotEmpty) {
      if (initialDeck == '__all__') {
        toOpenDeck = decks.isNotEmpty ? decks.first.deckName : null;
      } else {
        final exact = decks.where((d) => d.deckName == initialDeck).toList();
        final prefix = decks.where((d) => d.deckName.startsWith('$initialDeck::')).toList();
        if (exact.isNotEmpty) {
          toOpenDeck = exact.first.deckName;
        } else if (prefix.isNotEmpty) {
          toOpenDeck = initialDeck;
        }
      }
    }
    setState(() {
      _decks        = decks;
      _deckMetas    = deckMetas;
      _loading      = false;
    });
    if (toOpenDeck != null) {
      await _openDeck(toOpenDeck);
    }
  }

  Future<void> _openDeck(String deckName) async {
    setState(() {
      _selectedDeck = deckName;
      _deckFilterRoot = deckName;
      _cardPage     = 1;
      _cards        = [];
      _loadingCards = true;
    });
    await _fetchCards(reset: true);
  }

  Future<void> _selectDeckFilter(String deckName) async {
    if (_selectedDeck == deckName) return;
    setState(() {
      _selectedDeck = deckName;
      _cardPage = 1;
      _cards = [];
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _fetchCards(reset: true);
  }

  List<_DeckFilterOption> _deckFilterOptions() {
    final root = _deckFilterRoot ?? _selectedDeck;
    if (root == null) return const [];
    final options = <_DeckFilterOption>[
      _DeckFilterOption(path: root, label: '全部'),
    ];
    final prefix = '$root::';
    final childDecks = _decks
        .map((deck) => deck.deckName)
        .where((name) => name.startsWith(prefix))
        .toSet()
        .toList()
      ..sort();
    for (final deckName in childDecks) {
      final label = deckName.substring(prefix.length).replaceAll('::', ' > ');
      options.add(_DeckFilterOption(path: deckName, label: label));
    }
    return options;
  }

  Future<void> _fetchCards({bool reset = false}) async {
    if (_selectedDeck == null) return;
    if (_loadingCards && !reset) return;
    if (reset) _cardPage = 1;
    setState(() {
      _loadingCards = true;
      if (reset) {
        _cards = [];
      }
    });
    final query = _searchQuery;
    final cardsFuture = localDb.listByDeck(
      deckName: _selectedDeck,
      prefixMatch: true,
      query: query,
      learningStage: _selectedStage,
      page: _cardPage,
      limit: _pageSize,
    );
    final stageCountsFuture = localDb.countByLearningStage(
      deckName: _selectedDeck,
      prefixMatch: true,
      query: query,
    );
    final results = await Future.wait<dynamic>([cardsFuture, stageCountsFuture]);
    final cards = results[0] as List<LocalVocabModel>;
    final stageCounts = results[1] as Map<int, int>;
    final total = stageCounts.values.fold<int>(0, (sum, count) => sum + count);
    final stageTotal = stageCounts[_selectedStage] ?? 0;
    if (!mounted) return;
    setState(() {
      _cards        = reset ? cards : [..._cards, ...cards];
      _cardTotal    = total;
      _stageTotal   = stageTotal;
      _stageCounts  = stageCounts;
      _loadingCards = false;
    });
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _setLearningStage(LocalVocabModel card, int stage) async {
    await localDb.setLearningStage(card.id, stage: stage);
    if (!mounted) return;
    await _fetchCards(reset: true);
  }

  Future<void> _deleteDeck(String deckName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除词库'),
        content: Text('确定要删除「$deckName」及其所有卡片？\n此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await localDb.deleteDeck(deckName);
      await _loadDecks();
      if (mounted) _showSnack('已删除「$deckName」');
    }
  }

  Future<String?> _copyCoverToLocal(String sourcePath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final coverDir = Directory(p.join(docsDir.path, 'vocab_covers'));
    await coverDir.create(recursive: true);
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final dest = p.join(coverDir.path, 'cover_${DateTime.now().millisecondsSinceEpoch}$ext');
    return File(sourcePath).copy(dest).then((file) => file.path);
  }

  Future<void> _showDeckActions(_DeckTreeNode node) async {
    final meta = _deckMetas[node.fullPath];
    final isShared = meta?.isShared == true && (meta?.sharedDeckId?.isNotEmpty ?? false);
    final importedFromShared = meta?.sourceType == 'shared';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('编辑词库信息'),
              subtitle: const Text('名称、封面、介绍'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            if (!importedFromShared)
              ListTile(
                leading: Icon(isShared ? Icons.undo_rounded : Icons.ios_share_rounded),
                title: Text(isShared ? '撤回分享' : '共享词库'),
                subtitle: Text(isShared ? '下架后其他用户将无法继续导入' : '发布给其他用户导入使用'),
                onTap: () => Navigator.pop(ctx, isShared ? 'unshare' : 'share'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
              title: Text('删除词库', style: TextStyle(color: Colors.red.shade400)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      await _editDeckMeta(node);
    } else if (action == 'share') {
      await _publishDeck(node);
    } else if (action == 'unshare') {
      await _unshareDeck(node);
    } else if (action == 'delete') {
      await _deleteDeck(node.fullPath);
    }
  }

  Future<String?> _coverAsBase64(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final ext = p.extension(path).toLowerCase();
    final mime = ext == '.png'
        ? 'image/png'
        : ext == '.webp'
            ? 'image/webp'
            : 'image/jpeg';
    final bytes = await file.readAsBytes();
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<void> _publishDeck(_DeckTreeNode node) async {
    final meta = _deckMetas[node.fullPath];
    if (meta?.sourceType == 'shared') {
      _showSnack('从共享词库导入的词库不可再次共享');
      return;
    }
    if (meta?.isShared == true && (meta?.sharedDeckId?.isNotEmpty ?? false)) {
      _showSnack('该词库已分享，可在长按菜单中撤回分享');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发布共享词库'),
        content: Text('将「${meta?.displayName ?? node.displayName}」发布到共享词库，其他用户可浏览并导入。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('发布')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final cards = await localDb.listByDeck(
        deckName: node.fullPath,
        prefixMatch: true,
        page: 1,
        limit: 10000,
      );
      if (cards.isEmpty) {
        _showSnack('该词库暂无可发布卡片');
        return;
      }
      final coverBase64 = await _coverAsBase64(meta?.coverImagePath);
      final result = await apiService.createSharedVocabDeck(
        title: meta?.displayName ?? node.displayName,
        description: meta?.description,
        coverBase64: coverBase64,
        sourceType: meta?.sourceType ?? 'manual',
        jlptLevel: cards.first.jlptLevel,
        cards: cards.map((card) => {
          'word': card.word,
          if (card.deckName != null && card.deckName!.isNotEmpty) 'deck_name': card.deckName,
          'reading': card.reading,
          'meaning_zh': card.meaningZh,
          if (card.meaningEn != null) 'meaning_en': card.meaningEn,
          if (card.exampleSentence != null) 'example_sentence': card.exampleSentence,
          if (card.exampleReading != null) 'example_reading': card.exampleReading,
          if (card.exampleMeaningZh != null) 'example_meaning_zh': card.exampleMeaningZh,
          if (card.audioUrl != null) 'audio_url': card.audioUrl,
          'part_of_speech': card.partOfSpeech,
          'jlpt_level': card.jlptLevel,
        }).toList(),
      );
      final deck = result['deck'] is Map ? Map<String, dynamic>.from(result['deck'] as Map) : const <String, dynamic>{};
      await localDb.setDeckShared(
        deckName: node.fullPath,
        isShared: true,
        sharedDeckId: deck['id']?.toString(),
      );
      await _loadDecks();
      if (mounted) _showSnack('已发布到共享词库');
    } catch (e) {
      if (mounted) _showSnack('发布失败：$e');
    }
  }

  Future<void> _unshareDeck(_DeckTreeNode node) async {
    final meta = _deckMetas[node.fullPath];
    final sharedDeckId = meta?.sharedDeckId;
    if (sharedDeckId == null || sharedDeckId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回分享'),
        content: Text('确定撤回「${meta?.displayName ?? node.displayName}」的共享？撤回后不会删除本地词库。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('撤回')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await apiService.deleteSharedVocabDeck(sharedDeckId);
      await localDb.setDeckShared(deckName: node.fullPath, isShared: false);
      await _loadDecks();
      if (mounted) _showSnack('已撤回分享');
    } catch (e) {
      if (mounted) _showSnack('撤回失败：$e');
    }
  }

  Future<void> _editDeckMeta(_DeckTreeNode node) async {
    final existing = _deckMetas[node.fullPath];
    final nameCtrl = TextEditingController(text: existing?.displayName ?? node.displayName);
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    String? coverPath = existing?.coverImagePath;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('编辑词库信息'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.image,
                      allowMultiple: false,
                    );
                    final path = result?.files.first.path;
                    if (path == null) return;
                    final copied = await _copyCoverToLocal(path);
                    if (copied != null) setDialog(() => coverPath = copied);
                  },
                  child: Container(
                    width: 92,
                    height: 124,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: coverPath == null || !File(coverPath!).existsSync()
                        ? const Icon(Icons.add_photo_alternate_rounded, size: 34)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(coverPath!), fit: BoxFit.cover),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '显示名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '介绍',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await localDb.upsertDeckMeta(
        deckName: node.fullPath,
        displayName: nameCtrl.text,
        coverImagePath: coverPath,
        description: descCtrl.text,
        sourceType: existing?.sourceType ?? 'manual',
      );
      await _loadDecks();
    }
  }

  Future<void> _openCardDetail(LocalVocabModel card) async {
    if (!mounted) return;

    final idx = _cards.indexOf(card);
    await context.push(
      '/local-vocab/${card.id}',
      extra: LocalVocabDetailArgs(
        initialCard: card,
        cards: _cards,
        initialIndex: idx >= 0 ? idx : 0,
      ),
    );

    if (mounted) {
      await _fetchCards(reset: true);
    }
  }

  void _openImportOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('导入我的词库',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('支持 Anki、CSV、TXT/TSV，也可以从浏览器复制表格内容后粘贴导入。',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('从共享词库导入'),
                subtitle: const Text('浏览其他用户发布的个人词库'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/shared-vocab');
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('选择文件导入'),
                subtitle: const Text('.apkg / .csv / .txt / .tsv'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/anki-import');
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_rounded),
                title: const Text('文字导入'),
                subtitle: const Text('粘贴从网页、表格、笔记中复制的词库内容'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/anki-import?mode=paste');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s  = S.of(context);
    final inPlanMode = widget.planId != null && widget.planId!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.localVocab),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () {
            if (_selectedDeck != null) {
              setState(() { _selectedDeck = null; _deckFilterRoot = null; _cards = []; });
            } else {
              context.canPop() ? context.pop() : context.go('/vocabulary');
            }
          },
        ),
      ),
      body: MembershipGate(
        featureId: 'anki_quiz',
        isMember: _isMember,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _decks.isEmpty
                ? _buildEmpty(cs, s)
                : _selectedDeck == null
                    ? _buildDeckList(cs, s)
                    : _buildCardList(cs, s),
      ),
      bottomNavigationBar: inPlanMode
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              color: cs.surface,
              child: Text(
                '学习计划模式：我的词库 ${_selectedDeck ?? ''}',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            )
          : null,
    );
  }

  // ── 空状态 ────────────────────────────────────────────────────────────────
  Widget _buildEmpty(ColorScheme cs, S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 86,
              height: 110,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.menu_book_rounded, size: 42, color: cs.primary),
            ),
            const SizedBox(height: 18),
            const Text('创建我的词库',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('导入 CSV、TXT、Anki 文件，或从浏览器复制表格内容粘贴导入。',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline, height: 1.5)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add_rounded),
              onPressed: _openImportOptions,
              label: const Text('导入词库'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 构建牌组树 ────────────────────────────────────────────────────────────
  /// 将扁平的 deck_name 列表（可能含 "::" 层级）构建为树结构
  List<_DeckTreeNode> _buildDeckTree() {
    // 汇总每个完整路径的直接卡片数
    final Map<String, int> directTotal = {};
    final Map<String, int> directPending = {};
    for (final d in _decks) {
      directTotal[d.deckName] = d.total;
      directPending[d.deckName] = d.pending;
    }

    // 收集所有路径节点（含中间节点）
    final Map<String, _DeckTreeNode> nodeMap = {};
    for (final d in _decks) {
      final parts = d.deckName.split('::');
      for (int i = 0; i < parts.length; i++) {
        final fullPath = parts.sublist(0, i + 1).join('::');
        nodeMap.putIfAbsent(fullPath, () => _DeckTreeNode(
          fullPath: fullPath,
          displayName: parts[i],
          depth: i,
        ));
      }
    }

    // 构建父子关系
    for (final node in nodeMap.values) {
      final parts = node.fullPath.split('::');
      if (parts.length > 1) {
        final parentPath = parts.sublist(0, parts.length - 1).join('::');
        nodeMap[parentPath]?.children.add(node);
      }
    }

    // 计算每个节点的总卡片数（自身 + 所有后代）
    void computeTotals(_DeckTreeNode node) {
      node.ownTotal = directTotal[node.fullPath] ?? 0;
      node.ownPending = directPending[node.fullPath] ?? 0;
      for (final child in node.children) {
        computeTotals(child);
      }
      node.subtreeTotal = node.ownTotal +
          node.children.fold(0, (sum, c) => sum + c.subtreeTotal);
      node.subtreePending = node.ownPending +
          node.children.fold(0, (sum, c) => sum + c.subtreePending);
    }

    // 排序子节点
    void sortChildren(_DeckTreeNode node) {
      node.children.sort((a, b) => a.displayName.compareTo(b.displayName));
      for (final child in node.children) {
        sortChildren(child);
      }
    }

    // 收集根节点
    final roots = nodeMap.values
        .where((n) => !n.fullPath.contains('::'))
        .toList();
    for (final root in roots) {
      computeTotals(root);
      sortChildren(root);
    }
    roots.sort((a, b) => a.displayName.compareTo(b.displayName));

    return roots;
  }

  // ── 牌组列表（树形视图）──────────────────────────────────────────────────
  Widget _buildDeckList(ColorScheme cs, S s) {
    final roots = _buildDeckTree();

    return RefreshIndicator(
      onRefresh: _loadDecks,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            const Expanded(
              child: Text('我的书架',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            IconButton.filledTonal(
              tooltip: '导入词库',
              icon: const Icon(Icons.add_rounded),
              onPressed: _openImportOptions,
            ),
          ]),
          const SizedBox(height: 4),
          Text('共 ${roots.length} 个词库，${_decks.fold<int>(0, (sum, d) => sum + d.total)} 张卡片',
              style: TextStyle(fontSize: 13, color: cs.outline)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: roots.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 20,
              crossAxisSpacing: 14,
              childAspectRatio: 0.54,
            ),
            itemBuilder: (_, index) => _buildShelfDeck(cs, roots[index], index),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfDeck(ColorScheme cs, _DeckTreeNode node, int index) {
    final meta = _deckMetas[node.fullPath];
    final coverPath = meta?.coverImagePath;
    final coverFile = coverPath == null ? null : File(coverPath);
    final hasCover = coverFile != null && coverFile.existsSync();
    final sourceLabel = switch (meta?.sourceType) {
      'apkg' => 'Anki 导入',
      'csv' => 'CSV 导入',
      'txt' => 'TXT 导入',
      'tsv' => 'TSV 导入',
      'paste' => '文字导入',
      'legacy' => '历史词库',
      _ => '个人词库',
    };
    final colors = [
      const Color(0xFF9F4F53),
      const Color(0xFF2F6F73),
      const Color(0xFF7357A6),
      const Color(0xFFD17A22),
      const Color(0xFF4F6F9F),
      const Color(0xFF6B7F3A),
    ];
    final cover = colors[index % colors.length];
    final hasChildren = node.children.isNotEmpty;
    final title = meta?.displayName.trim().isNotEmpty == true
      ? meta!.displayName.trim()
      : node.displayName;
    final subtitle = meta?.description?.trim().isNotEmpty == true
      ? meta!.description!.trim()
      : (hasChildren ? '${node.children.length} 个子词库' : sourceLabel);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openDeck(node.fullPath),
      onLongPress: () => _showDeckActions(node),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.78,
            child: SizedBox.expand(
              child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: hasCover ? cs.surfaceContainerHighest : cover,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: hasCover
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(coverFile, fit: BoxFit.cover),
                    )
                  : Stack(
                      children: [
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Icon(
                            hasChildren ? Icons.auto_stories_rounded : Icons.menu_book_rounded,
                            color: Colors.white.withValues(alpha: 0.55),
                            size: 24,
                          ),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${node.subtreeTotal}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900)),
                              Text('张卡片',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.82),
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 16,
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }

  /// 递归构建树节点 Widget 列表
  List<Widget> _buildTreeItems(ColorScheme cs, _DeckTreeNode node) {
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = _expandedNodes.contains(node.fullPath);
    final depth = node.depth;

    final item = InkWell(
      onTap: () => _openDeck(node.fullPath),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.only(
          left: 12.0 + depth * 20.0,
          right: 8,
          top: 10,
          bottom: 10,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2))),
        ),
        child: Row(children: [
          // 展开/折叠按钮或占位
          if (hasChildren)
            GestureDetector(
              onTap: () => setState(() {
                if (isExpanded) {
                  _expandedNodes.remove(node.fullPath);
                } else {
                  _expandedNodes.add(node.fullPath);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                  size: 20,
                  color: cs.outline,
                ),
              ),
            )
          else
            const SizedBox(width: 24),

          // 牌组图标
          Icon(
            hasChildren ? Icons.folder_rounded : Icons.description_rounded,
            size: 18,
            color: depth == 0 ? cs.primary : cs.outline,
          ),
          const SizedBox(width: 8),

          // 牌组名称
          Expanded(
            child: Text(
              node.displayName,
              style: TextStyle(
                fontSize: depth == 0 ? 15 : 14,
                fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),

          // 卡片数
          SizedBox(
            width: 64,
            child: Text(
              '${node.subtreeTotal}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ),

          // 删除按钮（只在根节点显示）
          if (depth == 0)
            SizedBox(
              width: 32,
              child: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: Colors.red.shade300,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '删除词库',
                onPressed: () => _deleteDeck(node.fullPath),
              ),
            )
          else
            const SizedBox(width: 32),
        ]),
      ),
    );

    return [
      item,
      if (hasChildren && isExpanded)
        ...node.children.expand((child) => _buildTreeItems(cs, child)),
    ];
  }

  // ── 卡片列表 ──────────────────────────────────────────────────────────────
  Widget _buildCardList(ColorScheme cs, S s) {
    // 显示当前牌组路径（用 :: 分隔的最后一段）
    final rootParts = (_deckFilterRoot ?? _selectedDeck)?.split('::') ?? [];
    final deckParts = _selectedDeck?.split('::') ?? [];
    final deckTitle = deckParts.isNotEmpty ? deckParts.last : s.localVocab;
    final rootTitle = rootParts.isNotEmpty ? rootParts.last : deckTitle;
    final filterOptions = _deckFilterOptions();
    final newCount = _stageCounts[0] ?? 0;
    final reviewCount = _stageCounts[1] ?? 0;
    final masteredCount = _stageCounts[2] ?? 0;

    return Column(
      children: [
        // 顶部牌组路径 + 卡片数
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Expanded(
              child: filterOptions.length > 1
                  ? _buildDeckFilterDropdown(cs, rootTitle, filterOptions)
                  : Text(
                      deckParts.length > 1
                          ? deckParts.join(' > ')
                          : deckTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            Text('$_cardTotal ${s.cards}',
                style: TextStyle(color: cs.outline, fontSize: 13)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () { _searchCtrl.clear(); _fetchCards(reset: true); })
                  : null,
            ),
            onSubmitted: (_) => _fetchCards(reset: true),
          ),
        ),
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildStageTabs(cs, newCount, reviewCount, masteredCount),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loadingCards && _cards.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (_cards.isEmpty)
                      _emptySection(cs, '当前分组暂无内容')
                    else
                      ..._cards.map((card) => _buildCardTile(cs, card)),

                    if (_loadingCards && _cards.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDeckFilterDropdown(
    ColorScheme cs,
    String rootTitle,
    List<_DeckFilterOption> options,
  ) {
    final current = options.any((option) => option.path == _selectedDeck)
        ? options.firstWhere((option) => option.path == _selectedDeck)
        : options.first;
    final label = current.path == _deckFilterRoot ? '$rootTitle · 全部' : current.label;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openDeckFilterSheet(rootTitle, options),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
          ),
          Icon(Icons.expand_more_rounded, size: 20, color: cs.outline),
        ]),
      ),
    );
  }

  Future<void> _openDeckFilterSheet(String rootTitle, List<_DeckFilterOption> options) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, index) {
              final option = options[index];
              final active = option.path == _selectedDeck;
              return RadioListTile<String>(
                value: option.path,
                groupValue: _selectedDeck,
                title: Text(option.path == _deckFilterRoot ? '$rootTitle · 全部' : option.label),
                dense: true,
                selected: active,
                onChanged: (value) => Navigator.pop(ctx, value),
              );
            },
          ),
        ),
      ),
    );
    if (selected != null) await _selectDeckFilter(selected);
  }

  Widget _buildStageTabs(ColorScheme cs, int newCount, int reviewCount, int masteredCount) {
    Widget item({
      required int stage,
      required String label,
      required int count,
      required Color activeColor,
    }) {
      final active = _selectedStage == stage;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            if (_selectedStage == stage) return;
            setState(() {
              _selectedStage = stage;
              _cardPage = 1;
              _cards = [];
            });
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
            await _fetchCards(reset: true);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.14)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? activeColor.withValues(alpha: 0.45)
                    : cs.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  stage == 0
                      ? Icons.fiber_new_rounded
                      : stage == 1
                          ? Icons.autorenew_rounded
                          : Icons.verified_rounded,
                  size: 16,
                  color: active ? activeColor : cs.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  '$label $count',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? activeColor : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        item(stage: 0, label: '新词', count: newCount, activeColor: cs.primary),
        const SizedBox(width: 8),
        item(stage: 1, label: '复习', count: reviewCount, activeColor: Colors.orange),
        const SizedBox(width: 8),
        item(stage: 2, label: '掌握', count: masteredCount, activeColor: Colors.green),
      ],
    );
  }

  Widget _emptySection(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(text, style: TextStyle(fontSize: 12, color: cs.outline)),
    );
  }

  Widget _buildCardTile(ColorScheme cs, LocalVocabModel card) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(card.jlptLevel,
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(_displayWord(card),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              if (card.learningStage > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (card.learningStage == 2 ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: (card.learningStage == 2 ? Colors.green : Colors.orange)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    card.learningStage == 2 ? '掌握' : '复习',
                    style: TextStyle(
                      fontSize: 11,
                      color: card.learningStage == 2 ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(_displaySub(card), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<int>(
                tooltip: '学习状态',
                onSelected: (value) => _setLearningStage(card, value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0, child: Text('新词')),
                  PopupMenuItem(value: 1, child: Text('复习')),
                  PopupMenuItem(value: 2, child: Text('掌握')),
                ],
                child: Icon(
                  card.learningStage == 0
                      ? Icons.fiber_new_rounded
                      : card.learningStage == 1
                          ? Icons.autorenew_rounded
                          : Icons.verified_rounded,
                  size: 20,
                  color: card.learningStage == 0
                      ? cs.primary
                      : card.learningStage == 1
                          ? Colors.orange
                          : Colors.green,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
            ],
          ),
          onTap: () => _openCardDetail(card),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

// ─── 牌组树节点模型 ──────────────────────────────────────────────────────────

class _DeckTreeNode {
  final String fullPath;     // 完整路径，如 "Root::Sub::Leaf"
  final String displayName;  // 显示名称，如 "Leaf"
  final int depth;           // 层级深度（0 = 根）
  final List<_DeckTreeNode> children = [];
  int ownTotal = 0;          // 该节点自身的卡片数
  int ownPending = 0;        // 该节点自身的待同步数
  int subtreeTotal = 0;      // 该节点 + 所有后代的卡片总数
  int subtreePending = 0;    // 该节点 + 所有后代的待同步总数

  _DeckTreeNode({
    required this.fullPath,
    required this.displayName,
    required this.depth,
  });
}

class _DeckFilterOption {
  final String path;
  final String label;

  const _DeckFilterOption({required this.path, required this.label});
}

// ─── 本地词库闪卡复习面板 ─────────────────────────────────────────────────────

class _LocalVocabFlashCard extends StatefulWidget {
  final List<LocalVocabModel> cards;
  final int initialIndex;
  const _LocalVocabFlashCard({required this.cards, required this.initialIndex});
  @override
  State<_LocalVocabFlashCard> createState() => _LocalVocabFlashCardState();
}

class _LocalVocabFlashCardState extends State<_LocalVocabFlashCard> {
  bool _showAnswer = false;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.cards.length) return;
    setState(() { _currentIndex = index; _showAnswer = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final card = widget.cards[_currentIndex];
    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < widget.cards.length - 1;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // 拖动把手
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 内容区
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              children: [
                // ── 单词卡 ────────────────────────────────────────────────
                GestureDetector(
                  onTap: () => setState(() => _showAnswer = true),
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity == null) return;
                    if (details.primaryVelocity! < -200) _goTo(_currentIndex + 1);
                    if (details.primaryVelocity! > 200) _goTo(_currentIndex - 1);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primaryContainer, cs.secondaryContainer],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(children: [
                      // JLPT 级别标签
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(card.jlptLevel,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.tertiary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(card.partOfSpeech,
                              style: TextStyle(color: cs.tertiary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      // 单词（始终显示，振假名标注）
                      FuriganaText(text: _displayWord(card), fontSize: 44, color: cs.primary),
                      const SizedBox(height: 8),
                      if (!_showAnswer)
                        Text('点击卡片查看答案',
                            style: TextStyle(color: cs.outline, fontSize: 13)),
                    ]),
                  ),
                ),

                // ── 答案区域 ──────────────────────────────────────────────
                if (_showAnswer) ...[
                  const SizedBox(height: 20),
                  // 中文释义
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('释义', style: TextStyle(fontSize: 12, color: cs.outline, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(card.meaningZh,
                          style: TextStyle(fontSize: 17, color: cs.onSurface, fontWeight: FontWeight.w600)),
                      if (card.meaningEn != null && card.meaningEn!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(card.meaningEn!,
                            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                      ],
                    ]),
                  ),
                  // 例句
                  if (card.exampleSentence != null && card.exampleSentence!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('例句', style: TextStyle(fontSize: 12, color: cs.outline, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(card.exampleSentence!,
                            style: TextStyle(fontSize: 15, color: cs.onSurface, height: 1.6)),
                      ]),
                    ),
                  ],
                  // 来源牌组 & 同步状态
                  const SizedBox(height: 12),
                  Row(children: [
                    if (card.deckName != null)
                      Chip(
                        avatar: Icon(Icons.folder_rounded, size: 14, color: const Color(0xFF00897B)),
                        label: Text(card.deckName!,
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: const Color(0xFF00897B).withValues(alpha: 0.1),
                        side: BorderSide(color: const Color(0xFF00897B).withValues(alpha: 0.3)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    const Spacer(),
                  ]),
                ] else ...[
                  // 未揭示答案时的提示
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => setState(() => _showAnswer = true),
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('显示答案', style: TextStyle(fontSize: 16)),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── 底部导航栏 ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
            ),
            child: Row(children: [
              OutlinedButton.icon(
                onPressed: hasPrev ? () => _goTo(_currentIndex - 1) : null,
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
                label: const Text('上一个'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const Spacer(),
              Text('${_currentIndex + 1} / ${widget.cards.length}',
                  style: TextStyle(fontSize: 13, color: cs.outline, fontWeight: FontWeight.w500)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: hasNext ? () => _goTo(_currentIndex + 1) : null,
                icon: const Text(''),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('下一个'),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  ],
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
