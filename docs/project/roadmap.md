# UBAA 2 路线图

本页写给维护者和贡献者，说明 UBAA 2 的长期方向和产品交付顺序。当前阶段目标见[目标](goal.md)，已实现和已验证的内容见[项目现状](status.md)，架构细节见[架构导读](../architecture/overview.md)。

## 愿景：一个核心，多个宿主

UBAA 2 不再扩展旧版 KMP 工程，而是重构为“Rust 核心 + 多种宿主”：

| 宿主 | 平台 | 状态 |
|---|---|---|
| 图形界面 | Android、iOS、HarmonyOS、Windows、macOS、Linux | 已实现，准备发布 v2.0.0 |
| 桌面命令模式 | 随 Windows、macOS、Linux 应用提供，与图形界面共用账号和本机数据；Linux 支持没有图形界面的 SSH 环境 | 已实现 |
| SDK | Rust、Flutter/Dart，以后可能扩展到 Node.js、Kotlin、Swift、ArkTS | 长期方向 |
| MCP Server | 供本地 Agent 调用 | 长期方向 |

所有宿主由同一个 Rust Core 驱动，业务逻辑不放在任何 UI 框架里。网络只保留直连和学校 WebVPN 两种方式，旧版的服务器中转模式和 Ktor Server 已移除。

## 分工原则

- **Rust Core** 负责一切与业务正确性有关的内容：认证、直连与 WebVPN 协议、Cookie 与会话、加密签名、HTML/JSON 解析、各业务 API、稳定的数据模型与错误。Core 不依赖任何 UI 或移动平台 API。
- **Flutter** 负责界面、导航和交互。HarmonyOS 使用 OpenHarmony Flutter 分支，需要锁定 Flutter OH、HarmonyOS SDK、DevEco Studio 和插件版本。平台差异集中在插件层。
- **桌面命令模式** 与图形界面复用同一套无界面应用服务，命令定义和输出格式由公共 Rust 命令库维护。命令不需要先打开窗口，也不需要后台常驻进程。设计见[桌面共享服务](../design/desktop-shared-state.md)。

## 产品交付顺序

| 交付 | 用户得到什么 | 状态 |
|---|---|---|
| 日程界面 | 汇总学校安排与自建事项，查看、编辑、完成和导出 `.ics` | 已实现 |
| 统一命令模式 | 图形界面与终端共用账号和数据 | 已实现 |
| 北航云盘 | 浏览、管理、上传下载、分享与回收站 | 已实现 |
| 日程同步 | 多台设备经云盘合并自建事项和本地标记 | 已实现，默认关闭 |
| 应用服务 | 更新检查、定向公告、经同意的产品改进统计（[ADR 0008](../adr/0008-app-service-worker.md)） | 已实现，待生产部署 |
| v2.0.0 发布 | 六平台正式安装包 | 进行中，见[发布流程](../runbooks/flutter-release.md) |

以后的范围：本地通知、自然语言添加日程、多语言 SDK、MCP Server。

## MCP Server（长期）

MCP Server 复用 Rust Core，不重新实现业务 API。第一阶段只提供本地 `stdio` 方式和只读工具，例如 `get_schedule`、`get_grades`、`get_exams`、`list_assignments`、`search_classrooms`、`get_library_seats`、`get_announcements`。

```text
Agent -> stdio -> ubaa-mcp -> Rust Core -> 直连 / WebVPN
```

选课、签到、预约、评教提交等有副作用的操作，必须单独设计确认机制，默认不允许 Agent 执行。

## 计划怎么拆

产品计划按“用户能实际操作并验收的结果”划分。实现步骤、缺陷修复、平台验证和独立审查都放在同一个交付里，不再拆成新的产品阶段。完成条件见[开发命令](../development/commands.md#检查选择与完成条件)。
