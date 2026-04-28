import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../services/anki_parser.dart';
import '../../services/local_db.dart';
import '../../services/api_service.dart';
import '../../widgets/membership_gate.dart';

enum _Step { pick, parsing, preview, importing, done, error }

class AnkiImportScreen extends StatefulWidget {
  final bool pasteMode;

  const AnkiImportScreen({super.key, this.pasteMode = false});
  @override
  State<AnkiImportScreen> createState() => _AnkiImportScreenState();
}

class _AnkiImportScreenState extends State<AnkiImportScreen> {
  // ─── 状态 ───────────────────────────────────────────────────────────────
  _Step _step = _Step.pick;
  String? _filePath;
  String? _fileName;
  AnkiPreview? _preview;

  // 导入配置
  final _deckNameCtrl = TextEditingController(text: 'Anki Import');
  final _deckDescCtrl = TextEditingController();
  final _pasteCtrl = TextEditingController();
  bool _pasteMode = false;
  String? _coverImagePath;
  String _partOfSpeech = 'all';

  // 字段映射选择（字段名称 index，null = 不导入）
  int? _mapWord;
  int? _mapReading;
  int? _mapMeaningZh;
  int? _mapMeaningEn;
  int? _mapExample;
  int? _mapExampleReading;
  int? _mapExampleMeaningZh;

  // 结果
  Map<String, dynamic> _result = {};
  String _errorMsg = '';

  bool _savedLocally = false;
  bool _isMember = true;

  @override
  void initState() {
    super.initState();
    _pasteMode = widget.pasteMode;
    if (_pasteMode) {
      _deckNameCtrl.text = '我的词库';
    }
    _checkMembership();
  }

  Future<void> _checkMembership() async {
    try {
      final user = await apiService.getMe();
      if (mounted) setState(() => _isMember = user.isMember);
    } catch (_) {}
  }

  @override
  void dispose() {
    _deckNameCtrl.dispose();
    _deckDescCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  static const _templateText = '''单词｜读音｜释义｜例句｜例句读音｜例句释义
傲慢｜ごうまん｜傲慢；骄傲｜傲慢な態度を改めるべきだ。／彼の傲慢な発言に驚いた。｜ごうまんなたいどをあらためるべきだ。／かれのごうまんなはつげんにおどろいた。｜应该改掉傲慢的态度。／我对他傲慢的发言感到惊讶。
偏見｜へんけん｜偏见；成见｜偏見を持たずに話を聞く。／偏見で人を判断してはいけない。｜へんけんをもたずにはなしをきく。／へんけんでひとをはんだんしてはいけない。｜不带偏见地听别人说话。／不能带着偏见判断别人。
見送る｜みおくる｜送行；暂缓｜駅まで友人を見送った。／計画を見送る。｜えきまでゆうじんをみおくった。／けいかくをみおくる。｜送朋友到车站。／暂缓计划。''';

  // ─── 步骤 1：选文件 ──────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    // 使用 FileType.any：Android 不识别 .apkg 的 MIME 类型，
    // FileType.custom 会导致 .apkg 被系统置灰无法选择。
    // 改为全类型显示，选择后再做扩展名校验。
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    // 校验扩展名
    final ext = p.extension(file.name).toLowerCase();
    const supported = ['.apkg', '.txt', '.csv', '.tsv'];
    if (!supported.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('不支持的文件格式：$ext\n支持：.apkg / .txt / .csv / .tsv'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }

    setState(() {
      _filePath = file.path;
      _fileName = file.name;
      _step = _Step.parsing;
      _errorMsg = '';
    });
    await _runPreview(file.path!);
  }

  Future<void> _importPastedText() async {
    final text = _pasteCtrl.text.trim();
    if (text.isEmpty) {
      _showSnack('请先粘贴词库内容');
      return;
    }
    final ext = text.contains('｜') ? '.bar' : (text.contains('\t') ? '.tsv' : '.csv');
    final dir = await getTemporaryDirectory();
    final fileName = 'pasted_vocab_${DateTime.now().millisecondsSinceEpoch}$ext';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(text);
    setState(() {
      _filePath = file.path;
      _fileName = fileName;
      _step = _Step.parsing;
      _errorMsg = '';
    });
    await _runPreview(file.path);
  }

  Future<void> _pickCoverImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    final docsDir = await getApplicationDocumentsDirectory();
    final coverDir = Directory(p.join(docsDir.path, 'vocab_covers'));
    await coverDir.create(recursive: true);
    final ext = p.extension(path).isEmpty ? '.jpg' : p.extension(path);
    final dest = p.join(coverDir.path, 'cover_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(path).copy(dest);
    if (mounted) setState(() => _coverImagePath = dest);
  }

  void _fillTemplate() {
    setState(() {
      _pasteMode = true;
      _pasteCtrl.text = _templateText;
    });
  }

  // ─── 步骤 2：客户端本地解析预览 ─────────────────────────────────────────
  Future<void> _runPreview(String filePath) async {
    try {
      final preview = await AnkiParser.preview(filePath);
      final m = preview.autoMapping;
      final exampleDefaults = _resolveExampleDefaultMappings(preview, m);
      if (!_pasteMode) {
        _deckNameCtrl.text = p.basenameWithoutExtension(_fileName ?? '我的词库');
      }
      setState(() {
        _preview      = preview;
        _mapWord      = m['word'];
        _mapReading   = m['reading'];
        _mapMeaningZh = m['meaning_zh'];
        _mapMeaningEn = m['meaning_en'];
        _mapExample   = exampleDefaults['example'];
        _mapExampleReading = exampleDefaults['example_reading'];
        _mapExampleMeaningZh = exampleDefaults['example_meaning_zh'];
        _step         = _Step.preview;
      });
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _step = _Step.error; });
    }
  }

  Map<String, int?> _resolveExampleDefaultMappings(
    AnkiPreview preview,
    Map<String, int?> auto,
  ) {
    final fields = preview.fields;
    final used = <int>{
      if (auto['word'] != null) auto['word']!,
      if (auto['reading'] != null) auto['reading']!,
      if (auto['meaning_zh'] != null) auto['meaning_zh']!,
      if (auto['meaning_en'] != null) auto['meaning_en']!,
    };

    int? pickByName(List<RegExp> patterns) {
      for (var i = 0; i < fields.length; i++) {
        if (used.contains(i)) continue;
        final name = fields[i].toLowerCase();
        for (final p in patterns) {
          if (p.hasMatch(name)) return i;
        }
      }
      return null;
    }

    int? pickNextUnused() {
      for (var i = 0; i < fields.length; i++) {
        if (!used.contains(i)) return i;
      }
      return null;
    }

    int? ex = auto['example'] ??
        pickByName([
          RegExp(r'example|sentence|例句|例文|sample|context', caseSensitive: false),
        ]);
    if (ex != null) used.add(ex);

    int? exReading = auto['example_reading'] ??
        pickByName([
          RegExp(r'example.*reading|sentence.*reading|例句读音|例文読み|文読み|example kana|sentence kana|pronunciation', caseSensitive: false),
        ]);
    exReading ??= pickNextUnused();
    if (exReading != null) used.add(exReading);

    int? exMeaning = auto['example_meaning_zh'] ??
        pickByName([
          RegExp(r'example.*meaning|sentence.*meaning|例句释义|例句翻译|例文訳|example translation|sentence translation', caseSensitive: false),
        ]);
    exMeaning ??= pickNextUnused();

    return {
      'example': ex,
      'example_reading': exReading,
      'example_meaning_zh': exMeaning,
    };
  }

  // ─── 步骤 3：本地解析 → 存本地 DB → 尝试同步服务端 ──────────────────────
  Future<void> _doImport() async {
    if (_filePath == null || _preview == null) return;
    if (_mapWord == null) {
      _showSnack('请先设置「单词」字段映射');
      return;
    }
    setState(() => _step = _Step.importing);
    try {
      final mapping = <String, int?>{
        'word':       _mapWord,
        'reading':    _mapReading,
        'meaning_zh': _mapMeaningZh,
        'meaning_en': _mapMeaningEn,
        'example':    _mapExample,
        'example_reading': _mapExampleReading,
        'example_meaning_zh': _mapExampleMeaningZh,
      };

      // ── 1. 本地解析 ──────────────────────────────────────────────────────
      final cards = await AnkiParser.parse(_filePath!, mapping);
      if (cards.isEmpty) throw Exception('未解析到有效卡片，请检查字段映射');

      final deckName = _deckNameCtrl.text.trim().isEmpty
          ? '我的词库'
          : _deckNameCtrl.text.trim();
      const uuid = Uuid();

      // ── 2. 写入本地 SQLite（离线也可用）────────────────────────────────────
      final rows = cards.map((c) {
        final json = c.toJson();
        // 优先使用 .apkg 中解析出的牌组层级名称，否则使用用户输入的牌组名
        final cardDeckName = (json['deck_name'] as String?)?.isNotEmpty == true
            ? json['deck_name'] as String
            : deckName;
        return {
          ...json,
          'id':             json['id'] as String? ?? uuid.v4(),
          // all 表示不按词性筛选导入，统一保留为 other 以兼容后端字段
          'part_of_speech': _partOfSpeech == 'all' ? 'other' : _partOfSpeech,
          'deck_name':      cardDeckName,
        };
      }).toList();

      final localCount = await localDb.insertCards(rows);
      final sourceType = _pasteMode
          ? 'paste'
          : (p.extension(_fileName ?? '').toLowerCase().replaceFirst('.', '').isEmpty
              ? 'manual'
              : p.extension(_fileName ?? '').toLowerCase().replaceFirst('.', ''));
      final importedDeckNames = rows
          .map((row) => row['deck_name']?.toString() ?? deckName)
          .where((name) => name.isNotEmpty)
          .toSet();
      for (final importedDeckName in importedDeckNames) {
        await localDb.upsertDeckMeta(
          deckName: importedDeckName,
          displayName: importedDeckName.split('::').last,
          coverImagePath: _coverImagePath,
          description: _deckDescCtrl.text,
          sourceType: sourceType,
        );
      }
      _savedLocally = true;

      setState(() {
        _result = {
          'imported':  localCount,
          'failed':    0,
          'deck_name': deckName,
        };
        _step = _Step.done;
      });
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _step = _Step.error; });
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _reset() => setState(() {
        _step = _Step.pick;
        _preview = null;
        _result = {};
        _errorMsg = '';
        _filePath = null;
        _fileName = null;
        _coverImagePath = null;
        _deckDescCtrl.clear();
        _pasteCtrl.clear();
        _savedLocally   = false;
        _mapExampleReading = null;
        _mapExampleMeaningZh = null;
      });

  // ─── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s  = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.ankiImport),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/vocabulary'),
        ),
        actions: [
          if (_step != _Step.pick)
            IconButton(icon: const Icon(Icons.refresh), tooltip: '重置', onPressed: _reset),
        ],
      ),
      body: MembershipGate(
        featureId: 'anki_import',
        isMember: _isMember,
        child: switch (_step) {
          _Step.pick      => _buildPickStep(cs, s),
          _Step.parsing   => _buildParsingStep(cs, s),
          _Step.preview   => _buildPreviewStep(cs, s),
          _Step.importing => _buildImportingStep(cs, s),
          _Step.done      => _buildDoneStep(cs, s),
          _Step.error     => _buildErrorStep(cs, s),
        },
      ),
    );
  }

  // ── 选择文件 ──────────────────────────────────────────────────────────────
  Widget _buildPickStep(ColorScheme cs, S s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            const SizedBox(height: 24),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.folder_open_rounded), label: Text('文件')),
                ButtonSegment(value: true, icon: Icon(Icons.content_paste_rounded), label: Text('粘贴')),
              ],
              selected: {_pasteMode},
              onSelectionChanged: (v) => setState(() => _pasteMode = v.first),
            ),
            const SizedBox(height: 28),
            if (!_pasteMode)
              _buildFileImportPane(cs, s)
            else
              _buildPasteImportPane(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildFileImportPane(ColorScheme cs, S s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.upload_file_rounded, size: 52, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text('导入我的词库', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '支持 Anki、CSV、TXT/TSV 文件，导入后会保存为本地个人词库。',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, height: 1.5),
            ),
            const SizedBox(height: 32),
            // 支持格式说明
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _FormatBadge(label: '.apkg', desc: s.apkgDesc),
                  const Divider(height: 16),
                  _FormatBadge(label: '.txt / .tsv', desc: s.tsvDesc),
                  const Divider(height: 16),
                  _FormatBadge(label: '.csv', desc: s.csvDesc),
                ],
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('选择文件'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _fillTemplate,
              icon: const Icon(Icons.article_rounded),
              label: const Text('查看导入模板示例'),
            ),
          ],
        ),
    );
  }

  Widget _buildPasteImportPane(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('文字导入',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('从网页、表格、备忘录复制 CSV 或制表符分隔内容，粘贴后会先进入字段映射预览。',
            style: TextStyle(color: cs.outline, height: 1.5)),
        const SizedBox(height: 14),
        TextField(
          controller: _pasteCtrl,
          minLines: 10,
          maxLines: 16,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: _templateText,
            alignLabelWithHint: true,
            labelText: '粘贴词库内容',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            '模板列统一用「｜」分隔：单词｜读音（可不填）｜释义｜例句｜例句读音｜例句释义。多个例句可在同一列内用「／」分隔。',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _fillTemplate,
              icon: const Icon(Icons.article_rounded),
              label: const Text('填入示例'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _importPastedText,
              icon: const Icon(Icons.preview_rounded),
              label: const Text('预览导入'),
            ),
          ),
        ]),
      ],
    );
  }

  // ── 解析中 ───────────────────────────────────────────────────────────────
  Widget _buildParsingStep(ColorScheme cs, S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(s.parsing, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_fileName ?? '', style: TextStyle(color: cs.outline, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ── 预览 & 配置 ───────────────────────────────────────────────────────────
  Widget _buildPreviewStep(ColorScheme cs, S s) {
    final preview     = _preview!;
    final fields      = preview.fields;
    final fieldOptions = [null, ...fields.asMap().keys];
    String fieldLabel(int? idx) => idx == null ? s.notMapped : '${fields[idx]}（第${idx + 1}列）';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: cs.primaryContainer,
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.insert_drive_file_rounded, color: cs.primary),
              title: Text(_fileName ?? '',
                  style: TextStyle(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
              subtitle: Text(
                '${preview.format.toUpperCase()}  ·  ${preview.total} ${s.cards}  ·  ${s.parsedLocally}',
                style: TextStyle(color: cs.primary, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 字段映射 ──
          Text(s.fieldMapping, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(s.fieldMappingHint, style: TextStyle(color: cs.outline, fontSize: 12)),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _MappingTile(
                  label: '${s.word} *',
                  icon: Icons.translate_rounded,
                  value: _mapWord,
                  options: fieldOptions,
                  optionLabel: fieldLabel,
                  required: true,
                  onChanged: (v) => setState(() => _mapWord = v),
                ),
                const Divider(height: 1, indent: 56),
                _MappingTile(
                  label: s.reading,
                  icon: Icons.record_voice_over_rounded,
                  value: _mapReading,
                  options: fieldOptions,
                  optionLabel: fieldLabel,
                  onChanged: (v) => setState(() => _mapReading = v),
                ),
                const Divider(height: 1, indent: 56),
                _MappingTile(
                  label: s.meaningZh,
                  icon: Icons.menu_book_rounded,
                  value: _mapMeaningZh,
                  options: fieldOptions,
                  optionLabel: fieldLabel,
                  onChanged: (v) => setState(() => _mapMeaningZh = v),
                ),
                const Divider(height: 1, indent: 56),
                _MappingTile(
                  label: s.meaningEn,
                  icon: Icons.translate_rounded,
                  value: _mapMeaningEn,
                  options: fieldOptions,
                  optionLabel: fieldLabel,
                  onChanged: (v) => setState(() => _mapMeaningEn = v),
                ),
                const Divider(height: 1, indent: 56),
                _MappingTile(
                  label: s.exampleSentence,
                  icon: Icons.format_quote_rounded,
                  value: _mapExample,
                  options: fieldOptions,
                  optionLabel: fieldLabel,
                  onChanged: (v) => setState(() => _mapExample = v),
                ),
                const Divider(height: 1, indent: 56),
                _MappingTile(
                  label: '例句读音',
                  icon: Icons.record_voice_over_rounded,
                  value: _mapExampleReading,
                  options: fieldOptions,
                  optionLabel: fieldLabel,
                  onChanged: (v) => setState(() => _mapExampleReading = v),
                ),
                const Divider(height: 1, indent: 56),
                _MappingTile(
                  label: '例句释义',
                  icon: Icons.translate_rounded,
                  value: _mapExampleMeaningZh,
                  options: fieldOptions,
                  optionLabel: fieldLabel,
                  onChanged: (v) => setState(() => _mapExampleMeaningZh = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 导入配置 ──
          Text(s.importSettings, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                  controller: _deckNameCtrl,
                  decoration: InputDecoration(
                    labelText: s.deckName,
                    prefixIcon: const Icon(Icons.folder_rounded),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deckDescCtrl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '词库介绍',
                    hintText: '例如：N2 高频词、小说常见表达、商务日语词库',
                    prefixIcon: Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickCoverImage,
                  child: Container(
                    height: 92,
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 58,
                          height: 72,
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: _coverImagePath == null
                              ? const Icon(Icons.image_rounded)
                              : Image.file(File(_coverImagePath!), fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('词库封面', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(_coverImagePath == null ? '可选，用于书架展示和后续共享' : '已选择封面图片',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                      const SizedBox(width: 8),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _partOfSpeech,
                  decoration: InputDecoration(labelText: s.partOfSpeech, border: const OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'all',          child: Text('全部词性 All (推荐)')),
                    DropdownMenuItem(value: 'noun',         child: Text('名词 Noun')),
                    DropdownMenuItem(value: 'verb',         child: Text('动词 Verb')),
                    DropdownMenuItem(value: 'adjective',    child: Text('形容词 Adjective')),
                    DropdownMenuItem(value: 'adverb',       child: Text('副词 Adverb')),
                    DropdownMenuItem(value: 'particle',     child: Text('助词 Particle')),
                    DropdownMenuItem(value: 'other',        child: Text('其他 Other')),
                  ],
                  onChanged: (v) => setState(() => _partOfSpeech = v!),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // 数据预览
          if (preview.samples.isNotEmpty && fields.isNotEmpty) ...[
            Text(s.dataPreview, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                headingRowHeight: 36,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 60,
                columns: fields.map((f) => DataColumn(label: Text(f, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))).toList(),
                rows: preview.samples.map((row) => DataRow(
                  cells: fields.map((f) {
                    final val = row[f] ?? '';
                    return DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(val, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ),
                    );
                  }).toList(),
                )).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          FilledButton.icon(
            onPressed: _doImport,
            icon: const Icon(Icons.download_rounded),
            label: Text('${s.startImport}  (${preview.total} ${s.cards})'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── 导入中 ────────────────────────────────────────────────────────────────
  Widget _buildImportingStep(ColorScheme cs, S s) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(strokeWidth: 3),
          const SizedBox(height: 24),
          Text(s.importing, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(_deckNameCtrl.text, style: TextStyle(color: cs.outline)),
        ],
      ),
    );
  }

  // ── 完成 ──────────────────────────────────────────────────────────────────
  Widget _buildDoneStep(ColorScheme cs, S s) {
    final imported  = _result['imported']   as int?  ?? 0;
    final failed    = _result['failed']     as int?  ?? 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, size: 48, color: Colors.green.shade600),
            ),
            const SizedBox(height: 20),
            Text(s.importDone, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
            const SizedBox(height: 24),
            _ResultRow(label: s.importedCount, value: '$imported', color: Colors.green),
            if (failed > 0) _ResultRow(label: s.skippedCount, value: '$failed', color: Colors.orange),
            _ResultRow(label: s.deckName, value: _result['deck_name']?.toString() ?? ''),
            const SizedBox(height: 12),
            _StatusChip(
              icon: Icons.storage_rounded,
              label: s.savedLocally,
              active: _savedLocally,
              activeColor: Colors.blue,
            ),
            const SizedBox(height: 32),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file_rounded),
                  onPressed: _reset,
                  label: Text(s.importMore),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.storage_rounded),
                  onPressed: () => context.push('/local-vocab'),
                  label: Text(s.viewLocalVocab),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── 错误 ──────────────────────────────────────────────────────────────────
  Widget _buildErrorStep(ColorScheme cs, S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: cs.error),
            const SizedBox(height: 16),
            Text(s.importFailed, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.error)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_errorMsg, style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _reset, child: Text(s.retry)),
          ],
        ),
      ),
    );
  }
}

// ─── 辅助 Widget ──────────────────────────────────────────────────────────────

class _FormatBadge extends StatelessWidget {
  final String label;
  final String desc;
  const _FormatBadge({required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(desc, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
    ]);
  }
}

class _MappingTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? value;
  final List<int?> options;
  final String Function(int?) optionLabel;
  final ValueChanged<int?> onChanged;
  final bool required;

  const _MappingTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: required && value == null ? cs.error : cs.primary),
      title: Text(label, style: TextStyle(
        fontWeight: FontWeight.w500,
        color: required && value == null ? cs.error : null,
      )),
      trailing: DropdownButton<int?>(
        value: value,
        underline: const SizedBox.shrink(),
        alignment: AlignmentDirectional.centerEnd,
        style: TextStyle(fontSize: 13, color: cs.onSurface),
        items: options.map((idx) => DropdownMenuItem(
          value: idx,
          child: Text(optionLabel(idx), overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ResultRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     active;
  final Color    activeColor;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.active,
    this.activeColor   = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }
}
