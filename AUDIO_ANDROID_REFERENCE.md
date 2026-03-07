# Android 音频播放问题快速查找表

## 快速导航

| 症状 | 原因 | 解决方案 | 文件 |
|------|------|---------|------|
| **应用无法播放音频** | 缺少 WRITE_EXTERNAL_STORAGE 权限 + 未检查权限 | 见问题 #1, #2, #3 | AndroidManifest.xml, permission_service.dart |
| **TTS/朗读无声音** | 缺少 RECORD_AUDIO 权限声明 + 未检查权限 | 见问题 #1, #4 | AndroidManifest.xml, vocabulary_detail_screen.dart |
| **音量按钮无效** | AudioSession 未初始化 + 音量未显式设置 | 见问题 #5, #6 | audio_player_widget.dart |
| **Android 11+ 应用崩溃** | 所有权限问题 | 见问题 #1-#4 | 所有文件 |
| **权限被拒绝时应用崩溃** | 缺少运行时权限检查 | 见问题 #2, #3, #7 | main.dart, permission_service.dart |
| **错误提示不清楚** | 没有具体的权限错误消息 | 见问题 #7, #9 | audio_player_widget.dart |

---

## 问题编号速查

### 🔴 关键问题

**#1 AndroidManifest.xml 缺权限**
- 症状: Android 11+ 无法读写文件
- 修复文件: `mobile/android/app/src/main/AndroidManifest.xml`
- 修复内容: 添加 WRITE_EXTERNAL_STORAGE, READ_EXTERNAL_STORAGE, MODIFY_AUDIO_SETTINGS
- 时间: 5分钟
- 参考: AUDIO_ANDROID_QUICK_FIX.md 步骤 1

**#2 缺少运行时权限请求**
- 症状: Android 6.0+ 权限被拒绝导致功能崩溃
- 修复文件: `mobile/lib/main.dart`, `mobile/lib/services/permission_service.dart` (新建)
- 修复内容: 创建权限服务 + 在 main() 中初始化权限
- 时间: 30分钟
- 参考: AUDIO_ANDROID_QUICK_FIX.md 步骤 2, 3

**#3 文件写入权限未检查**
- 症状: 权限被拒绝时文件写入失败
- 修复文件: `mobile/lib/services/api_service.dart` (downloadToTempFile 方法)
- 修复内容: 添加权限检查和文件操作错误处理
- 时间: 15分钟
- 参考: AUDIO_ANDROID_QUICK_FIX.md 步骤 6

**#4 TTS 未检查麦克风权限**
- 症状: TTS 可能因缺少麦克风权限而失败
- 修复文件: `mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart` (_speak 方法)
- 修复内容: 在调用 TTS 前检查麦克风权限
- 时间: 10分钟
- 参考: AUDIO_ANDROID_QUICK_FIX.md 步骤 5

### 🟡 中等问题

**#5 AudioSession 未初始化**
- 症状: 音量按钮无效，音频焦点无法处理
- 修复文件: `mobile/lib/widgets/audio_player_widget.dart` (initState)
- 修复内容: 初始化 AudioSession
- 时间: 10分钟
- 参考: AUDIO_ANDROID_QUICK_FIX.md 步骤 4

**#6 音量未显式设置**
- 症状: 播放音量可能过小或不一致
- 修复文件: `mobile/lib/widgets/audio_player_widget.dart` (initState)
- 修复内容: 调用 _player.setVolume(1.0)
- 时间: 5分钟
- 参考: AUDIO_ANDROID_QUICK_FIX.md 步骤 4

**#7 音频播放前权限检查缺失**
- 症状: 权限拒绝时无清晰错误提示
- 修复文件: `mobile/lib/widgets/audio_player_widget.dart` (_togglePlay 方法)
- 修复内容: 在播放前检查存储权限
- 时间: 5分钟
- 参考: AUDIO_ANDROID_QUICK_FIX.md 步骤 4

### 🟠 低优先级问题

**#8 SSL 证书验证警告不够明确**
- 修复文件: `mobile/lib/services/api_service.dart` (HttpClientAdapter)
- 参考: AUDIO_ANDROID_AUDIT.md 第 7 点

**#9 TTS 错误提示不够详细**
- 修复文件: `mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart` (_speak 方法)
- 参考: AUDIO_ANDROID_AUDIT.md 第 8 点

**#10 缺少缓存文件有效性验证**
- 修复文件: `mobile/lib/services/api_service.dart` (downloadToTempFile 方法)
- 参考: AUDIO_ANDROID_AUDIT.md 第 5 点

---

## 修复文件位置速查

### 需要修改的文件 (5 个)

```
mobile/android/app/src/main/AndroidManifest.xml
├─ 添加 WRITE_EXTERNAL_STORAGE
├─ 添加 READ_EXTERNAL_STORAGE
└─ 添加 MODIFY_AUDIO_SETTINGS

mobile/lib/main.dart
├─ 导入 permission_handler
└─ 添加 _requestInitialPermissions()

mobile/lib/widgets/audio_player_widget.dart
├─ 导入 audio_session
├─ 导入 permission_handler
├─ 添加 _initAudioSession() 方法
├─ 在 initState 中调用 _initAudioSession()
├─ 在 initState 中设置 _player.setVolume(1.0)
└─ 在 _togglePlay 中检查存储权限

mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart
├─ 导入 permission_handler
└─ 在 _speak() 中检查麦克风权限

mobile/lib/services/api_service.dart
└─ 改进 downloadToTempFile 方法的错误处理
```

### 需要新建的文件 (1 个)

```
mobile/lib/services/permission_service.dart
├─ 类: PermissionService
├─ 方法: requestMicrophonePermission()
├─ 方法: requestStoragePermission()
├─ 方法: _handlePermissionStatus()
└─ 方法: _showDialog()
```

---

## 依赖项检查

```yaml
# mobile/pubspec.yaml 中已有的相关库
✅ permission_handler: ^11.3.0    # 权限管理（已有）
✅ just_audio: ^0.9.36            # 音频播放（已有）
✅ audio_session: ^0.18.12        # AudioSession（已有，未使用）
✅ flutter_tts: ^4.0.2            # TTS（已有）

# 无需添加新依赖！所有必要库都已在 pubspec.yaml 中
```

---

## 修复优先级路径

### 路径 A: 快速修复 (3.5 小时)
推荐用于立即解决 Android 11+ 兼容性问题

```
1. 修改 AndroidManifest.xml (+权限)
   ↓ (5 分钟)
2. 创建 permission_service.dart
   ↓ (15 分钟)
3. 修改 main.dart (+权限初始化)
   ↓ (10 分钟)
4. 修改 audio_player_widget.dart (+AudioSession)
   ↓ (25分钟)
5. 修改 vocabulary_detail_screen.dart (+权限检查)
   ↓ (10 分钟)
6. 改进 api_service.dart (+错误处理)
   ↓ (15 分钟)
7. 本地测试和验证
   ↓ (30 分钟)
8. 提交代码
```

### 路径 B: 分阶段修复
推荐用于需要更稳健评估的情况

```
第 1 天:
- 修复关键问题 #1-4 (1.5 小时)
- 本地编译验证
- 跑单元测试（如有）

第 2 天:
- 修复中等问题 #5-7 (0.5 小时)
- 真机测试多个 Android 版本 (2 小时)
- 修复测试发现的问题

第 3 天:
- 修复低优先级 #8-10 (0.5 小时)
- 最终集成测试
- 代码审查和合并
```

---

## 测试场景速查

| 场景 | 流程 | 预期结果 | 检查列表 |
|------|------|---------|---------|
| **首次启动** | 重装 APK + 启动 | 显示权限请求对话框 | ☐ 启动时请求 ☐ 对话框可用 |
| **播放音频** | 词汇列表 → 点播放 | 播放声音，显示进度 | ☐ 播放 ☐ 进度条 ☐ 音量有效 |
| **朗读单词** | 词汇详情 → 点朗读 | 朗读正常 | ☐ 网络检查 ☐ TTS 引擎检查 |
| **拒绝权限** | 选择"拒绝" | 显示错误提示 | ☐ 错误消息清晰 ☐ 有打开设置按钮 |
| **弱网下载** | 限速 100KB/s | 启动重试机制 | ☐ 重试 3 次 ☐ 最终成功或超时 |
| **权限撤销** | 系统设置撤销权限 | 下次操作时请求重新授权 | ☐ 检测撤销 ☐ 重新请求 |

---

## 常见错误和对策

| 错误信息 | 原因 | 解决方案 | 相关问题 |
|---------|------|---------|---------|
| `FileSystemException: Cannot open file` | 写权限被拒绝 | 检查 WRITE_EXTERNAL_STORAGE 权限 | #1, #3 |
| `Permission Denied` | 运行时权限拒绝 | 调用 permissionService.requestStoragePermission() | #2, #3, #7 |
| `Microphone permission denied` | 麦克风权限被拒绝 | 调用 permissionService.requestMicrophonePermission() | #2, #4 |
| `Sound is null` | 音量未设置或 AudioSession 未初始化 | 调用 _player.setVolume(1.0) + _initAudioSession() | #5, #6 |
| `Certificate verification failed` | SSL 证书问题 | 已在 api_service.dart 中处理 | #8 |
| `TTS engine not available` | TTS 引擎未安装或权限不足 | 检查系统设置中的 TTS 引擎配置 | #4, #9 |

---

## 代码段速查

### 权限请求代码
```dart
// 在 permission_service.dart 中
final permissionService = PermissionService();

// 在需要权限的地方使用
if (!await permissionService.requestStoragePermission(context)) {
  // 处理权限被拒绝
  setState(() {
    _hasError = true;
    _errorMessage = '需要存储权限';
  });
  return;
}
```

### AudioSession 初始化
```dart
Future<void> _initAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(
    AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
    ),
  );
}
```

### 权限检查 (一行)
```dart
if (!(await Permission.microphone.isGranted)) {
  // 检查状态
}
```

---

## 性能影响分析

| 修改 | 对性能的影响 | 内存增加 | 启动时间增加 |
|------|------------|----------|-------------|
| 权限请求 | 无 (异步) | <1MB | <100ms |
| AudioSession 初始化 | 无（一次性） | <1MB | <50ms |
| 权限检查 (播放时) | 无（检查）| 0 | <10ms |
| 错误处理添加 | 无（条件分支） | <0.5MB | 0 |
| **总体** | **无显著影响** | **<2MB** | **<200ms** |

---

## 发布检查清单

在发布新版本前，验证以下内容:

```
权限:
☐ AndroidManifest.xml 已更新所有 4 个权限
☐ permission_service.dart 已创建并导入
☐ main.dart 中权限初始化代码已添加
☐ 所有权限请求都有对应错误处理

功能:
☐ 音频播放工作正常
☐ TTS 朗读工作正常
☐ 音量按钮有效
☐ 音频焦点处理正确（手机铃声中断后恢复）

测试:
☐ Android 6.0 测试通过
☐ Android 10 测试通过
☐ Android 12 测试通过
☐ 权限拒绝场景测试通过
☐ 弱网环境测试通过

代码质量:
☐ 编译无错误
☐ 编译无警告
☐ 代码风格一致
☐ 注释清晰
☐ 代码审查已通过

文档:
☐ 更新了 CHANGELOG
☐ 更新了 README（如涉及）
☐ 生成了发布说明
```

---

**最后更新**: 2026-03-07  
**文档版本**: 1.0  
**相关文档**: AUDIO_ANDROID_AUDIT.md, AUDIO_ANDROID_QUICK_FIX.md, AUDIO_ANDROID_CHECKLIST.md
