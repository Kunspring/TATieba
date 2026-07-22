# 贝占口巴

一个用 Flutter 构建的第三方百度贴吧客户端，支持全平台运行，并内置 AI 助手。

## 平台支持

| Android | iOS | Web | Windows | macOS | Linux |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## 功能

### 贴吧浏览
- **推荐流**：首页推荐帖子列表，支持分页加载
- **进吧**：浏览指定贴吧，支持吧内搜索和分区索引
- **帖子详情**：查看帖子内容、评论、图片、视频，支持只看楼主
- **收藏**：收藏帖子和贴吧，支持离线缓存
- **用户主页**：查看用户信息、等级、发帖记录

### 账号系统
- **二维码登录**：扫码登录百度账号
- **网页登录**：内置 WebView 完成百度通行证认证
- **多账号**：支持绑定和切换百度账号

### 消息
- **私信**：发送和接收私信，支持实时推送（WebSocket）
- **消息通知**：新消息本地推送提醒
- **签到提醒**：定时提醒签到，支持自定义时间

### AI 助手
- **智能对话**：接入大语言模型，支持流式输出和多轮工具调用
- **上下文感知**：根据当前浏览的贴吧、帖子自动提供相关建议
- **工具调用**：搜索帖子、查看消息、打开页面等
- **记忆系统**：长期记忆与一致性校验，跨会话保持上下文
- **语音交互**：语音输入（支持讯飞 STT）和语音合成（TTS）输出
- **情绪融合**：根据对话内容动态调整回复风格和颜文字
- **像素艺术**：内置 ASCII/像素画渲染引擎
- **摇晃唤醒**：摇晃手机快速唤起助手对话

### 其他
- **深色模式**：跟随系统或手动切换
- **省流模式**：无图模式，节省流量
- **毛玻璃效果**：全局毛玻璃导航栏和 UI
- **视频播放**：内置视频播放器
- **图片查看**：支持缩放、保存图片
- **签到**：一键签到关注的贴吧

## 技术栈

- **框架**：Flutter 3.x + Dart 3.x
- **网络**：HTTP + WebSocket，自实现百度贴吧 API 签名与 Protobuf 通信
- **状态管理**：基于 `ValueNotifier` + `ListenableBuilder` 的轻量级方案
- **AI**：兼容 OpenAI 格式的 LLM API，支持 Function Calling
- **语音**：讯飞语音识别 + Flutter TTS
- **本地存储**：SharedPreferences
- **图片缓存**：CachedNetworkImage + 自研封面图缓存

## 项目结构

```
lib/
├── constants/        # 应用常量
├── models/           # 数据模型
├── screens/          # 页面
│   ├── home/         #   首页推荐流
│   ├── detail/       #   帖子详情
│   ├── messages/     #   私信
│   └── user/         #   用户主页
├── services/         # 业务服务层
│   ├── tieba_*       #   贴吧 API 相关
│   ├── agent_*       #   AI 助手相关
│   └── app_*         #   应用配置相关
├── theme/            # 主题系统
├── utils/            # 工具函数
└── widgets/          # 通用组件
```

## 开始开发

### 环境要求

- Flutter SDK >= 3.11.5
- Dart SDK >= 3.11.5
- Android Studio / Xcode（对应平台开发）

### 运行

```bash
# 安装依赖
flutter pub get

# 运行（选择目标平台）
flutter run -d windows        # Windows
flutter run -d chrome         # Web
flutter run -d android        # Android
flutter run -d ios            # iOS
flutter run -d macos          # macOS
```

### 构建

```bash
# Android APK
flutter build apk --release

# Windows
flutter build windows --release

# Web
flutter build web --release
```

### AI 助手配置

在应用内「助手设置」页面配置：
- API 地址（兼容 OpenAI Chat Completions 格式）
- API Key
- 模型名称
- 系统提示词（支持自定义 Persona）

## CI/CD

项目配置了 GitHub Actions，在 push/PR 时自动执行：
- 代码格式化检查（`dart format`）
- 静态分析（`flutter analyze`）
- 单元测试（`flutter test`）

## 声明

本项目为第三方客户端，与百度公司无关。仅供学习交流使用，请勿用于商业用途。

## License

MIT
