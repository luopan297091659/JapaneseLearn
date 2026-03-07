# 📲 APK 快速安装指南

**APK 文件**: `d:\PROJECT\JapaneseLearn\mobile\build\app\outputs\flutter-apk\app-release.apk`  
**文件大小**: 57.4 MB | **应用版本**: 1.0.0 | **最低系统**: Android 7.0+

---

## 🚀 快速安装 (3 种方式)

### 方式 1️⃣: USB 电脑安装 (推荐 - 最快)

**需要**:
- Android 手机 (USB 调试模式)
- USB 数据线
- 电脑已安装 Android SDK (adb 工具)

**步骤**:
```bash
# 1. 连接手机并启用 USB 调试
#    设置 → 开发者选项 → USB 调试 (勾选)

# 2. 打开命令行/PowerShell，进入项目目录
cd d:\PROJECT\JapaneseLearn

# 3. 检查设备连接
adb devices
# 应显示: List of attached devices
#         <device_id>  device

# 4. 安装 APK
adb install -r mobile\build\app\outputs\flutter-apk\app-release.apk

# 5. 等待安装完成（~ 30-60 秒）
# 显示: Success 表示安装成功

# 6. 启动应用
adb shell am start -n com.example.japanese_learn/.MainActivity
```

✅ **完成!** 应用会在手机屏幕上打开

---

### 方式 2️⃣: 文件分享安装 (无需电脑工具)

**需要**:
- APK 文件 (57.4 MB)
- 云存储 / 邮件 / 文件传输方式

**步骤**:

1. **上传 APK 到云与网络**
   - 复制文件到云盘 (Google Drive / OneDrive / 百度网盘)
   - 或发送邮件给自己或朋友
   - 或使用 QQ / 微信文件传输

2. **在手机上下载**
   - 打开云应用 / 邮件 / 聊天应用
   - 下载 APK 文件到设备

3. **安装应用**
   - 打开文件管理器，找到 APK
   - 点击 APK 文件开始安装
   - 如提示"安装未知应用"，选择允许
   - 等待安装完成 (~30 秒)
   - 点击"打开"启动应用

✅ **完成!** 应用已安装

---

### 方式 3️⃣: Android Studio 安装 (开发者用)

**步骤**:
```bash
# 进入项目目录
cd d:\PROJECT\JapaneseLearn\mobile

# 使用 Flutter 直接安装到连接的设备
flutter install

# 输出示例:
# Launching lib/main.dart on Android in release mode...
# [✓] Built build/app/outputs/flutter-apk/app-release.apk (54.8MB).
# [✓] Installed build/app/outputs/flutter-apk/app-release.apk.
```

✅ **完成!** 应用已安装到手机

---

## ✨ 首次启动

1. **权限请求**
   - 存储权限 (允许): 用于保存词汇和音频
   - 麦克风权限 (允许): 用于发音评估
   - 网络权限: 自动授予

2. **账户登录/注册**
   - 选择"注册"创建新账户
   - 或选择"登录"使用现有账户

3. **选择学习级别**
   - N5 (初级) / N4 / N3 / N2 / N1 (高级)
   - 根据实际水平选择

4. **开始学习**
   - 进入词汇等学习模块
   - 享受学习!

---

## 📋 系统要求与支持

| 要求 | 规格 |
|------|------|
| **最低 Android** | 7.0 (API 24) |
| **推荐 Android** | 11+ (API 30+) |
| **存储空间** | 100+ MB 可用空间 |
| **内存 (RAM)** | 2+ GB 推荐 |
| **网络** | WiFi 或 4G |

### 支持的设备

✅ **完全支持**:
- Samsung (所有现代型号)
- Xiaomi / Redmi
- OPPO / Vivo
- OnePlus
- 华为 (非谷歌服务版本)
- Google Pixel
- 其他 Android 7.0+ 设备

---

## 🎧 首次使用建议

### 1. 安装 TTS 引擎 (文本转语音)

如果朗读功能不工作:

```
手机设置 → 辅助功能 
       → 文字转语音输出 (Text-to-speech output)
       → 首选引擎：安装 Google 文字转语音
       → 语言：日本語 (日語)
```

### 2. 授予必要权限

```
手机设置 → 应用
       → 言旅 (JapaneseLearn)
       → 权限
       → 打开:
          ✓ 存储 (允许)
          ✓ 麦克风 (允许)
          ✓ 网络 (自动)
```

### 3. 选择学习计划

- **初学者**: 从 N5 开始
- **中级**: N3 / N4
- **高级**: N1 / N2

### 4. 预加载资源 (可选)

- WiFi 连接时系统会自动缓存音频
- 首次完整同步需要 1-2 分钟
- 之后离线也能学习已下载资源

---

## 🔧 故障排查

### 问题: "安装失败"

**原因 1**: 版本冲突
```bash
# 解决: 先卸载旧版本
adb uninstall com.example.japanese_learn
# 然后重新安装
adb install app-release.apk
```

**原因 2**: 存储空间不足
```
手机设置 → 存储
清理空间至 100+ MB
重新尝试安装
```

### 问题: 应用启动后立即闪退

**检查 1**: 网络连接
- 确保手机连接到 WiFi 或 4G
- 测试: 打开浏览器访问网站

**检查 2**: 后端服务器
- 确保后端服务运行中
- 检查服务器地址: `https://139.196.44.6:8002`

**检查 3**: 查看错误日志
```bash
adb logcat | grep -i java
# 查找 Exception 错误信息
```

### 问题: 无法下载音频

**检查 1**: 网络连接质量
- 切换到 5G / WiFi
- 重启手机网络

**检查 2**: 存储权限
- 检查应用是否获得存储权限
- 重新启动应用

**检查 3**: 磁盘空间
- 清理手机存储空间
- 预留至少 200 MB

### 问题: TTS 朗读不工作

**解决**:
```
手机设置 → 辅助功能
        → 文字转语音输出
        → 首选引擎：选择 Google 文字转语音
        → 语言：日本語 / 日本語
```

---

## 📞 需要帮助？

### 检查日志

```bash
# 实时查看应用日志
adb logcat | grep "japanese_learn\|flutter\|dart"

# 保存日志到文件
adb logcat > app_log.txt

# 通过邮件或群组分享日志
```

### 验证安装成功

```bash
# 检查应用是否已安装
adb shell pm list packages | grep japanese_learn

# 输出应显示:
# package:com.example.japanese_learn

# 获取应用信息
adb shell dumpsys package com.example.japanese_learn | grep version
```

---

## 🚀 进阶 (开发者)

### 生成 App Bundle (市场分发优化)

```bash
cd d:\PROJECT\JapaneseLearn\mobile

# 编译 AAB (更小的文件，市场首选)
flutter build appbundle --release

# 输出位置:
# build/app/outputs/bundle/release/app-release.aab
# 大小: ~40-45 MB (比 APK 小 ~20%)
```

### 签名配置 (生产发布)

```bash
# 1. 创建签名密钥
keytool -genkey -v -keystore japanese_learn.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias japanese_learn

# 2. 使用签名打包
flutter build apk --release \
  --keystore=japanese_learn.jks \
  --key-alias=japanese_learn \
  --keystore-password=<your-password>
```

### 上传到应用市场

- **Google Play Store**: 需要开发者账户 ($25 一次性费用)
- **华为应用市场**: 类似流程
- **小米应用商店**: 需要企业资质

---

## 📊 应用统计

| 指标 | 数值 |
|------|------|
| 应用名称 | 言旅 Kotabi |
| 包名 | com.example.japanese_learn |
| 版本 | 1.0.0 |
| 构建号 | 1 |
| APK 大小 | 57.4 MB |
| 支持 ABI | arm64-v8a, armeabi-v7a |
| 最小 API | 24 |
| 目标 API | 36 |

---

## ✅ 安装完成检查清单

- [ ] APK 已成功安装
- [ ] 应用可以启动
- [ ] 登录/注册功能正常
- [ ] 可以加载词汇列表
- [ ] 音频播放正常
- [ ] TTS 朗读工作 (已安装日语引擎)
- [ ] 可以连接到后端服务器
- [ ] 数据同步成功

✨ **所有项目完成? 恭喜! 安装成功!**

---

**更新时间**: 2026年3月7日  
**版本**: 1.0.0  
**文件**: app-release.apk (57.4 MB)
