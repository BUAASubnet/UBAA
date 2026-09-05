# 测试策略

测试按证据层级和生产领域组织；不同层级不能互相冒充。根测试文件负责注册，领域子文件承载行为与合成
数据；下表列出实际入口，阶段验证与最终候选证据统一见[当前迁移状态](../migration/status.md)。

| 层级 | 当前位置 | 证明内容 |
|---|---|---|
| Core 单元/合同 | `crates/ubaa-core/src/**` 内单元测试、`crates/ubaa-core/tests/` | DTO、解析、加密向量、错误、URL、Cookie、Session CAS、路线与 facade 行为 |
| 脱敏 Fixture | `fixtures/`、`crates/ubaa-test-support/src/fixtures.rs` | 最小合成 payload 的解析形状与敏感标记拒绝；不证明真实上游当前行为 |
| Rust Mock 集成 | `crates/ubaa-test-support/tests/auth.rs`、`readonly.rs` | 精确方法/URL/参数/Header/分页、认证顺序、缓存并发和 Direct/WebVPN 路线锁定 |
| CLI 合同 | `apps/ubaa-cli/tests/cli_contract.rs` | Clap/help、human/JSON schema v10、旧 v9 envelope 拒绝、路线诊断、脱敏、写确认和退出语义 |
| CLI 二进制/Core-live | `apps/ubaa-cli/tests/binary_e2e.rs`、`apps/ubaa-cli/tests/core_live_runtime.rs`、`apps/ubaa-cli/src/bin/core_live/{main,args,evidence,steps}.rs` | facade-only 宿主、真实进程 stdout/stderr、缺凭据/auto 拒绝、安全摘要与会话清理 |
| 结构与 Shell 合同 | `scripts/tests/layout.sh`、`contract-versions.sh`、`references.sh`、`flutter-toolchains.sh`、`live-launchers.sh`、`facade-test-contract.sh` | index/工作树结构棘轮、公开版本、refs 副作用边界、工具链完整输出与失败退出码、凭据 stdin、构建失败/信号清理与测试注入关闭态 |
| FRB bridge | `crates/ubaa-flutter-bridge` 测试、`packages/ubaa_bindings/test/` | typed DTO/错误、panic 归约、公开 schema 快照和 codegen 零漂移 |
| Dart domain/app/platform | `packages/ubaa_domain/test/`、`packages/ubaa_app/test/`、`packages/ubaa_platform/test/` | 模型、状态机、bridge 投影、生命周期、权限/凭据/照片 typed 边界 |
| 写入协调与宿主接线 | `packages/ubaa_app/test/write_coordinator_test.dart`、`app_write_lifecycle_test.dart`、`write_readback_reentry_test.dart`；`packages/ubaa_host/test/`；`packages/ubaa_ui/test/write_coordination_test.dart` | 唯一状态机、单次消费、取消/过期、注销/重建失效、回读重入与 UI 命令完整性 |
| Widget/golden | `packages/ubaa_ui/test/` | 十二领域页面、loading/empty/failure/stale、查询、写确认、响应式、明暗主题和可访问性 |
| 宿主 integration | `apps/ubaa_flutter/integration_test/app_flow_test.dart` | 脱敏 backend 下的登录、十二项查询、十项写入 prepare/确认/单次 commit/读取核对 |
| 原生构建/产物 | Flutter 五平台 CI、本机 artifact check、OHOS API26 无签名门禁 | 宿主可构建及最小包结构；不证明签名、安装、实体设备或真实账号链路 |
| 真实只读 | `scripts/live/verify.sh` + `scripts/live/core-live.sh` | Direct/WebVPN 各自单客户端的当前 Core 协议矩阵；只输出安全摘要 |

## 确定性门禁

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

`just check` 当前运行 Shell `bash -n`/可用的 ShellCheck、layout/contract-version/refs/flutter-toolchains/live 合同、layout 与
公开版本 checker、锁定 Cargo
元数据、格式、Clippy、workspace 测试、构建、Rustdoc 与
差异检查；Flutter/codegen 独立运行。focused test 必须先证明本次行为，完整门禁只证明没有发现其它回归。

阶段 14A 的 [Flutter 工具链合同](../../scripts/tests/flutter-toolchains.sh) 只在临时目录构造假 SDK 与 Git，
不运行真实 Flutter；六项回归覆盖长多段 stdout 完整消费、错误或空首行版本、错误 commit、保留真实命令
失败退出码，以及 OHOS 同样的输出约束。工具链检查不能因只取首行而提前关闭输出管道，也不能屏蔽 pipefail。
修复提交 `7b8eed3a` 的六项合同、完整 `just check` 和两个改动脚本的 ShellCheck 0.11.0 已通过；新候选
完整验收须将 ShellCheck 加入 PATH，实际执行全仓静态检查，不沿用工具缺失时的 SKIP。

`23066064` 与 `c21a12dd` 随后补齐全仓 ShellCheck：静态 source 使用 `-x -P SCRIPTDIR`，OHOS 命令路径
明确引用，根目录定位失败立即返回，两处否定匹配改为显式失败断言。字面 Markdown、生成标记和 trap
间接调用只有定点诊断注释；全仓 ShellCheck 0.11.0 与完整 `just check` 已通过。

CLI [照片输入测试](../../apps/ubaa-cli/src/io/input.rs) 覆盖原文件和同尺寸替换文件的身份区别；跨平台实现
通过稳定 `same_file::Handle` 持有初检文件，Unix 继续检查设备与 inode，大小限制与安全错误不放宽。
本地 Unix 回归不能证明 Windows stable 编译通过；合同 workflow 的 Windows Rust job 必须单独通过。

前次候选 `d43c177` 的 19 项本地门禁和五平台原生 CI 成功不覆盖其合同 CI 失败。修复后必须以新候选完整
SHA 重跑本地与两条 workflow，不预填最终 PASS；失败和重跑日志按独立尝试目录保留，见[当前状态](../migration/status.md)。

## 行为变更与来源对照

每个认证、读取或写入行为先在两个冻结来源和安全实时证据中确认事实，再增加会失败的脱敏 Fixture/Mock/解析
测试。无等价协议时记录“不适用”；来源冲突时停止具体边界并写 decision log。纯文件移动不得修改测试名称、
数量、golden 字节、公开 schema、文案、key、semantics 或调用顺序。

公开 DTO 出现破坏性类型变化时不得沿用旧版本号静默输出：Phase 11C 将 Bykc 未知签到状态显式建模后，
CLI envelope 从 schema v2 升为 v3，合同测试要求全部成功、失败、参数错误、聚合和诊断输出使用 v3，并拒绝
旧 v2 envelope。Phase 11D 又将 Signin 原始状态改为可空、加入 typed 资格/目标和写结果分支，因此当时公开
envelope 显式升为 schema v4，真实 dispatcher 合同覆盖确定 true/false 与 `outcome_unknown` 并拒绝旧 v3。
Phase 11E 将 LibBook 座位状态改为可空整数，以 typed `reserveEligibility/reserveTarget` 取代
`isAvailable`，并加入确定的 `LibBookReserveResult`，因此当时 CLI envelope 显式升为 schema v5、
Flutter bridge contract 显式升为 v4。Phase 11F 又将 LibBook booking `status` 改为可空整数，加入
typed `cancelEligibility/cancelTarget`，并让取消请求携带本地 `id/page/limit` 同页 authority 上下文；
当时 CLI envelope 因此显式升为 schema v6、Flutter bridge contract 升为 v5，合同测试拒绝旧
schema v5/bridge v4。该测试范围不包含磁盘 `session.json`；其 schema v2 由 Session/CAS 测试独立保护，
`config.toml` 继续使用版本 1。

Phase 11G 将 Cgyy 时段 `reservationStatus` 改为可空整数，以 typed
`reservationEligibility/reservationTarget` 取代 `isReservable`，并把预约结果收窄为安全收据；当时 CLI
envelope 显式升为 schema v7、Flutter bridge contract 升为 v6，合同测试拒绝旧 schema v6/bridge v5。
该升级仍不改变磁盘 `session.json` schema v2 或 `config.toml` 版本 1。

Phase 11H 为 Cgyy 订单增加 typed `cancelEligibility/cancelTarget/cancelledTarget`，并以 caller-pinned
列表/详情 API 固定取消后的原路线双回读；当时 CLI envelope 显式升为 schema v8、Flutter bridge
contract 升为 v7，合同测试拒绝旧 schema v7/bridge v6。取消测试另外固定 0-based 首页、原子
路线匹配、本次局部结果证明、generation-safe UI 刷新与“回读失败不重发写”。磁盘版本仍不变。

Phase 11I 为 Ygdk 项目增加 typed `submitEligibility/submitTarget`，将 prepare 请求收紧为完整 target、
canonical 时间和必需照片，并加入 expected-route 原子提交与 caller-pinned 概览/记录回读；当时 CLI envelope 显式升为 schema v9、Flutter bridge contract 升为 v8，
合同测试拒绝旧 schema v8/bridge v7。

Phase 11J 为 Evaluation 课程增加 typed `submitEligibility/submitTarget`，把 prepare 请求收紧为非空、有序、
无重复的 targets，并新增 `success/failure/outcomeUnknown/unattempted` 四态逐项结果及 caller-pinned 原路线回读；
当前 CLI envelope 显式升为 schema v10、Flutter bridge contract 升为 v9，合同测试拒绝旧 schema v9/bridge v8。
该阶段的 typed 实现与本地确定性门禁已在 `4b0dcb0` 落地；整轮结构治理的最终候选与远端证据仍单独记录。

Phase 11K 的 `WriteCoordinator` 同时服务生产链与旧 `WriteFlowController` 类型别名。app 测试覆盖旧方法
签名/错误码、prepare/cancel/confirm 单次消费、未知结果回读、失效晚到结果与同步通知重入；Host 测试覆盖
生产接线和平台位置等待期间注销，UI 测试覆盖状态外部所有权及缺任一写命令时默认拒绝。UI 测试 harness
只连接真实 coordinator 与脱敏 callback，不复制业务状态机；对 app 的依赖仅存在于 UI 的 dev dependencies。

## 写入测试边界

十项用户写入分别由领域合同、共享协调器和宿主测试保护；任何确定性证据都不授权真实操作：

1. Core/CLI 证明精确请求、默认拒绝和 `--confirm-write`；
2. bridge/app/UI 证明 typed prepare 不提交、取消无副作用、确认只提交一次；
3. `outcome_unknown` 或 commit 异常不自动重试，要求先读取核对；
4. 宿主 integration 使用脱敏 fake backend，不访问真实账号；
5. 每次真实写入仍需具体操作、目标、路线和时间授权，并立即使用读取接口核对。

历史单次授权写探针不自动证明当前提交、另一条路线或另一项操作。

LibBook 预约另由 Core/Bridge/App/UI 回归固定三条边界：确定业务拒绝作为 `success=false` 返回；发送后的
`outcome_unknown` 保留 Core 稳定 code/kind/安全 message 且强制不可重试；确定成功与未知结果都会在不重放
写请求的前提下刷新 `libbookBookings`，供用户核对。

LibBook 取消回归必须另外固定：canonical `status=1` 为 allowed、`6/8` 为 denied，其余为 unknown；
`statusName` 改动不影响资格；prepare 与 commit 都 fresh 读取 action 指定的同一 `page/limit` 并唯一匹配
booking ID；最终取消 wire 只有 `{id}` 且恰好发送一次。确定 false、发送后 unknown、重复 commit 和生命周期
失效均消费一次性 intent；成功或 unknown 只刷新同一预约页一次。响应分页缺失、畸形、非正或别名冲突必须
在 cancel 前失败；未知成功文案不能默认成功，公开成功/失败/终态结果不得包含 raw message 或敏感标记。
prepare/commit 读取 `/v4/member/seat` 时的非成功 envelope 也必须覆盖含个人数据、token 和控制字符的失败
fixture，并同时断言 Core、CLI human/JSON 与 Bridge 只输出固定安全文案、不会发送最终 cancel。

Cgyy 预约回归必须固定：缺失或畸形 `reservationStatus`/占用字段为 unknown，明确可用状态与完整唯一身份才
产生 allowed target，denied/unknown 均不产生 target；非 canonical、重复或不完整的站点/空间/时段身份也
必须失败关闭。Flutter 只接受一至两个同站点、日期、空间和空间组、时段 ID 与 raw ordinal 各自唯一且相邻的
typed action，AppController、直接 BridgeBackend 和 Core preflight 的绕过路径分别覆盖。prepare 与 commit
都 fresh 读取同一目标 authority，验证码重试只发生在最终发送前，最终 reservation submit 恰好一次；
确定成功的可选附加数据仅为安全收据，发送后不确定只输出不可重试 `outcome_unknown`；重复 commit、
raw message、验证码材料、完整订单和个人信息均不得跨公开边界。

## 真实只读与发布证据

CI 不接收真实凭据。Direct 与 WebVPN 必须人工串行运行，按“操作 × 路线”记录 PASS/FAIL/BLOCKED/
NOT_APPLICABLE；父集合为空且有同批次证据时才允许 N/A。`auto` 只有 Mock 路由证据。Cgyy 的
`static_fallback` 必须明确来源，不能计作上游接口成功。

Fixture/Mock、Flutter build、simulator、golden、无签名 HAP 和产物上传分别证明不同层级；都不能替代实体
设备、硬件安全存储、签名、公证、商店发布或真实写后核对。
