# MindBubble：10 个来源软件与通用导入

在「管理泡泡」点击「导入」，左侧选择国际软件（5）、国内软件（5）或「通用导入」，右侧按来源显示专属方式与操作说明。

## 当前已实现

| 来源 | 导入入口 | 数据格式 |
| --- | --- | --- |
| Obsidian | Vault 文件夹、文件/ZIP | Markdown、相对图片 |
| Notion | 导出 ZIP、Integration API | Markdown + CSV 或授权页面 |
| Evernote | ENEX 文件/ZIP | ENEX、图片 |
| Google Keep | Takeout ZIP、JSON | 文本、清单、标签 |
| Microsoft OneNote | Microsoft Graph Token、HTML/ZIP | 页面 HTML 转 Markdown |
| 思源笔记 | 本机内核 API、Markdown 目录/ZIP | Markdown |
| 语雀 | 文件/目录 | 已导出的 Markdown、HTML、ZIP |
| FlowUs 息流 | 文件/目录 | Markdown、HTML、CSV、ZIP |
| 飞书文档 | 文件/目录 | 已转换的 Markdown、HTML、CSV、ZIP |
| flomo 浮墨笔记 | HTML/ZIP | 每条 memo、时间戳、图片 |
| 通用导入 | 文件/目录 | Markdown、HTML、JSON、CSV、XLSX、ENEX、ZIP |

Logseq Graph、MindBubble 标准 JSON 等可使用通用导入。

## API 连接说明

- Notion：创建 Internal Integration，将待导入页面共享给 Integration，再输入 Token。
- OneNote：输入具有 Notes.Read 用户委托权限的有效 Microsoft Graph Access Token。已实现读取页面与文本；尚未配置 OAuth 一键登录，图片附件的保真度有待扩展。
- 思源笔记：在同一设备上运行思源内核，复制「设置 → 关于」中的 API Token。读取地址固定为 http://127.0.0.1:6806。移动端建议使用 Markdown 导出文件。
- 语雀、FlowUs、飞书：目前使用导出文件入口，开放平台账号授权方式仍需后续实现。飞书原生 Docx、Word、PDF 需要先转换成受支持格式。

以上 API 是主动触发的单次读取，令牌只保存在导入窗口内存里。OAuth 一键连接、自动定期同步、Android 系统分享接收和 iOS Share Extension 需后续实现。

## 增量与冲突

扫描后预览新增、更新、未变化、冲突。冲突可以保留本地、采用来源或另存副本。相同来源再次导入时沿用相同来源标识；不同 Vault、账号或集合可以通过「增量导入设置」使用不同标识。

来源记录保存在 import-ledger.json 中。相对图片存入 MindBubble 内容寻址附件库，文件与图片可参与 WebDAV 同步。

## 手机和平板

Android/iOS 可以选择已有的 ZIP 或其他导出文件。文件夹型来源的持久授权和后台监听需要进一步适配 Android SAF 和 iOS 安全作用域，不应将桌面文件夹扫描视作移动端持续同步。

首页刷新功能独立于日期，Windows 还支持 F5。
