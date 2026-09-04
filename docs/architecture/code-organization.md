# 代码与目录组织设计

状态：2026-09-03 已批准执行；2026-09-05 已完成 Phase 11H，当前阶段为 Phase 11I

基线提交：`11a296904d623b33da0a83157f714a7c5912ca8d`

适用范围：当前 `ubaa2` 分支的 Rust Core/CLI/Test Support、Flutter/FRB/OHOS、测试、脚本、文档与 CI

## 1. 目标

本轮实施可验证的结构治理：保持外部合同、上游协议事实和安全边界不变，消除超大手写文件、拥挤源码
目录、生成代码审查噪声、测试定位困难和过期文档入口；同时关闭会继续迫使代码回到聚合文件的结构性
根因。行为敏感的收敛只做“已有行为的 typed 化与单一所有权”，必须先有来源对照和失败的行为测试，
不得借结构治理重新解释上游协议。完成后，维护者应能从领域名直接定位 Core、CLI、bridge、应用层、
UI 与测试，不必在数千行聚合文件中搜索。

本轮硬目标如下：

1. 受版本控制的手写代码文件不得超过 1000 行；FRB 机械生成文件与锁定的 Cargokit 快照除外。
2. 一个目录直属的手写代码文件不得超过 16 个；平台工具链规定目录和生成目录除外。
3. `lib.rs`、`mod.rs` 与 Dart package 入口只承担声明、组合和稳定导出，不继续承载跨领域实现。
4. 大型协议按认证、传输、读取、写入、解析、算法和测试拆分，但不合并不同协议的同名 helper。
5. 测试目录镜像生产领域；一个失败测试可从文件路径判断所属领域和证据层级。
6. FRB 生成路径、公开 DTO 名、schema、golden 文件名和宿主入口行为默认保持稳定；公开合同确需破坏性
   变更时必须显式提升版本并记录原因，不得沿用旧版本号静默改变字段。
7. `just check`、Flutter/FRB 门禁、CLI E2E、敏感扫描和两条真实只读路线继续独立提供证据。
8. 生产宿主只依赖 Core `facade`；Core 不拥有 CLI 输出/退出策略，路线选择和 route state 各只有一个权威实现。
9. Flutter 生产写入只有一个状态机；UI 只消费 typed action eligibility，不从中文文案或展示字段反推资格。

设计批准时冻结的 CLI JSON schema v2 已完成阶段 04 的机械所有权迁移。Phase 11C 随后把 Bykc
`checkin` 从必填整数改为可空，并以含 `unknown` 的 `signEligibility`/`signOutEligibility` 取代两个布尔字段，
同时加入 `outcome_unknown` 封闭错误码；这些是有意且经来源/TDD 支持的破坏性合同变化。因此 CLI envelope
显式升级为 schema v3，bridge contract 同步从 v1 升为 v2，旧版本只作为历史证据保留。该版本升级不涉及
本地持久化，`session.json` 继续使用 schema v2。

Phase 11D 再次显式提升公开版本：Signin `signStatus` 改为可空并加入 typed eligibility/target，Flutter bridge
contract 使用 v3；CLI 成功数据加入 Signin 写结果并将今日 DTO 改为 fail-closed 形状，envelope/schema 使用
v4。确定业务 `success=false` 保持外层成功、CLI 退出 0；`outcome_unknown` 仍退出 5。两者必须分别测试。

Phase 11E 将 LibBook 座位 `status` 改为可空整数并加入 Core 派生的预约 eligibility/target，Flutter bridge
contract 使用 v4；CLI schema 使用 v5 并收录严格预约结果。预约 prepare/commit 必须按日期、时段和座位
唯一匹配 fresh authority，最终 confirm 只越过一次不可重放发送边界；磁盘 `session.json` 仍为 schema v2。

Phase 11F 将 LibBook booking `status` 改为可空整数，并加入 Core 派生的
`cancelEligibility/cancelTarget`；Flutter bridge contract 使用 v5，CLI schema 使用 v6。取消 action 保存
`id/page/limit`，prepare、commit 与 readback 必须读取同一页并唯一匹配目标；最终 cancel wire 仍只有 `{id}`
且只越过一次不可重放发送边界。`session.json` 保持 schema v2，`config.toml` 保持版本 1。

Phase 11G 将 Cgyy 时段 `reservationStatus` 改为可空整数，并加入 Core 派生的
`reservationEligibility/reservationTarget`；Flutter bridge contract 使用 v6，CLI schema 使用 v7。Flutter
预约输入只接受一至两个同站点、日期、空间和空间组、时段 ID/原始 ordinal 唯一且 ordinal 相邻的 typed
action。prepare 与 commit 都 fresh 复核资格，验证码重试只发生在最终写入前，最终 reservation submit 只
越过一次 non-idempotent 发送边界；成功结果至多附带安全收据，发送后无法判定时返回不可重试
`outcome_unknown`，两者都不公开验证码、完整订单或个人信息。`session.json` 保持 schema v2，
`config.toml` 保持版本 1。

Phase 11H 将 Cgyy 订单取消从展示状态/时间推断收口为 Core 派生的
`cancelEligibility/cancelTarget/cancelledTarget`；Flutter bridge contract 使用 v7，CLI schema 使用 v8。
prepare/commit 都 fresh 读取同 ID 详情并以上海时区复核四小时截止点；commit 只在 Core 内解析
一次路线并复用同一 runtime 越过一次 non-idempotent 发送边界。成功或结果未知后的列表/详情
双回读固定 intent 原路线，只消费本次局部 `cancelledTarget` 证明，不从旧 snapshot 或展示字段推断。

1000 行是阻止重新形成“几千行单文件”的硬门槛，不是推荐尺寸。普通实现文件优先控制在 300–600 行，
高内聚状态机或 DTO 清单可接近 800 行；接近硬门槛的文件不得继续吸收新领域。

## 2. 审查基线与量化结论

本轮先执行了 `git status --short --branch`、`just refs` 和完整 `just check`。工作树基线干净，冻结引用
分别为 `ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 与
`examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a`，完整 Rust/CLI/Shell 确定性门禁通过。
Flutter 独立审查同时运行了当前 `just flutter-check`，6 个 package/app 范围静态分析通过，140 个普通
Flutter 测试通过；该结果不包含宿主 integration、原生构建、签名或设备证据。

排除 FRB 生成文件与 Cargokit 后，当前共有 15 个超千行手写代码文件：

| 行数 | 文件 | 混合职责 |
|---:|---|---|
| 4030 | `packages/ubaa_ui/lib/src/widgets.dart` | 登录、壳、十二领域、查询、写确认和错误 UI；Phase 11A–B 已删除博雅选课与退选的字符串资格推断 |
| 3747 | `crates/ubaa-test-support/tests/readonly.rs` | 多领域请求序列、解析、缓存和路由测试 |
| 3222 | `packages/ubaa_ui/test/widgets_test.dart` | UI、查询、写入、golden、响应式和无障碍测试 |
| 2598 | `apps/ubaa-cli/src/lib.rs` | 两套 backend、adapter、执行器和渲染器 |
| 2031 | `crates/ubaa-core/src/facade/mod.rs` | 构造、认证、路由、全部读写和诊断客户端 |
| 1830 | `packages/ubaa_app/lib/src/bridge_backend.dart` | 全领域读取投影、写入和错误映射 |
| 1700 | `crates/ubaa-core/src/features/cgyy.rs` | 验证码、认证、HTTP、读写、日志与解析 |
| 1652 | `crates/ubaa-flutter-bridge/src/api/read.rs` | 读取 DTO、公开调用和全领域映射 |
| 1510 | `packages/ubaa_app/test/app_controller_test.dart` | 生命周期、认证、读取、写入和竞态测试 |
| 1424 | `apps/ubaa-cli/tests/cli_contract.rs` | help、schema、路由、脱敏与写阻止 |
| 1423 | `crates/ubaa-core/src/features/judge.rs` | 解析、认证、批处理、缓存和日期算法 |
| 1417 | `crates/ubaa-core/src/features/spoc.rs` | 认证、分页、详情、诊断、解析和日期算法 |
| 1165 | `crates/ubaa-test-support/tests/auth.rs` | 登录、生命周期、冲突与错误传输 |
| 1130 | `crates/ubaa-core/src/session/mod.rs` | 双路线协调、文件 CAS、权限、锁和安全校验 |
| 1001 | `apps/ubaa_flutter/integration_test/app_flow_test.dart` | 认证、查询、写入宿主流程 |

直属手写代码文件超过 16 个的目录有两个：

| 数量 | 目录 | 原因 |
|---:|---|---|
| 24 | `apps/ubaa-cli/src` | 参数、backend、执行、IO 和 binary 辅助全部平铺 |
| 20 | `crates/ubaa-core/src/features` | 大型领域实现、算法与共享状态并列平铺 |

FRB 生成 Dart/Rust 合计超过三万行，但每个文件都有生成标记、固定输出目录与零漂移门禁。它们是需要隔离
和标注的机械产物，不是需要人工拆分的业务代码。

## 3. 当前问题

### 3.1 高优先级结构问题

- `facade/mod.rs`、CLI `lib.rs` 与 `BridgeBackend` 都把“所有领域”集中在单个组合点，新增一个领域通常要在
  同一大文件中跨越合同、adapter、dispatch 和渲染逻辑。
- `facade` 内有 48 处路线 runtime 选择，固定路线与聚合路线又分别维护完整能力面；结构重复放大了漏接
  某一路线或某一宿主的风险。
- Cgyy、Judge 与 SPOC 把协议事实、传输编排、解析、缓存/并发和测试放在同一文件，任何纯解析修改都会
  暴露大量无关敏感协议上下文。
- Flutter typed DTO 到达 `BridgeBackend` 后很快被投影为通用字符串字段；UI 又集中在一个文件中消费全部
  领域。目录没有提供领域所有权，搜索结果和改动冲突面都过大。
- 大型测试入口按“readonly/widgets/controller”聚合，而不是按领域与行为镜像，导致 focused test 定位慢，
  共享 fake 也被埋在文件尾部。

### 3.2 中优先级信息架构问题

- CLI 参数文件已经拆出，但 `execution.rs` 与 `render.rs` 仍是薄壳，真正实现仍在 `lib.rs`，文件名对开发者
  有误导性。
- `session/mod.rs` 已有 `cookies/types/ports/storage` 子文件，却把大部分协调、文件存储与安全函数继续留在
  `mod.rs`，并由 `cookies.rs` 反向依赖父模块 helper。
- Rust bridge 手写 `read.rs` 同时定义 54 个读取 DTO、公开调用和 mapper；机械生成路径清晰，手写路径不清晰。
- 官方 Flutter 与 OHOS 的 185 行 composition root 基本重复，生命周期和 callback wiring 依赖人工同步。
- `README.md` 与工程规范仍描述旧的 Rust/CLI 只读范围；`docs/index.md` 未导航到重要 Flutter 合同、测试和
  决策文档；`status.md` 以 1697 行混合当前结论和历史流水。
- `goal.md` 声明每次合并执行 Flutter check/codegen，但已提交 GitHub Actions 没有对应共享 package 与
  零漂移 job；`just check` 名称也没有表达它只覆盖 Rust/Shell 确定性门禁。

### 3.3 必须独立取证和测试的结构根因

以下问题不是文件搬运可以安全决定的事项，但若不处理，最终仍会留下高优先级架构债。因此它们纳入本轮
后半段的独立行为阶段，不与机械移动混合：

- UI 仍按中文字段标签、状态文本、状态码和时间窗口决定部分写入口。每个受影响操作先完成两个冻结来源、
  当前 typed DTO 与已有测试的逐列对照，再让 Core/bridge 返回 typed action eligibility；UI 不再解析展示文本。
- `WriteFlowController` 与主 UI 内部写状态形成两套实现。先用 app/widget 测试锁定 prepare、confirm、commit、
  outcome unknown、receipt/readback、刷新与取消语义，再让生产 UI 只使用一个 `WriteCoordinator`。
- `runtime` 与 feature state/types 存在概念依赖循环。先锁定 `Arc` 身份、代次、锁、TTL、容量、fork 共享和并发
  语义，再把 route state 移到低层 `internal/route_state`；只改变所有权和依赖方向。
- Core 公共模块允许宿主绕开 `facade`。先建立 `facade::testing` 的最小稳定测试注入面，迁移 Test Support、CLI
  与 bridge，再将 `auth/features/ports/session/config/connection` 收窄为 crate-private；这是本工作区的内部 API
  收口，不改变 facade DTO 身份。
- facade 有 48 处 runtime 选择且存在两套路线解析。先建立 direct/webvpn/auto、session ready/not-ready、成功/
  失败/回退的等价矩阵，随后集中为唯一 runtime selector 和 route resolver；网络调用顺序、错误码和退出语义
  必须逐项等价。
- Core `output.rs` 与 `ErrorCode::exit_code` 把 CLI 展示/进程策略放在领域库。阶段 04 先锁定当时的 JSON
  schema v2、human 输出、stdout/stderr 与 exit matrix，再将策略整体迁入 CLI `io`，Core 只保留结构化错误；
  Phase 11C 的 schema v3 是后续独立记录的行为合同升级，不改写该迁移事实。

任何阶段一旦出现来源不一致或未被测试解释的语义差异，立即停止实现，在 decision log 记录具体文件、锁定
提交和安全的实时观察；只有实时证据或适用冻结实现支持的行为可以进入生产代码。

## 4. 方案比较与选择

### 4.1 方案 A：一次性重写分层与行为模型

同时收窄 Core 公共面、统一路线算法、引入 typed presentation/action、统一写状态机并重建目录。终态理论上
最整齐，但会把协议、产品行为、状态机和物理移动混在同一 diff 中，无法证明失败来自搬运还是新语义，也
不符合冻结来源和分阶段提交要求。

### 4.2 方案 B：只格式化和切割文件

通过 `part`、`include` 或机械分段快速降低行数，不调整目录所有权和测试镜像。风险最低，但仍会保留“所有
领域共享一个入口”的搜索噪声与重复修改面，不能达到快速定位目标。

### 4.3 采用方案：结构棘轮下的纵向切片

先引入可测试的结构检查与当前违例基线；随后按测试、CLI、Core 基础设施、Core 复杂领域、FRB、Flutter
应用层、Flutter UI 的顺序逐块迁移。每个公共入口保留兼容导出，每次只移一个职责，阶段通过后从违例基线
删除对应路径。最终违例基线为空，CI 禁止重新引入超大文件和拥挤目录。

该方案允许首轮使用 Dart library `part` 保持私有 helper 与行为完全等价，但目标路径必须按领域命名；Rust
使用真实子模块与显式 re-export，禁止用长期 `include!` 把一个逻辑文件伪装成多个物理文件。

## 5. 目标目录结构

只展开本轮会改变或需要固定边界的部分；平台工具链规定的 Android/iOS/macOS/Linux/Windows/OHOS runner
目录保持原位。

```text
UBAA/
├── apps/
│   ├── ubaa-cli/
│   │   ├── src/
│   │   │   ├── lib.rs                     # 模块声明和稳定 re-export
│   │   │   ├── main.rs                    # 普通 CLI bootstrap
│   │   │   ├── command/
│   │   │   │   ├── mod.rs                 # Cli/Command 组合
│   │   │   │   ├── auth.rs
│   │   │   │   ├── academic.rs            # schedule/exam/grades/classroom
│   │   │   │   ├── assignments.rs         # spoc/judge/signin
│   │   │   │   ├── libbook.rs
│   │   │   │   ├── ygdk.rs
│   │   │   │   ├── bykc.rs
│   │   │   │   ├── cgyy.rs
│   │   │   │   └── evaluation.rs
│   │   │   ├── backend/
│   │   │   │   ├── mod.rs                 # 两个现有能力 trait
│   │   │   │   ├── fixed.rs               # RouteClient adapter
│   │   │   │   └── routed.rs              # UbaaClient adapter
│   │   │   ├── execute/
│   │   │   │   ├── mod.rs                 # 入口与公共投影
│   │   │   │   ├── aggregate.rs           # 双路线认证/状态/注销
│   │   │   │   ├── fixed.rs               # 固定路线 dispatcher
│   │   │   │   ├── routed.rs              # 聚合路线 dispatcher
│   │   │   │   └── features/
│   │   │   │       ├── mod.rs
│   │   │   │       ├── academic.rs         # schedule/exam/grades/classroom
│   │   │   │       ├── assignments.rs      # spoc/judge/signin
│   │   │   │       ├── libbook.rs
│   │   │   │       ├── ygdk.rs
│   │   │   │       ├── bykc.rs
│   │   │   │       ├── cgyy.rs
│   │   │   │       └── evaluation.rs
│   │   │   ├── io/
│   │   │   │   ├── mod.rs
│   │   │   │   ├── input.rs
│   │   │   │   ├── schema.rs               # CLI envelope owner；阶段 04 迁入时 v2，当前 v8
│   │   │   │   ├── human.rs
│   │   │   │   ├── error.rs                # 稳定错误 payload 与名称投影
│   │   │   │   ├── render.rs               # stdout/stderr 渲染与 Core 错误投影
│   │   │   │   └── exit_code.rs            # 进程退出策略只属于 CLI
│   │   │   └── bin/core_live/
│   │   │       ├── main.rs
│   │   │       ├── args.rs
│   │   │       ├── evidence.rs
│   │   │       └── steps.rs
│   │   └── tests/
│   │       ├── cli_contract.rs             # 薄入口
│   │       ├── cli_contract/{common,help,output,output_helpers,routing,writes,exit,libbook_cancel,cgyy_reservation}.rs
│   │       ├── binary_e2e.rs
│   │       └── core_live_runtime.rs
│   ├── ubaa_flutter/
│   │   ├── lib/main.dart                   # SDK/能力注入与 runApp
│   │   └── integration_test/
│   │       ├── app_flow_test.dart          # 单一测试入口
│   │       └── app_flow/{auth,query,write,support}.dart
│   └── ubaa_ohos/lib/main.dart             # OHOS SDK/能力注入与 runApp
├── crates/
│   ├── ubaa-core/src/
│   │   ├── lib.rs                          # 只导出 facade 与稳定基础类型
│   │   ├── facade/
│   │   │   ├── mod.rs                      # 稳定 facade 类型出口
│   │   │   ├── client.rs                   # 字段、open/with 构造
│   │   │   ├── auth.rs                     # prepare/login/status/logout
│   │   │   ├── routing.rs                  # 唯一路线解析与 runtime selector
│   │   │   ├── read/{mod,academic,services,assignments}.rs
│   │   │   ├── write/{mod,campus,reservations}.rs
│   │   │   ├── diagnostic.rs               # RouteClient
│   │   │   ├── testing.rs                  # transport/session 的最小测试注入合同
│   │   │   └── types.rs
│   │   ├── internal/
│   │   │   ├── mod.rs
│   │   │   ├── runtime.rs                  # runtime 构造，不依赖 feature
│   │   │   └── route_state/
│   │   │       ├── mod.rs
│   │   │       ├── cache.rs
│   │   │       ├── credentials.rs
│   │   │       └── classroom.rs
│   │   ├── session/
│   │   │   ├── mod.rs
│   │   │   ├── coordinator.rs
│   │   │   ├── file_store.rs
│   │   │   ├── file_safety.rs
│   │   │   ├── cookies.rs
│   │   │   ├── ports.rs
│   │   │   ├── storage.rs
│   │   │   └── types.rs
│   │   └── features/
│   │       ├── mod.rs
│   │       ├── cgyy/{mod,auth,http,captcha,read,write,parser,crypto,sign,tests}.rs
│   │       ├── judge/{mod,service,batch,parser,calendar,tests}.rs
│   │       ├── spoc/{mod,auth,list,detail,parser,crypto,calendar,tests}.rs
│   │       ├── bykc/{mod,auth,read,write,parser,tests}.rs
│   │       ├── libbook/{mod,service,parser,crypto}.rs
│   │       ├── ygdk/{mod,service,parser,upload}.rs
│   │       └── classroom.rs、evaluation.rs、grades.rs、schedule.rs、signin.rs、user.rs
│   ├── ubaa-flutter-bridge/src/api/
│   │   ├── read/
│   │   │   ├── mod.rs                      # DTO 继续保有 api::read 路径
│   │   │   ├── methods.rs
│   │   │   └── mappers.rs
│   │   ├── write/
│   │   │   ├── mod.rs                      # DTO 与 pending 类型保持 api::write 路径
│   │   │   ├── prepare.rs                  # 意图建立与各领域 prepare
│   │   │   ├── commit.rs                   # 一次性消费、复核与提交
│   │   │   ├── support.rs                  # 验证、canonical digest 与安全映射
│   │   │   ├── tests.rs                    # cfg(test) 根与唯一测试注入 helper
│   │   │   └── tests/{contract,bykc,cgyy_reservation,libbook,libbook_cancel,lifecycle,signin,validation}.rs
│   │   ├── client.rs
│   │   └── simple.rs
│   └── ubaa-test-support/
│       ├── src/{lib,fixtures,http,session}.rs
│       └── tests/
│           ├── auth.rs                     # 薄入口
│           ├── auth/{common,login,lifecycle,conflict}.rs
│           ├── readonly.rs                 # 薄入口
│           ├── readonly/{common,academic,classroom,cgyy,spoc,judge}.rs
│           ├── readonly/spoc/{list,auth,detail}.rs
│           ├── readonly/judge/{read,isolation,concurrency,retry}.rs
│           └── support.rs
├── packages/
│   ├── ubaa_domain/lib/src/
│   │   ├── models.dart                     # 旧路径的显式兼容 export
│   │   ├── common/{route,error,auth}.dart
│   │   ├── feature/{catalog,query,result}.dart
│   │   └── write/{actions,inputs,intent}.dart
│   ├── ubaa_app/lib/src/
│   │   ├── backend.dart                    # 旧路径的显式兼容 export
│   │   ├── app_controller.dart             # 旧路径的显式兼容 export
│   │   ├── bridge_backend.dart             # 旧路径的显式兼容 export
│   │   ├── backend/{unavailable,demo}.dart
│   │   ├── contracts/{backend,routing,query,write,lifecycle}.dart
│   │   ├── controller/{app_controller,error_mapper}.dart
│   │   ├── bridge/
│   │   │   ├── bridge_backend.dart         # 组合与接口实现
│   │   │   ├── common.dart
│   │   │   ├── read/{academic,assignments,bykc,libbook,cgyy,ygdk,evaluation}.dart
│   │   │   └── write/{prepare,commit}.dart
│   │   ├── write/
│   │   │   ├── coordinator.dart            # 唯一生产写状态机
│   │   │   ├── state.dart
│   │   │   ├── receipt_verifier.dart
│   │   │   └── cgyy_validation.dart        # action-only 场馆预约输入门禁
│   │   └── contracts/                      # 现有 backend 能力合同
│   ├── ubaa_host/
│   │   ├── pubspec.yaml
│   │   ├── lib/ubaa_host.dart              # 公共 barrel
│   │   ├── lib/src/{ubaa_app_host,lifecycle,callbacks}.dart
│   │   └── test/{ubaa_app_host,lifecycle}_test.dart
│   ├── ubaa_ui/lib/src/
│   │   ├── widgets.dart                    # library/part 声明和公共入口
│   │   ├── app/{splash,login,shell,profile}.dart
│   │   ├── common/{detail_fields,pagination,error_card}.dart
│   │   ├── features/{academic,assignments,bykc,libbook,cgyy,ygdk,evaluation}.dart
│   │   └── write/{forms,confirmation}.dart
│   └── ubaa_bindings/lib/src/rust/**        # FRB 机械生成，禁止手改
├── fixtures/
│   ├── README.md
│   ├── auth/
│   └── readonly/                            # 本轮保留现有路径，registry 覆盖全部 fixture
├── scripts/
│   ├── README.md                            # 每个入口的副作用、网络与凭据要求
│   ├── bootstrap/references.sh              # 可联网建立缺失冻结引用
│   ├── check/{references,layout,sensitive,flutter-toolchains,flutter-codegen,flutter-workspace}.sh
│   ├── build/{flutter,ohos}.sh
│   ├── live/{verify,core-live}.sh
│   ├── release/{preflight,verify-flutter-artifact}.sh
│   ├── tests/{layout,live-launchers}.sh
│   └── lib/{repo,live-features}.sh           # 只存真实共享且有测试的函数
└── docs/
    ├── index.md
    ├── architecture/code-organization.md
    └── migration/
        ├── status.md                        # 当前小型仪表盘
        ├── decision-log.md                  # 只追加裁决，当前状态不重复
        └── history/status-through-2026-09-02.md
```

以上是本轮目标成员的完整清单，不创建 `其余`、`support`、`misc` 等模糊占位目录。只有目标文件拥有真实实现、
类型或测试时才创建；无需拆分的小领域保持列出的单文件。同名 Rust `foo.rs` 与 `foo/mod.rs` 不得并存。

Rust integration test 的薄入口使用显式 `#[path = "auth/login.rs"] mod login;` 组装子文件，避免错误地假设
Cargo 会从 `tests/auth.rs` 自动解析 `tests/auth/mod.rs`。Dart 测试拆分为同一 library 的 `part` 文件，只有根
`*_test.dart` 被 test runner 独立发现，子文件不使用 `_test.dart` 后缀。

`just refs-bootstrap` 是唯一可以联网并创建缺失引用的入口；`just refs` 改为纯校验，只接受两个引用目录已
存在、HEAD 为锁定提交且工作树干净，不联网、不写目录。AGENTS、setup、CI、release-preflight 与开发文档
统一使用这两个不同语义的 recipe，任何验证阶段都只调用纯校验的 `just refs`。

## 6. 稳定接口与依赖方向

### 6.1 Rust

目标依赖方向为：`domain/error → ports/session/connection → internal runtime/route_state → auth/features → facade → hosts`。
`internal` 不得反向导入 feature；feature 只能通过低层 state 合同保存数据。

- `upstream` 与 `runtime` 继续 crate-private。
- CLI 与 Rust bridge 的生产源码只从 `facade` 及其稳定 DTO 出口调用 Core；需要的 route/error/domain 类型
  由 `facade` 重导出，类型身份不改变。crate 根的 `domain`/`error` 只保留稳定基础类型旧路径兼容，
  不提供 transport、session、route resolver、feature 实现或任何协议操作；生产宿主仍禁止使用这两个旧路径。
- `facade::testing` 仅在非默认 Cargo feature `test-contract` 下编译并标记 `#[doc(hidden)]`；只有
  `ubaa-test-support` 与专用测试目标可以启用。CLI、Flutter bridge 和发布构建不得启用该 feature。增加 Cargo
  metadata/源码架构测试，证明生产宿主不能导入 transport、session store 或测试构造器。完成迁移后，
  `auth/features/ports/session/config/connection` 均收窄为 crate-private，不保留“双入口”兼容层。
- 测试迁移不得为保留测试数量而复制或复活已淘汰的 resolver、会话适配器或错误分类器。白盒测试必须直接
  命中生产模块的真实私有实现；测试注入面只提供构造生产对象所需的类型闭包，不拥有第二套业务语义。
- `OutputEnvelope`、human/JSON 渲染和 exit code 完整迁入 CLI；Core 错误只表达领域/协议事实，不表达进程退出。
- facade 拆分允许多个 `impl UbaaClient`/`impl RouteClient`，字段所有权和网络调用顺序不变。
- 所有 facade 操作使用一个 `runtime_for(route)`；所有自动路线使用一个 `resolve_route`，路线等价矩阵是删除
  重复分派的前置门禁。
- 不把 Cgyy、SPOC、Judge 等协议的 `error/envelope/authentication` helper 合成共享实现，除非有单独来源证据。

### 6.2 Dart/Flutter

依赖方向保持：`hosts → ubaa_host → ubaa_app + ubaa_ui + ubaa_platform`，`ubaa_app → bindings + domain +
platform`，`ubaa_ui → domain`，`bindings → FRB`。

- `ubaa_domain.dart`、`ubaa_app.dart`、`ubaa_ui.dart` 的现有公共名字继续可导入。
- 首轮允许 `part` 文件共享 library-private helper；part 入口只负责 imports/parts/公共组合，不放回全部实现。
- `BridgeBackend` 仍是唯一共享手写 Dart 代码中直接依赖 `ubaa_bindings` 的生产 adapter。
- `ubaa_domain` 定义 typed action/eligibility；bridge 只映射 Core DTO，UI 不读取 label/value/status/time 决定写权限。
- `WriteCoordinator` 是唯一生产写状态机；AppController 和 UI 均不保存第二套 pending intent/receipt 状态。
- `ubaa_host` 具有独立 `pubspec.yaml`、lock、barrel 与测试；只抽取两个宿主逐字重复的 controller
  生命周期和 callback wiring，不拥有协议、凭据或平台实现。两个宿主只保留 SDK/平台能力注入和 `runApp`。
- 不新建根 Pub workspace；两个 app 以各自的 path dependency/lock 接入新 package。新 package 必须同时接入
  `flutter-check`、`release-preflight` 和五平台 CI 的现有 package 路径触发面。
- golden 文件不改名、不重录；结构提交中任何 PNG diff 都视为失败。

### 6.3 生成边界

- `crates/ubaa-flutter-bridge/src/frb_generated.rs` 与 `packages/ubaa_bindings/lib/src/rust/**` 原位保留。
- `.gitattributes` 标记 FRB 输出为 generated，降低语言统计与评审噪声。
- 手写 Rust `api/read` 拆分时，公开 DTO 继续定义在 `read/mod.rs`；只把 inherent methods 和 private mapper
  移到子模块，确保 FRB 类型路径不漂移。
- 手写 Rust `api/write` 同样把公开 DTO 定义留在 `write/mod.rs`，把 prepare、commit 与私有 support 分开；
  `tests/` 按合同、Bykc、intent 生命周期和输入验证分组；因 facade 架构门禁只豁免 `tests.rs`，所有
  `with_routing` 测试注入只留在该根文件，叶测试仅调用封装 helper。公开 `crate::api::write::*` 路径和测试
  叶名称不得变化。
- 每个 bridge 结构阶段都运行 `just flutter-codegen-check`；出现生成 diff 时停止并按 API 变更处理。

## 7. 结构棘轮

新增 `scripts/check/layout.sh`、对应 Shell 合同测试与 `just layout-check`：

- 合并扫描 tracked/index 文件与 `git ls-files --others --exclude-standard` 返回的未忽略 untracked 文件，保证提交前
  和暂存后都看得到新源码；
- 覆盖 `.rs/.dart/.kt/.kts/.ets/.ts/.tsx/.js/.java/.swift/.m/.mm/.c/.cc/.cpp/.h/.hpp/.sh`；
- 读取文件头识别 FRB 生成文件，显式排除锁定的 `packages/ubaa_bindings/cargokit/`；
- 报告超过 1000 行的文件和直属手写代码超过 16 个的目录；
- 通过 `scripts/layout-baseline.txt` 暂时接受本设计第 2 节列出的现有违例；
- 新违例、数量变化后未清理的陈旧 baseline 项、未知排除项都失败；
- 每个结构阶段删除已修复项，最终 baseline 只保留中文说明，不含违例路径；
- `just check` 与 CI 在 baseline 机制下从第一阶段起持续通过，而不是等到最后才发现结构回归。

该门禁只约束物理可维护性，不用行数替代职责审查。review 仍必须检查文件是否按领域拥有单一原因变化。

## 8. 测试与 TDD 策略

### 8.1 结构门禁自身

先添加 `scripts/tests/layout.sh` 并运行，确认因 checker 不存在而按预期失败；随后实现 checker，覆盖：

- 新超长手写文件被拒绝；
- 生成文件被豁免；
- 拥挤目录被拒绝；
- 已登记 baseline 被接受；
- baseline 陈旧项被拒绝；
- tracked、staged 与未忽略 untracked 源码均被扫描，ignored/generated/vendored 输入被排除；
- Swift、Objective-C、C/C++ 与 Header 等宿主源码不能绕过门禁；
- 合规仓库通过。

### 8.2 纯结构搬运

结构搬运的 RED 由 layout baseline 中对应违例提供；现有行为测试是 characterization，搬运前后必须保持绿色。
不为了制造失败而修改已经正确的行为断言。每个阶段执行：

1. 确认目标路径仍在 layout baseline 中；
2. 运行本领域 focused 行为测试并记录通过；
3. 只移动/提取一个职责；
4. 再运行 focused 测试；
5. 从 baseline 删除目标路径，运行 `just layout-check`；
6. 运行阶段全量门禁并单独提交。

### 8.3 行为差异升级

若拆分需要改变任一 URL/service、redirect/final URL、Cookie/session/token 作用域、HTTP 方法/精确参数、
Header/编码、加密/签名、DTO/解析容错、缓存/并发、重试、错误/退出或产品写资格，则必须：

1. 停止当前纯结构任务；
2. 在 `docs/migration/source-parity.md` 为该操作补齐两个冻结来源与实时证据栏；
3. 先添加脱敏 fixture/Mock/parser/widget 失败测试并确认预期失败；
4. 以最小实现修复；
5. 运行 focused、敏感扫描、完整确定性与适用实时只读门禁；
6. 使用独立行为提交，不与目录移动混合。

真实写入不属于结构验收；没有逐操作、逐目标授权时继续只运行 deterministic/Mock 写入测试。

## 9. 实施顺序

1. **P0 契约与 CI 先行。** 固化审查问题和目标树；修正 README、工程规范、feature matrix、docs index、`goal.md`
   门禁表述与 CI，使随后每个提交都在真实 Rust + Flutter/FRB + OHOS 契约下验证。精简当前 status 并原样归档
   历史，decision log 只保留裁决。
2. **治理与结构门禁。** 先写失败的 layout checker 合同测试，再实现 checker/baseline、generated 属性和门禁
   recipe；随后把十二个脚本按 bootstrap/check/build/live/release/tests 分类，更新 Justfile/workflow/runbook。
3. **先拆 Rust 测试。** 拆 Test Support `auth/readonly`，补全全部 fixture 的统一 registry 与脱敏覆盖。
4. **拆 CLI 并移出输出策略。** 移动 command/backend/execute/io 与 CLI contract 子模块；用 RED contract test
   固定 schema/stdout/stderr/exit matrix，将 Core `output.rs` 和 `ErrorCode::exit_code` 迁入 CLI；core-live 改为
   显式 binary 私有模块。
5. **拆 Core 基础热点。** 拆 facade 与 session；先移动实现，再用现有路线/会话测试证明 runtime、CAS 与清理不变。
6. **关闭 Core 边界债。** 建立 route 等价矩阵和 state 并发/身份测试，集中 runtime selector/route resolver，迁移
   state 到 `internal`；建立 `facade::testing` 后迁移所有宿主和测试，并收窄非 facade 公共模块。
7. **拆 Core 复杂领域。** 依次处理 Cgyy、Judge、SPOC、Bykc、Libbook 与 Ygdk；算法文件跟随所属领域，每个
   领域在 `source-parity.md` 有逐操作对照并运行 focused test。
8. **拆 FRB 手写读取 API。** 保留 DTO 定义路径，提取 methods/mappers，要求 codegen 零漂移。
9. **先拆 Flutter 测试。** 使用 library parts 将 widget/controller/integration 测试按领域分组，保持测试数量、名称和
   golden 不变。
10. **拆 Flutter domain/app/host。** 拆通用模型、BridgeBackend 领域 mapper；建立完整 `ubaa_host` package 和测试，
    两个宿主只保留平台注入；接入 lockfile、检查脚本、release-preflight 与五平台 CI。
11. **关闭 Flutter 行为耦合。** 逐操作来源对照和 RED test 后引入 typed eligibility，并在本阶段逐项完成 UI
    消费迁移、删除 label/value/status/time 权限解析；扩展并迁移到唯一 `WriteCoordinator`，覆盖
    intent/confirm/commit/outcome-unknown/receipt/readback/refresh/cancel，并删除 UI 内部第二套写状态。每个操作
    或状态机切换都是独立行为提交，不包含文件搬运。
12. **纯拆 Flutter UI。** 只把第 11 步已经收敛且全绿的 widget/form 按 app/common/features/write 移动；不再
    改变任何条件、状态、回调、文案、key、semantics、布局或 golden。
13. **信息架构收口。** 更新最终目录图、脚本索引、当前 status、decision log、来源对照与 CI 证据链接，删除临时
    audit/baseline 项。
14. **最终总审查。** 确认 layout baseline 为空，运行全部确定性、生成、宿主、原生构建、五平台 CI、两条只读
    live 门禁和独立代码审查；所有高/中问题必须关闭或具有本轮不能越过的明确外部证据阻塞。

测试先拆能降低随后生产拆分的 focused 成本；Core/CLI 先于 Flutter 可以先稳定 facade 出口，避免 Dart 层追随
中途路径；行为敏感阶段在物理边界稳定后独立执行，UI 最后只消费已经 typed 化的 domain/app 边界。

## 10. 验证门禁

### 10.1 每个阶段

```text
git status --short --branch
just refs
just layout-check
just check-sensitive
<本阶段 focused tests>
just check
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
just flutter-check
git diff --check
```

暂存前检查文件名与 diff，禁止包含 `ubaa_old/`、`examples/`、`.env.local`、session、Cookie、token、验证码、
个人数据、原始响应、构建缓存或签名材料。

### 10.2 Rust/CLI/Core 阶段

```text
cargo test --locked -p ubaa-cli --all-targets
cargo test --locked -p ubaa-core -p ubaa-test-support --all-targets
just check
```

### 10.3 Flutter/FRB/UI 阶段

```text
just flutter-check
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
<锁定 Flutter SDK> flutter test apps/ubaa_flutter/integration_test/app_flow_test.dart -d macos --ignore-timeouts
```

涉及 composition、package graph 或 native wiring 时，必须运行 macOS 宿主 integration、macOS/Android APK/iOS
simulator 本机构建及产物结构检查；Linux/Windows 由官方五平台 workflow 证明。`ubaa_host` 或任何宿主依赖变更
同时要求：

```text
<锁定 Flutter SDK> flutter test apps/ubaa_flutter/integration_test/app_flow_test.dart -d macos --ignore-timeouts
just flutter-build platform=macos mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
just flutter-artifact-check <platform> <对应产物>
UBAA_DEVECO_HOME=/Users/moorefoss/Code/bin/command-line-tools \
  UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
```

OHOS 门禁必须确认 DevEco `26.0.0.821`、OpenHarmony API26、arm64 动态库与无签名 HAP 内容；无签名产物仍
不代表签名、安装或设备能力。

### 10.4 最终门禁

```text
just refs
just layout-check
just check-sensitive
just check
cargo test --locked -p ubaa-cli --all-targets
just flutter-check
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
just release-preflight
<锁定 Flutter SDK> flutter test apps/ubaa_flutter/integration_test/app_flow_test.dart -d macos --ignore-timeouts
just flutter-build platform=macos mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
UBAA_DEVECO_HOME=/Users/moorefoss/Code/bin/command-line-tools \
  UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
just verify-live mode=direct
just verify-live mode=webvpn
git diff --check
```

最终候选 HEAD（包含状态、裁决和证据文档提交）推送后，`.github/workflows/ci.yml` 与
`.github/workflows/flutter-platforms.yml` 的成功 run 必须具有与该 HEAD 完全相同的 `head_sha`；若路径过滤
未自动触发五平台 workflow，使用 `workflow_dispatch` 在该 HEAD 上运行。五平台 Windows、Linux、macOS、
iOS simulator、Android APK 的每个 job 和 macOS 宿主 integration 都必须成功。只接受最终 run 结论，不以
祖先提交、日志中的中间绿色行或 artifact 存在替代最终 HEAD 的终态。

Direct 与 WebVPN 必须串行，只记录安全摘要。真实只读成功不能替代 Flutter→FRB→Core、签名或设备证据；
本轮不执行真实写入，除非另有满足 `goal.md` 逐操作、逐目标条件的明确授权。

## 11. 完成定义

本轮只有同时满足以下条件才完成：

- 第 2 节列出的 15 个超千行手写文件全部消失或降到 1000 行以内；
- 两个拥挤源码目录均降到 16 个直属手写代码文件以内；
- layout baseline 无违例项，checker 合同测试和 `just layout-check` 通过；
- Rust 与 Dart 公共入口、CLI help/schema/exit、FRB schema、golden 与测试数量没有非预期变化；
- 复杂协议文件按职责目录化，函数体移动没有夹带协议“通用化”；
- CLI、Core、bridge、app、UI 与测试都能从领域名定位，入口文件不再承载跨领域实现；
- CLI JSON/human/exit 策略已离开 Core；Core 生产与测试消费者都经 `facade`/`facade::testing`，无公开旁路；
- facade 只有一个 runtime selector 和 route resolver，internal state 不反向依赖 feature，等价/并发测试通过；
- Flutter UI 的写资格只来自 typed eligibility，生产链只存在一个 `WriteCoordinator` 状态机；
- FRB 生成文件原位、零漂移并标为 generated；
- README、docs index、工程规范、status 与 CI 描述当前真实范围，不再把 Flutter 已实现能力写成范围外；
- 完整确定性、敏感、格式、codegen、Flutter、宿主 integration、本机三平台构建、OHOS API26 无签名 HAP、
  五平台 CI 终态与授权的两条 live 只读门禁有当前 HEAD 证据；
- 每个阶段一个主题提交，最终独立审查没有未处理的高/中严重度结构问题。

## 12. 本轮裁决

- 选择渐进纵向拆分，不做一次性架构重写；判断错误的代价是未来仍需一次行为迁移，但不会污染协议证据。
- 硬门槛采用 1000 行/16 个直属手写代码文件；判断错误的代价是少数高内聚文件可能被过早拆分，因此生成、
  vendored 与平台约定边界明确豁免，普通文件只以职责审查决定具体拆法。
- 保留 fixtures 的 `auth/readonly` 顶层路径，本轮只补 registry 与测试镜像；判断错误的代价是领域 fixture 仍需
  二次迁移，但避免大量 `include_str!` 路径 churn 与来源证据混杂。
- 脚本按副作用分类并一次更新 Justfile/workflow/runbook；判断错误的代价是入口路径 churn，因此保留所有
  `just` recipe 名作为稳定用户接口，脚本文件路径不再承诺兼容。
- UI 资格、写状态机、路线算法、runtime-state 与 Core 公共面不是纯结构提交，但属于本轮完成所需的结构根因；
  判断错误的代价是行为回归，因此每项单独来源对照、RED test、最小实现和提交，不能与物理搬运合并。
- `ubaa_host` 采用独立 package 而不是两个 `main.dart` 的共享相对文件；判断错误的代价是新增 package graph
  成本，但能让生命周期和 callback wiring 有明确所有者、独立测试和两个宿主一致性门禁。
