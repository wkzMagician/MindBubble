<div align="center">

<img src="assets/icon/mind_bubble.png" alt="浮念 Logo" width="140">

# 浮念 · MindBubble

让重要的想法，在恰好的时候重新浮现。

一个安静、专注、本地优先的概念复习与灵感管理应用。

</div>

<p align="center">
  <strong>Markdown · 智能浮现 · 本地优先 · WebDAV 同步 · Agent 友好</strong>
</p>

<p align="center">
  <a href="#它能做什么">功能</a> ·
  <a href="#界面预览">界面预览</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#数据与隐私">数据与隐私</a>
</p>

## 它能做什么

浮念把零散的知识、灵感和待回看的概念，放进一个会“再次遇见”它们的空间。你可以随手记录，也可以让应用按照自己的节奏，把内容重新带回眼前。

- **在 Ocean 中浏览**：每天打开应用，概念会以漂浮泡泡的形式出现；点击泡泡即可阅读内容。
- **控制浮现频率**：为每个概念设置五档出现频率，从很少到频繁，决定它被重新展示的节奏。
- **用 Markdown 记录**：标题和正文都支持 Markdown，适合保存短笔记、知识卡片、阅读摘录和长期思考。
- **集中管理泡泡**：搜索、创建、编辑、删除和批量导入概念，管理自己的知识池。
- **从表格快速导入**：支持 CSV 与 XLSX，适合把已有的笔记或知识库一次性带入浮念。
- **多设备保持一致**：通过兼容 WebDAV 的服务同步，可使用坚果云、Nextcloud 等服务。
- **和 Agent 一起工作**：内置 MCP 服务，Codex、Claude Code、OpenCode 等 Agent 可以读取、搜索和维护同一套本地泡泡。

## 界面预览

> 当前仓库暂未加入产品截图。下面的版块已预留，后续可直接替换为真实截图或动图。

| Ocean 主界面 | 泡泡管理 |
| --- | --- |
| **截图占位**：展示漂浮泡泡、今日概念和阅读入口 | **截图占位**：展示搜索、列表、新建和导入 |

| Markdown 编辑 | 同步设置 |
| --- | --- |
| **截图占位**：展示标题、正文和出现频率设置 | **截图占位**：展示 WebDAV 配置、同步状态和冲突处理 |

## 适合谁

浮念适合希望持续回看重要内容、但不想被复杂任务系统打扰的人，例如：

- 学习者：复习概念、公式、语言知识和课程笔记；
- 创作者：保存灵感、素材和正在酝酿的想法；
- 研究者与开发者：维护技术知识、项目决策和长期备忘；
- 喜欢掌控数据的人：以 Markdown 文件保存内容，数据可读、可迁移。

## 支持的平台

当前支持 Windows、macOS、Linux 和 Android。Web 不是本项目的支持目标。

桌面端支持“登录后自动运行”设置；Android 会在你下次打开应用时恢复本地状态并进行同步。

## 快速开始

### 直接使用

目前仓库以源码方式提供。请准备 Flutter SDK，并根据目标平台安装对应的桌面或 Android 构建环境，然后运行：

```powershell
flutter pub get
flutter run -d windows
```

`windows` 也可以替换为 `macos`、`linux` 或 `android`。首次打开后，在“管理泡泡”中创建一个概念即可开始使用。

### 开发与验证

```powershell
dart format .
flutter analyze
flutter test
```

## 数据与隐私

浮念采用本地优先设计：每个泡泡都保存为一个独立的 Markdown 文档，正文可由应用或外部编辑器读取和修改。应用会自动刷新外部保存的变化。

同步是可选功能。启用 WebDAV 后，泡泡文档会同步到你配置的服务；同步内容不会额外进行端到端加密，请根据自己的隐私需求选择服务并妥善保管凭据。

## Agent / MCP

浮念提供仓库内的 MCP 服务，让 Agent 使用与你相同的本地泡泡数据。支持的操作包括：

- 导入、列出和搜索泡泡；
- 查看、更新和删除单个泡泡。

详细配置请参考 [MCP 示例配置](tools/mind-bubble.mcp.json) 和 [MCP 服务脚本](tools/mind_bubble_mcp.py)。

## 构建发布包

在对应平台的开发环境中执行：

```powershell
flutter build windows
flutter build apk
flutter build appbundle
```

macOS 和 Linux 请分别在对应主机上执行 `flutter build macos` 或 `flutter build linux`。

## 项目状态

核心的概念记录、Ocean 浮现、Markdown 文档、批量导入和 WebDAV 同步能力已经在项目中实现。产品截图、发行版下载入口和更完整的用户指南将在后续补充。

## 参与贡献

欢迎围绕使用体验、跨平台适配、同步可靠性和文档改进提交 Issue 或 Pull Request。

## 致谢

浮念基于 Flutter 构建，并使用 Dartloom 相关组件提供本地文档存储、同步与单例运行支持。
