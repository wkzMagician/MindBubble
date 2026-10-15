# MindBubble 分来源增量导入指南

## 操作流程

打开「管理泡泡」，点击右上角导入按钮。导入工作区左侧选择来源软件，右侧展示该软件支持的导入方式和准备步骤：

1. 选择来源软件及推荐导入方式，需要时切换到另一种方式。
2. 选择文件夹、导出文件，或通过 Notion Integration Token 读取授权页面。
3. 查看扫描结果：新增、更新、未变化、冲突。发生冲突时选择保留本地、采用导入内容或另存副本。
4. 确认导入。后续重新导入相同来源，可自动识别变化。

| 来源软件 | 推荐方式 | 其他方式 | 增量识别依据 |
| --- | --- | --- | --- |
| Obsidian | Vault 根目录（含 Markdown 与图片） | ZIP、Markdown 文件 | 路径及来源标识 |
| Logseq | Graph 根目录（pages / journals / assets） | ZIP、Markdown 文件 | 路径及来源标识 |
| Notion | Markdown & CSV 导出 ZIP | Integration API | 页面 ID 或导出路径 |
| Evernote | ENEX 文件 | 多文件 ENEX、ENEX ZIP | GUID |
| Google Keep | Google Takeout ZIP | 多个 Keep JSON | ID 或文件路径 |
| Markdown | Markdown 文件夹 | Markdown 文件、ZIP | 相对路径 |
| CSV / Excel | CSV、XLSX 文件 | 多文件 | 表格行的 ID 或标题 |
| MindBubble | mind-bubble-import JSON | — | 原始 ID |

## Notion API

在 Notion 创建 Internal Integration，将要导入的页面共享给它。在「Notion → Notion API 连接」中输入 Integration Token，点击「读取 Notion 页面」。Token 只在当前导入窗口中使用。API 仅能读取授予 Integration 权限的页面。

## 来源标识

每个来源软件都有独立的来源标识，位于「增量导入设置」中。

- Obsidian、Logseq 和通用 Markdown 文件夹默认使用软件名与文件夹名，例如 `obsidian:MyVault`。
- 导出文件默认使用软件名作为来源标识，以便多次导出时自动匹配新增和更新。
- 导入不同的 Vault、账号或互不相关的数据集合时，为其设置不同且稳定的来源标识。重复导入同一集合时继续使用相同标识。

系统根据来源标识、笔记 ID 和内容哈希判断新增、更新、未变化及冲突，导入记录保存在应用支持目录的 `import-ledger.json`。

## 图片与同步

ZIP 与目录中的相对图片导入到 `assets` 对象目录，并同步更新 Markdown 引用。支持 PNG、JPG、JPEG、GIF、WEBP、BMP。图片与文档共用 WebDAV 自动同步流程。

ZIP 导入会检查压缩包体积、解压总量、路径安全和文件数量。重复导入只处理需要更新的笔记，来源中删除的笔记仍保留在本地。

首页现在采用独立于日期的手动刷新抽取逻辑，支持点击「刷新」及 Windows F5 快捷键。
