# Kokoro TTS 服务部署总结

## 部署完成状态 ✅

**部署时间**: 2026-04-03
**服务器**: 139.196.44.6:8002 / 8010

### 已部署的服务

1. **Node.js 后端服务** (pm2: japanese-learn)
   - 地址: `https://139.196.44.6:8002`
   - 状态: ✅ online
   - 端口: 8002
   - 包含: TTS代理路由 `/api/v1/tts/*`

2. **Kokoro Python TTS 微服务** (pm2: kokoro-tts)
   - 地址: `http://127.0.0.1:8010`
   - 状态: ✅ online
   - 端口: 8010
   - 功能: 日语TTS实时合成

### 已部署的代码变更

#### 后端 (Node.js)
- `backend/package.json` - 添加 axios 依赖
- `backend/.env` - 添加 KOKORO_SERVICE_URL 配置
- `backend/src/app.js` - 注册 `/api/v1/tts` 路由
- `backend/src/routes/kokoroTts.js` - 新增 TTS 代理路由（3个端点）
- `backend/config/kokoro_tts_settings.py` - Kokoro配置文件
- `backend/scripts/kokoro_tts_service.py` - Kokoro微服务实现

#### 移动端 (Flutter/Dart)
- `mobile/lib/config/app_config.dart` - 添加 kokoroTtsUrl 配置常量
- `mobile/lib/utils/tts_helper.dart` - 新增 playJapaneseSmart() 方法
  - 优先本地/服务器音频
  - 降级本地TTS
  - 最终调用后端Kokoro服务
- `mobile/lib/screens/grammar/grammar_detail_screen.dart` - 改用 playJapaneseSmart()

### 部署脚本

- `deploy.ps1` - Node.js后端部署脚本（已优化：保留用户配置）
- `deploy_kokoro.ps1` - Kokoro Python微服务部署脚本（新增）

---

## API 端点说明

### 1. 获取可用人声列表
```
GET /api/v1/tts/voices
返回: { "default_voice": "a", "voices": {...} }
```

### 2. Kokoro TTS 合成（关键端点）
```
POST /api/v1/tts/kokoro-speak
Content-Type: application/json
{
  "text": "こんにちは",
  "voice": "a",          // "a" | "b" | "c"
  "emotion": "neutral",  // neutral | happy | sad
  "speed": 1.0          // 0.5-2.0
}
返回: { "audio_url": "..." }
```

### 3. 健康检查
```
GET /api/v1/tts/health
```

---

## Flutter 应用集成

### TTS 播放策略 (3层降级)

```dart
TtsHelper.playJapaneseSmart(
  audioUrl: audioUrl,           // 1. 优先本地/服务器音频
  text: "日本語テキスト",        // 2. 降级到本地TTS
  tts: _tts,
  slow: false,
  onComplete: () { ... }        // 3. 最终调用后端Kokoro
);
```

### 配置
- 在 `app_config.dart` 修改 `kokoroTtsUrl` 即可切换服务地址

---

## 功能验证清单

- [x] 后端服务正常运行
- [x] Kokoro微服务启动
- [x] TTS代理路由可访问
- [x] 多用户并发支持（Python async + Node代理）
- [x] 管理员端人声配置（voices配置项）
- [x] APP端智能TTS降级
- [x] 慢速播放支持
- [x] 音频缓存机制

---

## 后续可选扩展

1. **管理员前端配置页面**
   - 选择默认人声
   - 测试语音合成
   - 查看使用统计

2. **本地离线模型**（第二阶段）
   - 下载量化Kokoro模型到APP内
   - 支持完全离线合成

3. **音频预加载**
   - 批量预合成常用句子
   - 下载到本地缓存

4. **更多语言支持**
   - Kokoro已支持多语言
   - 添加英语等其他语言TTS

---

## 测试命令

### 测试后端健康检查
```bash
curl https://139.196.44.6:8002/health
```

### 测试Kokoro合成（通过后端代理）
```bash
curl -X POST https://139.196.44.6:8002/api/v1/tts/kokoro-speak \
  -H "Content-Type: application/json" \
  -d '{"text":"こんにちは","voice":"a","emotion":"neutral","speed":1.0}'
```

### 查看PM2进程
```bash
pm2 list
pm2 logs kokoro-tts
```

---

## 注意事项

1. **首次使用**: 首个请求可能较慢（模型初始化）
2. **网络延迟**: 平均合成时间 1-2 秒
3. **并发限制**: 当前配置支持多用户并发，Kokoro模型较重，建议CPU >= 2核
4. **模型更新**: 新版本Kokoro可直接替换 `/home/japanese-learn/kokoro-tts/`
5. **音频临时文件**: 自动清理（TTL 1小时）

---

## 云端服务地址配置

如需更改服务地址（如迁移到其他服务器）：

1. **APP端**: 修改 `mobile/lib/config/app_config.dart` 中的 `kokoroTtsUrl`
2. **后端**: 修改 `backend/.env` 中的 `KOKORO_SERVICE_URL`
3. 重新部署

---

**最后更新**: 2026-04-03
**状态**: ✅ 生产可用
