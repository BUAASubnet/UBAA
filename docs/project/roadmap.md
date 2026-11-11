# UBAA 2 迁移路线图

状态：长期路线图；长期规则见 [AGENTS.md](../../AGENTS.md)，当前阶段目标见 [goal.md](goal.md)，实际验收结果见[迁移状态](status.md)
目标分支：`ubaa2`
旧版参考：`examples/ubaa_old/` 与 `examples/buaa-api/`，固定提交见 [references.md](../protocol/references.md)；不依赖不存在的 Tag

## 1. 目标

UBAA 2 的目标不是继续扩展现有 KMP 工程，而是将 UBAA 重构为一个“核心 SDK + 多种宿主”的产品：

- 移动端：Android、iOS、HarmonyOS
- 桌面 GUI：Windows、Linux、macOS
- 桌面命令模式：随 Windows、Linux、macOS App 提供，与 GUI 共用应用服务和本机数据；Linux 同时支持无图形 SSH 环境
- SDK：可被 Rust、Flutter/Dart、Node.js，以及后续 Kotlin、Swift、ArkTS 应用依赖
- Agent 集成：作为 MCP Server 被本地 Agent 调用
- 网络模式：最终只保留直连和 WebVPN，移除服务器中转模式及旧 Ktor Server

最终产品形态应当由同一个 Rust 核心驱动，而不是由某个 UI 框架承载业务逻辑。

多语言 SDK 和 MCP 属于长期扩展方向。近期产品交付集中在日程、统一命令模式和北航云盘，具体范围见下文。

## 2. 目标架构

```text
Flutter GUI / OHOS GUI      桌面命令入口
          \                   /
           共享的无界面应用服务
         账号、恢复、日程与用例编排
                    |
             typed Bridge / FRB
                    |
              Rust Core facade <--- SDK / MCP（后续）
                    |
          协议、业务、会话、缓存与存储

平台能力提供：安全材料、目录、文件选择与保存
公共命令库提供：参数、human/JSON 输出与退出码
```

### 2.1 Rust Core

Rust Core 应负责所有与业务正确性有关的内容：

- 认证、CAS/SSO、直连和 WebVPN 协议
- Cookie、Session、重定向和请求重试策略
- RSA、AES、MD5 等加密和签名
- HTML、JSON、验证码和业务数据解析
- 课表、考试、成绩、签到、SPOC、希冀、评教、研讨室、图书馆等业务 API
- 稳定的 DTO、错误模型和能力声明
- 可注入的 HTTP、存储、日志和时间抽象

Rust Core 不得依赖 Flutter、Tauri、Node.js、Android、iOS 或 HarmonyOS UI API。

### 2.2 Flutter 应用

Flutter 负责界面、导航、交互和平台展示：

- Android、iOS、Windows、Linux、macOS 使用 Flutter 官方目标
- HarmonyOS 使用 OpenHarmony Flutter 分支
- 通过 FFI 或平台插件调用 Rust Core
- 平台差异集中在插件层，不散落到业务代码

OpenHarmony Flutter 不是 Google Flutter 主仓库的标准目标，必须锁定 Flutter OH、HarmonyOS SDK、DevEco Studio 和插件版本，并维护独立的兼容性清单。

### 2.3 App 命令模式

桌面命令入口与 GUI 复用同一套无界面应用服务，经 Bridge/facade 使用 Rust Core。同机同用户共用账号、凭据、会话、缓存和日程，命令不要求 GUI 窗口预先打开，也不需要后台常驻服务：

```text
ubaa auth login
ubaa schedule current
ubaa grades list --term 2025-2026-1
ubaa judge assignments
ubaa classroom search --date 2026-09-01
```

命令保留 human/JSON 输出、管道、退出码、超时和取消。参数与序列化由公共 Rust 命令库维护。macOS/Windows 采用无窗口 Engine，Linux 使用同一 Dart 服务的 AOT 运行组件，Linux 命令入口不加载显示服务。平台运行依据与验收范围见[共享设计](../design/desktop-shared-state.md)。

独立 Rust CLI 宿主已从产品整合分支迁出，原有效测试覆盖保留在统一命令实现中。`core-live` 作为独立协议验证工具保留。统一命令模式的实现状态见[当前状态](status.md)。

### 2.4 MCP Server

MCP Server 复用 Rust Core，不重新实现业务 API。第一阶段优先提供本地 `stdio` 运行方式：

```text
Agent -> stdio -> ubaa-mcp -> Rust Core -> 直连/WebVPN
```

第一阶段只暴露只读工具：

- `get_schedule`
- `get_grades`
- `get_exams`
- `list_assignments`
- `search_classrooms`
- `get_library_seats`
- `get_announcements`

选课、签到、预约、评教提交等有副作用的能力必须单独设计确认机制，不能默认允许 Agent 执行。

## 3. 产品交付顺序

| 交付 | 用户结果 | 依赖 |
|---|---|---|
| 日程界面 | 汇总学校与自建事项，查看、编辑、完成和导出 `.ics` | 复用已有 Core、Bridge 与日程服务，补齐 GUI 与文件保存 |
| 统一命令模式 | GUI 与终端使用同一账号和数据，按保存设置恢复会话 | 收尾共享生命周期候选并整合，再完成三桌面入口和命令接线 |
| 北航云盘 | 浏览、管理、上传下载、分享与回收站 | 逐操作协议证据、Core 能力、文件适配及界面；无需等待旧 CLI 清理 |
| 日程同步 | 多设备合并自建事项和本地覆盖，失败显示待同步 | 云盘完整目录发现、每设备独立快照发布与逐记录合并；不依赖共同文件的并发覆盖 |
| 应用服务 | 更新检查、定向公告，以及经同意的遥测（上游健康度、错误、功能使用、性能、活跃与年级） | Cloudflare Worker 与 D1/KV、Core 独立 `app_service` 模块、首启隐私政策；见 [ADR 0008](../adr/0008-app-service-worker.md) |

日程周/月视图、冲突提示和宽屏布局沿用既有设计，可独立于同步推进。本地通知、自然语言添加、多语言 SDK 与 MCP 留在后续范围。

产品计划以可操作验收的结果划分。内部的实现步骤、缺陷修复、平台验证和独立审查不递归扩展成产品阶段。每项功能分别记录主线实现、候选状态和验证范围，完成条件沿用[开发命令](../development/commands.md#检查选择与完成条件)。
