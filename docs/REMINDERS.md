# 自动浮现与提醒

MindBubble 有两套独立的抽取状态：

- **首页手动刷新**：按刷新按钮或 Windows F5，重新抽取首页的一组笔记。
- **自动浮现提醒**：从整个笔记库单独抽取一条笔记的标题，桌面展示主题化独立浮窗，手机展示本地系统通知。**绝不更新首页的选择状态或触发主页刷新**。

## 设置

「管理泡泡」→「设置」→「自动浮现」：

| 项目 | 行为 |
| --- | --- |
| 自动浮现 | 默认关闭，启用后调度下一批提醒 |
| 浮现间隔 | 15–1440 分钟的非线性滑条，默认 120 分钟；15–60m 每 5m，1–3h 每 15m，3–6h 每 30m，6–12h 每 1h，12–24h 每 2h |
| 免打扰 | 默认 23:00–08:00，支持跨午夜；跳过提醒且不补发 |
| 桌面位置 | 四角可选，默认右下角 |
| 桌面停留 | 5、10、20、30 秒，默认 10 秒 |
| 托盘后台运行 | 启用提醒时可选择关闭主窗口后继续运行 |
| 开机启动 | 使用项目现有的桌面开机启动设置 |

设置保存到每台设备的 SharedPreferences；浮现权重继承笔记的 appearanceFrequency。自动浮现选择器具有独立的近期重复抑制历史。

## 平台执行

| 平台 | 调度和展示 | 交互 |
| --- | --- | --- |
| Windows | Flutter 后台定时器；Win32 独立 Topmost 提醒窗口、通知区域托盘 | Ocean 圆形蓝色 Bubble / 小红书暖白便签条；点击显示主窗并打开对应笔记 |
| macOS | Flutter 定时器；NSPanel 独立浮动面板、系统状态栏入口 | 两套主题样式，点击打开笔记 |
| Linux | Flutter 定时器；GTK 独立浮窗、GTK 托盘入口（依赖桌面环境的托盘支持） | 两套主题样式，点击打开笔记 |
| Android | 预安排 48 次非精确 AlarmManager 提醒；通知通过 BroadcastReceiver 展示；重启时恢复尚未到期的提醒 | 系统通知标题为 Bubble Title；点击跳转对应笔记；Android 13+ 请求通知权限 |
| iOS | 预安排 48 条 UNNotificationRequest，系统负责离线通知 | 系统通知标题为 Bubble Title；点击跳转对应笔记；首次启用申请授权 |

Android 为了降低电量和特殊闹钟权限负担使用 setAndAllowWhileIdle，系统节能策略可能延迟触发。iOS 后台无法保证无限期生成不同标题，预排程最多 48 条，应用重新启动/恢复、笔记或设置变更时更新队列；连续长期离线后需重新打开应用以继续补齐。

系统通知遵循 Android/iOS 原生 UI，具体外观由系统决定；桌面原生浮窗按 MindBubble 当前的 Ocean/小红书主题渲染。

## 提醒点击

Flutter MethodChannel 名称为 mindbubble/reminder。原生通知携带 bubbleId，点击将回传到主 Flutter 窗口，按 ID 从本地笔记库读取当前文档并显示 BubbleDetailDialog。已删除或不存在的笔记不再显示。主界面的 homeRefreshVersionProvider 不参与这一流程。

## 实现目录

- lib/services/reminder_settings.dart：间隔档位、免打扰、独立 ReminderSelector、预排程与设备配置
- lib/services/reminder_runtime.dart：跨平台调度、原生 Channel 调用、提醒点击分发
- lib/features/bubble_list/reminder_settings_panel.dart：设置界面
- android/app/src/main/kotlin/com/example/mind_bubble/MainActivity.kt：AlarmManager、Receiver、权限和冷启动点击
- ios/Runner/AppDelegate.swift：UNUserNotificationCenter 调度、用户点击事件
- windows/runner/reminder_bridge.cpp：Win32 弹窗、任务栏托盘与后台关闭行为
- macos/Runner/AppDelegate.swift：NSPanel 浮窗、NSStatusBar
- linux/runner/reminder_bridge.cc：GTK 浮窗、GtkStatusIcon

## 测试

- 浮现间隔上下限、非线性档位
- 跨午夜/同日免打扰、跳过时段不补发
- 未来 48 条的间隔、所选标题/ID 与权重抽样
- 设备设置持久化与独立选择器
- 设置面板渲染与桌面预览按钮

实际手机系统通知到达时间、OEM 后台策略、托盘环境行为，需在目标设备进行运行时验证。Mac/iOS 原生编译必须在 macOS 上执行；Windows 构建可在 Windows 开发环境验证。
