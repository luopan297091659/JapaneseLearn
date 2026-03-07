import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';

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
  const LocalVocabScreen({super.key});
  @override
  State<LocalVocabScreen> createState() => _LocalVocabScreenState();
}

class _LocalVocabScreenState extends State<LocalVocabScreen> {
  List<({String deckName, int total, int pending})> _decks = [];
  bool _loading = true;

  // 当前展开的牌组
  String? _selectedDeck;
  List<LocalVocabModel> _cards = [];
  bool _loadingCards = false;
  int _cardTotal = 0;
  int _cardPage  = 1;

  // 搜索
  final _searchCtrl = TextEditingController();

  // 同步状态
  bool _syncing = false;
  int  _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDecks() async {
    setState(() => _loading = true);
    final decks   = await localDb.listDecks();
    final pending = await syncService.pendingCount();
    if (!mounted) return;
    setState(() {
      _decks        = decks;
      _pendingCount = pending;
      _loading      = false;
    });
  }

  Future<void> _openDeck(String deckName) async {
    setState(() {
      _selectedDeck = deckName;
      _cardPage     = 1;
      _cards        = [];
      _loadingCards = true;
    });
    await _fetchCards(reset: true);
  }

  Future<void> _fetchCards({bool reset = false}) async {
    if (reset) _cardPage = 1;
    setState(() => _loadingCards = true);
    final query = _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim();
    final cards = await localDb.listByDeck(
      deckName: _selectedDeck,
      query:    query,
      page:     _cardPage,
      limit:    30,
    );
    final total = await localDb.countByDeck(deckName: _selectedDeck, query: query);
    if (!mounted) return;
    setState(() {
      _cards        = reset ? cards : [..._cards, ...cards];
      _cardTotal    = total;
      _loadingCards = false;
    });
  }

  Future<void> _syncAll() async {
    setState(() => _syncing = true);
    final result = await syncService.syncVocabulary();
    await _loadDecks();
    if (!mounted) return;
    setState(() => _syncing = false);
    final s = S.of(context);
    if (result != null && result.allDone) {
      _showSnack(s.syncSuccess);
    } else if (result != null && result.hasError) {
      _showSnack('${s.syncFailed}（${result.failed} 条失败）');
    } else {
      _showSnack(s.syncFailed);
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

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

  void _openCardDetail(BuildContext context, LocalVocabModel card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocalVocabFlashCard(card: card),
    );
  }

  // ─── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s  = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.localVocab),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/vocabulary'),
        ),
        actions: [
          if (_pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _syncing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Badge(
                      label: Text('$_pendingCount'),
                      child: IconButton(
                        icon: const Icon(Icons.sync_rounded),
                        tooltip: s.syncNow,
                        onPressed: _syncAll,
                      ),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _decks.isEmpty
              ? _buildEmpty(cs, s)
              : _selectedDeck == null
                  ? _buildDeckList(cs, s)
                  : _buildCardList(cs, s),
    );
  }

  // ── 空状态 ────────────────────────────────────────────────────────────────
  Widget _buildEmpty(ColorScheme cs, S s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: 72, color: cs.outline),
          const SizedBox(height: 16),
          Text(s.ankiImport, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(s.ankiImportHint, textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, height: 1.5)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file_rounded),
            onPressed: () => context.push('/anki-import'),
            label: Text(s.ankiImport),
          ),
        ],
      ),
    );
  }

  // ── 牌组列表 ──────────────────────────────────────────────────────────────
  Widget _buildDeckList(ColorScheme cs, S s) {
    return RefreshIndicator(
      onRefresh: _loadDecks,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 待同步汇总行
          if (_pendingCount > 0)
            Card(
              color: Colors.orange.shade50,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_rounded, color: Colors.orange.shade700),
                title: Text('$_pendingCount ${s.pendingCards}',
                    style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold)),
                subtitle: Text(s.syncFailed, style: TextStyle(color: Colors.orange.shade600, fontSize: 12)),
                trailing: _syncing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : FilledButton.tonal(
                        onPressed: _syncAll,
                        style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade100),
                        child: Text(s.syncNow, style: TextStyle(color: Colors.orange.shade800)),
                      ),
              ),
            ),

          ..._decks.map((deck) {
            final hasPending = deck.pending > 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.layers_rounded, color: cs.primary),
                ),
                title: Text(deck.deckName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Row(children: [
                  Text('${deck.total} 张', style: const TextStyle(fontSize: 12)),
                  if (hasPending) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${deck.pending} ${s.pendingSync}',
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                    ),
                  ],
                ]),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: Colors.red.shade300,
                      tooltip: '删除词库',
                      onPressed: () => _deleteDeck(deck.deckName),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _openDeck(deck.deckName),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 卡片列表 ──────────────────────────────────────────────────────────────
  Widget _buildCardList(ColorScheme cs, S s) {
    return Column(
      children: [
        // 顶部导航栏
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
              onPressed: () => setState(() { _selectedDeck = null; _cards = []; }),
              label: Text(s.localVocab),
            ),
            const Spacer(),
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
        Expanded(
          child: _loadingCards && _cards.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _cards.length + (_cards.length < _cardTotal ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i >= _cards.length) {
                      // 加载更多
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: OutlinedButton(
                            onPressed: () { _cardPage++; _fetchCards(); },
                            child: const Text('加载更多'),
                          ),
                        ),
                      );
                    }
                    final card = _cards[i];
                    return ListTile(
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
                      title: Text(_displayWord(card),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      subtitle: Text(_displaySub(card),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Icon(
                        card.synced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                        size: 18,
                        color: card.synced ? Colors.green : Colors.orange,
                      ),
                      onTap: () => _openCardDetail(context, card),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── 本地词库闪卡复习面板 ─────────────────────────────────────────────────────

class _LocalVocabFlashCard extends StatefulWidget {
  final LocalVocabModel card;
  const _LocalVocabFlashCard({required this.card});
  @override
  State<_LocalVocabFlashCard> createState() => _LocalVocabFlashCardState();
}

class _LocalVocabFlashCardState extends State<_LocalVocabFlashCard> {
  bool _showAnswer = false;

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final card = widget.card;

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
                      // 单词（始终显示）
                      Text(_displayWord(card),
                          style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: cs.primary, height: 1)),
                      const SizedBox(height: 8),
                      // 读音（答案揭示后才显示；字段颠倒时 reading 已作为主词，此处不重复）
                      if (_showAnswer && !_isSwapped(card))
                        Text(card.reading,
                            style: TextStyle(fontSize: 22, color: cs.secondary, fontWeight: FontWeight.w500))
                      else if (!_showAnswer)
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
                    Icon(
                      card.synced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                      size: 16,
                      color: card.synced ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      card.synced ? '已同步' : '未同步',
                      style: TextStyle(
                        fontSize: 12,
                        color: card.synced ? Colors.green : Colors.orange,
                      ),
                    ),
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
        ]),
      ),
    );
  }
}
