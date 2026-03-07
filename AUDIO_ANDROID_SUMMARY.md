# Android 音频播放审计 - 执行摘要

**审计日期**: 2026-03-07  
**应用**: Flutter Japanese Learning App (言旅 Kotabi)  
**检查范围**: Android 音频播放和 TTS 权限、配置、错误处理

---

## 🎯 审计结果: 发现 10 个问题

| 等级 | 问题数 | 严重性 | 修复优先级 |
|------|--------|--------|-----------|
| 🔴 关键 | 4 | **应用于 Android 11+ 无法工作** | 今日修复 |
| 🟡 中等 | 3 | **功能不完整（无音量控制等）** | 今日修复 |
| 🟠 低 | 3 | **用户体验改进** | 可延后 |

---

## 🔴 4 个关键问题详解

### 问题 1: 缺少 4 个 Android 权限声明
**位置**: `mobile/android/app/src/main/AndroidManifest.xml`

**缺失的权限**:
```xml
✅ 已有:
- android.permission.INTERNET
- android.permission.ACCESS_NETWORK_STATE  
- android.permission.RECORD_AUDIO

❌ 缺失:
- android.permission.WRITE_EXTERNAL_STORAGE
- android.permission.READ_EXTERNAL_STORAGE
- android.permission.MODIFY_AUDIO_SETTINGS
```

**影响**: 
- Android 11+: 应用无法读写音频文件
- 音量按钮不可用

**修复**: 5分钟 - 添加 3 行权限声明

---

### 问题 2: 运行时权限请求完全缺失
**位置**: `mobile/lib/main.dart` (无权限初始化)

**现状**:
```dart
// ❌ 现有代码直接启动应用，无权限请求
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  apiService.init();  // 没有权限检查
  runApp(...);
}
```

**问题**:
- Android 6.0+ 需要在运行时请求权限
- 当前代码完全缺少权限请求逻辑
- 权限被拒绝时应用会崩溃

**影响**: 
- Android 6+: 第一次启动时权限被拒绝导致功能崩溃
- 用户无法理解为什么无法播放音频

**修复**: 30分钟 - 创建 permission_service.dart + 初始化权限

---

### 问题 3: 文件操作未检查权限
**位置**: `mobile/lib/services/api_service.dart` (L164-200)

**代码问题**:
```dart
Future<String> downloadToTempFile(String url) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  
  // ❌ 直接写入，未检查权限
  await _dio.download(url, file.path);
  return file.path;
}
```

**可能的错误**:
```
FileSystemException: Cannot open file, path = '...'
PermissionDenied: Operation not permitted
```

**影响**:
- 权限被拒绝时应用崩溃
- 无有意义的错误提示

**修复**: 15分钟 - 添加权限检查和文件操作错误处理

---

### 问题 4: TTS 未检查麦克风权限
**位置**: `mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart` (L85-140)

**代码问题**:
```dart
Future<void> _speak() async {
  // ❌ 直接调用TTS，未检查麦克风权限
  final result = await _tts.speak(text);
}
```

**影响**:
- 某些 Android 版本上 TTS 失败
- 用户无法朗读单词

**修复**: 10分钟 - 添加麦克风权限检查

---

## 🟡 3 个中等问题

### 问题 5-6: 音频播放器配置不完整
**位置**: `mobile/lib/widgets/audio_player_widget.dart`

**缺失**:
```dart
// ❌ 没有配置 AudioSession（处理音量和焦点）
_player = AudioPlayer();

// ❌ 没有设置音量
_player.setVolume(1.0);
```

**影响**:
- 音量按钮不工作
- 其他应用声音打断无法恢复焦点

**修复**: 15分钟

---

### 问题 7: 音频播放前权限检查缺失
**位置**: `mobile/lib/widgets/audio_player_widget.dart` (_togglePlay 方法)

**缺失**:
```dart
Future<void> _togglePlay() async {
  // ❌ 直接播放，未检查存储权限
  await _player.setFilePath(localPath);
}
```

**影响**:
- 权限被拒绝时无清晰错误提示

**修复**: 5分钟

---

## 📦 完整修复方案

### 新增文件 (1个)
```
mobile/lib/services/permission_service.dart
- 管理所有权限请求
- 显示权限错误对话框
- 打开系统设置
```

### 修改的文件 (5个)

```
1. mobile/android/app/src/main/AndroidManifest.xml
   变更: +3 行权限声明

2. mobile/lib/main.dart
   变更: +15 行权限初始化代码

3. mobile/lib/widgets/audio_player_widget.dart
   变更: +100 行 (AudioSession 初始化 + 权限检查)

4. mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart
   变更: +10 行 (麦克风权限检查)

5. mobile/lib/services/api_service.dart
   变更: +50 行 (文件操作错误处理)
```

### 总代码变化
- 新增代码: ~235 行
- 修改代码: ~175 行  
- 文件数: 6 个

---

## ✅ 修复验收标准

| 检查项 | 当前 | 目标 |
|--------|------|------|
| 权限声明完整性 | ❌ 缺 3 个 | ✅ 全部正确 |
| 运行时权限请求 | ❌ 无 | ✅ 自动请求 |
| 权限检查点 | ❌ 0 个 | ✅ 7 个 |
| 音量控制 | ❌ 不工作 | ✅ 正常 |
| 错误提示具体性 | ⚠️ 通用 | ✅ 具体故障原因 |
| Android 11+ 兼容性 | ❌ 无法工作 | ✅ 完全支持 |

---

## 🧪 测试覆盖

修复必须通过以下测试:

```
✓ 首次启动时显示权限请求对话框
✓ Android 6.0 上正常播放音频
✓ Android 10 上正常播放音频
✓ Android 12 上正常播放音频
✓ 拒绝权限后显示清晰错误提示
✓ 有"打开设置"按钮并能正常打开
✓ 音量按钮有效
✓ TTS 工作正常
✓ 弱网环境下音频能重试
✓ 缓存能正确命中
```

---

## 📊 工作量估算

| 阶段 | 任务 | 预计时间 |
|------|------|---------|
| Phase 1 | 权限基础设施 (权限清单+service+main.dart) | 1 小时 |
| Phase 2 | 模块权限检查 (播放器+词汇详情+API) | 1 小时 |
| Phase 3 | 验收测试 (多版本 + 权限拒绝 + 弱网) | 1.5 小时 |
| **总计** | | **3.5 小时** |

---

## 📚 生成的文档

本审计生成了 3 份详细文件:

1. **AUDIO_ANDROID_AUDIT.md** (完整审计报告)
   - 详细的问题分析
   - 代码示例和修复方案
   - 安全建议

2. **AUDIO_ANDROID_QUICK_FIX.md** (快速修复指南)
   - 分步骤的修复说明
   - 可复制粘贴的代码
   - 验证步骤

3. **AUDIO_ANDROID_CHECKLIST.md** (检查清单)
   - 按优先级排列的问题清单
   - 测试场景和验收标准
   - FAQ 和参考资源

---

## 🚦 建议的行动计划

### 立即 (今天)
- [ ] 阅读 AUDIT 报告理解问题
- [ ] 按照 QUICK_FIX 指南进行修复
- [ ] 本地编译验证

### 短期 (明天)
- [ ] 在多个 Android 版本上测试
- [ ] 验证所有功能

### 中期 (本周)
- [ ] 提交代码进行 Code Review
- [ ] 构建并发布新版本

---

## 💡 关键洞察

1. **权限是关键**: 四个关键问题中三个都是权限相关。无适当权限，应用在 Android 11+ 上无法工作。

2. **缺少架构**: 应用完全缺少权限管理架构。需要创建 permission_service.dart 为中心化管理。

3. **老库未充分利用**: pubspec.yaml 中已有 audio_session 库，但从未被使用。许多问题可通过正确配置现有库解决。

4. **用户体验**: 当前错误提示过于通用。修复应提供具体的故障原因和解决方案。

5. **Android 11+ 必须**: Scoped Storage 和更严格的权限模型决定了修复的紧迫性。

---

## 📞 后续问题?

详细的代码修复和测试步骤请见以下文件:
- 代码示例: AUDIO_ANDROID_QUICK_FIX.md
- 完整分析: AUDIO_ANDROID_AUDIT.md
- 验收标准: AUDIO_ANDROID_CHECKLIST.md

**审计完成**: ✅  
**建议**: 🔴 立即实施修复 (影响 Android 11+ 用户)
