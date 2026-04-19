/**
 * 音频本地化服务
 * 功能：
 * 1. 从Kokoro TTS服务下载生成的音频文件
 * 2. 按功能模块保存到不同的本地磁盘目录
 * 3. 支持批量下载和错误重试
 * 4. 返回可用的本地路径
 * 
 * 路径规划（按功能模块分离）：
 * - 语法例句: /uploads/grammar/audio/  (现有)
 * - 单词和例句: /uploads/audio/vocab/   (新)
 * - 五十音音频: /uploads/audio/kana/    (新)
 */

const fs = require('fs').promises;
const path = require('path');
const axios = require('axios');

// 路径配置（按功能模块）
const AUDIO_PATHS = {
  grammar: path.join(process.cwd(), 'uploads', 'grammar', 'audio'),
  vocabulary: path.join(process.cwd(), 'uploads', 'audio', 'vocab'),
  kana: path.join(process.cwd(), 'uploads', 'audio', 'kana')
};

// URL路径前缀
const AUDIO_URL_PREFIXES = {
  grammar: '/uploads/grammar/audio',
  vocabulary: '/uploads/audio/vocab',
  kana: '/uploads/audio/kana'
};

const DOWNLOAD_TIMEOUT = 30000; // 30秒超时
const MAX_RETRIES = 3; // 最多重试3次

/**
 * 确保音频存储目录存在
 * @param {string} type - 音频类型: 'grammar' | 'vocabulary' | 'kana'
 */
async function ensureAudioDirectories(type = null) {
  try {
    const pathsToCreate = type
      ? [AUDIO_PATHS[type]]
      : Object.values(AUDIO_PATHS);

    for (const dirPath of pathsToCreate) {
      if (!dirPath) continue;
      await fs.mkdir(dirPath, { recursive: true });
      console.log(`[Audio] 已准备音频目录: ${dirPath}`);
    }
    return true;
  } catch (err) {
    console.error(`[Audio] 创建音频目录失败: ${err.message}`);
    return false;
  }
}

/**
 * 从URL下载文件并保存到本地
 * @param {string} kokoroUrl - Kokoro生成的音频URL
 * @param {string} type - 音频类型: 'grammar' | 'vocabulary' | 'kana'
 * @param {number} retryCount - 当前重试次数
 * @returns {Promise<{success: boolean, originalUrl: string, localPath?: string, error?: string}>}
 */
async function downloadAndLocalizeAudio(kokoroUrl, type = 'vocabulary', retryCount = 0) {
  if (!kokoroUrl || !AUDIO_PATHS[type]) {
    return { success: false, originalUrl: kokoroUrl, error: `URL为空或类型无效: ${type}` };
  }

  const filename = extractFilenameFromUrl(kokoroUrl);
  if (!filename) {
    return { success: false, originalUrl: kokoroUrl, error: '无法从URL提取文件名' };
  }

  const audioDir = AUDIO_PATHS[type];
  const localPath = path.join(audioDir, filename);

  try {
    // 检查文件是否已存在
    try {
      await fs.access(localPath);
      console.log(`[Audio] 文件已存在 [${type}]: ${filename}`);
      return {
        success: true,
        originalUrl: kokoroUrl,
        localPath: `${AUDIO_URL_PREFIXES[type]}/${filename}`
      };
    } catch {
      // 文件不存在，继续下载
    }

    // 如果是相对路径，拼接Kokoro服务地址
    let downloadUrl = kokoroUrl;
    if (!kokoroUrl.startsWith('http')) {
      const KOKORO_SERVICE_URL = process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010';
      downloadUrl = KOKORO_SERVICE_URL + kokoroUrl;
    }

    console.log(`[Audio] 下载音频 [${type}]: ${downloadUrl}`);

    // 下载文件
    const response = await axios.get(downloadUrl, {
      responseType: 'arraybuffer',
      timeout: DOWNLOAD_TIMEOUT,
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; JapaneseLearning/1.0)'
      }
    });

    // 保存到本地
    await fs.writeFile(localPath, response.data);
    console.log(`[Audio] ✓ 已保存 [${type}]: ${filename} (${(response.data.length / 1024).toFixed(2)}KB)`);

    return {
      success: true,
      originalUrl: kokoroUrl,
      localPath: `${AUDIO_URL_PREFIXES[type]}/${filename}`
    };
  } catch (err) {
    console.error(`[Audio] 下载失败 [${type}/${filename}]: ${err.message}`);

    // 重试逻辑
    if (retryCount < MAX_RETRIES) {
      const delayMs = (retryCount + 1) * 1000; // 1s, 2s, 3s递增延迟
      console.log(`[Audio] 将在${delayMs}ms后重试...`);
      await new Promise(r => setTimeout(r, delayMs));
      return downloadAndLocalizeAudio(kokoroUrl, type, retryCount + 1);
    }

    return {
      success: false,
      originalUrl: kokoroUrl,
      error: err.message
    };
  }
}

/**
 * 批param {string} type - 音频类型: 'grammar' | 'vocabulary' | 'kana'
 * @returns {Promise<Array>} 包含下载结果的数组
 */
async function batchDownloadAndLocalize(kokoroUrls, type = 'vocabulary') {
  if (!Array.isArray(kokoroUrls) || kokoroUrls.length === 0) {
    return [];
  }

  // 确保目标目录存在
  await ensureAudioDirectories(type);

  console.log(`[Audio] 批量下载 ${kokoroUrls.length} 个音频文件 [${type}]...`);

  // 并发下载，限制并发数为5
  const results = [];
  const batchSize = 5;

  for (let i = 0; i < kokoroUrls.length; i += batchSize) {
    const batch = kokoroUrls.slice(i, i + batchSize);
    const batchResults = await Promise.all(
      batch.map(url => downloadAndLocalizeAudio(url, type))
    );
    results.push(...batchResults);
  }

  const successCount = results.filter(r => r.success).length;
  console.log(`[Audio] 批量下载完成 [${type}]: ${successCount}/${kokoroUrls.length} 成功`);

  return results;
}

/**
 * 删除本地Kokoro音频文件
 * @param {string} type - 音频类型: 'grammar' | 'vocabulary' | 'kana'
 * @returns {Promise<boolean>}
 */
async function deleteLocalKokoroAudio(filename, type = 'vocabulary') {
  if (!filename || !AUDIO_PATHS[type]) return false;

  // 防止路径遍历攻击
  if (filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
    console.warn(`[Audio] 拒绝删除可疑文件: ${filename}`);
    return false;
  }

  const audioDir = AUDIO_PATHS[type];
  const filePath = path.join(audioDir, filename);

  try {
    // 验证文件在指定目录内
    const resolvedPath = path.resolve(filePath);
    const resolvedBase = path.resolve(audioDir);
    if (!resolvedPath.startsWith(resolvedBase)) {
      console.warn(`[Audio] 拒绝删除目录外的文件: ${filename}`);
      return false;
    }

    await fs.unlink(filePath);
    console.log(`[Audio] ✓ 已删除 [${type}]: ${filename}`);
    return true;
  } catch (err) {
    console.error(`[Audio] 删除失败 [${type}/${filename}]: ${err.message}`);
    return false;
  }
}

/**
 * 获取指定文件大小
 * @param {string} filename - 文件名
 * @param {string} type - 音频类型: 'grammar' | 'vocabulary' | 'kana'
 * @returns {Promise<number>} 文件大小（字节）
 */
async function getAudioFileSize(filename, type = 'vocabulary') {
  if (!filename || !AUDIO_PATHS[type]) return 0;

  const filePath = path.join(AUDIO_PATHS[type], filename);

  try {
    const stats = await fs.stat(filePath);
    return stats.size;
  } catch {
    return 0;
  }
}

/**
 * 获取指定类型目录总大小
 * @param {string} type - 音频类型: 'grammar' | 'vocabulary' | 'kana' | null (全部)
 * @returns {Promise<number>} 总大小（字节）
 */
async function getTotalStorageSize(type = null) {
  try {
    const pathsToCheck = type
      ? [AUDIO_PATHS[type]]
      : Object.values(AUDIO_PATHS);

    let totalSize = 0;

    for (const dirPath of pathsToCheck) {
      if (!dirPath) continue;
      try {
        const files = await fs.readdir(dirPath);
        for (const file of files) {
          const audioType = Object.keys(AUDIO_PATHS).find(k => AUDIO_PATHS[k] === dirPath);
          const size = await getAudioFileSize(file, audioType);
          totalSize += size;
        }
      } catch {
        // 目录不存在，继续
      }
    }

    return totalSize;
  } catch (err) {
    console.error(`[Audio] 计算存储大小失败: ${err.message}`);
    return 0;
  }
}

/**
 * 从URL提取文件名
 * @param {string} url - 完整URL
 * @returns {string} 文件名
 */
function extractFilenameFromUrl(url) {
  if (!url) return '';
  try {
    // 先尝试从路径直接提取文件名（支持相对路径和完整URL）
    let pathname = url;
    try {
      const urlObj = new URL(url);
      pathname = urlObj.pathname;
    } catch {
      // 相对路径，直接用 basename
    }
    let filename = path.basename(pathname);

    // 去掉查询参数
    if (filename.includes('?')) {
      filename = filename.split('?')[0];
    }

    // 如果没有后缀，添加.mp3（默认格式）
    if (!filename.includes('.')) {
      filename = filename + '.mp3';
    }

    return filename;
  } catch {
    return '';
  }
}

/**
 * 清理指定年龄以上的文件
 * @param {string} type - 音频类型: 'grammar' | 'vocabulary' | 'kana' | null (全部)
 * @param {number} maxAgeMs - 最大年龄（毫秒）
 * @returns {Promise<number>} 已删除的文件数
 */
/**
 * 清理指定年龄以上的文件
 * @param {string} type - 音频类型: 'grammar' | 'vocabulary' | 'kana' | null (全部)
 * @param {number} maxAgeMs - 最大年龄（毫秒）
 * @returns {Promise<number>} 已删除的文件数
 */
async function cleanupOldFiles(type = null, maxAgeMs = 30 * 24 * 60 * 60 * 1000) {
  try {
    const pathsToClean = type
      ? [AUDIO_PATHS[type]]
      : Object.values(AUDIO_PATHS);

    let deletedCount = 0;
    const now = Date.now();

    for (const dirPath of pathsToClean) {
      if (!dirPath) continue;
      try {
        const files = await fs.readdir(dirPath);

        for (const file of files) {
          const filePath = path.join(dirPath, file);
          const stats = await fs.stat(filePath);
          const fileAge = now - stats.mtimeMs;

          if (fileAge > maxAgeMs) {
            await fs.unlink(filePath);
            deletedCount++;
            console.log(`[Audio] 清理过期文件: ${file}`);
          }
        }
      } catch {
        // 目录不存在或访问失败，继续
      }
    }

    return deletedCount;
  } catch (err) {
    console.error(`[Audio] 清理过期文件失败: ${err.message}`);
    return 0;
  }
}

module.exports = {
  ensureAudioDirectories,
  downloadAndLocalizeAudio,
  batchDownloadAndLocalize,
  deleteLocalKokoroAudio,
  getAudioFileSize,
  getTotalStorageSize,
  extractFilenameFromUrl,
  cleanupOldFiles
};
