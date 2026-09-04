# 测试策略

测试按证据层级组织；不同层级不能互相冒充。当前结构治理会逐步让测试目录镜像生产领域，但在对应阶段提交前，
下表使用当前 HEAD 的真实路径。

| 层级 | 当前位置 | 证明内容 |
|---|---|---|
| Core 单元/合同 | `crates/ubaa-core/src/**` 内单元测试、`crates/ubaa-core/tests/` | DTO、解析、加密向量、错误、URL、Cookie、Session CAS、路线与 facade 行为 |
| 脱敏 Fixture | `fixtures/`、`crates/ubaa-test-support/src/lib.rs` | 最小合成 payload 的解析形状与敏感标记拒绝；不证明真实上游当前行为 |
| Rust Mock 集成 | `crates/ubaa-test-support/tests/auth.rs`、`readonly.rs` | 精确方法/URL/参数/Header/分页、认证顺序、缓存并发和 Direct/WebVPN 路线锁定 |
| CLI 合同 | `apps/ubaa-cli/tests/cli_contract.rs` | Clap/help、human/JSON schema v3、旧 v2 envelope 拒绝、路线诊断、脱敏、写确认和退出语义 |
| CLI 二进制/Core-live | `apps/ubaa-cli/tests/binary_e2e.rs`、`apps/ubaa-cli/tests/core_live_runtime.rs`、`apps/ubaa-cli/src/bin/core_live/{main,args,evidence,steps}.rs` | facade-only 宿主、真实进程 stdout/stderr、缺凭据/auto 拒绝、安全摘要与会话清理 |
| 结构与 Shell 合同 | `scripts/tests/layout.sh`、`references.sh`、`live-launchers.sh` | index/工作树结构棘轮、refs 副作用边界、凭据 stdin、构建失败/信号清理 |
| FRB bridge | `crates/ubaa-flutter-bridge` 测试、`packages/ubaa_bindings/test/` | typed DTO/错误、panic 归约、公开 schema 快照和 codegen 零漂移 |
| Dart domain/app/platform | `packages/ubaa_domain/test/`、`packages/ubaa_app/test/`、`packages/ubaa_platform/test/` | 模型、状态机、bridge 投影、生命周期、权限/凭据/照片 typed 边界 |
| Widget/golden | `packages/ubaa_ui/test/` | 十二领域页面、loading/empty/failure/stale、查询、写确认、响应式、明暗主题和可访问性 |
| 宿主 integration | `apps/ubaa_flutter/integration_test/app_flow_test.dart` | 脱敏 backend 下的登录、十二项查询、十项写入 prepare/确认/单次 commit/读取核对 |
| 原生构建/产物 | Flutter 五平台 CI、本机 artifact check、OHOS API26 无签名门禁 | 宿主可构建及最小包结构；不证明签名、安装、实体设备或真实账号链路 |
| 真实只读 | `scripts/live/verify.sh` + `scripts/live/core-live.sh` | Direct/WebVPN 各自单客户端的当前 Core 协议矩阵；只输出安全摘要 |

## 确定性门禁

```bash
just refs
just layout-check
just check-sensitive
just check
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
just flutter-check
git diff --check
```

`just check` 当前运行 Shell `bash -n`/可用的 ShellCheck、layout/refs/live 合同、layout checker、锁定 Cargo
元数据、格式、Clippy、workspace 测试、构建、Rustdoc 与
差异检查；Flutter/codegen 独立运行。focused test 必须先证明本次行为，完整门禁只证明没有发现其它回归。

## 行为变更与来源对照

每个认证、读取或写入行为先在两个冻结来源和安全实时证据中确认事实，再增加会失败的脱敏 Fixture/Mock/解析
测试。无等价协议时记录“不适用”；来源冲突时停止具体边界并写 decision log。纯文件移动不得修改测试名称、
数量、golden 字节、公开 schema、文案、key、semantics 或调用顺序。

公开 DTO 出现破坏性类型变化时不得沿用旧版本号静默输出：Phase 11C 将 Bykc 未知签到状态显式建模后，
CLI envelope 从 schema v2 升为 v3，合同测试要求全部成功、失败、参数错误、聚合和诊断输出使用 v3，并拒绝
旧 v2 envelope。该测试范围不包含磁盘 `session.json`；其 schema v2 由 Session/CAS 测试独立保护。

## 写入测试边界

十项用户写入已有确定性闭环，但这不授权真实操作：

1. Core/CLI 证明精确请求、默认拒绝和 `--confirm-write`；
2. bridge/app/UI 证明 typed prepare 不提交、取消无副作用、确认只提交一次；
3. `outcome_unknown` 或 commit 异常不自动重试，要求先读取核对；
4. 宿主 integration 使用脱敏 fake backend，不访问真实账号；
5. 每次真实写入仍需具体操作、目标、路线和时间授权，并立即使用读取接口核对。

历史单次授权写探针不自动证明当前提交、另一条路线或另一项操作。

## 真实只读与发布证据

CI 不接收真实凭据。Direct 与 WebVPN 必须人工串行运行，按“操作 × 路线”记录 PASS/FAIL/BLOCKED/
NOT_APPLICABLE；父集合为空且有同批次证据时才允许 N/A。`auto` 只有 Mock 路由证据。Cgyy 的
`static_fallback` 必须明确来源，不能计作上游接口成功。

Fixture/Mock、Flutter build、simulator、golden、无签名 HAP 和产物上传分别证明不同层级；都不能替代实体
设备、硬件安全存储、签名、公证、商店发布或真实写后核对。
