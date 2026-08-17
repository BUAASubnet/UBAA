# UBAA 2 迁移路线图

状态：规划稿  
目标分支：`ubaa2`  
旧版参考：`ubaa_old/` 与 Git Tag `ubaa-v1-reference`

## 1. 目标

UBAA 2 的目标不是继续扩展现有 KMP 工程，而是将 UBAA 重构为一个“核心 SDK + 多种宿主”的产品：

- 移动端：Android、iOS、HarmonyOS
- 桌面 GUI：Windows、Linux、macOS
- 桌面 CLI：Windows、Linux、macOS
- SDK：可被 Rust、Flutter/Dart、Node.js，以及后续 Kotlin、Swift、ArkTS 应用依赖
- Agent 集成：作为 MCP Server 被本地 Agent 调用
- 网络模式：最终只保留直连和 WebVPN，移除服务器中转模式及旧 Ktor Server

最终产品形态应当由同一个 Rust 核心驱动，而不是由某个 UI 框架承载业务逻辑。

## 2. 目标架构

```text
                         +----------------------+
                         |      UBAA Core       |
                         | Rust library/crates  |
                         +----------+-----------+
                                    |
       +----------------------------+-----------------------------+
       |                            |                              |
 +-----v------+              +------v------+                 +-----v------+
 | Flutter UI |              |   CLI       |                 | MCP Server |
 | 5 targets  |              | Rust binary |                 | stdio/HTTP |
 +-----+------+              +-------------+                 +------------+
       |
 +-----v-------------------------+
 | Flutter OpenHarmony host      |
 | ArkTS/native plugins as needed|
 +-------------------------------+
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

### 2.3 CLI

CLI 直接调用 Rust Core，不依赖 Flutter：

```text
ubaa auth login
ubaa schedule current
ubaa grades list --term 2025-2026-1
ubaa judge assignments
ubaa classroom search --date 2026-09-01
```

CLI 既是用户工具，也是跨平台协议回归和故障诊断工具。所有 CLI 命令必须支持结构化 JSON 输出，方便脚本和 Agent 使用。

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
