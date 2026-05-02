/**
 * 听力磨耳朵 —— 频道视频获取控制器
 *
 * 公开接口：
 *   GET /api/v1/listening-channels          获取活跃频道列表+最近视频（登录用户额外包含自己的私有频道）
 *   GET /api/v1/listening-channels/:id      获取某频道的视频列表
 * 用户接口（需登录）：
 *   GET /api/v1/listening-channels/my/channels
 *   POST /api/v1/listening-channels/my/channels
 *   DELETE /api/v1/listening-channels/my/channels/:id
 */
const https = require('https');
const http = require('http');
const { Op } = require('sequelize');
const { ListeningChannel } = require('../models');
const logger = require('../utils/logger');

const CACHE_TTL = 3 * 60 * 60 * 1000; // 3 小时缓存

// ── YouTube RSS 获取最新视频 ────────────────────────────────────────────────
function fetchYouTubeVideos(channelId) {
  return new Promise((resolve, reject) => {
    const url = `https://www.youtube.com/feeds/videos.xml?channel_id=${encodeURIComponent(channelId)}`;
    https.get(url, { timeout: 15000, headers: { 'User-Agent': 'Mozilla/5.0' } }, resp => {
      let data = '';
      resp.on('data', c => data += c);
      resp.on('end', () => {
        try {
          const videos = [];
          const entries = data.split('<entry>').slice(1);
          const maxVids = 12; // YouTube RSS default
          for (const entry of entries.slice(0, maxVids)) {
            const videoId = entry.match(/<yt:videoId>([^<]+)/)?.[1];
            const title   = entry.match(/<title>([^<]+)/)?.[1];
            const published = entry.match(/<published>([^<]+)/)?.[1];
            const thumb   = entry.match(/<media:thumbnail[^>]+url="([^"]+)"/)?.[1];
            if (videoId && title) {
              videos.push({
                videoId,
                title: decodeXmlEntities(title),
                thumbnail: thumb || `https://i.ytimg.com/vi/${videoId}/mqdefault.jpg`,
                publishedAt: published || '',
                platform: 'youtube',
                embedUrl: `https://www.youtube.com/embed/${videoId}`,
              });
            }
          }
          const channelName = data.match(/<author>\s*<name>([^<]+)/)?.[1] || '';
          resolve({ videos, channelName });
        } catch (e) {
          reject(new Error('YouTube RSS 解析失败: ' + e.message));
        }
      });
    }).on('error', reject);
  });
}

// ── Bilibili 获取最新视频（使用 recArchivesByKeywords API）──────────────────
function fetchBilibiliVideos(mid, maxVideos = 12) {
  const ps = Math.max(maxVideos, 1);
  return new Promise((resolve, reject) => {
    const url = `https://api.bilibili.com/x/series/recArchivesByKeywords?mid=${encodeURIComponent(mid)}&keywords=&orderby=pubdate&ps=${ps}&pn=1`;
    https.get(url, {
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://space.bilibili.com/',
      },
    }, resp => {
      let data = '';
      resp.on('data', c => data += c);
      resp.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.code !== 0) {
            logger.warn(`Bilibili API code=${json.code}: ${json.message}`);
            resolve({ videos: [], channelName: '' });
            return;
          }
          const list = json.data?.archives || [];
          const videos = list.map(v => ({
            videoId: v.bvid || `av${v.aid}`,
            title: v.title,
            thumbnail: (v.pic?.startsWith('//') ? 'https:' + v.pic : v.pic?.replace('http://', 'https://')) || '',
            publishedAt: v.pubdate ? new Date(v.pubdate * 1000).toISOString() : '',
            platform: 'bilibili',
            embedUrl: `https://player.bilibili.com/player.html?isOutside=true&bvid=${v.bvid}&autoplay=0&danmaku=0`,
            duration: v.duration || 0,
          }));
          resolve({ videos, channelName: '' });
        } catch (e) {
          reject(new Error('Bilibili API 解析失败: ' + e.message));
        }
      });
    }).on('error', reject);
  });
}

// ── Bilibili 获取单个视频 ──────────────────────────────────────────────────
function fetchBilibiliSingleVideo(videoId) {
  return new Promise((resolve, reject) => {
    const isBvid = /^BV[0-9A-Za-z]+$/i.test(videoId);
    const query = isBvid ? `bvid=${encodeURIComponent(videoId)}` : `aid=${encodeURIComponent(String(videoId).replace(/^av/i, ''))}`;
    const url = `https://api.bilibili.com/x/web-interface/view?${query}`;
    https.get(url, {
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com/',
      },
    }, resp => {
      let data = '';
      resp.on('data', c => data += c);
      resp.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.code !== 0 || !json.data) {
            logger.warn(`Bilibili video API code=${json.code}: ${json.message}`);
            resolve({ videos: [], channelName: '' });
            return;
          }
          const v = json.data;
          const bvid = v.bvid || videoId;
          resolve({
            videos: [{
              videoId: bvid,
              title: v.title || bvid,
              thumbnail: (v.pic?.startsWith('//') ? 'https:' + v.pic : v.pic?.replace('http://', 'https://')) || '',
              publishedAt: v.pubdate ? new Date(v.pubdate * 1000).toISOString() : '',
              platform: 'bilibili',
              embedUrl: `https://player.bilibili.com/player.html?isOutside=true&bvid=${bvid}&autoplay=0&danmaku=0`,
              duration: v.duration || 0,
            }],
            channelName: v.owner?.name || '',
            avatar: v.owner?.face || '',
          });
        } catch (e) {
          reject(new Error('Bilibili 视频解析失败: ' + e.message));
        }
      });
    }).on('error', reject);
  });
}

// ── Bilibili 获取用户信息 ──────────────────────────────────────────────────
function fetchBilibiliUserInfo(mid) {
  return new Promise((resolve) => {
    const url = `https://api.bilibili.com/x/web-interface/card?mid=${encodeURIComponent(mid)}`;
    https.get(url, { timeout: 10000, headers: { 'User-Agent': 'Mozilla/5.0' } }, resp => {
      let data = '';
      resp.on('data', c => data += c);
      resp.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.code === 0 && json.data?.card) {
            resolve({ name: json.data.card.name, avatar: json.data.card.face });
          } else {
            resolve(null);
          }
        } catch { resolve(null); }
      });
    }).on('error', () => resolve(null));
  });
}

// ── YouTube @handle → UC channel ID 解析 ──────────────────────────────────
function resolveYouTubeHandle(handle) {
  // Remove leading @ if present
  const cleanHandle = handle.startsWith('@') ? handle.slice(1) : handle;
  return new Promise((resolve) => {
    const url = `https://www.youtube.com/@${encodeURIComponent(cleanHandle)}`;
    https.get(url, {
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    }, resp => {
      // Follow redirects
      if (resp.statusCode >= 300 && resp.statusCode < 400 && resp.headers.location) {
        const redirectUrl = resp.headers.location;
        const channelMatch = redirectUrl.match(/\/channel\/(UC[\w-]+)/);
        if (channelMatch) {
          resolve(channelMatch[1]);
          return;
        }
      }
      let data = '';
      resp.on('data', c => data += c);
      resp.on('end', () => {
        // Try to extract channel ID from page HTML
        const patterns = [
          /"channelId"\s*:\s*"(UC[\w-]+)"/,
          /"externalId"\s*:\s*"(UC[\w-]+)"/,
          /channel_id=(UC[\w-]+)/,
          /\/channel\/(UC[\w-]+)/,
        ];
        for (const pattern of patterns) {
          const m = data.match(pattern);
          if (m) { resolve(m[1]); return; }
        }
        resolve(null);
      });
    }).on('error', () => resolve(null));
  });
}

// ── URL 解析：提取 channelId / mid ──────────────────────────────────────────
function parseChannelUrl(url) {
  let m;
  const normalizedUrl = String(url || '').trim();
  // YouTube: /channel/UCxxx
  m = normalizedUrl.match(/youtube\.com\/channel\/(UC[\w-]+)/);
  if (m) return { platform: 'youtube', channelId: m[1] };

  // YouTube: /@handle  or /@handle/videos etc.
  m = normalizedUrl.match(/youtube\.com\/@([\w.-]+)/);
  if (m) return { platform: 'youtube', handle: m[1] };

  // YouTube: /c/name
  m = normalizedUrl.match(/youtube\.com\/c\/([\w.-]+)/);
  if (m) return { platform: 'youtube', handle: m[1] };

  // Bilibili: space.bilibili.com/12345
  m = normalizedUrl.match(/space\.bilibili\.com\/(\d+)/);
  if (m) return { platform: 'bilibili', channelId: m[1] };

  // Bilibili: bilibili.com?mid=12345
  m = normalizedUrl.match(/bilibili\.com.*mid[=:](\d+)/);
  if (m) return { platform: 'bilibili', channelId: m[1] };

  // Bilibili: bilibili.com/video/BVxxx or /video/av12345, with optional trailing slash/query
  m = normalizedUrl.match(/bilibili\.com\/video\/(BV[0-9A-Za-z]+)/i);
  if (m) return { platform: 'bilibili', channelId: m[1], type: 'video' };
  m = normalizedUrl.match(/bilibili\.com\/video\/(av\d+)/i);
  if (m) return { platform: 'bilibili', channelId: m[1], type: 'video' };

  return null;
}

function decodeXmlEntities(s) {
  return s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#(\d+);/g, (_,n) => String.fromCharCode(n));
}

// ── 刷新单个频道的视频缓存 ──────────────────────────────────────────────────
async function refreshChannelCache(channel) {
  try {
    let result;
    if (channel.platform === 'youtube') {
      // YouTube：尝试解析 @handle → UC channel ID
      if (channel.channel_id?.startsWith('@')) {
        const resolved = await resolveYouTubeHandle(channel.channel_id);
        if (resolved) {
          await channel.update({ channel_id: resolved });
          logger.info(`YouTube handle ${channel.channel_id} → ${resolved}`);
        } else {
          logger.warn(`无法解析 YouTube handle: ${channel.channel_id}（服务器可能无法访问 YouTube）`);
          return;
        }
      }
      if (!channel.channel_id) return;
      result = await fetchYouTubeVideos(channel.channel_id);
    } else {
      if (!channel.channel_id) return;
      if (/^(BV[0-9A-Za-z]+|av\d+)$/i.test(channel.channel_id)) {
        result = await fetchBilibiliSingleVideo(channel.channel_id);
      } else {
        result = await fetchBilibiliVideos(channel.channel_id, channel.max_videos || 12);
      }
      // 同时尝试获取用户名和头像
      if (!channel.name || channel.name === '未命名频道') {
        const info = result?.avatar
          ? { name: result.channelName, avatar: result.avatar }
          : await fetchBilibiliUserInfo(channel.channel_id);
        if (info) {
          await channel.update({ name: info.name, avatar: info.avatar });
        }
      }
    }
    if (result && result.videos.length > 0) {
      const updateData = {
        video_cache: result.videos,
        cache_updated_at: new Date(),
      };
      if (result.channelName && (!channel.name || channel.name === '未命名频道')) {
        updateData.name = result.channelName;
      }
      await channel.update(updateData);
    }
  } catch (e) {
    logger.warn(`频道 ${channel.name} 视频刷新失败:`, e.message);
  }
}

// ── 公开 API ────────────────────────────────────────────────────────────────

/**
 * GET /api/v1/listening-channels
 * 返回扁平化、去重、分页的视频列表
 * Query: page=1, limit=30
 */
async function listChannels(req, res) {
  try {
    const userId = req.user?.id || null;
    let channels = await ListeningChannel.findAll({
      where: {
        is_active: true,
        [Op.or]: [
          { is_public: true },
          ...(userId ? [{ owner_user_id: userId }] : []),
        ],
      },
      order: [['sort_order', 'ASC'], ['createdAt', 'DESC']],
    });

    // 检查缓存是否过期，按需刷新
    const refreshPromises = [];
    for (const ch of channels) {
      const age = ch.cache_updated_at ? Date.now() - new Date(ch.cache_updated_at).getTime() : Infinity;
      if (age > CACHE_TTL) {
        refreshPromises.push(refreshChannelCache(ch));
      }
    }
    if (refreshPromises.length > 0) {
      await Promise.allSettled(refreshPromises);
      channels = await ListeningChannel.findAll({
        where: {
          is_active: true,
          [Op.or]: [
            { is_public: true },
            ...(userId ? [{ owner_user_id: userId }] : []),
          ],
        },
        order: [['sort_order', 'ASC'], ['createdAt', 'DESC']],
      });
    }

    // 合并所有视频为扁平列表，附加频道信息
    // 按频道优先级（sort_order）错位排列
    const seen = new Set();
    const channelVideos = []; // [{sortOrder, videos:[]}]
    for (const ch of channels) {
      let videos = ch.video_cache || [];
      if (typeof videos === 'string') { try { videos = JSON.parse(videos); } catch(e) { videos = []; } }
      if (!Array.isArray(videos)) videos = [];
      const deduped = [];
      for (const v of videos) {
        const key = `${v.platform || ch.platform}_${v.videoId}`;
        if (seen.has(key)) continue;
        seen.add(key);
        deduped.push({
          ...v,
          platform: v.platform || ch.platform,
          channelName: ch.name,
          channelId: ch.id,
          channelScope: ch.owner_user_id ? 'custom' : 'public',
        });
      }
      // 频道内按发布时间降序
      deduped.sort((a, b) => {
        const da = a.publishedAt ? new Date(a.publishedAt).getTime() : 0;
        const db = b.publishedAt ? new Date(b.publishedAt).getTime() : 0;
        return db - da;
      });
      if (deduped.length > 0) {
        channelVideos.push({ sortOrder: ch.sort_order || 0, videos: deduped });
      }
    }
    // 按 sort_order 排列频道（越小优先级越高）
    channelVideos.sort((a, b) => a.sortOrder - b.sortOrder);

    // 错位交叉合并：轮流从各频道取视频
    const allVideos = [];
    const indices = channelVideos.map(() => 0);
    let hasMore = true;
    while (hasMore) {
      hasMore = false;
      for (let i = 0; i < channelVideos.length; i++) {
        if (indices[i] < channelVideos[i].videos.length) {
          allVideos.push(channelVideos[i].videos[indices[i]]);
          indices[i]++;
          hasMore = true;
        }
      }
    }

    // 分页
    const page = Math.max(parseInt(req.query.page) || 1, 1);
    const ALLOWED_LIMITS = [20, 50, 100];
    let limit = parseInt(req.query.limit) || 20;
    if (!ALLOWED_LIMITS.includes(limit)) limit = 20;
    const total = allVideos.length;
    const totalPages = Math.ceil(total / limit) || 1;
    const start = (page - 1) * limit;
    const paged = allVideos.slice(start, start + limit);

    res.json({ data: paged, total, page, totalPages });
  } catch (err) {
    logger.error('listChannels error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

/**
 * GET /api/v1/listening-channels/:id
 * 返回单个频道详情 + 刷新视频
 */
async function getChannelVideos(req, res) {
  try {
    const ch = await ListeningChannel.findByPk(req.params.id);
    if (!ch) return res.status(404).json({ error: '频道不存在' });

    // 强制刷新
    await refreshChannelCache(ch);
    await ch.reload();
    res.json(formatChannel(ch));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

function formatChannel(ch) {
  const isYtHandle = ch.platform === 'youtube' && ch.channel_id?.startsWith('@');
  return {
    id: ch.id,
    platform: ch.platform,
    name: ch.name,
    avatar: ch.avatar,
    description: ch.description,
    channel_url: ch.channel_url,
    channel_id: ch.channel_id,
    yt_handle: isYtHandle ? ch.channel_id : null,
    videos: ch.video_cache || [],
  };
}

// ── 管理员 API ──────────────────────────────────────────────────────────────

async function adminListChannels(req, res) {
  const channels = await ListeningChannel.findAll({ order: [['sort_order', 'ASC'], ['createdAt', 'DESC']] });
  res.json({ data: channels });
}

async function adminCreateChannel(req, res) {
  const { channel_url, name, description, max_videos } = req.body;
  if (!channel_url) return res.status(400).json({ error: '请输入频道链接' });

  const parsed = parseChannelUrl(channel_url);
  if (!parsed) return res.status(400).json({ error: '无法识别的链接，请输入 YouTube 频道、Bilibili 空间或 Bilibili 视频 URL' });

  // YouTube @handle 尝试解析为 UC channel ID
  let channelId = parsed.channelId || (parsed.handle ? `@${parsed.handle}` : null);
  if (!channelId) return res.status(400).json({ error: '无法提取频道 ID' });

  if (parsed.platform === 'youtube' && channelId.startsWith('@')) {
    const resolved = await resolveYouTubeHandle(channelId);
    if (resolved) channelId = resolved;
  }

  try {
    const ch = await ListeningChannel.create({
      platform: parsed.platform,
      channel_url,
      channel_id: channelId,
      name: name || '未命名频道',
      description: description || '',
      max_videos: max_videos ? Math.max(parseInt(max_videos) || 12, 1) : 12,
      is_active: true,
    });

    // 立即抓取视频（YouTube handle 频道服务端可能无法抓取，不影响创建）
    await refreshChannelCache(ch);
    await ch.reload();

    res.status(201).json(ch);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

async function adminUpdateChannel(req, res) {
  const ch = await ListeningChannel.findByPk(req.params.id);
  if (!ch) return res.status(404).json({ error: 'Not found' });
  const { name, description, is_active, sort_order, max_videos } = req.body;
  await ch.update({
    ...(name !== undefined && { name }),
    ...(description !== undefined && { description }),
    ...(is_active !== undefined && { is_active }),
    ...(sort_order !== undefined && { sort_order }),
    ...(max_videos !== undefined && { max_videos: Math.max(parseInt(max_videos) || 12, 1) }),
  });
  res.json(ch);
}

async function adminDeleteChannel(req, res) {
  const ch = await ListeningChannel.findByPk(req.params.id);
  if (!ch) return res.status(404).json({ error: 'Not found' });
  await ch.destroy();
  res.json({ ok: true });
}

async function adminRefreshChannel(req, res) {
  const ch = await ListeningChannel.findByPk(req.params.id);
  if (!ch) return res.status(404).json({ error: 'Not found' });
  await refreshChannelCache(ch);
  await ch.reload();
  res.json(ch);
}

async function listUserChannels(req, res) {
  const channels = await ListeningChannel.findAll({
    where: {
      owner_user_id: req.user.id,
      is_public: false,
    },
    order: [['createdAt', 'DESC']],
  });
  res.json({ data: channels.map(formatChannel) });
}

async function createUserChannel(req, res) {
  const { channel_url, name, description, max_videos } = req.body || {};
  if (!channel_url) return res.status(400).json({ error: '请输入频道链接' });

  const parsed = parseChannelUrl(channel_url);
  if (!parsed) {
    return res.status(400).json({ error: '无法识别的链接，请输入 YouTube 频道、Bilibili 空间或 Bilibili 视频 URL' });
  }

  let channelId = parsed.channelId || (parsed.handle ? `@${parsed.handle}` : null);
  if (!channelId) return res.status(400).json({ error: '无法提取频道 ID' });

  // Try to resolve YouTube @handle → UC channel ID upfront
  if (parsed.platform === 'youtube' && channelId.startsWith('@')) {
    const resolved = await resolveYouTubeHandle(channelId);
    if (resolved) {
      channelId = resolved;
    }
    // If resolution fails, still save with @handle — will retry on cache refresh
  }

  const duplicated = await ListeningChannel.findOne({
    where: {
      owner_user_id: req.user.id,
      is_public: false,
      platform: parsed.platform,
      channel_id: channelId,
    },
  });
  if (duplicated) {
    return res.status(400).json({ error: '该频道已在你的列表中' });
  }

  const ch = await ListeningChannel.create({
    owner_user_id: req.user.id,
    is_public: false,
    platform: parsed.platform,
    channel_url,
    channel_id: channelId,
    name: name || '我的频道',
    description: description || '',
    max_videos: max_videos ? Math.max(parseInt(max_videos) || 12, 1) : 12,
    is_active: true,
    sort_order: 0,
  });

  await refreshChannelCache(ch);
  await ch.reload();
  res.status(201).json(formatChannel(ch));
}

async function deleteUserChannel(req, res) {
  const ch = await ListeningChannel.findOne({
    where: {
      id: req.params.id,
      owner_user_id: req.user.id,
      is_public: false,
    },
  });
  if (!ch) return res.status(404).json({ error: '频道不存在或无权限删除' });

  await ch.destroy();
  res.json({ ok: true });
}

module.exports = {
  listChannels, getChannelVideos,
  listUserChannels, createUserChannel, deleteUserChannel,
  adminListChannels, adminCreateChannel, adminUpdateChannel, adminDeleteChannel, adminRefreshChannel,
  parseChannelUrl, refreshChannelCache,
};
