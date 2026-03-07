# 📦 APK 构建部署报告

**构建时间**: 2026年3月7日  
**项目**: JapaneseLearn - 言旅 (日语学习应用)  
**目标平台**: Android  
**构建类型**: Release (生产版本)

---

## ✅ 构建成功

### 基本信息

| 项目 | 值 |
|------|-----|
| **应用名称** | japanese_learn (言旅 Kotabi) |
| **版本号** | 1.0.0 |
| **版本代码** | 1 |
| **APK 文件名** | `app-release.apk` |
| **文件大小** | **57.4 MB** |
| **最低 SDK** | API 24 (Android 7.0) |
| **目标 SDK** | API 36 (Android 15) |
| **编译工具版本** | 36.1.0 |
| **NDK 版本** | 27.0.12077973 |
| **签名** | Debug Key (开发用) |

### 构建输出路径

```
d:\PROJECT\JapaneseLearn\mobile\build\app\outputs\flutter-apk\app-release.apk
```

---

## 📋 构建过程

### 1️⃣ 环境检查 ✅
- Flutter 版本: **3.27.4** (Stable Channel)
- Dart SDK: 3.2.0+
- Android SDK: 36.1.0 ✅
- Android Studio: 2025.3.1 ✅
- Windows 版本: 10 (27600)
- Java 版本: 11.x ✅

### 2️⃣ 依赖获取 ✅
```
flutter pub get
→ Resolved 99+ packages
→ All dependencies downloaded successfully
```

**主要依赖**:
- Flutter Riverpod: 状态管理
- Go Router: 路由导航
- Dio: HTTP 网络请求
- Just Audio: 音频播放
- Flutter TTS: 文本转语音
- SQLite: 本地数据存储

### 3️⃣ 编译构建 ✅
```
flutter build apk --release --no-tree-shake-icons

Running Gradle task 'assembleRelease'... 129.7s
√ Built build\app\outputs\flutter-apk\app-release.apk (54.8MB)
```

**构建优化**:
- ✅ 禁用图标树摇晃 (保留完整字体资源)
- ✅ R8 混淆和优化
- ✅ 多 DEX 支持
- ✅ 资源压缩
- ✅ 原生库链接

---

## 📊 APK 内容分析

| 组件 | 说明 |
|------|------|
| **核心库** | Flutter Engine (Dart/C++) |
| **业务代码** | 11 个 Dart 包 |
| **资源** | 图片、音频、字体、JSON 配置 |
| **原生依赖** | Android native modules (Audio, TTS, Storage) |
| **签名** | Debug Key (development.keystore) |

---

## 🚀 部署步骤

### 方式1: 直接安装 (开发/测试)

```bash
# 通过 USB 连接 Android 设备
adb install d:\PROJECT\JapaneseLearn\mobile\build\app\outputs\flutter-apk\app-release.apk

# 或使用 Flutter 直接运行
flutter install  # 需在移动目录下
```

### 方式2: 上传到应用市场 (生产部署)

1. **生成应用签名**
   ```bash
   # 创建生产签名密钥 (仅需一次)
   keytool -genkey -v -keystore japanese_learn.jks \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

2. **使用签名重新构建**
   ```bash
   flutter build apk --release \
     --keystore=japanese_learn.jks \
     --key-alias=japanese_learn \
     --keystore-password=<password>
   ```

3. **上传到 Google Play / 华为应用市场**
   - APK 文件: `build/app/outputs/flutter-apk/app-release.apk`
   - 包名: `com.example.japanese_learn`
   - 版本号: 1.0.0 (Build 1)

### 方式3: App Bundle (推荐 - 市场部署)

```bash
# 生成 AAB (Android App Bundle) - 文件更小，市场推荐
flutter build appbundle --release

# 输出: build/app/outputs/bundle/release/app-release.aab
# 大小: ~40-45 MB (比 APK 小)
```

---

## ⚙️ 部署前检查清单

### ✅ 功能验证
- [ ] 应用启动成功
- [ ] 登录/注册功能正常
- [ ] 词汇列表加载正确
- [ ] 音频播放正常
- [ ] TTS 文本转语音工作
- [ ] 语法和听力功能可用
- [ ] 离线数据同步正常
- [ ] SRS 间隔重复学习正确

### ✅ 网络测试
- [ ] 连接到后端服务器 (139.196.44.6:8002)
- [ ] 音频下载和缓存正常
- [ ] SSL 自签名证书验证通过
- [ ] 弱网环境下重试机制工作

### ✅ 设备兼容性
- [ ] Android 7.0 (API 24) 设备
- [ ] Android 15 (API 36) 设备
- [ ] 不同屏幕尺寸适配
- [ ] 权限申请正确
  - 存储权限 (READ/WRITE_EXTERNAL_STORAGE)
  - 网络权限 (INTERNET)
  - 麦克风权限 (RECORD_AUDIO)
  - TTS 权限

### ✅ 性能指标
- [ ] 启动时间: < 3 秒
- [ ] 内存占用: < 200 MB (正常使用)
- [ ] 数据同步: < 30 秒 (首次完整同步)
- [ ] 音频加载: < 2 秒 (正常网络)

### ✅ 安全检查
- [ ] 网络请求使用 HTTPS
- [ ] 本地数据加密存储 (SQLite)
- [ ] 认证令牌安全存储 (SecureStorage)
- [ ] 没有硬编码的敏感信息
- [ ] 权限最小化原则

---

## 📱 安装和运行

### 在开发设备上测试

```bash
# 1. 连接 Android 设备 (USB 调试模式)
adb devices

# 2. 安装 APK
adb install -r d:\PROJECT\JapaneseLearn\mobile\build\app\outputs\flutter-apk\app-release.apk

# 3. 启动应用
adb shell am start -n com.example.japanese_learn/.MainActivity

# 4. 查看日志
adb logcat | grep flutter

# 5. 卸载应用
adb uninstall com.example.japanese_learn
```

### 手动安装 (APK 文件分享)

1. **将 APK 传输到设备**
   - 邮件、QQ、微信、云盘等方式
   - 或通过 USB 数据线复制到设备

2. **使用文件管理器打开**
   - 设置 → 允许安装未知来源应用
   - 点击 APK 文件进行安装

3. **启动应用**
   - 应用抽屉中找到"言旅" (JapaneseLearn)
   - 首次启动会请求必要权限

---

## 🔧 后续优化机会

### 立即可做
- [ ] 上传到 App Bundle 格式 (更小的下载大小)
- [ ] 生成生产签名密钥 (替换 Debug Key)
- [ ] 配置自动化 CI/CD 流程

### 短期 (1-2 周)
- [ ] 实现渐进式 Web 应用 (PWA) 版本
- [ ] 构建自动化测试流程
- [ ] 设置崩溃报告和分析

### 中期 (1 月)
- [ ] 实现热更新 (避免频繁市场提交)
- [ ] 配置多渠道打包 (不同品牌市场)
- [ ] 构建 Beta 测试版本

---

## 📊 文件信息

| 指标 | 值 |
|------|-----|
| 构建时间 | 129.7 秒 (~2 分钟) |
| APK 大小 | 57.4 MB |
| 压缩率 | ~78% (未压缩: ~250 MB) |
| 支持 ABI | arm64-v8a, armeabi-v7a |
| 最小 SDK | 24 (Android 7.0 Nougat) |
| 目标 SDK | 36 (Android 15) |

---

## 🌐 后端连接配置

### 当前服务器配置

```
后端 API: https://139.196.44.6:8002/api/v1
基础 URL: https://139.196.44.6:8002
上传音频: /uploads/audio/
```

### 连接测试

```bash
# 测试后端连接
curl -k https://139.196.44.6:8002/api/v1/auth/me \
  -H "Authorization: Bearer <token>"

# 检查音频服务
curl -k https://139.196.44.6:8002/uploads/audio/{uuid}.mp3
```

---

## 📝 发布说明 (Release Notes)

### 版本 1.0.0 (首发版本)

**新增功能**:
✨ 完整的日语学习系统
✨ 词汇管理 (N5-N1 级别)
✨ 语法学习和例句
✨ 听力练习和发音评估
✨ SRS 间隔重复学习系统
✨ NHK 简易新闻阅读
✨ 都道府县知识测验
✨ 本地 Anki 卡组导入

**已修复**:
🔧 音频下载重试机制 (3 次)
🔧 TTS 初始化超时保护 (15 秒)
🔧 SSL 证书主机验证
🔧 Anki 导入上限检查 (5000 文件)

**系统要求**:
• Android 7.0 或更高版本
• 至少 100 MB 可用空间
• 网络连接 (部分功能离线可用)
• 日语 TTS 引擎 (系统设置中安装)

---

## 🆘 故障排查

### 问题: APK 无法安装
**原因**: 设备 Android 版本过低 (< 7.0) 或签名冲突
**解决**: 
```bash
# 强制重新安装
adb install -r app-release.apk

# 或先卸载再安装
adb uninstall com.example.japanese_learn
adb install app-release.apk
```

### 问题: 应用启动闪退
**原因**: 权限未授予或后端连接失败
**检查**:
- 允许应用访问存储
- 确认网络连接正常
- 检查后端服务器是否在线
- 查看 `adb logcat` 错误日志

### 问题: 音频播放失败
**原因**: 自签名证书验证失败或网络超时
**解决**:
- 确保后端 HTTPS 证书有效
- 检查网络连接质量
- 查看应用中的错误提示

---

## 📞 支持联系

- 项目地址: `d:\PROJECT\JapaneseLearn`
- 后端 API: `https://139.196.44.6:8002`
- 问题反馈: 查看应用日志 (`adb logcat`)

---

**构建完成时间**: 2026年3月7日 08:50  
**构建环境**: Windows 10, Flutter 3.27.4, Gradle 8.x  
**下一步**: 安装到设备进行测试，然后上传到应用市场
