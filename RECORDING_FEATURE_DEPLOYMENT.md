# 浏览器录音功能部署和测试指南

## 📋 部署摘要

### 已完成的工作

#### 1. 录音功能实现（admin/index.html）
添加了基于WebRTC MediaRecorder API的完整浏览器录音系统：

**核心组件：**
- `RecordingState` - 全局录音状态管理对象
- `initializeRecording(rowId, type)` - 初始化麦克风并创建MediaRecorder
- `recordExampleAudio(rowId)` - 词汇例句录音功能
- `recordGrammarExampleAudio(rowId)` - 文法例句录音功能
- `recordVocabAudio()` - 单词主音频录音功能
- `stopRecording()` - 停止录音并上传
- `cancelRecording()` - 取消录音，不上传

**UI按钮新增：**
```
词汇编辑 -> 📻单词音频: 🎤录音 | 📤上传 | 🔊试听
词汇编辑 -> 💡例句管理: 🎤录音 | 📤上传 | 🔊试听 | 🗑️删除
文法编辑 -> 📚例句管理: 🎤录音 | 📤上传 | 🔊试听 | 🗑️删除
```

**录音工作流：**
1. 用户点击🎤按钮
2. 页面底部浮现录音控制UI（显示实时录音时长）
3. 用户说出内容
4. 点击"停止" → 自动上传到 `/admin/audio/upload` 端点
5. 音频URL自动填入对应字段
6. 点击"取消" → 放弃录音，不上传

#### 2. 部署脚本改进（deploy.ps1）

**主要改动：**
- ❌ 移除了直接上传 `config/` 目录（防止覆盖用户配置）
- ✅ 添加了备份/恢复逻辑来保留用户自定义配置
- ✅ 仅上传必要的配置文件（ai_settings.json, feature_tiers.json）

**配置保留机制：**
```powershell
# 新增步骤 2.3：
1. 检查远程是否有现有配置，如果有则备份为 .backup
2. 上传本地新配置文件
3. 如果新配置不完整，恢复备份文件
```

**受影响的配置文件：**
- `ai_settings.json` - AI服务API密钥、配额设置
- `feature_tiers.json` - 功能分级、会员权限、免费限制

#### 3. 快速更新脚本

创建了 `deploy_admin_only.ps1` 用于快速部署admin UI更新，无需重新安装依赖：
```powershell
# 仅部署admin/index.html文件 (~2秒完成)
.\deploy_admin_only.ps1
```

---

## 🧪 测试指南

### 前置条件
- ✅ 后端服务已部署至 `139.196.44.6:8002`
- ✅ 管理员已登录至 `http://139.196.44.6:8002/admin/`
- ✅ 浏览器客户端已授予麦克风权限
- ✅ 网络连接正常

### 测试场景1：记录单词音频

**步骤：**
1. 进入管理员面板 → 词汇 → 选择或新建词汇（例：「食べる」）
2. 找到 **📻 单词音频** 部分
3. 点击 **🎤 录音** 按钮
4. 允许浏览器访问麦克风（首次需要授权）
5. 页面底部出现"🎤 录音中... 0:00"和控制按钮
6. 读出单词"た べ る"（约1-2秒）
7. 点击 **停止** 按钮
8. 等待上传提示："录音上传成功"
9. 验证 **单词音频** 字段显示URL: `/audio/recording-[timestamp].webm`
10. 点击 **🔊 试听** 确认音频播放正确

**预期结果：**
```
✅ 音频URL字段自动填充
✅ 音频文件成功上传到后端
✅ 试听按钮能播放录音
✅ 保存后音频URL持久化到数据库
```

### 测试场景2：记录例句音频

**步骤：**
1. 进入管理员面板 → 词汇 → 编辑词汇「大学」（大がく）
2. 找到 **💡 例句管理** 部分（如果为空，先添加例句）
3. 在某一行的 **🎤 录音** 按钮上点击
4. 允许麦克风权限
5. 读出例句"大学に行く。"
6. 点击 **停止**
7. 验证这一行的音频URL字段自动填充
8. 点击同行的 **🔊 试听** 验证录音

**预期结果：**
```
✅ 只有点击录音的那一行音频URL被填充
✅ 其他行音频URL不受影响
✅ 录音内容清晰可听
```

### 测试场景3：记录文法例句音频

**步骤：**
1. 进入管理员面板 → 文法 → 编辑文法「～でした」
2. 找到 **📚 例句管理** 部分
3. 点击例句行的 **🎤 录音** 按钮
4. 读出例句"昨日は雨でした。"
5. 点击 **停止**
6. 验证音频URL填充和播放

**预期结果：**
```
✅ 文法例句录音成功上传
✅ 与词汇录音流程一致
```

### 测试场景4：兼容性测试

| 浏览器 | 支持状态 | 测试方法 |
|--------|---------|--------|
| Chrome 87+ | ✅ 完全支持 | 运行所有测试场景 |
| Firefox 79+ | ✅ 完全支持 | 运行所有测试场景 |
| Safari 14.1+ | ⚠️ 部分支持 | 需要使用 `webkitAudioContext` |
| Edge 87+ | ✅ 完全支持 | 运行所有测试场景 |
| IE 11 | ❌ 不支持 | 显示错误提示 |

**测试命令（F12开发者工具）：**
```javascript
// 验证浏览器支持
navigator.mediaDevices && navigator.mediaDevices.getUserMedia ? "✅ 支持" : "❌ 不支持"

// 验证录音状态
console.log(RecordingState)
```

### 测试场景5：错误处理

| 场景 | 操作 | 预期行为 |
|------|------|--------|
| 拒绝麦克风权限 | 点击🎤，弹窗选"取消" | 提示"获取麦克风权限失败" |
| 网络中断 | 录音完成时网络断开 | 提示"上传失败: ..." |
| 并发录音 | 录音中再点其他🎤 | 提示"已有录音进行中，请先停止" |
| 取消录音 | 点击"取消" | 不上传，提示"已取消录音" |
| 浏览器无支持 | IE11中点击🎤 | 提示"您的浏览器不支持音频录音功能" |

---

## 🔄 向后兼容性验证

### 现有数据迁移测试

**测试：编辑已有的词汇是否仍能显示旧格式数据**

1. 编辑一个之前创建的词汇（包含旧格式的example_sentence字段）
2. 验证 **💡 例句管理** 部分是否正确加载旧数据
3. 修改例句，保存
4. 重新编辑该词汇
5. 验证数据是否已转换为新格式（example_sentences数组）

**代码逻辑：** `initializeExampleRows()` 函数
```javascript
// 新格式优先
if(v?.example_sentences && Array.isArray(v.example_sentences)) {
  v.example_sentences.forEach(ex => addExampleRow(ex.jp, ex.reading, ex.zh, ex.audio_url))
}

// 旧格式回退
if(exIndex === 0 && v?.example_sentence) {
  addExampleRow(v.example_sentence, v.example_reading, v.example_meaning_zh, v.example_audio_url)
}
```

---

## 🚀 部署流程

### 第一次完整部署（安装依赖）

```powershell
cd D:\PROJECT\JapaneseLearn
.\deploy.ps1
```

**步骤明细：**
1. ✅ 创建远程目录
2. ✅ 上传代码（src/, public/, scripts/)
3. ✅ 备份已有配置（如果存在）
4. ✅ 上传新配置文件（ai_settings.json, feature_tiers.json）
5. ✅ 修复SVG编码
6. ✅ npm install 依赖
7. ✅ pm2 启动服务

**预期输出：**
```
[1/5] 创建远程目录...
[2/5] 上传文件...
[2.3/5] 备份和恢复用户配置...
  - 已上传 ai_settings.json
  - 已上传 feature_tiers.json
[2.5/5] 修复SVG文件名编码...
[3/5] 安装依赖...
[4/5] 启动服务...
[5/5] 部署完成
  API:  http://139.196.44.6:8002/api/v1
  后台: http://139.196.44.6:8002/admin/
```

### 快速更新Admin UI（无需重装依赖）

```powershell
# 仅上传前端文件和重启pm2
.\deploy_admin_only.ps1
```

**返回输出：**
```
[1/2] 上传管理员界面...
[2/2] 重启服务...
[OK] Admin UI deployed successfully
```

### 配置保留验证

部署后，验证用户配置是否被保留：

```bash
# 在服务器端检查
ssh root@139.196.44.6
cat /home/japanese-learn/backend/config/ai_settings.json | grep api_key
cat /home/japanese-learn/backend/config/feature_tiers.json | head -20
```

**预期：** 应显示用户之前配置的值，而不是默认值

---

## 📝 故障排查

### 问题1：点击🎤无反应

**可能原因与解决方案：**

| 原因 | 解决方案 |
|------|--------|
| 浏览器不支持 | 更新浏览器到最新版；使用Chrome/Firefox/Edge |
| 麦克风被禁用 | 检查操作系统麦克风设置；浏览器权限设置 |
| HTTPS要求 | 使用HTTPS协议（如适用）；localhost可用HTTP |
| 缺少权限 | 访问 `chrome://settings/content/microphone` 授权 |

**浏览器控制台诊断（按F12）：**
```javascript
// 检查支持
navigator.mediaDevices.getUserMedia ? "✅" : "❌"

// 检查权限状态
navigator.permissions.query({name: 'microphone'}).then(r => console.log(r.state))

// 测试麦克风访问
navigator.mediaDevices.getUserMedia({audio: true})
  .then(() => console.log("✅ 麦克风可用"))
  .catch(e => console.error("❌", e.message))
```

### 问题2：上传失败 - "上传失败: ..."

**可能原因：**
- 网络不稳定
- 服务器 `/admin/audio/upload` 端点故障
- 磁盘空间满
- 权限不足

**验证服务器：**
```bash
# 检查磁盘空间
df -h /home/japanese-learn

# 检查权限
ls -la /home/japanese-learn/backend/uploads/audio/

# 检查后端日志
pm2 logs japanese-learn | tail -50
```

### 问题3：音频质量差/噪音多

**改进建议：**
1. 使用有线麦克风（比笔记本内置更好）
2. 在安静环境录制
3. 嘴离麦克风10-15cm距离
4. 说话清晰自然，避免过快或过慢

**服务器端检查录音文件：**
```bash
# 列出已上传的音频文件
ls -lah /home/japanese-learn/backend/uploads/audio/ | tail -10

# 检查文件格式
file /home/japanese-learn/backend/uploads/audio/recording-*.webm
```

---

## 📊 性能指标

| 指标 | 预期值 | 备注 |
|------|--------|------|
| 麦克风权限申请 | <1秒 | 首次需授权，后续无延迟 |
| 录音启动 | <200ms | WebRTC初始化 |
| 点击停止到上传完成 | 2-5秒 | 取决于文件大小和网络 |
| 音频文件大小 | 50-300KB | 5秒mono@48kHz WebM编码 |
| 磁盘存储成本 | 每小时~40MB | 按小时基准预估 |
| 并发录音能力 | 单用户1个 | 防止意外并发 |

---

## 📞 支持和反馈

如遇问题，请检查：
1. 浏览器控制台错误（F12 → Console）
2. 后端日志（`pm2 logs japanese-learn`）
3. 网络请求（F12 → Network → 检查upload请求）
4. 服务器磁盘空间和权限

---

## ✅ 验收清单

- [x] 录音功能代码实现
- [x] UI按钮添加
- [x] 后端audio upload端点已存在
- [x] 配置保留机制实现
- [x] 快速部署脚本创建
- [x] 向后兼容（旧数据访问）
- [x] 部署到生产服务器
- [ ] 用户完整测试（待用户验收）

---

**更新时间：2026-03-29**  
**部署版本：v1.1.0**  
**状态：Ready for Testing ✅**
