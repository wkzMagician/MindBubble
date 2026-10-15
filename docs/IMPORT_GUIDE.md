# MindBubble 增量导入指南

## 使用流程

打开「管理泡泡」，点击导入图标，填写来源名称，选择文件夹、单个或多个文件、ZIP 或 Notion API。扫描完毕先预览新增、更新、未变化和冲突，再确认导入。

**同一来源的后续导入使用同一个来源名称。** 系统根据来源 ID 和内容哈希识别变化。

| 来源 | 输入形式 | 稳定身份 |
| --- | --- | --- |
| Obsidian / Logseq | Markdown 库文件夹 | 相对路径 |
| Notion 导出 | Markdown + CSV ZIP | 页面 ID 或路径 |
| Notion API | Integration Token | 页面 ID |
| Evernote | ENEX | GUID |
| Google Keep | Takeout ZIP 或单个 JSON | ID 或路径 |
| Markdown | 文件、文件夹、ZIP | 相对路径 |
| MindBubble | 标准 mind-bubble-import JSON v1 | 原始 ID |
| CSV / XLSX | 带 title 和 description 列 | 行号 |

## Notion API

先在 Notion 创建 Integration，再将相应页面共享给它。在导入窗口输入 Integration Token，点击「从 Notion API 增量导入」。Token 只保留在当前窗口。系统从授权页面读取文本、列表、代码和图片。

## 图片与附件

导出包中的相对图片会导入到 assets 对象目录，以文件哈希命名，并更新 Markdown 引用。图片资源与文档一起进入 WebDAV 同步流程。支持 PNG、JPG、JPEG、GIF、WEBP、BMP；其他附件的链接保留。

## 重复导入与冲突

- 来源未变化时跳过，保留本地编辑。
- 来源变化而本地保持原样时更新。
- 两端都修改时标记冲突，可保留本地、采用来源或保存副本。
- 来源删除后本地仍保留，方便用户整理。

导入记录保存在应用支持目录的 import-ledger.json。支持中断后重试及重复导入。ZIP 检查体积、文件数量和路径安全。

首页的每日自动浮现按原有逻辑运行；WebDAV 自动同步也保持原样。
