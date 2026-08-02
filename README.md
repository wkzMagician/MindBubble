# 浮念（MindBubble）

浮念是一个让重要概念在合适时机重新浮现的跨平台应用。它本地优先，支持 Markdown 正文、五档浮现频率、Agent 导入和 WebDAV 同步。

## 支持的平台

Windows、macOS、Linux 和 Android 共用同一 SQLite 数据模型。Windows、macOS、Linux 的设置页可以开启“登录后自动运行”；Android 不会在开机后后台拉起，而会在用户下次打开应用时恢复状态与同步。

| 平台 | 开发要求 | 发布物 |
| --- | --- | --- |
| Windows | Flutter SDK、Visual Studio 的“使用 C++ 的桌面开发” | MSIX |
| macOS | Flutter SDK、Xcode | DMG |
| Linux | Flutter SDK、GTK/Clang 构建依赖 | AppImage |
| Android | Flutter SDK、Android Studio/SDK | APK、AAB |

```powershell
flutter pub get
flutter run -d windows # 也可替换为 macos、linux、android
dart format lib test
flutter analyze
flutter test
```

## 每日选择逻辑

每天第一次打开 Ocean 时会缓存最多五个泡泡，当天不会因频率调整重新抽选。每个候选泡泡的权重由以下因素构成：未展示的新泡泡在创建次日获得 `+100`、距离上次展示越久最多 `+50`、频率档位“很少”到“频繁”分别为 `-30/-15/0/+15/+30`、随机扰动最多 `+20`；近 1 天展示过扣 `50`，近 3 天展示过扣 `20`。随后按非负相对权重随机无重复抽取。

## 导入

管理页顶部的导入按钮支持 CSV 和 XLSX。首发识别 `title`/`标题` 与 `description`/`正文`/`描述` 列，缺失标题或正文的行跳过；标题按大小写无关去重。导入服务已与 UI 分离，后续映射向导和兼容 SQLite 数据库导入可复用同一服务。

## Agent / MCP

仓库内的 [MCP 服务](tools/mind_bubble_mcp.py) 让 Codex、Claude Code、OpenCode 等 Agent 使用同一套本地泡泡数据。它提供 `import_bubbles`、`list_bubbles`、`search_bubbles`、`get_bubble`、`update_bubble`、`delete_bubble`；批量导入默认按标题去重，频率字段为 `appearanceFrequency: 1..5`。

### 启动 MCP 服务

先确认 Python 可用，然后将下面命令中的占位路径改为你的实际路径：

```powershell
$env:MIND_BUBBLE_DB = "/path/to/your/data/mind_bubble.db"
python /path/to/your/project/tools/mind_bubble_mcp.py
```

正常情况下该进程不会输出提示，而是等待 MCP 客户端通过标准输入发送请求；不要手工输入 JSON。数据库文件在第一次启动 MindBubble 后自动创建。

### 给 Agent 配置 MCP

配置的核心是：以 `python` 运行 `tools/mind_bubble_mcp.py`，并把 `MIND_BUBBLE_DB` 指向 MindBubble 实际使用的数据库。可直接以 [示例配置](tools/mind-bubble.mcp.json) 为模板：

```json
{
  "mcpServers": {
    "mind-bubble": {
      "command": "python",
      "args": ["/path/to/your/project/tools/mind_bubble_mcp.py"],
      "env": {
        "MIND_BUBBLE_DB": "/path/to/your/data/mind_bubble.db"
      }
    }
  }
}
```

- Codex：在 MCP 配置中添加上面的 `mind-bubble` server，或通过 Codex 的 MCP 管理界面选择该脚本和环境变量。
- Claude Code：把该对象加入项目根目录的 `.mcp.json` 的 `mcpServers`。
- OpenCode：把同一个 `mcpServers` 对象加入其项目或用户级 MCP 配置。

配置后重启 Agent，并询问“列出 MindBubble 泡泡”验证是否发现 `list_bubbles` 工具。

## WebDAV 同步

在“管理泡泡 → 设置 → 云端同步（WebDAV）”中填写同步信息。应用使用 WebDAV，因此可接入坚果云、Nextcloud 或任何兼容 WebDAV 的云服务。

### 坚果云设置示例

1. 注册并登录坚果云账号。
2. 在坚果云网页的“账户信息 / 安全选项”中创建一个**应用密码**；不要使用网页登录密码。
3. 打开 MindBubble 的“云端同步（WebDAV）”，保留服务器地址 `https://dav.jianguoyun.com/dav/`。
4. 账号填写坚果云登录邮箱；“应用密码 / API Key”填写第 2 步生成的应用密码。
5. 点击“保存并启用”。配置会持久化，之后启动应用不需要重新输入；设置页中的密码仍以黑点显示。
6. 需要同步的每台设备都填写同一份 WebDAV 凭据。

WebDAV 配置保存在应用支持目录的 `webdav_config.json` 中。按照产品设定，泡泡同步内容不进行额外端到端加密。

## 打包

```powershell
flutter build windows
flutter build apk
flutter build appbundle
# 在对应主机执行：flutter build macos / flutter build linux
```
