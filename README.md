<div align="center">

<img src="assets/icon/mind_bubble.png" alt="MindBubble Logo" width="140">

# 浮念 · MindBubble

**有推荐算法的笔记软件。**

有些信息需要不断提醒。让值得记住的笔记，在日常里一次次浮现。

[下载安装](https://github.com/wkzMagician/MindBubble/releases) · [功能](#功能) · [快速开始](#快速开始) · [开发与构建](#开发与构建)

</div>

## 记下来之后，还需要再遇见

读到的一段话、想坚持的原则、课程里的一个概念，记下来的那一刻很有价值。但过了一周、一个月，如果没有再遇见，它们也可能慢慢淡出生活。

浮念想解决的是这件事：**有的信息需要不断提醒，才会真正参与我们的思考和行动。**

把这些内容写成笔记，或者从已有的笔记库导入。浮念会从你的笔记中推荐一组内容，让你在打开应用、桌面回顾或收到提醒时，重新遇见它们。你可以告诉它哪些内容值得多看，哪些可以少出现，让回顾逐渐贴近自己的需要。

## 推荐如何工作

浮念的推荐算法围绕“接下来值得再看哪条笔记”工作。Ocean 泡泡、信息流卡片和通知使用同一套推荐逻辑，推荐计算在本地完成。

- **提醒价值**：根据笔记的提醒价值决定相对优先级；配置模型后，可生成分析结果，你也可以手动修改推荐属性。
- **回顾反馈**：对出现频率的反馈会调整偏好；有可用的语义向量时，反馈也会影响相似内容。
- **时间间隔**：刚出现的笔记会暂时降低再次出现的机会，随着时间推移逐渐恢复。
- **多样性与探索**：减少同一批推荐中相似内容的扎堆，并给较少出现的笔记留下机会。

推荐以概率抽取，每轮不重复选择同一条笔记。它没有为每条笔记设置固定的复习周期。你可以调整推荐参数，也可以停止某条笔记的推荐，之后仍能在列表中找到它并重新启用。

算法和数据说明见 [自适应推荐](docs/adaptive_recommendations.md)。

## 功能

### 记录、阅读和整理

- **Markdown 笔记**：创建、编辑、搜索和管理笔记，支持外链、网络图片、本地图片附件和源码模式。
- **两种回顾视图**：在 Ocean 中浏览漂浮的笔记泡泡，或用信息流卡片浏览推荐内容。
- **笔记封面**：使用文字封面或正文图片；可调整文字、配色和图片位置，也可使用已配置的文本模型提炼封面标题。
- **推荐属性与反馈**：查看、修改笔记的分析属性和偏好，主动重新分析，或关闭单条笔记的推荐。

### 让笔记回到日常

- **自动提醒**：设置 15 分钟至 24 小时的提醒周期和免打扰时段；桌面端在后台展示回顾入口，手机端通过系统通知提醒。也可以手动刷新推荐。
- **独立模型配置**：文本模型用于标题、摘要和笔记分析，向量模型用于语义相似度和推荐多样性，两者可以分别选择和配置。
- **多种模型连接**：支持 API 和账号登录；桌面端还可连接本地 Ollama 或使用已安装、已登录的 Codex CLI。具体可用方式与设置见 [模型配置](docs/MODELS.md)。

### 带着已有笔记开始

- **多来源导入**：支持 Obsidian、Notion、Evernote、Google Keep、OneNote、思源、语雀、FlowUs、飞书、Flomo 的专属导入，以及通用文件导入。各来源的准备步骤和支持格式见 [导入指南](docs/IMPORT_GUIDE.md)。
- **WebDAV 同步**：可选连接兼容 WebDAV 的服务，在设备之间同步笔记与附件，支持冲突预览。详见 [同步与启动](docs/sync_startup.md)。
- **Agent / MCP**：通过内置 MCP 服务导入、列出、搜索、读取、更新和删除笔记，也支持带检查点的增量导入。

## 快速开始

从 [Releases](https://github.com/wkzMagician/MindBubble/releases) 下载适合设备的发布包；可用平台以对应版本的附件为准。

1. 新建一条你希望经常想起的笔记，或从笔记列表导入已有内容。
2. 浏览首页推荐，打开感兴趣的笔记阅读，并按需要给出频率反馈。
3. 在设置中开启自动提醒，选择适合自己的周期和免打扰时段。
4. 需要自动分析和语义推荐时，分别配置文本模型与向量模型；需要跨设备使用时，再配置 WebDAV。

已有笔记即使没有模型分析属性，也可以参与推荐。文本分析和向量生成需要使用你配置的模型服务；数据会发送到相应服务，选择本地模型时由本地服务处理。

提醒周期控制何时发起一轮回顾，具体推荐哪些笔记由算法决定。桌面端支持登录后自动运行；Android 会在下次打开应用时恢复本地状态并同步。平台差异见 [提醒说明](docs/REMINDERS.md)。

## 数据与隐私

笔记和附件以本地文件保存，每条笔记都是独立的 Markdown 文档，可以由应用或外部编辑器读取、修改。应用会刷新外部保存的变化。

WebDAV 同步按需启用，同步内容不会额外进行端到端加密；请选择可信的服务，并按自己的需求配置访问和加密措施。模型分析所使用的服务与笔记同步分别配置。

## Agent / MCP 接入

Agent 可以通过仓库提供的 MCP 服务操作同一套本地笔记数据。配置和协议见：

- [MCP 示例配置](tools/mind-bubble.mcp.json)
- [MCP 服务脚本](tools/mind_bubble_mcp.py)
- [导入格式与接口](docs/MIND_BUBBLE_IMPORT_FORMAT.md)
- [mind-bubble-import skill](skills/mind-bubble-import/SKILL.md)

## 开发与构建

项目基于 Flutter，Dart SDK 要求为 `>=3.8.0 <4.0.0`。配置所需平台的 Flutter 开发环境后运行：

```powershell
flutter pub get
flutter run -d windows
```

可在相应开发主机上选择 macOS、Linux、Android 或 iOS 设备。项目选择的平台为 Android、iOS、Windows、macOS、Linux，Web 不在支持目标内。

提交前运行：

```powershell
dart format .
flutter analyze
flutter test
```

常用构建命令，在对应平台的开发环境中执行：

```powershell
flutter build windows
flutter build macos
flutter build linux
flutter build apk
flutter build appbundle
flutter build ios
```

业务代码位于 `lib/features`，应用胶水和服务位于 `lib/app`、`lib/services`。项目通过普通 Dart / Flutter 包使用 Dartloom 的模型、存储、同步和单例能力；所选包与平台记录在 `.dartloom/project.yaml`。

欢迎通过 Issue 或 Pull Request 反馈体验、改进平台适配和文档。
