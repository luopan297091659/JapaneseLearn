/**
 * Anki Import Controller
 * 
 * 支持格式：
 *   - .apkg  — Anki 导出包（ZIP + SQLite）
 *   - .txt   — Anki 文本导出（制表符分隔）
 *   - .csv   — CSV 格式
 *   - .tsv   — TSV 格式
 *
 * 导入方式：
 *   - 客户端解析后提交 /vocabulary/bulk（移动端）
 *   - 服务端直接解析 /anki/server-import（管理后台）
 */

const path = require('path');
const os = require('os');
const multer = require('multer');
const AdmZip = require('adm-zip');
const { v4: uuidv4 } = require('uuid');
const { Vocabulary, GrammarLesson, GrammarExample, ContentVersion } = require('../models');

// utilities moved to service for better separation
const {
  UPLOAD_AUDIO_DIR,
  getSqlJs,
  stripHtml,
  extractSoundRef,
  detectMapping,
  bumpVersion,
} = require('../services/ankiService');

// ─── Multer: 内存存储，最大 100 MB ──────────────────────────────────────────
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 100 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (['.apkg', '.txt', '.csv', '.tsv'].includes(ext)) return cb(null, true);
    cb(new Error('仅支持 .apkg / .txt / .csv / .tsv 格式'));
  },
});

module.exports.upload = upload;

// ─── 服务端解析 .apkg（含音频提取）────────────────────────────────────────────
async function serverParseApkg(buffer) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'anki-srv-'));
  try {
    const zip = new AdmZip(buffer);
    zip.extractAllTo(tmpDir, true);

    // 查找 SQLite 数据库
    const candidates = ['collection.anki21b', 'collection.anki21', 'collection.anki2'];
    const dbFile = candidates.map(f => path.join(tmpDir, f)).find(f => fs.existsSync(f));
    if (!dbFile) throw new Error('无法在 .apkg 中找到 Anki 数据库（不支持 anki21b 压缩格式）');

    // 读取媒体映射表 {index → filename}
    const mediaFile = path.join(tmpDir, 'media');
    const mediaMap = {};
    if (fs.existsSync(mediaFile)) {
      try { Object.assign(mediaMap, JSON.parse(fs.readFileSync(mediaFile, 'utf-8'))); } catch { /* ignore */ }
    }

    // 提取音频文件 → uploads/audio/
    const AUDIO_EXTS = new Set(['.mp3', '.ogg', '.wav', '.aac', '.m4a', '.flac', '.opus']);
    const audioUrlMap = {}; // original filename → "/uploads/audio/uuid.ext"
    for (const [idx, filename] of Object.entries(mediaMap)) {
      const ext = path.extname(filename).toLowerCase();
      if (!AUDIO_EXTS.has(ext)) continue;
      const srcFile = path.join(tmpDir, idx);
      if (!fs.existsSync(srcFile)) continue;
      const destName = `${uuidv4()}${ext}`;
      const destPath = path.join(UPLOAD_AUDIO_DIR, destName);
      fs.copyFileSync(srcFile, destPath);
      audioUrlMap[filename] = `/uploads/audio/${destName}`;
    }

    // 用 sql.js 解析 SQLite（纯 JS 实现，无需 native）
    const SQL = await getSqlJs();
    const dbBuffer = fs.readFileSync(dbFile);
    const db = new SQL.Database(dbBuffer);

    // 读取字段名（兼容 Anki 新旧版本）
    const fieldNameMap = {}; // mid → string[]
    try {
      const ntRes = db.exec('SELECT id FROM notetypes');
      if (ntRes[0]) {
        for (const [ntId] of ntRes[0].values) {
          const fRes = db.exec(`SELECT name FROM fields WHERE ntid = ${ntId} ORDER BY ord`);
          if (fRes[0]) fieldNameMap[String(ntId)] = fRes[0].values.map(r => String(r[0]));
        }
      }
    } catch {
      try {
        const colRes = db.exec('SELECT models FROM col');
        if (colRes[0]?.values[0]) {
          const models = JSON.parse(String(colRes[0].values[0][0]));
          for (const [id, m] of Object.entries(models)) {
            fieldNameMap[String(id)] = ((m).flds || []).map(f => f.name);
          }
        }
      } catch { /* ignore */ }
    }

    // 读取所有笔记
    const notesRes = db.exec('SELECT id, mid, tags, flds FROM notes');
    db.close();

    const notes = notesRes[0]
      ? notesRes[0].values.map(r => ({
          id:   String(r[0]),
          mid:  String(r[1]),
          tags: String(r[2] || ''),
          flds: String(r[3] || ''),
        }))
      : [];

    return { notes, fieldNameMap, audioUrlMap };
  } finally {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch { /* ignore */ }
  }
}

// ─── 解析文本格式（.txt / .csv / .tsv）────────────────────────────────────────
function parseTxt(buffer, ext) {
  const text = buffer.toString('utf-8');
  const sep  = ext === '.csv' ? ',' : '\t';

  // 过滤 Anki 注释行（# 开头）
  const allLines = text.split('\n').filter(l => l.trim());
  const lines    = allLines.filter(l => !l.startsWith('#'));

  if (lines.length === 0) return { fields: [], rows: [], hasHeader: false };

  // 尝试判断首行是否为标题行
  const firstCells = lines[0].split(sep).map(c => c.trim().replace(/^"|"$/g, ''));
  const looksLikeHeader = firstCells.every(c => /^[a-zA-Z\u4e00-\u9fff_\- ]+$/.test(c) && !/[\u3040-\u30ff]/.test(c));

  let fields, dataRows;
  if (looksLikeHeader && lines.length > 1) {
    fields   = firstCells;
    dataRows = lines.slice(1);
  } else {
    fields   = firstCells.map((_, i) => `字段${i + 1}`);
    dataRows = lines;
  }

  const rows = dataRows.map(line =>
    line.split(sep).map(c => c.trim().replace(/^"|"$/g, ''))
  );

  return { fields, rows, hasHeader: looksLikeHeader };
}

/** 获取某 mid 对应的字段名列表 */
function resolveFields(fieldNameMap, mid) {
  return fieldNameMap[String(mid)]
    || fieldNameMap[Object.keys(fieldNameMap)[0]]
    || [];
}

// ─── API: 预览导入 ───────────────────────────────────────────────────────────
async function previewImport(req, res) {
  if (!req.file) return res.status(400).json({ error: '未上传文件' });

  try {
    const ext = path.extname(req.file.originalname).toLowerCase();

    if (ext === '.apkg') {
      const { notes, fieldNameMap, audioUrlMap } = await serverParseApkg(req.file.buffer);
      if (!notes.length) return res.json({ format: 'apkg', fields: [], samples: [], total: 0, audioUrlMap: {} });

      const firstNote = notes[0];
      const fields    = resolveFields(fieldNameMap, firstNote.mid);
      const mapping   = detectMapping(fields);
      const hasAudio  = Object.keys(audioUrlMap).length > 0;

      const samples = notes.slice(0, 5).map(note => {
        const flds = note.flds.split('\x1f');
        return Object.fromEntries(fields.map((name, i) => [name, stripHtml(flds[i] || '')]));
      });

      return res.json({
        format: 'apkg',
        fields,
        mapping,
        samples,
        total: notes.length,
        hasAudio,
        audioCount: Object.keys(audioUrlMap).length,
      });
    }

    // txt / csv / tsv
    const { fields, rows, hasHeader } = parseTxt(req.file.buffer, ext);
    const mapping = detectMapping(fields);
    const samples = rows.slice(0, 5).map(flds =>
      Object.fromEntries(fields.map((name, i) => [name, flds[i] || '']))
    );

    return res.json({
      format: ext.replace('.', ''),
      fields,
      mapping,
      samples,
      total: rows.length,
      hasHeader,
      hasAudio: false,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── API: 服务端直接导入（管理后台使用）─────────────────────────────────────────
async function serverImport(req, res) {
  if (!req.file) return res.status(400).json({ error: '未上传文件' });

  const {
    import_type    = 'vocabulary',
    mapping: mappingJson,
    deck_name      = 'Anki Import',
    jlpt_level     = 'N3',
    part_of_speech = 'other',
    has_header     = 'false',
  } = req.body;

  let mapping;
  try {
    mapping = typeof mappingJson === 'object' ? mappingJson : JSON.parse(mappingJson);
  } catch {
    return res.status(400).json({ error: 'mapping 参数格式错误，需为 JSON' });
  }

  const VALID_LEVELS = ['N5', 'N4', 'N3', 'N2', 'N1'];
  const VALID_POS    = ['noun','verb','adjective','adverb','particle','conjunction','interjection','other'];
  const safeLevel = VALID_LEVELS.includes(jlpt_level) ? jlpt_level : 'N3';
  const safePos   = VALID_POS.includes(part_of_speech) ? part_of_speech : 'other';

  try {
    const ext = path.extname(req.file.originalname).toLowerCase();
    let allItems = [];   // [{ flds: string[], audioUrl: string|null }]
    let audioCount = 0;

    if (ext === '.apkg') {
      const { notes, fieldNameMap, audioUrlMap } = await serverParseApkg(req.file.buffer);
      audioCount = Object.keys(audioUrlMap).length;
      for (const note of notes) {
        const rawFlds = note.flds.split('\x1f');
        // 从原始字段提取音频引用
        let audioUrl = null;
        for (const raw of rawFlds) {
          const ref = extractSoundRef(raw);
          if (ref && audioUrlMap[ref]) { audioUrl = audioUrlMap[ref]; break; }
        }
        allItems.push({ flds: rawFlds.map(stripHtml), audioUrl });
      }
    } else {
      const { rows } = parseTxt(req.file.buffer, ext);
      const skipFirst = has_header === 'true';
      for (const flds of (skipFirst ? rows.slice(1) : rows)) {
        allItems.push({ flds, audioUrl: null });
      }
    }

    if (allItems.length === 0) return res.status(400).json({ error: '未找到有效数据' });

    let imported = 0, failed = 0;

    // ── 语法导入 ──────────────────────────────────────────────────────────────
    if (import_type === 'grammar') {
      const patIdx  = (mapping.pattern       ?? 0);
      const explIdx = (mapping.explanation    ?? mapping.explanation_zh ?? 1);
      const exzhIdx = (mapping.explanation_zh ?? mapping.explanation    ?? 1);
      const exsIdx  = mapping.example         ?? mapping.example_sentence;
      const exmIdx  = mapping.example_meaning_zh ?? mapping.example_meaning;

      for (const { flds, audioUrl } of allItems) {
        const pattern = (flds[patIdx] || '').substring(0, 300).trim();
        if (!pattern) continue;
        try {
          const lesson = await GrammarLesson.create({
            id:            uuidv4(),
            title:         pattern,
            title_zh:      (flds[exzhIdx] || '').substring(0, 200) || null,
            jlpt_level:    safeLevel,
            pattern,
            explanation:   (flds[explIdx] || pattern).substring(0, 2000),
            explanation_zh:(flds[exzhIdx] || '').substring(0, 2000) || null,
            order_index:   0,
          });
          if (exsIdx !== undefined && flds[exsIdx]) {
            await GrammarExample.create({
              id:               uuidv4(),
              grammar_lesson_id: lesson.id,
              sentence:         (flds[exsIdx] || '').substring(0, 2000),
              meaning_zh:       exmIdx !== undefined ? (flds[exmIdx] || '').substring(0, 2000) : '',
              audio_url:        audioUrl,
            });
          }
          imported++;
        } catch { failed++; }
      }
      await bumpVersion('grammar');

    // ── 词汇导入 ──────────────────────────────────────────────────────────────
    } else {
      const wi  = mapping.word       ?? 0;
      const ri  = mapping.reading;
      const zhi = mapping.meaning_zh;
      const eni = mapping.meaning_en;
      const exi = mapping.example    ?? mapping.example_sentence;

      const rows = [];
      for (const { flds, audioUrl } of allItems) {
        const word = (flds[wi] || '').substring(0, 100).trim();
        if (!word) continue;
        rows.push({
          id:               uuidv4(),
          word,
          reading:          ri  !== undefined ? (flds[ri]  || word).substring(0, 200) : word,
          meaning_zh:       zhi !== undefined ? (flds[zhi] || '-').substring(0, 1000) :
                            eni !== undefined ? (flds[eni] || '-').substring(0, 1000) : '-',
          meaning_en:       eni !== undefined ? (flds[eni] || null) : null,
          example_sentence: exi !== undefined ? (flds[exi] || null) : null,
          audio_url:        audioUrl,
          part_of_speech:   safePos,
          jlpt_level:       safeLevel,
          category:         deck_name.substring(0, 50),
          tags:             { source: 'anki', deck: deck_name },
        });
      }

      if (rows.length === 0) return res.status(400).json({ error: '没有找到有效卡片，请检查字段映射' });

      const CHUNK = 500;
      for (let i = 0; i < rows.length; i += CHUNK) {
        const chunk = rows.slice(i, i + CHUNK);
        try {
          await Vocabulary.bulkCreate(chunk, { ignoreDuplicates: true });
          imported += chunk.length;
        } catch { failed += chunk.length; }
      }
      await bumpVersion('vocabulary');
    }

    res.json({
      success: true, imported, failed, total: allItems.length,
      audio_count: audioCount, deck_name, import_type,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── API: 原有客户端上报式导入（保留兼容） ───────────────────────────────────
async function importAnki(req, res) {
  if (!req.file) return res.status(400).json({ error: '未上传文件' });

  const {
    mapping: mappingJson,
    deck_name    = 'Anki Import',
    jlpt_level   = 'N3',
    part_of_speech = 'other',
    has_header   = 'false',
  } = req.body;

  let mapping;
  try {
    mapping = typeof mappingJson === 'object' ? mappingJson : JSON.parse(mappingJson);
  } catch {
    return res.status(400).json({ error: 'mapping 参数格式错误，需为 JSON' });
  }

  const VALID_LEVELS = ['N5', 'N4', 'N3', 'N2', 'N1'];
  const VALID_POS    = ['noun','verb','adjective','adverb','particle','conjunction','interjection','other'];
  const safeLevel = VALID_LEVELS.includes(jlpt_level) ? jlpt_level : 'N3';
  const safePos   = VALID_POS.includes(part_of_speech) ? part_of_speech : 'other';

  try {
    const ext  = path.extname(req.file.originalname).toLowerCase();
    const rows = [];

    const buildRow = (flds) => {
      const wi  = mapping.word;
      const ri  = mapping.reading;
      const zhi = mapping.meaning_zh;
      const eni = mapping.meaning_en;
      const exi = mapping.example;

      const word = stripHtml(flds[wi] || '').substring(0, 100);
      if (!word) return null;

      return {
        id: uuidv4(),
        word,
        reading:          (stripHtml(flds[ri] || '') || word).substring(0, 200),
        meaning_zh:       (stripHtml(zhi !== undefined ? flds[zhi] : (eni !== undefined ? flds[eni] : '')) || '-').substring(0, 1000),
        meaning_en:       eni !== undefined ? stripHtml(flds[eni] || '').substring(0, 1000) : null,
        example_sentence: exi !== undefined ? stripHtml(flds[exi] || '').substring(0, 2000) : null,
        part_of_speech:   safePos,
        jlpt_level:       safeLevel,
        category:         deck_name.substring(0, 50),
        tags:             { source: 'anki', deck: deck_name },
      };
    };

    if (ext === '.apkg') {
      const { notes, fieldNameMap } = await serverParseApkg(req.file.buffer);
      for (const note of notes) {
        const flds = note.flds.split('\x1f');
        const row  = buildRow(flds);
        if (row) rows.push(row);
      }
    } else {
      const { rows: dataRows } = parseTxt(req.file.buffer, ext);
      const skipFirst = has_header === 'true';
      for (const flds of (skipFirst ? dataRows.slice(1) : dataRows)) {
        const row = buildRow(flds);
        if (row) rows.push(row);
      }
    }

    if (rows.length === 0) {
      return res.status(400).json({ error: '没有找到有效卡片，请检查字段映射' });
    }

    const CHUNK = 500;
    let imported = 0;
    let failed   = 0;

    for (let i = 0; i < rows.length; i += CHUNK) {
      const chunk = rows.slice(i, i + CHUNK);
      try {
        await Vocabulary.bulkCreate(chunk, { ignoreDuplicates: true });
        imported += chunk.length;
      } catch (err) {
        failed += chunk.length;
      }
    }

    res.json({ success: true, imported, failed, total: rows.length, deck_name });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── API: 获取 Anki 导入记录（按 category + source=anki 统计）───────────────
async function listAnkiDecks(req, res) {
  try {
    const { sequelize } = require('../models');
    const [rows] = await sequelize.query(`
      SELECT category AS deck_name,
             COUNT(*) AS card_count,
             MIN(created_at) AS imported_at
      FROM vocabulary
      WHERE JSON_EXTRACT(tags, '$.source') = 'anki'
      GROUP BY category
      ORDER BY imported_at DESC
    `);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = { upload, previewImport, importAnki, serverImport, listAnkiDecks };
