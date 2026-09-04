# UBAA 2

UBAA 2 是面向北京航空航天大学服务的跨平台客户端。Rust Core 是唯一协议、认证、路线、Cookie、Session、
加密、解析和业务规则实现。CLI 与 Rust bridge 的生产业务调用只经 facade，CLI 自有命令、JSON/human 渲染
和退出策略；Dart 与平台宿主只经 bridge 使用 Core。

## 当前状态

当前已完成“无签名执行目标”，但**没有完成正式发布**：

- Rust Core 与 CLI 已实现认证、Direct/WebVPN/Auto 路由、双路线会话、用户中心、十二项业务读取和十项写入协议；
- Windows、macOS、Linux、Android、iOS 使用官方 Flutter 共享 Dart/UI，HarmonyOS 使用锁定的 OHOS fork；
- 阶段 11I 提交上的十二项读取页面、typed 查询及十项写入流程已有 Fixture/Mock、Rust、Dart、
  widget/golden 与脱敏宿主 integration 证据；Ygdk typed 提交已通过本地确定性门禁，最终候选绑定尚未完成；
- Direct 与 WebVPN 的当前真实证据只覆盖 Core-live 只读矩阵，不代表真实 App 账号链路或真实写入；
- 正式签名、证书、公证、商店上传、实体设备、原生安全存储 handler 和真实写入核对仍是后置条件。

当前公开合同版本为 CLI JSON schema v9 与 Flutter bridge contract v8；这两个版本都与磁盘
`session.json` schema v2、`config.toml` 版本 1 相互独立。

当前状态及证据边界见[迁移与交付状态](docs/migration/status.md)。代码组织治理的当前权威是
[代码与目录组织设计](docs/architecture/code-organization.md)和
[实施计划](docs/superpowers/plans/2026-09-03-code-organization.md)。

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
| `crates/ubaa-core` | 领域、认证、路线、会话、协议、解析、读写与 facade |
| `crates/ubaa-flutter-bridge` | facade 到 FRB 的稳定 typed 投影；不暴露内部协议状态 |
| `crates/ubaa-test-support` | 脱敏 fixture、Mock transport 与确定性集成支持 |
| `apps/ubaa-cli` | human/JSON schema v9 命令行宿主与只读 Core-live 入口 |
| `apps/ubaa_flutter` | Windows/macOS/Linux/Android/iOS 官方 Flutter 薄宿主 |
| `apps/ubaa_ohos` | HarmonyOS/OHOS fork 薄宿主与 API26 runner |
| `packages/ubaa_domain` | Dart 稳定领域模型 |
| `packages/ubaa_app` | 应用状态、bridge adapter 与写入协调 |
| `packages/ubaa_platform` | 平台路径、权限、凭据和照片 typed 边界 |
| `packages/ubaa_ui` | 共享页面、查询、确认、响应式与可访问性 UI |
| `packages/ubaa_bindings` | FRB 机械生成 Dart 输出和 Cargokit 平台构建支持 |
| `scripts` | 按副作用分类的 bootstrap、check、build、live、release 与确定性合同入口 |
| `docs` | 架构、合同、开发命令、迁移证据与运行手册 |

完整文档入口见[文档索引](docs/index.md)。

## CLI 快速开始

```bash
just refs-bootstrap # 仅首次缺少冻结引用时运行；允许联网创建
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
失败只输出一个 schema-v9 信封，合同见[认证与用户合同](docs/contracts/auth-and-user.md)和
[CLI JSON Schema](docs/contracts/cli-json.schema.json)。该输出版本独立于磁盘存储合同；`session.json` 仍为
schema v2，`config.toml` 仍为版本 1。当前 Flutter bridge contract 为 v8；图书馆预约记录的 `status` 为
nullable int，并由 Core 提供 typed `cancelEligibility/cancelTarget`。取消 action 在本地携带
`id/page/limit` 以便 prepare、commit 和写后读取核对使用同一页，但最终上游取消正文仍只有 `id`。
场馆时段的 `reservationStatus` 同样为 nullable int，只有 Core 明确给出 `allowed` 和完整
`reservationTarget` 时才生成 `CgyyReserveAction`。Flutter 场馆预约输入只接受一至两个同站点、日期、空间、
空间组且 raw ordinal 唯一相邻的 action；prepare 与 commit 都重新读取资格，最终非幂等提交最多发送一次，
成功结果至多附带安全收据，发送后无法判定时返回不可重试的 `outcome_unknown`；两者都不公开验证码材料、
完整订单或个人信息。
场馆取消同样只消费 Core 派生的 `cancelEligibility/cancelTarget`；prepare 与 commit 均
重新读取同 ID 订单，并按上海时区严格校验开始前四小时截止点。最终取消只在同一
原子路线解析中发送一次；确定成功或 `outcome_unknown` 都固定原路线回读第一页列表与
同 ID 详情，只有两者都带 Core 严格派生的已取消证明时才标记已核对，回读失败绝不重发写请求。
阳光打卡同样只消费 fresh overview 派生的 typed `submitTarget(classifyId,itemId)`；prepare 不上传，commit
在 Core 的 expected-route 原子入口中固定路线、Session/credential generation、fresh authority、单次 upload
和单次 final。上传与最终提交均禁止自动重试；确定成功和 `outcome_unknown` 只在 intent 原路线各执行一次
caller-pinned overview 与 records 首页读取，安全收据只允许可选正 `recordId`。

## 确定性验证

```bash
just refs
just layout-check
just contract-version-check
just check-sensitive
just check
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
just flutter-check
git diff --check
```

`just layout-check` 对手写源码执行 1000 行/16 个直属文件的结构棘轮；`just contract-version-check` 纯静态
交叉校验 CLI/Bridge 常量、JSON Schema、Dart 接受版本与当前文档；`just check` 当前覆盖布局/refs/live
Shell 合同、上述版本门禁、Rust/Cargo、CLI、构建、文档和差异，不包含 Flutter/codegen，并先对全部 Shell
执行 `bash -n`，环境有 ShellCheck 时再执行静态检查。后两项必须独立运行。平台构建、
无签名 OHOS HAP 与发布前置命令见[开发命令](docs/development/commands.md)和
[Flutter 发布 Runbook](docs/runbooks/flutter-release.md)。

## 真实只读验证

```bash
just verify-live mode=direct
just verify-live mode=webvpn
```

真实验证只允许显式 Direct 或 WebVPN，并在一个固定路线 `RouteClient` 中串行执行。凭据来自被忽略的
`.env.local`，只经 stdin 使用；Core-live 只输出路线、操作、状态、稳定错误码、耗时、数量和依赖原因等
安全摘要。`auto` 只保留 Core/Mock 确定性证据。Fixture、Mock、CI 或历史成功都不能替代当前真实协议结果。

## 安全边界

`ubaa_old/`、`examples/`、`.env.local`、运行时 Session、验证码、真实响应和凭据始终只读且不得提交。
宿主不得调用 Core 私有协议模块、拼接上游 URL、读取 Cookie/Token 或关闭 TLS 校验。无签名构建不能称为
正式发布，确定性写入流程不能称为真实写入成功。
