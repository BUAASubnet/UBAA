# 代码与目录组织实施计划

日期：2026-09-03

设计依据：`docs/architecture/code-organization.md`

执行模式：无人值守、分阶段、每阶段独立提交

基线提交：`11a296904d623b33da0a83157f714a7c5912ca8d`

## 1. 不可变条件

- `ubaa_old/`、`examples/`、`.env.local`、运行会话、验证码、真实响应与凭据只读且不得暂存。
- 上游协议、公开 DTO、CLI schema v2、FRB schema、golden、用户文案、key、semantics 和网络调用顺序不得因
  文件移动而改变。
- 机械结构提交与行为敏感提交严格分开；行为阶段必须先有来源对照和预期失败测试。
- 真实写入不属于本计划；Direct/WebVPN 只读验证串行执行并只保留安全摘要。
- 阶段 00–01 使用当前已有门禁；从阶段 02 checker 在同一提交中落地后，每个阶段提交前均运行：`just refs`、
  `just layout-check`、`just check-sensitive`、focused test、`just check`、
  `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check`、`just flutter-check`、`git diff --check`。
- 每次提交只用明确 pathspec 暂存，禁止 `git add .`；提交前执行 `git diff --cached --name-only` 和
  `git diff --cached` 人工检查，确认没有冻结目录、`.env.local`、session、Cookie、token、验证码、个人数据、
  原始响应、构建缓存或签名材料，再运行 `just check-sensitive` 并提交。
- 任何生成代码漂移、golden diff、测试数量意外变化、敏感扫描失败或未解释行为差异都阻止阶段提交。

## 2. 提交与证据账本

| 阶段 | 主题 | RED/前置证据 | 目标提交 | 状态 |
|---|---|---|---|---|
| 00 | 审查、设计与实施计划 | 15 个超千行、2 个拥挤目录；设计与计划复审 GO | `docs: 固化代码组织审查与实施计划` | 已提交：`6a1c8be` |
| 01 | 当前事实、文档入口与 CI 契约 | CI 缺少 Flutter/codegen；文档范围过期 | `docs(ci): 对齐当前无签名范围与合并门禁` | 已提交：`a6ee746` |
| 02 | refs 纯校验、脚本分类与 layout 棘轮 | checker 不存在的合同测试失败 | `build: 建立结构棘轮并按副作用整理脚本` | 已提交：`c345f4a` |
| 03A | Test Support fixture 注册表 | 三个 Cgyy fixture 未注册的 focused test 失败 | `test: 完整登记脱敏只读 fixture` | 已提交：`ce69c26` |
| 03B | Rust Test Support 测试镜像 | layout baseline 的 auth/readonly 违例 | `test: 按领域拆分 Core 集成证据` | 已验证待提交 |
| 04 | CLI 目录、输出与退出策略 | CLI schema/stdout/stderr/exit characterization | `refactor(cli): 拆分命令执行并收回宿主输出策略` | 待执行 |
| 05 | facade/session 机械拆分 | facade/session focused tests 绿色 | `refactor(core): 拆分 facade 与 session 所有权` | 待执行 |
| 06A | route selector | direct/webvpn/auto 等价矩阵 | `refactor(core): 集中路线解析与 runtime 选择` | 待执行 |
| 06B | route state | Arc/generation/TTL/fork/concurrency 矩阵 | `refactor(core): 下沉路线状态并消除依赖环` | 待执行 |
| 06C | facade/test-contract | 生产宿主旁路 compile-fail RED | `refactor(core): 用 facade 封闭宿主与测试边界` | 待执行 |
| 07A | Cgyy 目录化 | Cgyy parser/request/cache tests | `refactor(core): 按职责拆分 Cgyy` | 待执行 |
| 07B | Judge 目录化 | batch/cache/calendar tests | `refactor(core): 按职责拆分 Judge` | 待执行 |
| 07C | SPOC 目录化 | auth/paging/detail/calendar tests | `refactor(core): 按职责拆分 SPOC` | 待执行 |
| 07D | Bykc 目录化 | crypto/request/semester tests | `refactor(core): 按职责拆分 Bykc` | 待执行 |
| 07E | Libbook 目录化 | parser/crypto/request tests | `refactor(core): 归档 Libbook 服务与算法` | 待执行 |
| 07F | Ygdk 目录化 | parser/upload/request tests | `refactor(core): 归档 Ygdk 服务与上传` | 待执行 |
| 08 | FRB 手写 read API | schema snapshot 与 codegen 零漂移 | `refactor(bridge): 分离读取 DTO 方法与映射` | 待执行 |
| 09 | Flutter 测试镜像 | 三个超千行测试入口 baseline | `test(flutter): 按领域拆分应用与宿主测试` | 待执行 |
| 10A | domain/app/bridge 拆分 | package focused tests 绿色 | `refactor(flutter): 建立领域与应用所有权` | 待执行 |
| 10B | ubaa_host package | 宿主 wiring 一致性测试 RED | `refactor(flutter): 抽取共享宿主组合根` | 待执行 |
| 11A | Bykc 选课资格 | 操作级来源对照与字符串漂移 RED | `refactor(flutter): typed 化博雅选课资格` | 待执行 |
| 11B | Bykc 退选资格 | 操作级来源对照与未知状态 RED | `refactor(flutter): typed 化博雅退选资格` | 待执行 |
| 11C | Bykc 签到资格 | 操作级来源对照与可签到 RED | `refactor(flutter): typed 化博雅签到资格` | 待执行 |
| 11D | Signin 签到资格 | 操作级来源对照与重复签到 RED | `refactor(flutter): typed 化课堂签到资格` | 待执行 |
| 11E | Libbook 预约资格 | 操作级来源对照与状态码 RED | `refactor(flutter): typed 化图书馆预约资格` | 待执行 |
| 11F | Libbook 取消资格 | 操作级来源对照与目标状态 RED | `refactor(flutter): typed 化图书馆取消资格` | 待执行 |
| 11G | Cgyy 预约资格 | 操作级来源对照与可预约 RED | `refactor(flutter): typed 化场馆预约资格` | 待执行 |
| 11H | Cgyy 取消资格 | 操作级来源对照与截止时间 RED | `refactor(flutter): typed 化场馆取消资格` | 待执行 |
| 11I | Ygdk 提交资格 | 操作级来源对照与输入完整性 RED | `refactor(flutter): typed 化阳光打卡资格` | 待执行 |
| 11J | Evaluation 提交资格 | 操作级来源对照与待评状态 RED | `refactor(flutter): typed 化评教提交资格` | 待执行 |
| 11K | 唯一 WriteCoordinator | 生产 UI 双状态机契约 RED | `refactor(flutter): 统一写入状态机` | 待执行 |
| 12 | Flutter UI 纯移动 | 行为阶段全绿、widgets baseline 仍存在 | `refactor(ui): 按页面与领域拆分组件` | 待执行 |
| 13 | 信息架构收口 | baseline 空、最终目录清单 | `docs: 收口代码组织状态与证据` | 待执行 |
| 14 | 最终候选与远端证据 | 全部门禁、live、native、API26 | `docs: 记录最终 HEAD 验证证据` | 待执行 |

## 3. 详细任务

### 阶段 00：审查、设计与计划

文件：

- 新增 `docs/architecture/code-organization.md`。
- 新增本计划。
- 将 `.superpowers/audit-2026-09-03/` 视为临时只读审查输入，不提交；把有用结论合并到正式文档后删除。

验收：设计复审为 GO；文档明确问题、目标树、行为边界、验证与完成定义。

### 阶段 01：P0 当前事实与 CI

文件：

- 更新 `README.md`、`CONTRIBUTING.md`、`docs/index.md`、
  `docs/development/engineering-standards.md`、`docs/development/commands.md`、
  `docs/development/testing.md`、`docs/migration/full-feature-matrix.md`。
- 把 `docs/migration/status.md` 的旧流水原样移到
  `docs/migration/history/status-through-2026-09-02.md`；当前页只保留 implementation/verified/evidence 三类 HEAD、
  能力矩阵、已验证/未验证与后置 BLOCKED。
- 在 `goal.md` 顶部登记本轮结构治理为活动阶段并链接设计/计划；不改写历史证据事实。
- 更新 `.github/workflows/ci.yml`：contract job 执行当前已有的 refs/sensitive/Rust、固定官方 Flutter package
  test 和 FRB 零漂移；阶段 01 不调用尚未存在的 layout recipe。缓存只能保存工具链/依赖，不能保存凭据或
  runtime session。
- 更新 `.github/workflows/flutter-platforms.yml` 的路径过滤和脚本路径；保留五平台矩阵及 macOS integration。

验证：Markdown 链接检查、workflow YAML 解析、`just check`、Flutter/codegen 门禁。

### 阶段 02：refs、脚本与结构棘轮

RED：先新增 `scripts/tests/layout.sh`，在隔离临时 Git 仓库中验证 checker 尚不存在而失败；逐项覆盖超长、拥挤、
baseline、陈旧 baseline、tracked/staged/untracked、ignored/generated/vendored 和宿主扩展名。

实现：

- 新增 `scripts/check/layout.sh` 与 `scripts/layout-baseline.txt`；初始精确登记设计中的 15 个文件和 2 个目录。
- 拆 `scripts/ensure-references.sh` 为可联网的 `scripts/bootstrap/references.sh` 与纯只读
  `scripts/check/references.sh`；`just refs-bootstrap` 指向前者，`just refs` 指向后者。
- 更新 CI：全新 runner checkout 后先以独立 setup step 执行 `just refs-bootstrap`，再以 gate step 执行纯
  `just refs`；checker/baseline 本地合同全绿后，同一阶段把 `just layout-check` 接入 CI。本地验证与
  `release-preflight` 只能调用纯 `just refs`，缺少引用时失败并提示人工运行 bootstrap，不得隐式联网。
- 移动脚本：
  - `check-sensitive.sh` → `check/sensitive.sh`
  - `check-flutter-toolchains.sh` → `check/flutter-toolchains.sh`
  - `flutter-codegen-check.sh` → `check/flutter-codegen.sh`
  - `flutter-check.sh` → `check/flutter-workspace.sh`
  - `flutter-build.sh` → `build/flutter.sh`
  - `ohos-check.sh` → `build/ohos.sh`
  - `verify-live.sh` → `live/verify.sh`
  - `core-live.sh` → `live/core-live.sh`
  - `release-preflight.sh` → `release/preflight.sh`
  - `verify-flutter-artifact.sh` → `release/verify-flutter-artifact.sh`
  - `test-verify-live.sh` → `tests/live-launchers.sh`
- 只把被两个以上入口真实共享的 repo-root 和 live feature 清单放入 `scripts/lib/`，并由 Shell 合同覆盖。
- 更新 `justfile`、workflow、runbook、AGENTS、setup 与脚本自身相对路径；保留现有 `just` recipe 名。
- `flutter-check` 在 analyze/test 前执行 Dart format check；Shell 脚本执行 `bash -n` 和可用的 ShellCheck。
- `.gitattributes` 标记 FRB Rust/Dart 输出为 generated。

验收：layout 合同测试全绿，所有现有 recipe 从任意 cwd 的行为与副作用说明一致；baseline 没有未知项。

### 阶段 03A–B：Rust Test Support fixture 与测试镜像

03A 先独立修复 fixture 注册表：在不修改 fixture 内容的前提下，让现有脱敏测试精确覆盖普通
`.html`/`.json` fixture，登记全部 2 个认证与 16 个只读 fixture；该行为修复不得与物理拆分混入同一提交。

03B 再执行以下机械移动：

- `tests/auth.rs` 保留显式 `#[path]` 入口，移动为 `auth/common.rs`、`login.rs`、`lifecycle.rs`、`conflict.rs`。
- `tests/readonly.rs` 保留显式入口，移动为 `readonly/common.rs`、`academic.rs`、`classroom.rs`、`cgyy.rs`、
  `spoc.rs`、`judge.rs`；SPOC 再按 list/auth/detail、Judge 再按 read/isolation/concurrency/retry 拆分，不创建
  多余测试 binary。common 只保留同一 integration target 内被多个 leaf 真实共享的 helper/transport；leaf
  显式导入自身依赖，不使用 glob prelude。
- `src/lib.rs` 拆为 `fixtures.rs`、`http.rs`、`session.rs`；fixture registry 覆盖现有 18 个受跟踪 fixture，并
  对最小化、消费者和禁止字段做测试。
- 从 layout baseline 删除 auth/readonly 两项。

focused：`cargo test --locked -p ubaa-test-support --all-targets`，并核对测试名集合前后相同。

### 阶段 04：CLI 与宿主策略

先新增/加强测试：

- `tests/cli_contract/output.rs` 固定 JSON schema v2、human、route metadata、stdout/stderr 和敏感遮罩。
- `tests/cli_contract/exit.rs` 固定全部 `ErrorCode` 到进程退出码矩阵。
- `tests/cli_contract/help.rs`、`routing.rs`、`writes.rs` 固定 Clap/help、fixed/routed 与写确认阻止。
- 测试先通过现有实现；再加入 Core 不再公开 output/exit 的源码架构断言，观察预期失败。

机械拆分：

- 参数移入 `command/` 的 8 个领域文件；`commands.rs` 成为 `command/mod.rs`。
- 两个 backend trait/adapter 移入 `backend/{mod,fixed,routed}.rs`。
- dispatcher 移入 `execute/{mod,aggregate,fixed,routed}.rs`；领域 handler 移入明确列出的 7 个文件。
- 输入、schema、human/error/exit 移入 `io/`；将 Core `output.rs` 与 `ErrorCode::exit_code` 原样迁入 CLI，再删除
  Core 导出与 Core 中仅为 CLI 存在的测试。
- `core-live.rs` 拆成显式 Cargo binary `bin/core_live/{main,args,evidence,steps}.rs`。
- `lib.rs` 只保留声明与稳定 CLI 测试入口；从 baseline 删除 `lib.rs` 与 `cli_contract.rs`。

focused：`cargo test --locked -p ubaa-cli --all-targets`、`cargo test --locked -p ubaa-core --all-targets`。

### 阶段 05：facade 与 session 机械拆分

只移动函数体，不改条件/顺序：

- `facade/mod.rs` → `client.rs`、`auth.rs`、`routing.rs`、`read/*`、`write/*`、`diagnostic.rs`、`types.rs`。
- `session/mod.rs` → `coordinator.rs`、`file_store.rs`、`file_safety.rs`；消除 `cookies.rs` 对父模块私有 helper 的
  反向路径，但保持 helper 逻辑逐字等价。
- 缩小文件级 Clippy allow，只保留确有必要的函数级例外。
- 从 baseline 删除 facade/session 两项。

focused：auth、route matrix、session CAS/permission/symlink/lock/fork tests；随后 Core/Test Support 全目标。

### 阶段 06A–C：Core 路线、state 与 facade 边界

RED/characterization：

- 增加 direct/webvpn/auto × ready/not-ready × success/failure/fallback 路线等价矩阵；记录每项调用序列与错误。
- 增加 `Arc` 身份、generation、lock、TTL、capacity、fork-sharing 和并发竞态测试。
- 增加架构测试：CLI/bridge manifest 不得启用 `test-contract`；生产源码不得导入非 facade 模块；禁用 feature
  的 compile-fail fixture 不能访问测试构造器。

实现并分别提交：

- 06A 只集中所有 facade 路线选择到 `runtime_for(route)` 与唯一 `resolve_route`，逐项删除重复 match。
- 06B 只移动 `features/state.rs`、`state_cache.rs` 到 `internal/route_state`，让 internal 不再依赖 feature。
- 06C 添加非默认 `test-contract` feature 和 `#[doc(hidden)] facade::testing`；仅 Test Support/专用测试启用；
  CLI/bridge 只导入 facade 重导出的稳定类型；把 auth/features/ports/session/config/connection 收窄为
  crate-private。

每个行为差异必须独立提交；若来源冲突，写 decision log 后停止该边界，不以猜测通过。

### 阶段 07：Core 复杂领域目录化

每个子阶段先在 `docs/migration/source-parity.md` 更新当前文件到两个冻结来源的操作级映射，再仅移动已有实现：

- 07A Cgyy：`auth/http/captcha/read/write/parser/crypto/sign/tests`；不改 token、重试、Cookie、签名或空结果。
- 07B Judge：`service/batch/parser/calendar/tests`；不改 worker 数、TTL、排序、再激活或 UC 仲裁。
- 07C SPOC：`auth/list/detail/parser/crypto/calendar/tests`；不改分页、提交绑定或认证重试。
- 07D Bykc：`auth/read/write/parser/tests`；不改 AES/RSA/SHA-1、随机 key 或当前学期选择。
- 07E Libbook：`service/parser/crypto`；不改 AES 请求向量或状态解析。
- 07F Ygdk：`service/parser/upload`；不改 multipart、图片限制或上传顺序。

每个领域独立 focused test、敏感扫描与提交；依次删除 cgyy/judge/spoc baseline，features 根直属文件降至预算内。

### 阶段 08：FRB 手写读取 API

- `api/read.rs` 改为 `api/read/mod.rs`，公开 DTO 仍在该模块定义，类型路径不变。
- inherent method 移到 `methods.rs`，private DTO mapper 移到 `mappers.rs`。
- 运行 schema snapshot、bridge unit、FRB codegen 两次并要求生成目录零 diff。
- 从 baseline 删除 read.rs。

### 阶段 09：Flutter 测试镜像

- `widgets_test.dart` 为唯一 root test，使用非 `_test.dart` part 拆为 shell、feature details、queries、writes、states、
  accessibility、goldens 和 fakes。
- `app_controller_test.dart` 拆为 lifecycle、auth、read、write、race、fakes parts。
- `integration_test/app_flow_test.dart` 拆为 auth、query、write、support parts。
- 保持测试名称、数量、fake 行为和 26 个 golden 字节不变；从 baseline 删除三个测试违例。

### 阶段 10A：Dart domain/app/bridge

- `models.dart` 迁入 `common/`、`feature/`、`write/`，barrel 保持旧公开导入可用。
- `backend.dart` 拆 `contracts/`、Unavailable/Demo 实现；`app_controller.dart` 拆 controller/error mapper。
- `bridge_backend.dart` 成为组合文件，read mapper 按 academic/assignments/bykc/libbook/cgyy/ygdk/evaluation，write
  按 prepare/commit；仅 BridgeBackend 依赖 bindings。
- 从 baseline 删除 bridge_backend；每个 package 执行 format/analyze/test。

### 阶段 10B：共享宿主

RED：新增 `ubaa_host` 测试，证明 SDK 初始化成功/失败、backend factory、平台能力、controller dispose、callback
wiring 在官方 Flutter 与 OHOS 组合根等价；测试初始因 package 不存在而失败。

实现：创建完整 `packages/ubaa_host` package、barrel、source、tests；接入两个 app pubspec/lock、workspace 检查、
release-preflight 与 CI。两个 `main.dart` 只保留各自 SDK/平台注入和 `runApp`。

额外门禁：macOS integration、本机 macOS/Android APK/iOS simulator build+artifact、OHOS API26 无签名 HAP。

### 阶段 11A–J：typed action eligibility

共同 RED：在 domain/bridge/app/UI 测试中证明修改中文 label/value 不再改变按钮资格；缺失/未知 typed 状态默认
拒绝，Core prepare 仍是最终权威。每个操作分别完成 AGENTS.md 规定的全部来源对照列：business
CAS/bootstrap URL 与 service、redirect/final URL、Cookie/session/token 作用域、HTTP method 与精确参数、Header
与 body 编码、加密/签名/挑战常量、DTO 字段类型与缺失值、缓存/并发/去重/重试、错误/退出和产品语义。无等价
协议时明确记录 `不适用`；两个冻结来源冲突时停止该操作并写 decision log，不能从 UI 文案补字段。

- 11A Bykc 选课；11B Bykc 退选；11C Bykc 签到。
- 11D Signin 课堂签到。
- 11E Libbook 预约；11F Libbook 取消。
- 11G Cgyy 预约；11H Cgyy 取消及开始前四小时规则。
- 11I Ygdk 提交；11J Evaluation 提交。

每个操作有自己的 sanitized RED 和 focused test，不以领域组级测试代替；从 Core facade DTO → bridge DTO →
domain action/eligibility → app mapping → UI 消费完整迁移，并在同一操作提交删除其旧字符串/时间解析，不移动
UI 文件。

### 阶段 11K：唯一 WriteCoordinator

RED：覆盖 prepare、cancel、confirm once、重复确认、过期、commit 异常、outcome unknown、不自动重试、Cgyy
receipt/readback、领域刷新、刷新失败和 dispose 中断；证明生产 UI 目前未使用现有 controller。

实现：把现有 `WriteFlowController` 演进为 `write/{coordinator,state,receipt_verifier}.dart`，生产 AppController/UI
只持有一个 coordinator 和 immutable state；删除 `_pendingWrite/_writeError/_writeSubmitting` 等第二套状态。

### 阶段 12：UI 纯拆分

只移动已经稳定的实现：

- app：splash、login、shell、profile。
- common：detail fields、pagination、error card。
- features：academic、assignments、bykc、libbook、cgyy、ygdk、evaluation。
- write：forms、confirmation。

`widgets.dart` 只保留 library/part 与公共入口；不得修改任何逻辑表达式、回调顺序、文案、key、semantics 或
布局。运行全部 widget/golden/integration，确认 PNG 无变化并从 baseline 删除 widgets.dart。

### 阶段 13：信息架构收口

- layout baseline 只保留说明、无违例路径；独立扫描确认没有新的 >1000 行文件或 >16 直属源码目录。
- 更新设计文档为 implemented，计划账本填入提交；更新最终目录图、README、docs index、status、decision log、
  source parity、脚本 README 与命令文档。
- 删除 `.superpowers/audit-2026-09-03/` 临时报告；人工检查所有入口文件和模块名无 `misc/utils/common2` 等模糊
  所有权。

### 阶段 14：最终候选、实时只读与远端 CI

1. 先完成候选证据文档、暂存人工审查并提交，得到此后不再修改的最终候选 HEAD。
2. 在该精确 HEAD 上重新串行执行设计文档第 10.4 节全部本地门禁，包括 CLI E2E、Flutter/codegen、
   release-preflight、macOS integration、本机三平台构建/产物、OHOS API26 无签名 HAP、Direct 与 WebVPN
   只读验证；安全结果保存在外部执行记录和最终交付消息，不再为记录结果修改仓库。
3. 推送同一最终候选 HEAD，查询 `.github/workflows/ci.yml` 与 `flutter-platforms.yml`，必要时 workflow_dispatch。
4. 仅当两条成功 run 的 `head_sha` 与最终候选 HEAD 完全相等、所有 job 终态成功时记录 PASS。
5. 独立代码审查不得遗留高/中问题；低问题必须有明确 owner 或在本轮修完。
6. 再次执行 `git status --short --branch`，要求本地与 `origin/ubaa2` 一致且工作树干净。

若必须把最终 run URL 或 PASS 写回仓库，该提交立即成为新的候选 HEAD，必须从第 2 步重新完整执行本地门禁、
两条 workflow 和 head_sha 绑定，之后不得再产生提交。

## 4. 停止条件

- 冻结来源与实时证据冲突；
- 需要真实写入但没有逐操作、逐目标授权；
- 公开 schema、FRB 生成或 golden 出现无法解释的漂移；
- session、Cookie、token、验证码、个人数据或原始响应进入 diff；
- 最终 CI/head_sha 无法绑定或任一 required job 失败。

停止只针对具体边界；其它独立阶段继续推进。阻断必须记录可复核证据，不能以“计划完成”代替代码完成。
