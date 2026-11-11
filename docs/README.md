# UBAA 开发者文档

这里是 UBAA 开发者和维护者的文档入口。普通用户请看使用指南 [www.ubaa.top](https://www.ubaa.top)，它的源码在 [`site/`](site/)。

## 从这里开始

| 我想…… | 看这里 |
|---|---|
| 在本机跑起来 | [快速上手](development/getting-started.md) → [开发环境](development/setup.md) |
| 了解整体架构 | [架构导读](architecture/overview.md) → [代码组织](architecture/code-organization.md) |
| 提交第一个 PR | [贡献指南](../CONTRIBUTING.md) |
| 知道该跑哪些检查 | [开发命令](development/commands.md) |
| 看懂文档里的术语 | [术语表](development/glossary.md) |
| 了解项目进展 | [项目现状](project/status.md)、[当前目标](project/goal.md)、[路线图](project/roadmap.md) |
| 修改校园协议 | 先读 [AGENTS.md 来源对照门禁](../AGENTS.md#来源对照门禁)，再到[协议依据](protocol/README.md)找对应功能 |

## 按修改内容定位代码

| 修改内容 | 生产代码 | 测试 |
|---|---|---|
| 协议、解析和操作资格 | [Core features](../crates/ubaa_core/src/features/)、[facade](../crates/ubaa_core/src/facade/) | Core 测试、`ubaa_test_support` |
| 命令参数与输出 | [ubaa_command](../crates/ubaa_command/src/) | 命令合同测试与二进制端到端测试 |
| Rust 与 Dart 之间的数据和句柄 | [Bridge API](../crates/ubaa_flutter_bridge/src/api/) | Rust Bridge、Bindings 与生成检查 |
| Dart 侧的领域适配 | [Bridge 领域](../packages/ubaa_app/lib/src/bridge/features/) | [App 领域测试](../packages/ubaa_app/test/features/) |
| 会话、恢复和缓存 | [Controller](../packages/ubaa_app/lib/src/controller/) | [session](../packages/ubaa_app/test/session/)、[recovery](../packages/ubaa_app/test/recovery/)、[cache](../packages/ubaa_app/test/cache/) |
| 写入与回读 | [写协调器](../packages/ubaa_app/lib/src/write/)、[Controller write](../packages/ubaa_app/lib/src/controller/write/) | [App write 测试](../packages/ubaa_app/test/write/) |
| 功能页面 | [UI features](../packages/ubaa_ui/lib/src/features/) | [UI 领域测试](../packages/ubaa_ui/test/features/) |
| 导航、查询与通用展示 | [UI app](../packages/ubaa_ui/lib/src/app/)、[common](../packages/ubaa_ui/lib/src/common/) | [query](../packages/ubaa_ui/test/query/)、[navigation](../packages/ubaa_ui/test/navigation/)、[visual](../packages/ubaa_ui/test/visual/) |
| 平台能力与宿主接线 | [Host](../packages/ubaa_host/lib/)、[Platform](../packages/ubaa_platform/lib/) | 各包测试；[原生能力清单](../scripts/integration-tests.json)与[覆盖边界](development/testing.md) |
| 应用服务 Worker | [services/app_service](../services/app_service/) | Worker 测试，见[应用服务手册](runbooks/app-service.md) |

## 文档目录

| 目录 | 内容 | 读者 |
|---|---|---|
| [site/](site/) | 使用指南网站（VitePress），部署到 www.ubaa.top | 用户 |
| [development/](development/) | 快速上手、环境、命令、测试、工程规范、开发约定、术语表 | 贡献者 |
| [architecture/](architecture/) | 架构导读、代码组织、Core 边界、平台矩阵 | 贡献者 |
| [contracts/](contracts/) | 稳定合同：认证、连接、只读功能、Bridge、命令 JSON、离线缓存、日程、云盘、应用服务 | 贡献者 |
| [adr/](adr/) | 架构决策记录 | 贡献者 |
| [design/](design/) | 现行产品与界面规格 | 贡献者 |
| [runbooks/](runbooks/) | 操作手册：签名、发布、部署、真实验证、本地诊断 | 维护者 |
| [project/](project/) | 当前目标、路线图、项目现状 | 维护者 |
| [protocol/](protocol/README.md) | 协议来源对照、冻结参考、决策记录 | 改协议的开发者与 agent |
| [archive/](archive/README.md) | 已被取代的计划、状态快照和验收证据，只用于追溯 | 追溯历史时 |

写文档前请读[文档规范](development/conventions.md#文档规范)。

## 架构决策（ADR）

| 编号 | 决策 |
|---|---|
| [0001](adr/0001-rust-core-cli-first.md) | Rust Core 与命令行优先 |
| [0002](adr/0002-serde-and-injectable-transport.md) | Serde 与可注入 transport |
| [0003](adr/0003-url-crypto-cookie-session.md) | URL、加密、Cookie 与凭据 |
| [0004](adr/0004-verified-http-and-html-parser.md) | 经过验证的 HTTP 与 HTML 解析依赖 |
| [0005](adr/0005-flutter-frb-six-platforms.md) | Flutter + FRB 六平台宿主 |
| [0006](adr/0006-explicit-dart-modules.md) | 显式 Dart 模块 |
| [0007](adr/0007-operation-scopes-and-verification.md) | 操作作用域与验证闭包 |
| [0008](adr/0008-app-service-worker.md) | 应用服务 Worker |
