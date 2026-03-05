# 日本語学習 - Japanese Learning App

日语学习系统，支持 Android 和 iOS 双平台，采用 Flutter + Node.js + MySQL 技术栈。

---

## 📐 系统架构

```
JapaneseLearn/
├── backend/                # Node.js + Express REST API
│   ├── src/
│   │   ├── app.js          # 入口文件
│   │   ├── config/         # 数据库配置
│   │   ├── controllers/    # 业务逻辑控制器
│   │   ├── middlewares/    # JWT 认证中间件
│   │   ├── models/         # Sequelize 数据模型
│   │   ├── routes/         # API 路由
│   │   └── utils/          # 工具函数 (JWT, SRS算法, 日志)
│   └── database/
│       └── seeds/          # 初始种子数据 (N5词汇/语法/测题)
└── mobile/                 # Flutter App (Android + iOS)
    └── lib/
        ├── main.dart        # App 入口 + 主题
        ├── config/          # API 配置
        ├── models/          # 数据模型
        ├── services/        # API 请求服务
        ├── router/          # GoRouter 路由管理
        └── screens/         # 各功能页面
            ├── auth/        # 登录 / 注册
            ├── home/        # 首页 + SRS 复习
            ├── vocabulary/  # 单词学习
            ├── grammar/     # 语法课程
            ├── listening/   # 听力练习
            ├── quiz/        # 测验 + 结果
            ├── news/        # 日语新闻
            └── profile/     # 个人中心 + 进度统计
```

---

## 🚀 功能模块

| 功能 | 说明 |
|------|------|
| 📖 单词学习 | N5-N1 词汇，含假名/汉字/词义/例句/音频 |
| 🗂 间隔复习 (SRS) | SM-2 算法，智能安排复习时间，类似 Anki |
| 📚 语法课程 | JLPT 文型讲解 + 例文，含中文解说 |
| 🎧 听力练习 | 音频播放，含原文/翻译，分级练习 |
| 📝 测验模式 | MCQ 选择题，支持词义/读音/填空等题型 |
| 📰 日语新闻 | NHK Easy 风格新闻听读，含难度分级 |
| 📊 学习统计 | 连续学习天数、每日时长、测验平均分、SRS 卡片情况 |

---

## 🛠 快速启动

### 后端

```bash
cd backend
cp .env.example .env          # 修改数据库配置
npm install
npm run dev                   # 启动开发服务器 (端口 3000)
```

**初始化数据库：**
```bash
# 1. 启动 MySQL，创建数据库
mysql -u root -p < database/seeds/initial_data.sql
# 2. 应用会在启动时自动 sync 建表
```

### 移动端 (Flutter)

```bash
cd mobile
flutter pub get
# 修改 lib/config/app_config.dart 中的 baseUrl 为你的服务器地址
flutter run                   # Android 模拟器 或 iOS 模拟器
flutter run --release         # 发布版本
```

---

## 📡 API 接口

| 路径 | 描述 |
|------|------|
| `POST /api/v1/auth/register` | 用户注册 |
| `POST /api/v1/auth/login` | 用户登录 |
| `GET  /api/v1/vocabulary` | 获取词汇列表（支持分级/搜索） |
| `GET  /api/v1/grammar` | 获取语法课程 |
| `GET  /api/v1/srs/due` | 获取今日待复习卡片 |
| `POST /api/v1/srs/review` | 提交复习结果（SM-2 算法） |
| `GET  /api/v1/quiz/generate` | 生成测验题目 |
| `POST /api/v1/quiz/submit` | 提交测验答案 |
| `GET  /api/v1/listening` | 获取听力材料 |
| `GET  /api/v1/news` | 获取日语新闻 |
| `GET  /api/v1/progress/summary` | 获取学习进度统计 |

---

## 🗄 数据库模型

- **users** - 用户信息、等级、连续学习天数
- **vocabulary** - 词汇（单词/读音/词义/例句/音频，分 N1-N5）
- **grammar_lessons** - 语法课程（文型/讲解/例文）
- **srs_cards** - SRS 记忆卡片（SM-2 算法字段）
- **quiz_questions** - 测验题库（选择题/填空题）
- **quiz_sessions** - 测验记录
- **listening_tracks** - 听力音频材料
- **news_articles** - 新闻文章（含音频/原文/Ruby注音）
- **user_progress** - 学习活动日志

---

## 🧠 SRS 算法

采用 **SM-2 间隔重复算法**：

$$\text{EF'} = \text{EF} + (0.1 - (5 - q)(0.08 + (5-q) \times 0.02))$$

- `q = 0-5`：用户对卡片的记忆质量评分（完全忘了→很熟悉）
- `EF`：难易度系数，初始值 2.5，最小值 1.3
- 根据 `EF` 和重复次数计算下次复习间隔天数

---

## 📱 屏幕截图（结构说明）

```
登录/注册 → 首页（连续天数 + SRS提醒 + 功能网格）
         → 单词列表 → 单词详情（加入SRS）
         → 语法列表 → 语法详情（例文展示）
         → 听力列表 → 音频播放器（含原文）
         → 测验      → 结果页（得分 + 正确率）
         → 新闻列表 → 新闻详情（音频+原文）
         → 个人中心（进度统计 + 设置）
         → SRS 复习（翻转卡片式复习）
```
