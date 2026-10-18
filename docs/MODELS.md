# 模型配置

“模型设置”分别保存文本模型和向量模型。文本模型负责笔记标题提炼、摘要和分析评分；向量模型负责语义相似度、偏好传播和推荐多样性。选择 API 文本模型时，仍可使用本机 Ollama 生成向量。

每套配置分别保存服务地址、模型名和 API 密钥。切换连接方式会保留已填写的配置。旧版 `embedding_endpoint`、`embedding_model` 自动迁移为独立的 Ollama 向量配置，原来的文本 API 密钥继续使用。

模型配置单独保存在应用本地元数据目录的 `model-settings` 中，首次读取会迁移原配置。旧版应用或其他设置项的偏好缓存不会再覆盖模型配置。

## 手机与桌面

手机提供 API 和账号登录。桌面额外提供 Ollama，以及已有的 Codex CLI 订阅方式。手机运行时也会拒绝调用从旧配置中保留下来的 Ollama 或 CLI。

- **ChatGPT**：通过 Codex 设备授权登录。打开授权页、输入应用显示的设备代码、返回应用。需要有 Codex 使用权限，并在 ChatGPT 安全设置中启用设备授权。应用使用 Codex Responses 服务生成文本，自动刷新登录凭据。
- **OpenRouter**：使用 S256 PKCE 授权。打开授权页，批准访问，再将页面给出的授权码粘贴回应用。账号可用于文本生成和向量生成，按 OpenRouter 账号的额度计费。
- ChatGPT 登录只用于文本生成。向量模型的账号方式使用 OpenRouter。

账号令牌和 API 密钥写入系统安全存储，普通模型配置中不包含这些凭据。退出登录会删除本机保存的账号凭据。

联网模型遵循环境代理和 Windows 手动系统代理；本机 Ollama 地址始终直连。

## 补全已有笔记的向量

配置向量模型后，点击“补全笔记向量”。应用跳过已经具有同一模型向量的笔记，为缺少向量或模型已经更换的笔记生成向量。这个操作保留现有标题提炼、摘要、分析评分、偏好和展示记录。

向量请求每批最多 4 篇；本机 Ollama 推理超时为 3 分钟。文本分析仍按 16 篇分批。补全由用户操作触发，启动应用时不等待本地模型加载。

向量模型使用“服务地址 + 模型名”标记向量空间。不同模型标识或不同维数的向量不参与相似度计算。切换向量模型后，可再次执行补全。

## 本机安装

当前测试配置为 `qwen3-embedding:0.6b`，通过 `http://127.0.0.1:11434` 提供服务，每条输出 1024 维向量。

- 运行程序：`D:\Models\ollama\runtime`
- 模型文件：`D:\Models\ollama\models`
- 启动脚本：`D:\Models\ollama\start-ollama.ps1`
- 临时目录、服务日志：`D:\Models\ollama`

Windows 当前用户登录时启动本地服务；服务只监听本机地址。`OLLAMA_MODELS` 用户环境变量指向上述模型目录。开机启动项名称为 `MindBubble Embeddings`。

`tool/audit_note_embeddings.dart` 是本地诊断入口，验证实际笔记的向量、隔离副本的存储读写和推荐计算。输出目录通过 `EMBEDDING_AUDIT_OUTPUT` 指定；运行前后检查正式笔记文件未变。该入口不启动同步或调用文本生成模型。

协议参考：[ChatGPT / Codex 授权](https://developers.openai.com/codex/auth)、[OpenRouter PKCE](https://openrouter.ai/docs/guides/overview/auth/oauth)。
