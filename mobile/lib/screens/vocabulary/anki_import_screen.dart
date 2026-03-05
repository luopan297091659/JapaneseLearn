import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../services/anki_parser.dart';
import '../../services/api_service.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';

enum _Step { pick, parsing, preview, importing, done, error }

class AnkiImportScreen extends StatefulWidget {
  const AnkiImportScreen({super.key});
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
  String _jlptLevel = 'N3';
  String _partOfSpeech = 'other';

  // 字段映射选择（字段名称 index，null = 不导入）
  int? _mapWord;
  int? _mapReading;
  int? _mapMeaningZh;
  int? _mapMeaningEn;
  int? _mapExample;

  // 结果
  Map<String, dynamic> _result = {};
  String _errorMsg = '';

  // 同步状态
  bool _savedLocally = false;
  bool _syncedToServer = false;
  int  _localCount = 0;

  @override
  void dispose() {
    _deckNameCtrl.dispose();
    super.dispose();
  }

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

  // ─── 步骤 2：客户端本地解析预览 ─────────────────────────────────────────
  Future<void> _runPreview(String filePath) async {
    try {
      final preview = await AnkiParser.preview(filePath);
      final m = preview.autoMapping;
      _deckNameCtrl.text = p.basenameWithoutExtension(_fileName ?? 'Anki Import');
      setState(() {
        _preview      = preview;
        _mapWord      = m['word'];
        _mapReading   = m['reading'];
        _mapMeaningZh = m['meaning_zh'];
        _mapMeaningEn = m['meaning_en'];
        _mapExample   = m['example'];
        _step         = _Step.preview;
      });
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _step = _Step.error; });
    }
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
      };

      // ── 1. 本地解析 ──────────────────────────────────────────────────────
      final cards = await AnkiParser.parse(_filePath!, mapping);
      if (cards.isEmpty) throw Exception('未解析到有效卡片，请检查字段映射');

      final deckName = _deckNameCtrl.text.trim().isEmpty
          ? 'Anki Import'
          : _deckNameCtrl.text.trim();
      const uuid = Uuid();

      // ── 2. 写入本地 SQLite（离线也可用）────────────────────────────────────
      final rows = cards.map((c) {
        final json = c.toJson();
        return {
          ...json,
          'id':           json['id'] as String? ?? uuid.v4(),
          'part_of_speech': _partOfSpeech,
          'jlpt_level':     _jlptLevel,
          'deck_name':      deckName,
        };
      }).toList();

      final localCount = await localDb.insertCards(rows);
      _savedLocally = true;
      _localCount   = localCount;

      // ── 3. 尝试同步到服务端（失败不影响本地保存）──────────────────────────
      bool serverOk = false;
      Map<String, dynamic> serverResult = {};
      try {
        serverResult = await apiService.bulkImportVocabulary(
          cards:        rows,
          deckName:     deckName,
          jlptLevel:    _jlptLevel,
          partOfSpeech: _partOfSpeech,
        );
        // 将刚插入的 id 标记为已同步
        final ids = rows.map((r) => r['id'] as String).toList();
        await localDb.markSynced(ids);
        serverOk = true;
      } catch (_) {
        // 网络不可用 / 服务器错误 → 保持 synced=0，稍后手动同步
        serverOk = false;
      }

      _syncedToServer = serverOk;
      setState(() {
        _result = {
          'imported':  serverOk ? (serverResult['imported'] ?? localCount) : localCount,
          'failed':    serverOk ? (serverResult['failed']   ?? 0)          : 0,
          'deck_name': deckName,
          'local_only': !serverOk,
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
        _savedLocally   = false;
        _syncedToServer = false;
        _localCount     = 0;
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
            IconButton(icon: const Icon(Icons.refresh), onPressed: _reset),
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: '返回首页',
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
      body: switch (_step) {
        _Step.pick      => _buildPickStep(cs, s),
        _Step.parsing   => _buildParsingStep(cs, s),
        _Step.preview   => _buildPreviewStep(cs, s),
        _Step.importing => _buildImportingStep(cs, s),
        _Step.done      => _buildDoneStep(cs, s),
        _Step.error     => _buildErrorStep(cs, s),
      },
    );
  }

  // ── 选择文件 ──────────────────────────────────────────────────────────────
  Widget _buildPickStep(ColorScheme cs, S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            Text(s.ankiImport, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              s.ankiImportHint,
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
              label: Text(s.selectFile),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
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
                DropdownButtonFormField<String>(
                  value: _jlptLevel,
                  decoration: InputDecoration(labelText: s.jlptLevel, border: const OutlineInputBorder()),
                  items: ['N5', 'N4', 'N3', 'N2', 'N1']
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => setState(() => _jlptLevel = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _partOfSpeech,
                  decoration: InputDecoration(labelText: s.partOfSpeech, border: const OutlineInputBorder()),
                  items: const [
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
    final localOnly = _result['local_only'] as bool? ?? false;

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
            // 本地 / 同步状态徽标
            _StatusChip(
              icon: Icons.storage_rounded,
              label: s.savedLocally,
              active: _savedLocally,
              activeColor: Colors.blue,
            ),
            const SizedBox(height: 6),
            _StatusChip(
              icon: _syncedToServer ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              label: _syncedToServer ? s.syncedToServer : s.pendingSync,
              active: _syncedToServer,
              activeColor: Colors.green,
              inactiveColor: Colors.orange,
            ),
            if (localOnly)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.sync_rounded),
                  onPressed: () => _syncNow(s),
                  label: Text(s.syncNow),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                ),
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

  Future<void> _syncNow(S s) async {
    _showSnack(s.syncing);
    final result = await syncService.syncVocabulary(
      jlptLevel:    _jlptLevel,
      partOfSpeech: _partOfSpeech,
    );
    if (!mounted) return;
    if (result != null && result.allDone) {
      setState(() => _syncedToServer = true);
      _showSnack(s.syncSuccess);
    } else {
      _showSnack(s.syncFailed);
    }
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
  final Color    inactiveColor;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.active,
    this.activeColor   = Colors.green,
    this.inactiveColor = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;
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
