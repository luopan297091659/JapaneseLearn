# Android 音频问题检查清单和修复优先级

## 📋 问题清单（按优先级排序）

### 🔴 关键问题 (MUST FIX)

```
□ [1] AndroidManifest.xml 缺少权限声明
  位置: mobile/android/app/src/main/AndroidManifest.xml
  缺失: WRITE_EXTERNAL_STORAGE, READ_EXTERNAL_STORAGE, MODIFY_AUDIO_SETTINGS
  严重性: 🔴 应用无法在 Android 11+ 上正常工作
  修复时间: 5 分钟
  文件行数: 需要在 </manifest> 前添加 3 行代码

□ [2] 运行时权限请求机制完全缺失
  位置: mobile/lib/main.dart, mobile/lib/services/
  现状: 没有权限初始化代码
  严重性: 🔴 Android 6.0+ 上权限会被拒绝导致功能崩溃
  修复时间: 30 分钟
  需要新增: permission_service.dart (60 行代码)

□ [3] 存储权限未运行时检查
  位置: mobile/lib/services/api_service.dart (downloadToTempFile 方法)
  现状: 直接写入临时文件，未检查权限或处理异常
  严重性: 🔴 文件写入失败时导致应用崩溃
  修复时间: 15 分钟
  文件行数: L164-200 需要修改

□ [4] TTS 调用前未检查麦克风权限
  位置: mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart#_speak()
  现状: 直接调用 TTS，未请求权限
  严重性: 🔴 某些系统上 TTS 因无权限而工作异常
  修复时间: 10 分钟
  文件行数: L85-140 需要添加权限检查
```

### 🟡 中等问题 (SHOULD FIX)

```
□ [5] AudioSession 配置缺失
  位置: mobile/lib/widgets/audio_player_widget.dart#initState
  现状: 未初始化 AudioSession，导致音量控制失效
  严重性: 🟡 音量按钮无效，无音频焦点处理
  修复时间: 10 分钟
  已有库: audio_session: ^0.18.12 (在 pubspec.yaml 中)

□ [6] 音量设置缺失
  位置: mobile/lib/widgets/audio_player_widget.dart
  现状: 创建 AudioPlayer 后未设置音量
  严重性: 🟡 播放音量可能过小，用户体验不佳
  修复时间: 5 分钟
  代码行数: 1 行 (_player.setVolume(1.0);)

□ [7] 音频播放前权限检查缺失
  位置: mobile/lib/widgets/audio_player_widget.dart#_togglePlay
  现状: 直接写入临时文件，未验证存储权限
  严重性: 🟡 权限拒绝时无明确错误提示
  修复时间: 5 分钟
  代码行数: 需要在 _togglePlay 开头添加权限检查
```

### 🟠 低优先级问题 (NICE TO HAVE)

```
□ [8] SSL 证书验证警告消息未明确
  位置: mobile/lib/services/api_service.dart#L75-92
  现状: 已有基本验证，但缺少生产环境警告
  严重性: 🟠 开发环境注意事项，不影响功能
  修复时间: 5 分钟

□ [9] TTS 错误提示不够详细
  位置: mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart#_speak
  现状: TTS 失败时只显示"不可用"，无指导用户解决方案
  严重性: 🟠 用户体验，建议但非关键
  修复时间: 10 分钟

□ [10] 缺少缓存文件有效性验证
  位置: mobile/lib/services/api_service.dart (downloadToTempFile)
  现状: 检查文件存在但未验证文件大小或完整性
  严重性: 🟠 极少数情况下可能播放损坏的缓存文件
  修复时间: 10 分钟
```

---

## 🎯 修复路线图

### Phase 1: 权限基础设施 (建议今天完成)
**预计时间: 1 小时**

- [x] 理解问题
- [ ] 修改 AndroidManifest.xml (5分钟)
- [ ] 创建 permission_service.dart (15分钟)
- [ ] 更新 main.dart (10分钟)
- [ ] 测试权限请求 (15分钟)
- [ ] 验证是否有编译错误 (5分钟)

### Phase 2: 模块权限检查 (建议今天完成)
**预计时间: 1 小时**

- [ ] 更新 audio_player_widget.dart (15分钟)
- [ ] 更新 vocabulary_detail_screen.dart (10分钟)
- [ ] 改进 api_service.dart 错误处理 (15分钟)
- [ ] 本地测试 (15分钟)
- [ ] 解决编译错误 (5分钟)

### Phase 3: 验收测试 (建议明天)
**预计时间: 1.5 小时**

- [ ] 在 Android 6.0 设备/模拟器上测试
- [ ] 在 Android 10 设备/模拟器上测试
- [ ] 在 Android 12 设备/模拟器上测试
- [ ] 测试权限拒绝场景
- [ ] 弱网环境下测试音频播放
- [ ] 验证音量控制工作正常
- [ ] 验证 TTS 工作正常

---

## 📊 问题影响范围

### 受影响的功能

| 功能 | 影响程度 | 问题ID | 优先级 |
|------|---------|--------|--------|
| 音频播放 | 🔴 严重 | [1,2,3] | 关键 |
| TTS 朗读 | 🔴 严重 | [2,4] | 关键 |
| 音量控制 | 🟡 中等 | [5,6] | 中等 |
| 音频焦点 | 🟡 中等 | [5] | 中等 |
| SSL 验证 | 🟠 低 | [8] | 低 |
| 错误提示 | 🟠 低 | [7,9] | 低 |

### 受影响的 Android 版本

| 版本 | API | 问题 | 修复方案 |
|------|-----|------|---------|
| Android 5.x | 21-22 | 无运行时权限，清单权限自动生效 | ✅ 可行 |
| Android 6.0 | 23 | 开始需要运行时权限 | ⚠️ 必须修复 |
| Android 10 | 29 | 引入 Scoped Storage | ⚠️ 必须修复 |
| Android 11+ | 30+ | Scoped Storage 强制，特定权限更严格 | 🔴 **关键** |
| Android 12+ | 31+ | 增加 NEARBY_WIFI_DEVICES 等新权限 | 🔴 **关键** |

---

## 🔄 修复前后文件变化

### 新增文件
```
mobile/lib/services/permission_service.dart  (60 行)
```

### 修改文件
```
mobile/android/app/src/main/AndroidManifest.xml   (+3 行权限)
mobile/lib/main.dart                              (+15 行)
mobile/lib/widgets/audio_player_widget.dart       (+100 行)
mobile/lib/screens/vocabulary/vocabulary_detail_screen.dart (+10 行权限检查)
mobile/lib/services/api_service.dart              (+50 行错误处理)
```

### 总体影响
- 新增代码: ~235 行
- 修改行数: ~175 行
- 文件变动: 6 个文件

---

## 📝 验收标准

### 功能验收

- [ ] **权限请求**
  - 首次启动时显示权限请求对话框
  - 用户可以允许或拒绝
  - 拒绝后显示详细错误提示

- [ ] **音频播放**
  - 有存储权限时正常播放
  - 无存储权限时显示"需要存储权限"
  - 音量按钮有效
  - 音频能够暂停/恢复

- [ ] **TTS 功能**
  - 有麦克风权限时正常朗读
  - 无麦克风权限时请求权限
  - TTS 不可用时显示解决方案

- [ ] **错误处理**
  - 网络错误显示"网络连接失败"
  - 权限错误显示"需要 XXX 权限"
  - SSL 错误显示"证书验证失败"

### 代码质量标准

- [ ] 代码编译无错误
- [ ] 代码编译无警告
- [ ] 所有权限检查都有对应的错误提示
- [ ] 没有硬编码的权限键名称
- [ ] 代码注释清晰

---

## 🧪 测试场景

### 场景 1: 首次启动 (Android 6.0+)
```
步骤:
1. 清除应用数据并删除应用
2. 重新安装 APK
3. 启动应用

预期:
- 显示"允许麦克风和存储权限"对话框
- 用户允许后应用正常启动
- 用户拒绝后显示错误提示
```

### 场景 2: 播放音频
```
步骤:
1. 打开词汇详情页面
2. 点击播放按钮

预期:
- 如果有权限: 正常播放，显示进度条
- 如果无权限: 显示"需要存储权限"错误
- 音量按钮可调节音量
```

### 场景 3: 朗读单词
```
步骤:
1. 打开词汇详情页面
2. 点击朗读按钮

预期:
- 首次: 请求麦克风权限
- 有权限: 朗读工作正常
- 无权限: 显示"需要麦克风权限"
- 无 TTS 引擎: 显示解决方案
```

### 场景 4: 权限拒绝后
```
步骤:
1. 拒绝权限
2. 尝试播放音频或朗读

预期:
- 显示清晰的错误提示
- 有"打开设置"按钮
- 用户可以点击打开系统设置
```

### 场景 5: 弱网环境
```
步骤:
1. 使用 Android Studio 模拟器限速到 100KB/s
2. 播放音频

预期:
- 启动重试机制 (3 次 × 指数退避)
- 显示进度条
- 最终播放成功或显示"网络超时"
```

---

## 📞 常见问题 (FAQ)

### Q1: 修复后会不会影响不需要权限的功能?
**A:** 不会。权限检查只在实际使用时触发。查看词汇列表等功能不受影响。

### Q2: 用户拒绝权限后还能继续使用应用吗?
**A:** 可以。只有音频播放和 TTS 功能会显示错误提示。其他功能正常。

### Q3: 需要修改 build.gradle 吗?
**A:** 不需要。已有的配置已支持所有权限。只需更新清单文件。

### Q4: 支持的最低 Android 版本是多少?
**A:** minSdk = 24 (Android 7.0)，完全支持所有权限模型。

### Q5: 修复后还需要做什么吗?
**A:** 建议在多个 Android 版本上进行完整测试，特别是 Android 6、10、12。

---

## 🔗 参考资源

- [Android Permissions 官方文档](https://developer.android.com/guide/topics/permissions/overview)
- [Runtime Permissions 实现](https://developer.android.com/training/permissions/requesting)
- [Scoped Storage 迁移指南](https://developer.android.com/training/data-storage/shared/photopicker)
- [permission_handler 插件文档](https://pub.dev/packages/permission_handler)
- [just_audio 文档](https://pub.dev/packages/just_audio)
- [flutter_tts 文档](https://pub.dev/packages/flutter_tts)

---

## 📋 检查清单使用方式

打印此清单并在修复过程中检查：

```
修复步骤:
1. ☐ 阅读并理解所有 10 个问题
2. ☐ 完成 Phase 1 (权限基础设施)
3. ☐ 完成 Phase 2 (模块权限检查)
4. ☐ 运行所有 5 个测试场景
5. ☐ 验证所有功能验收标准
6. ☐ 代码质量检查
7. ☐ 提交代码并创建发布版本
```

---

**完成度: [0%] 文档完成但修复未开始**

最后更新: 2026-03-07
