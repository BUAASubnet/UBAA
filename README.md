# UBAA 2

UBAA 2 是面向北京航空航天大学服务的跨平台客户端。Rust Core 是唯一协议、认证、路线、Cookie、Session、
加密、解析和业务规则实现。CLI 与 Rust bridge 的生产业务调用只经 facade，CLI 自有命令、JSON/human 渲染
和退出策略；Dart 与平台宿主只经 bridge 使用 Core。

## 当前状态

当前目标见[阶段目标](goal.md)，长期规则由 [AGENTS.md](AGENTS.md)定义。现行模块与目录见[代码组织](docs/architecture/code-organization.md)，结果与剩余验收边界见[当前状态](docs/migration/status.md)。结构治理与此前整体 UI/设备/发布验收分别记账。

2026-09-07 已完成本地可维护性治理：统一错误语义、增加安全诊断与严格门禁，并整理可共享交接证据。
该历史阶段见[验收记录](docs/migration/evidence/2026-09-07-maintainability.md)。真实账号与设备验证遵守 [AGENTS 授权规则](AGENTS.md#真实账号与验收范围)，历史任务记录不能提供当前授权。

- Rust Core 与 CLI 已实现认证、Direct/WebVPN/Auto 路由、双路线会话、用户中心、十二项业务读取和十项写入协议；
- Windows、macOS、Linux、Android、iOS 使用官方 Flutter 共享 Dart/UI，HarmonyOS 使用锁定的 OHOS fork；
- 十二项读取页面、typed 查询及十项写入流程已有 Fixture/Mock、Rust、Dart、widget/golden 与脱敏宿主
  integration 阶段证据；Evaluation typed 批量提交已在阶段 11J `4b0dcb0` 落地，阶段 11K `b6ff2c7`
  已统一 Dart 写入协调，结构治理的最终候选验证仍单独记录；
- Direct 与 WebVPN 的历史真实证据只覆盖对应提交的 Core-live 只读矩阵，不代表本轮真实 App 账号链路或真实写入；
- 系统安全材料与统一加密缓存已接入，原生运行按平台分别验收；实体设备、签名、公证、商店上传和真实业务写入均不由模拟器或只读结果证明。

当前公开合同版本为 CLI JSON schema v12 与 Flutter bridge contract v42；这两个版本都与磁盘
`session.json` schema v2、`config.toml` 版本 1、业务缓存 schema v6 相互独立。

产品代际名 UBAA 2 与包的 SemVer、平台构建号和合同版本相互独立，发布规则见[版本约定](docs/development/conventions.md#版本号与依赖)。

官方更新与二次开发的应用标识、签名材料、本机配置及 CI 字段见[应用签名配置](docs/runbooks/app-signing.md)。

当前状态及证据边界见[迁移与交付状态](docs/migration/status.md)。代码组织治理的当前权威是
[代码与目录组织设计](docs/architecture/code-organization.md)和
[现行模块决策](docs/adr/0006-explicit-dart-modules.md)及[操作作用域决策](docs/adr/0007-operation-scopes-and-verification.md)。

## 能力范围

用户中心之外，当前业务域包括：

- 课表、考试、成绩、空闲教室；
- SPOC、希冀作业、课堂签到；
- 阳光打卡、图书馆座位、博雅课程、场馆预约、教学评教。

读取能力由 Core/CLI/FRB/Flutter typed 链路消费。写入能力包括博雅选课/退选/签到签退、课堂签到、图书馆
预约/取消、场馆预约/取消、阳光打卡和教学评教。真实写入默认不执行；每次必须由用户对具体操作、目标、
路线和时间单独授权，结果不确定时禁止自动重试。

## 仓库结构

| 位置 | 职责 |
|---|---|
| `crates/ubaa_core` | 领域、认证、路线、会话、协议、解析、读写与 facade |
| `crates/ubaa_flutter_bridge` | facade 到 FRB 的稳定 typed 投影；不暴露内部协议状态 |
| `crates/ubaa_test_support` | 脱敏 fixture、Mock transport 与确定性集成支持 |
| `apps/ubaa_cli` | human/JSON schema v12 命令行宿主与只读 Core-live 入口 |
| `apps/ubaa_flutter` | Windows/macOS/Linux/Android/iOS 官方 Flutter 薄宿主 |
| `apps/ubaa_ohos` | HarmonyOS/OHOS fork 薄宿主与 API26 runner |
| `packages/ubaa_domain` | Dart 稳定领域模型 |
| `packages/ubaa_app` | 应用状态、bridge adapter 与写入协调 |
| `packages/ubaa_host` | 共享 AppController 生命周期、平台能力注入与 UI callback 接线 |
| `packages/ubaa_platform` | 平台能力边界、共享错误策略与有界本地诊断 |
| `packages/ubaa_ui` | 共享页面、查询、确认、响应式与可访问性 UI |
| `packages/ubaa_bindings` | FRB 机械生成 Dart 输出和 Cargokit 平台构建支持 |
| `scripts` | 按副作用分类的 bootstrap、check、build、live、release 与确定性合同入口 |
| `docs` | 架构、合同、开发命令、迁移证据与运行手册 |

完整文档入口见[文档索引](docs/index.md)。

用户网站源码见 [UBAA 使用指南](docs/site/index.md)。运行 `npm ci`、`npm run docs:dev` 可本地编辑，
`npm run docs:build` 构建并检查站内链接。GitHub Pages 启用与分支切换见[网站维护手册](docs/runbooks/docs-site.md)。

修改协议先定位 Core 的对应领域；修改展示投影定位 `ubaa_app` 的 `bridge/features`；修改写入生命周期定位
`ubaa_app` 的 `write` 与 `controller`；修改界面定位 `ubaa_ui`。共享 `WriteState`/`WriteOutcome` 位于
`ubaa_domain`，`WriteCoordinator` 是应用层唯一生产写状态机；宿主向 UI 注入状态及 prepare/cancel/confirm
命令，UI 不保存另一份待确认意图，也不从展示文本推断写资格。

UI 的[应用页面](packages/ubaa_ui/lib/src/app/)、[领域组件](packages/ubaa_ui/lib/src/features/)、[查询](packages/ubaa_ui/lib/src/common/filters/)和[详情接线](packages/ubaa_ui/lib/src/common/details/)通过独立 library 组织；widgets.dart 只显式导出公共组件。应用协调见 [controller](packages/ubaa_app/lib/src/controller/)，Bridge 领域适配见 [bridge/features](packages/ubaa_app/lib/src/bridge/features/)。

常用入口：`just source-files` 定位源码；`just flutter-test ubaa_app test/features/grades` 执行领域回归。完整验证见[测试策略](docs/development/testing.md)。

## CLI 快速开始

```bash
just refs-bootstrap # 仅首次缺少冻结引用时运行；允许联网创建
just quality-tools-bootstrap # 显式准备固定的开发质量工具依赖
just refs
cargo build --locked --workspace
cargo run --locked -p ubaa-cli -- --help
```

普通登录会同时准备内部 Direct 与 WebVPN 路线；密码只通过不回显输入或 stdin 读取，不能放入 argv。

```bash
cargo run --locked -p ubaa-cli -- auth login --username YOUR_USERNAME
cargo run --locked -p ubaa-cli -- auth status
cargo run --locked -p ubaa-cli -- user show
cargo run --locked -p ubaa-cli -- schedule terms
cargo run --locked -p ubaa-cli -- grades list --term 2025-2026-1
cargo run --locked -p ubaa-cli -- auth logout
```

默认 Session 位于操作系统的用户私有配置目录；隔离测试可使用 `--config-dir <path>`。CLI 每次 JSON 成功或
失败只输出一个 schema-v12 信封，合同见[认证与用户合同](docs/contracts/auth-and-user.md)和
[CLI JSON Schema](docs/contracts/cli-json.schema.json)。该输出版本独立于磁盘存储合同；当前 Flutter bridge contract 为 v42。
图书馆、场馆、阳光与教学评教的 typed 资格、prepare/commit、单次发送、未知结果和原路线回读规则，统一见 [Bridge 写入合同](docs/contracts/flutter-bridge.md#6-写-intent)。CLI、Bridge 与缓存格式的兼容边界分别见对应合同。

## 开发与验证

工具安装见[开发环境](docs/development/setup.md)，Dart/Flutter 调用规则见 [AGENTS](AGENTS.md#项目工具链入口)。日常检查、完整维护验收、CI 实际范围、平台构建及真实只读命令统一见[开发命令](docs/development/commands.md)。测试分层、golden 与人工入口见[测试策略](docs/development/testing.md)。

真实验证只执行已获授权的功能与路线，结果按候选单独记录。Fixture、Mock、CI 或历史成功均不能替代当前真实协议结果，真实写入仍受逐次具体授权及发送后禁止自动重试的规则限制。

## 安全边界

`examples/ubaa_old/`、`examples/buaa-api/`、`.env.local`、运行时 Session、验证码、真实响应和凭据始终只读且不得提交。
宿主不得调用 Core 私有协议模块、拼接上游 URL、读取 Cookie/Token 或关闭 TLS 校验。无签名构建不能称为
正式发布，确定性写入流程不能称为真实写入成功。

项目自身采用 [MIT 许可证](LICENSE)。移植代码、协议参考及随仓库保留的第三方源码见[第三方声明](THIRD_PARTY_NOTICES.md)。
