const fs = require('fs');
const path = require('path');
const { Op } = require('sequelize');
const { JlptResourceDirectory, JlptResourceFile, ToolUsageLog } = require('../models');
const { isActiveMember } = require('../middlewares/membership');

const LEVELS = ['N1', 'N2', 'N3', 'N4', 'N5'];
const YEARS = Array.from({ length: 16 }, (_, i) => 2010 + i);
const SESSIONS = ['07', '12'];
const UPLOAD_ROOT = path.join(__dirname, '../../private/jlpt-resources');
const PUBLIC_ROOT = '/api/v1/jlpt-resources/files';

function assertDirectoryInput(level, year, session) {
  const normalizedLevel = String(level || '').toUpperCase();
  const normalizedYear = Number(year);
  const normalizedSession = String(session || '').padStart(2, '0');
  if (!LEVELS.includes(normalizedLevel)) throw new Error('JLPT 级别无效');
  if (!YEARS.includes(normalizedYear)) throw new Error('年份必须在 2010-2025 之间');
  if (!SESSIONS.includes(normalizedSession)) throw new Error('场次必须是 07 或 12');
  return { level: normalizedLevel, year: normalizedYear, session: normalizedSession };
}

function normalizeOriginalName(originalName = '') {
  const raw = String(originalName || '').trim() || 'file';
  try {
    const decoded = Buffer.from(raw, 'latin1').toString('utf8');
    if (decoded && decoded !== raw && !decoded.includes('�')) return decoded;
  } catch { /* keep original */ }
  return raw;
}

function safeStoredName(originalName = '') {
  const ext = path.extname(originalName).toLowerCase();
  const base = path.basename(originalName, ext)
    .replace(/[^\w\u4e00-\u9fa5ぁ-んァ-ヶー.-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80) || 'file';
  return `${Date.now()}_${Math.random().toString(16).slice(2, 10)}_${base}${ext}`;
}

function directoryPath(level, year, session) {
  return path.join(UPLOAD_ROOT, level, String(year), session);
}

function downloadUrl(id) {
  return `${PUBLIC_ROOT}/${id}/download`;
}

function requestMeta(req) {
  return {
    ip: (req.headers['x-forwarded-for'] || req.ip || '').toString().split(',')[0].trim().slice(0, 60),
    user_agent: (req.headers['user-agent'] || '').toString().slice(0, 300),
    referer: (req.headers.referer || req.headers.referrer || '').toString().slice(0, 500),
  };
}

async function ensureDirectory(level, year, session, membershipRequired = false) {
  const input = assertDirectoryInput(level, year, session);
  await fs.promises.mkdir(directoryPath(input.level, input.year, input.session), { recursive: true });
  const [dir] = await JlptResourceDirectory.findOrCreate({
    where: input,
    defaults: { ...input, membership_required: !!membershipRequired },
  });
  return dir;
}

async function ensureAllDirectories() {
  await Promise.all(LEVELS.flatMap(level => YEARS.flatMap(year => SESSIONS.map(session => ensureDirectory(level, year, session)))));
}

function toDirectoryJson(dir) {
  const files = dir.files || [];
  return {
    id: dir.id,
    level: dir.level,
    year: dir.year,
    session: dir.session,
    membership_required: !!dir.membership_required,
    file_count: Array.isArray(files) ? files.length : Number(dir.get?.('file_count') || 0),
    files: Array.isArray(files) ? files.map(toFileJson) : undefined,
  };
}

function toFileJson(file) {
  return {
    id: file.id,
    directory_id: file.directory_id,
    original_name: file.original_name,
    mime_type: file.mime_type,
    file_size: Number(file.file_size || 0),
    createdAt: file.createdAt,
  };
}

async function adminListJlptResources(_req, res) {
  await ensureAllDirectories();
  const dirs = await JlptResourceDirectory.findAll({
    order: [['level', 'ASC'], ['year', 'DESC'], ['session', 'DESC']],
  });
  const files = await JlptResourceFile.findAll({
    order: [['created_at', 'DESC']],
  });
  const filesByDir = new Map();
  files.forEach(file => {
    const key = String(file.directory_id);
    const list = filesByDir.get(key) || [];
    list.push(file);
    filesByDir.set(key, list);
  });
  res.json({
    data: dirs.map(dir => toDirectoryJson({
      ...dir.toJSON(),
      files: filesByDir.get(String(dir.id)) || [],
    })),
  });
}

async function adminUploadJlptResources(req, res) {
  const { level, year, session } = assertDirectoryInput(req.body.level, req.body.year, req.body.session);
  const files = Array.isArray(req.files) ? req.files : [];
  if (!files.length) return res.status(400).json({ error: '请选择要上传的文件' });

  const dir = await ensureDirectory(level, year, session, req.body.membership_required === 'true' || req.body.membership_required === '1');
  if (req.body.membership_required !== undefined) {
    await dir.update({ membership_required: req.body.membership_required === 'true' || req.body.membership_required === '1' });
  }

  const destDir = directoryPath(level, year, session);
  const created = [];
  for (const file of files) {
    const originalName = normalizeOriginalName(file.originalname);
    const storedName = safeStoredName(originalName);
    const dest = path.join(destDir, storedName);
    await fs.promises.writeFile(dest, file.buffer);
    const row = await JlptResourceFile.create({
      directory_id: dir.id,
      original_name: originalName,
      stored_name: storedName,
      file_url: PUBLIC_ROOT,
      mime_type: file.mimetype,
      file_size: file.size,
    });
    await row.update({ file_url: downloadUrl(row.id) });
    created.push(row);
  }

  const directoryFiles = await JlptResourceFile.findAll({
    where: { directory_id: dir.id },
    order: [['created_at', 'DESC']],
  });

  res.status(201).json({
    ok: true,
    directory: toDirectoryJson({ ...dir.toJSON(), files: directoryFiles }),
    files: created.map(toFileJson),
  });
}

async function adminUpdateJlptResourceDirectory(req, res) {
  const dir = await JlptResourceDirectory.findByPk(req.params.id);
  if (!dir) return res.status(404).json({ error: '目录不存在' });
  await dir.update({ membership_required: !!req.body.membership_required });
  res.json({ ok: true, data: toDirectoryJson(dir) });
}

async function deletePhysicalFile(file) {
  const dir = file.directory;
  if (!dir) return;
  const target = path.resolve(directoryPath(dir.level, dir.year, dir.session), file.stored_name);
  const root = path.resolve(UPLOAD_ROOT);
  if (!target.startsWith(root + path.sep)) return;
  await fs.promises.rm(target, { force: true });
}

async function adminBulkDeleteJlptResources(req, res) {
  const ids = Array.isArray(req.body.ids) ? req.body.ids.map(String).filter(Boolean) : [];
  if (!ids.length) return res.status(400).json({ error: '请选择要删除的文件' });
  const files = await JlptResourceFile.findAll({
    where: { id: { [Op.in]: ids } },
    include: [{ model: JlptResourceDirectory, as: 'directory' }],
  });
  for (const file of files) await deletePhysicalFile(file);
  const affected = await JlptResourceFile.destroy({ where: { id: { [Op.in]: ids } } });
  res.json({ ok: true, affected });
}

async function publicListJlptResourceDirectories(req, res) {
  await ensureAllDirectories();
  const dirs = await JlptResourceDirectory.findAll({
    order: [['level', 'ASC'], ['year', 'DESC'], ['session', 'DESC']],
  });
  const files = await JlptResourceFile.findAll({ attributes: ['id', 'directory_id'] });
  const fileCounts = files.reduce((acc, file) => {
    const key = String(file.directory_id);
    acc.set(key, (acc.get(key) || 0) + 1);
    return acc;
  }, new Map());
  const userCanMemberDownload = req.user?.role === 'admin' || isActiveMember(req.user);
  res.json({
    data: dirs
      .map(dir => ({
        dir,
        count: fileCounts.get(String(dir.id)) || 0,
      }))
      .filter(item => item.count > 0)
      .map(({ dir, count }) => ({
        ...toDirectoryJson({
          ...dir.toJSON(),
          files: Array.from({ length: count }, () => ({ id: '' })),
        }),
        can_download: !dir.membership_required || userCanMemberDownload,
        files: undefined,
      })),
  });
}

async function publicListJlptResourceFiles(req, res) {
  const { level, year, session } = assertDirectoryInput(req.query.level, req.query.year, req.query.session);
  const dir = await JlptResourceDirectory.findOne({ where: { level, year, session } });
  if (!dir) return res.json({ directory: { level, year, session, membership_required: false }, data: [] });
  const files = await JlptResourceFile.findAll({
    where: { directory_id: dir.id },
    order: [['created_at', 'DESC']],
  });
  const canDownload = !dir.membership_required || req.user?.role === 'admin' || isActiveMember(req.user);
  res.json({
    directory: { ...toDirectoryJson({ ...dir.toJSON(), files }), files: undefined, can_download: canDownload },
    data: files.map(file => ({ ...toFileJson(file), can_download: canDownload })),
  });
}

async function publicDownloadJlptResourceFile(req, res) {
  const file = await JlptResourceFile.findByPk(req.params.id, {
    include: [{ model: JlptResourceDirectory, as: 'directory' }],
  });
  if (!file || !file.directory) return res.status(404).json({ error: '文件不存在' });
  if (file.directory.membership_required && req.user?.role !== 'admin' && !isActiveMember(req.user)) {
    return res.status(403).json({ error: 'MEMBERSHIP_REQUIRED', message: '该目录仅会员可下载' });
  }
  const target = path.resolve(directoryPath(file.directory.level, file.directory.year, file.directory.session), file.stored_name);
  const root = path.resolve(UPLOAD_ROOT);
  if (!target.startsWith(root + path.sep) || !fs.existsSync(target)) return res.status(404).json({ error: '文件不存在' });
  await ToolUsageLog.create({
    tool_id: 'jlpt-papers',
    action: 'download',
    user_id: req.user?.id || null,
    ...requestMeta(req),
    meta: {
      file_id: file.id,
      directory_id: file.directory_id,
      level: file.directory.level,
      year: file.directory.year,
      session: file.directory.session,
      original_name: file.original_name,
      file_size: Number(file.file_size || 0),
    },
  }).catch(() => {});
  res.download(target, file.original_name);
}

module.exports = {
  adminListJlptResources,
  adminUploadJlptResources,
  adminUpdateJlptResourceDirectory,
  adminBulkDeleteJlptResources,
  publicListJlptResourceDirectories,
  publicListJlptResourceFiles,
  publicDownloadJlptResourceFile,
};
