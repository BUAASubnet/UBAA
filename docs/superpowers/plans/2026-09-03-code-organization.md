# 代码与目录组织实施计划

日期：2026-09-03

设计依据：`docs/architecture/code-organization.md`

执行模式：无人值守、分阶段、每阶段独立提交

基线提交：`11a296904d623b33da0a83157f714a7c5912ca8d`

当前状态：2026-09-05，阶段 00–13 已完成。候选 `d43c177` 的 19 项本地门禁和五平台原生 CI 通过，
合同 CI 未通过；阶段 14A 已修复工具链输出、Windows 文件身份兼容性与全仓 Shell 门禁。本页所属提交作为修复后的
新候选，重新执行完整验收并在仓库外绑定同一 SHA，不在本文件预填最终 PASS。

## 1. 不可变条件

- `ubaa_old/`、`examples/`、`.env.local`、运行会话、验证码、真实响应与凭据只读且不得暂存。
- 上游协议、公开 DTO、CLI schema、FRB schema、golden、用户文案、key、semantics 和网络调用顺序不得因
  文件移动而改变。本轮已登记例外是 Phase 11C 的行为合同：Bykc 未知签到状态需要破坏性 typed 表达，故
  CLI envelope 从 v2 显式升为 v3、bridge contract 从 v1 显式升为 v2；不得在旧版本号下静默改变字段，且
  磁盘 `session.json` 仍保持 schema v2。Phase 11D 的 Signin 可空状态与 typed 资格再次显式把 CLI
  envelope/schema 从 v3 升为 v4、bridge contract 从 v2 升为 v3；Phase 11E 的 LibBook 可空座位状态、
  typed 预约资格与稳定目标再分别升为 CLI schema v5 和 bridge contract v4；Phase 11F 的 LibBook 可空
  booking 状态、typed 取消资格与同页 authority 再升为 CLI schema v6 和 bridge contract v5；Phase 11G
  的 Cgyy canonical 状态、typed 预约资格/目标和安全收据继续升为 CLI schema v7 和 bridge contract v6；Phase 11H
  的 Cgyy typed 取消资格/目标/已取消证明与 caller-pinned 双回读再升为 CLI schema v8 和 bridge contract v7；磁盘 session
  版本始终不变。Phase 11I 的 Ygdk typed 提交提升为 CLI schema v9 / bridge v8；Phase 11J 的 Evaluation
  typed 批量结果提升为当前 CLI schema v10 / bridge v9。Phase 11K 及之后的机械整理不再改变版本。
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
| 03B | Rust Test Support 测试镜像 | layout baseline 的 auth/readonly 违例 | `test: 按领域拆分 Core 集成证据` | 已提交：`8d60bb9` |
| 04A | CLI 合同测试镜像 | CLI schema/stdout/stderr/exit characterization | `test(cli): 按宿主合同拆分 CLI characterization` | 已提交：`60fe3e3` |
| 04B1 | CLI 命令参数与现有 IO 目录 | 23 个合同测试与 46 个 CLI all-targets | `refactor(cli): 按领域归档命令与 IO` | 已提交：`837da26` |
| 04B2 | CLI backend 与执行层 | 04B1 行为基线及公开 API 集合 | `refactor(cli): 按领域拆分 backend 与执行层` | 已提交：`81e4cdb` |
| 04C | Core 输出与退出策略迁入 CLI | Core 不再拥有 output/exit 的架构 RED | `refactor(cli): 将输出与退出策略收回宿主` | 已提交：`0f0dde1` |
| 04D | core-live 验证宿主 | Cargo target 名与 runtime characterization | `refactor(cli): 显式拆分 core-live 验证宿主` | 已提交：`e6b0459` |
| 05 | facade/session 机械拆分 | facade/session focused tests 绿色 | `refactor(core): 拆分 facade 与 session 所有权` | 已提交：`60b210b` |
| 06A | route selector | 20 格路线矩阵、9 格优先级、Bridge prepare/commit | `refactor(core): 集中路线解析与 runtime 选择` | characterization `0fcf8d5`、实现 `397bbc8` 已提交；结构棘轮与全量门禁通过 |
| 06A2 | Bridge intent 锁序 | 重新登录失效旧 intent 的并发 RED | `fix(bridge): 原子失效并发写入意图` | 已提交：`5117eb6`；11 个 bridge 写测试与严格 Clippy 通过 |
| 06B | route state | Arc/generation/TTL/fork/concurrency 矩阵 | `refactor(core): 下沉路线状态并消除依赖环` | 已完成：`941eb16`、`1a096a6`、`df589f2`、`62d33fe`、`74328e9`、`b110827`、`e769ec8`、`0c6273d`；108 个 Core 单元测试与严格全目标 Clippy 通过 |
| 06C | facade/test-contract | 生产宿主旁路 compile-fail RED | `refactor(core): 用 facade 封闭宿主与测试边界` | 已提交：`2c940c8`；159 项 Core 单测、56 项显式 integration/架构测试、feature on/off 编译夹具、全 workspace、Flutter/FRB 与独立复审通过 |
| 07A | Cgyy 目录化 | Cgyy parser/request/cache tests | `refactor(core): 按职责拆分 Cgyy` | 已提交：`425ecaa` |
| 07B | Judge 目录化 | batch/cache/calendar tests | `refactor(core): 按职责拆分 Judge` | 已提交：`93a3210` |
| 07C | SPOC 目录化 | auth/paging/detail/calendar tests | `refactor(core): 按职责拆分 SPOC` | 已提交：`29e7a93` |
| 07D | Bykc 目录化 | crypto/request/semester tests | `refactor(core): 按职责拆分 Bykc` | 已提交：`4e358b4` |
| 07E | Libbook 目录化 | parser/crypto/request tests | `refactor(core): 归档 Libbook 服务与算法` | 已提交：`f1abc7c` |
| 07F | Ygdk 目录化 | parser/upload/request tests | `refactor(core): 归档 Ygdk 服务与上传` | 已提交：`d1741f0`；结构基线 `c42ffe4` |
| 08 | FRB 手写 read API | schema snapshot、解释后的首次生成差异与二次零漂移 | `refactor(bridge): 分离读取 DTO 方法与映射` | 已提交：`2cc1745`；Cargo/Clippy、11 项 Dart schema/API、两次 codegen 零漂移、独立复审通过 |
| 09 | Flutter 测试镜像 | 三个超千行测试入口 baseline | `test(flutter): 按领域拆分应用与宿主测试` | 已提交：`6e66a41`；UI 49、App 31、macOS integration 6，26 个 golden 零变化，独立复审通过 |
| 10A | domain/app/bridge 拆分 | package focused tests 绿色 | `refactor(flutter): 建立领域与应用所有权` | 已完成：公共面 `3cd2ad5`、错误过滤 `8a28016`、Domain `ebda967`、Bridge 护栏 `cd4ab7e`、App `ba633ac`、Bridge `9fbb83a`；全 Flutter、FRB 零漂移与 `just check` 通过 |
| 10B | ubaa_host package | 宿主 wiring 一致性测试 RED | `refactor(flutter): 抽取共享宿主组合根` | 已提交：`324979e`；共享入口、完整 callback、生命周期竞态、三平台产物与 OHOS API26 门禁通过 |
| 11A | Bykc 选课资格 | 缺字段、目标错配、提交前资格漂移与展示字符串漂移 RED | `refactor(flutter): typed 化博雅选课资格` | 已提交：`c76a81a`；Core/Bridge typed 资格、prepare/commit fail-closed、FRB/Domain/App/UI 映射、全量门禁与 macOS integration 6 项通过，独立复审 Ready |
| 11B | Bykc 退选资格 | 操作级来源对照与未知状态 RED | `refactor(flutter): typed 化博雅退选资格` | 已提交：`0a16276`；inner course ID、Core/Bridge 双复核、FRB/Domain/App/UI typed action、全量门禁与 macOS integration 6 项通过，独立复审 Ready |
| 11B2 | Bridge write 目录化 | 20 个写测试叶名称与行为不变、Bridge 24 项全绿、FRB 生成零漂移 | `refactor(bridge): 按职责拆分写入 API` | 已提交：`a147132`；最大生产文件 294 行、最大测试叶 425 行，完整 Rust/Flutter 门禁与双重独立复审通过 |
| 11C | Bykc 签到资格 | 操作级来源对照、unknown fail-closed 与可签到 RED | `refactor(flutter): typed 化博雅签到资格` | 已提交：来源 `a17bda4`、实现 `0a110b5`；Core 最终资格、单次发送边界、typed action、位置能力、schema v3、全量门禁与独立复审通过 |
| 11D | Signin 签到资格 | 操作级来源对照与重复签到 RED | `refactor(flutter): typed 化课堂签到资格` | 已提交：来源 `39dd438`、公开合同 `48444fd`、实现 `b988ae1`；Core 双复核、单次发送、typed action、schema v4/bridge v3、全量门禁、macOS integration 7 项与独立终审通过 |
| 11E | Libbook 预约资格 | 操作级来源对照与状态码 RED | `refactor(flutter): typed 化图书馆预约资格` | 已提交：来源 `61f8f99`、实现 `445240d`；日期/时段/座位唯一 fresh authority、冻结请求头、单次发送、typed action、schema v5/bridge v4、全量门禁、macOS integration 7 项与独立终审通过 |
| 11F | Libbook 取消资格 | 操作级来源对照与目标状态 RED | `refactor(flutter): typed 化图书馆取消资格` | 已提交：来源 `3e35b75`、实现 `ef63d0a`；同页唯一 fresh authority、严格分页、固定安全结果、单次发送、typed action、schema v6/bridge v5、全量门禁、macOS integration 7 项与独立复核通过 |
| 11G | Cgyy 预约资格 | 操作级来源对照与可预约 RED | `refactor(flutter): typed 化场馆预约资格` | 已提交：来源 `187097c`、实现 `40b7b4e`；canonical 身份/三态资格、prepare/commit 双 fresh authority、发送前最多三轮 captcha、最终 submit 单次 non-idempotent 边界、安全收据、action-only 公开入口、schema v7/bridge v6、全量门禁、macOS integration 7 项与独立终审通过；不包含真实写入 |
| 11H | Cgyy 取消资格 | 操作级来源对照与截止时间 RED | `refactor(flutter): typed 化场馆取消资格` | 已提交：来源 `c2e07ae`、实现 `f4e3137`；canonical 同 ID/三态资格、上海四小时截止、prepare/commit 双 fresh、Core 原子路线与单次 non-idempotent 发送、caller-pinned 0-based 列表/详情双回读、strict 已取消证明、schema v8/bridge v7、全量门禁、macOS integration 7 项与独立终审通过；不包含真实写入 |
| 11I | Ygdk 提交资格 | 操作级来源对照与输入完整性 RED | `refactor(flutter): typed 化阳光打卡资格` | 已提交：`d8484ad`；Core fresh typed authority、expected-route 原子提交、单次 upload/final、caller-pinned 双回读、schema v9/bridge v8、全量门禁、macOS integration 7 项与独立终审通过；不包含真实写入 |
| 11J | Evaluation 提交资格 | 操作级来源对照、待评状态及冲突行去重 RED | `refactor(flutter): typed 化评教提交资格` | 来源 `50bcb60`、实现 `4b0dcb0`；完整 Rust/Flutter/FRB、macOS integration 与独立审查修复通过 |
| 11K | 唯一 WriteCoordinator | 生产 UI 双状态机、通知重入与命令能力 RED | `refactor(flutter): 统一写入状态机` | 已提交 `b6ff2c7`；完整 Rust、Flutter 374 项、FRB、macOS integration 7 项、本机三平台产物、OHOS API26 及独立复审通过；[细化计划](2026-09-05-write-coordinator.md) |
| 12 | Flutter UI 纯移动 | 行为阶段全绿、widgets baseline 仍存在 | `refactor(ui): 按页面与领域拆分组件` | 已提交 `1f63127e`；完整 Rust、Flutter 374 项、FRB、macOS integration 复跑 7 项、独立复审通过；27 行入口、21 part、23 类/295 成员 AST 等价，26 张 golden 不变 |
| 12B | Core 入口职责整理 | 两个入口仍混入具体 HTTP/Reqwest 实现 | `refactor(core): 精简 HTTP 与端口入口` | 已提交 `7202fcf9`；7 组源码/测试块逐字相同，定向及全量门禁通过；[来源对照](../../migration/source-parity-entry-modules.md) |
| 13 | 信息架构收口 | baseline 空、最终目录清单 | `docs: 收口代码组织状态与证据` | 已提交 `d43c177`；当时 493 文件、135 目录零违例，实际目录/职责/开发定位/命令已复核；集成 cwd 与产物检查遗漏均已修正 |
| 14 | 最终候选与远端证据 | 全部门禁、live、native、API26 | 仓库外验收记录与最终交付消息 | `d43c177` 的 19 项本地与五平台原生 CI 通过，合同 CI 失败；整体未通过，转入 14A 后以新候选重验 |
| 14A | 工具链输出、Windows 文件身份与 Shell 门禁 | 合同 CI Broken pipe / E0658；假 SDK 长输出及全仓 ShellCheck 失败 | 四项修复及本页所属候选提交 | `4017edd7`、`7b8eed3a`、`23066064`、`c21a12dd` 已提交；完整 `just check`、CLI 127 项、Shell 六项、全仓 ShellCheck 0.11.0 及独立复审通过；新候选完整本地与两条同 SHA CI 仍须重验 |

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

### 阶段 04A–D：CLI 与宿主策略

04A 先拆分并加强测试：

- `tests/cli_contract/output.rs` 固定阶段 04 当时的 JSON schema v2、human、route metadata、stdout/stderr 和
  敏感遮罩；Phase 11C 的 v3 升级必须独立更新真实序列化、JSON Schema 与旧 v2 拒绝测试。
- `tests/cli_contract/exit.rs` 固定全部 `ErrorCode` 到进程退出码矩阵。
- `tests/cli_contract/help.rs`、`routing.rs`、`writes.rs` 固定 Clap/help、fixed/routed 与写确认阻止。
- 保留 23 个测试叶子；退出测试通过公开 renderer 覆盖全部错误码、JSON/human 输出和 writer failure。

04B 只执行命令、backend、dispatcher 与现有 IO 的机械拆分。为避免把参数归档与 2598 行执行器迁移放入同一
审查单元，拆为两个连续提交：

- 04B1：参数移入 `command/` 的 8 个领域文件，`commands.rs` 成为 `command/mod.rs`；现有输入、渲染与 command
  output 移入 `io/`。本阶段仍消费 Core 的 output/exit 合同，不夹带所有权变更。
- 04B2：两个 backend trait 与默认不可用错误构造归 `backend/mod.rs`，`fixed.rs`、`routed.rs` 只保留对应
  Core adapter；renderer 与错误投影归 `io/error.rs`；dispatcher 移入
  `execute/{mod,aggregate,fixed,routed}.rs`，共享只读投影归 `execute/mod.rs`，领域 handler 移入明确列出的 7 个
  文件。七个领域文件同时容纳 fixed/routed handler，Auth/User 留在 dispatcher，双路线认证/状态/注销归
  `aggregate.rs`。`lib.rs` 只保留声明与稳定 CLI 测试入口，并从 baseline 删除 `lib.rs`。

04B2 的依赖方向固定为：`command`、`routing`、`io` 是基础层；`backend` 只依赖 Core 与 `io`，禁止依赖
`execute`；`execute/features` 依赖 `backend`、`command` 与 `io`；fixed/routed/aggregate dispatcher 依赖
features；`io` 禁止反向依赖 backend/execute。内部代码直接使用真实模块路径，不得经 crate 根 re-export
回指。根级全部公开参数类型、两个 backend trait、`ReadonlyRouteContext`、六个执行入口及
`render_startup_error` 保持原路径和可见性，`CommandOutput` 仍仅为 `pub(crate)`，领域 handler 不扩大到 crate 根。

04C 先在 CLI binary 架构测试中加入聚合断言并观察预期失败：Core 不再导出/持有 `output.rs`，Core
`ErrorCode` 不再定义 CLI 退出映射，且 CLI 生产源码不再引用 `ubaa_core::output`。随后把 Core `output.rs` 的
schema/envelope 迁入 CLI `io/schema.rs`，把 `CliJsonError`、名称投影和错误 payload 构造迁入 `io/error.rs`，把
stdout/stderr renderer 与 Core 错误投影迁入单向依赖 `schema + error + exit_code` 的 `io/render.rs`，把
`ExitCode` 和映射迁入 `io/exit_code.rs`。`schema` 只依赖 `error`，不得由 `error` 反向导入 `schema`；执行层只调用
`render`，避免 IO 子模块形成循环。Rust 的外部类型规则不允许 CLI 继续为 Core `ErrorCode` 提供 inherent method，因此改用
`pub(crate) const fn exit_code(ErrorCode) -> ExitCode`；`main.rs` 中 Clap Error 自身的 `.exit_code()` 保持不变。
`CliFeature` 及现有 CLI 合同测试直接构造的 envelope/meta 类型由 `ubaa-cli` crate 根稳定重导出，避免私有类型
出现在公开签名。Core 中九项 output/envelope 合同必须以原测试名、独立 `#[test]` 叶子和完整精确断言迁到
CLI output 合同；Core 的一项退出码矩阵由已加强的 CLI exit 合同接管，迁移前后测试叶总量不得净减少。架构
测试需递归扫描 Core/CLI 全部 Rust 源码，同时拒绝 Core 中 output 文件/目录、CLI 专属稳定符号和 CLI 对
`ubaa_core::output` 的直接、花括号或别名导入，不能只匹配一个固定文件或字面量。完成这些迁移后，才
删除 Core 导出、文件与对应测试；不得改变 JSON schema、stdout/stderr 或数值退出码，bridge/Test Support 的
Core 结构化错误消费也不得改变。

04D 最后机械拆分验证宿主：

- `core-live.rs` 拆成显式 Cargo binary `bin/core_live/{main,args,evidence,steps}.rs`。
- 在 Cargo manifest 设置 `autobins = false`，显式固定 `ubaa → src/main.rs` 与
  `core-live → src/bin/core_live/main.rs` 两个 binary，保持脚本和产物路径不变。
- `binary_e2e.rs` 以排序后的精确文件集合聚合检查 `core_live/**/*.rs`，`core_live_runtime.rs` 使用 Cargo 提供的
  `CARGO_BIN_EXE_core-live`，不再猜测 target 目录或 Windows 扩展名。
- `main → steps → {args,evidence,Core}`，`evidence → Core error`，`args` 独立；15 项只读功能顺序、单一路线、
  stdin 两行凭据、证据字段/脱敏、0/2/5 退出语义和三个 week 测试叶保持不变。

focused：`cargo test --locked -p ubaa-cli --all-targets`、`cargo test --locked -p ubaa-core --all-targets`。

### 阶段 05：facade 与 session 机械拆分

只移动函数体，不改条件/顺序：

- `facade/mod.rs` → `client.rs`、`auth.rs`、`routing.rs`、`read/*`、`write/*`、`diagnostic.rs`、`types.rs`。
- `session/mod.rs` → `coordinator.rs`、`file_store.rs`、`file_safety.rs`；消除 `cookies.rs` 对父模块私有 helper 的
  反向路径，但保持 helper 逻辑逐字等价。
- `UbaaClient` 的字段及跨兄弟模块调用的 route guard/finish/clear helper 仅提升为 `pub(super)`，不扩大到
  crate 或外部；`RouteClient` 与其 impl 同驻 `diagnostic.rs`，保持字段私有。`facade/mod.rs` 继续稳定重导出
  `RouteClient/UbaaClient/Routed/RoutedError/RoutedResult/NetworkState/RouteDiagnostic/RouteResolution`，本阶段不提前
  创建 06C 的 `testing` 接口。
- session 依赖方向固定为 `file_safety → error`、`cookies → file_safety`、`types → cookies`、
  `file_store → {file_safety,storage,types,ports}`、`coordinator → {file_store,file_safety,types,ports}`；父 `mod.rs`
  仅声明和重导出，`session_error` 只为 `pub(super)`，不得复制 helper。
- 缩小文件级 Clippy allow，只保留确有必要的函数级例外。
- 从 baseline 删除 facade/session 两项。

focused：auth、route matrix、session CAS/permission/symlink/lock 以及现有 Judge worker isolation/concurrency；直接
runtime fork-sharing characterization 属于 06B，不在本机械阶段提前实现。随后运行 Core/Test Support 全目标。

### 阶段 06A–C：Core 路线、state 与 facade 边界

RED/characterization：

- 增加 direct/webvpn/auto × ready/not-ready × success/failure/fallback 路线等价矩阵；记录每项调用序列与错误。
  当前合同明确禁用跨路线 fallback，因此矩阵中的 fallback 场景必须证明另一槽位即使 ready 也不会被调用，
  `usedFallback=false`；本轮不得借重构启用回退或网络错误重放。
- 增加 parent/fork 的 transport/store/feature-state `Arc` 身份、Cookie 复制与隔离、独立 runtime state、generation、
  lock、TTL 精确边界、capacity/oldest eviction 和并发竞态测试。
- 增加架构测试：CLI/bridge manifest 不得启用 `test-contract`；生产源码不得导入非 facade 模块；禁用 feature
  的 compile-fail fixture 不能访问测试构造器。

实现并分别提交：

- 06A 先提交等价 characterization，再集中所有 facade 路线选择到 `runtime_for(route)` 与唯一
  `resolve_route`，逐项删除重复 match；旧 pure resolver 必须委托同一权威实现或内部化，不得保留第二套算法。
- 06A2 单独修复 Bridge write intent 的既有并发锁序：先用确定性 RED 证明 commit 等待 Core 锁期间，重新登录或
  路线重开必须仍能失效该 intent 且业务 HTTP 为零；再统一为 `inner → write_intents` 锁序，取出 intent 后立即
  释放 map 锁、持有 Core 锁完成提交。该行为修复不得混入 06A 的机械路线重构。
- 06B 先提交状态 characterization。`features/state.rs` 直接持有多种 feature credential/list 类型，故需先把
  state-owned payload 迁入低层 `internal/route_state/{credentials,cache}.rs`，再移动
  `state.rs/state_cache.rs` 并以源码门禁证明 `internal/**` 不依赖 `crate::features`。若确定性测试证实 Signin
  generation check 与 credential lock 间的 TOCTOU，必须先以独立 RED/修复提交解决，不得夹入机械移动。
- 06C 先迁移 Core integration tests：facade 行为测试使用 `facade::testing`，其余白盒测试成为 crate unit test
  或进入显式 `--features test-contract` 门禁，测试集合不得静默减少。随后添加非默认 `test-contract` feature 和
  `#[doc(hidden)] facade::testing`；用 manifest 检查、生产源码递归扫描及 feature-on/off compile fixtures 三重
  证明 CLI/bridge 不启用测试入口且只导入 facade 重导出的同一稳定类型。Test Support 明确启用该 feature，最后
  把 auth/features/ports/session/config/connection 收窄为 crate-private。该收口只声明并验证 workspace 内部兼容，
  不宣称未知仓外消费者的 semver 兼容。复审还必须逐项确认测试命中真实生产 resolver、双路线协调器、失效
  分类器与 parser；删除任何只为测试保留且语义已经淘汰的替身。`facade::testing` 暴露的公开签名必须类型闭合，
  同时默认 feature 构建不得因测试便利方法产生 dead-code 告警。

每个行为差异必须独立提交；若来源冲突，写 decision log 后停止该边界，不以猜测通过。

### 阶段 07：Core 复杂领域目录化

每个子阶段先在 `docs/migration/source-parity.md` 更新当前文件到两个冻结来源的操作级映射，再仅移动已有实现：

- 07A Cgyy：`auth/http/captcha/read/write/parser/crypto/sign/tests`；不改 token、重试、Cookie、签名或空结果。
- 07B Judge：`service/batch/parser/calendar/tests`；不改 worker 数、TTL、排序、再激活或 UC 仲裁。
- 07C SPOC：`auth/list/detail/parser/crypto/calendar/tests`；不改分页、提交绑定或认证重试。
- 07D Bykc：`auth/read/write/parser/tests`；不改 AES/RSA/SHA-1、随机 key 或当前学期选择。
- 07E Libbook：`service/parser/crypto`；不改 AES 请求向量或状态解析。
- 07F Ygdk：`auth/http/read/write/parser/upload/tests`；不改 multipart、图片限制或上传顺序。

07B 在 06B/06C 后按新 route-state 与可见性基线复核，再执行。先补 source-parity 中“当前 Rust 符号 →
`LocalJudgeApi.kt/JudgeApi.kt/Judge.kt` 及测试 → examples 不适用”的机械映射，并在旧实现上增加四项全绿
characterization：根公开面与 5m/2m/4 worker/3 reactivation 预算、冻结 header 与 GET 空 body、完整排序键、
乱序完成时返回最早规范化输入失败。然后以 `mod` 为组合点拆 `parser/calendar/service/batch/tests`：parser/calendar
不得依赖 service，service 不依赖 batch，batch 依赖 service/parser/calendar/route-state，低层 route-state 不得
反向依赖 feature。保持 8 个 Core unit、26 个 Test Support 及其余 6 个相关测试叶，在新增后共 44 个；所有
缓存容量/generation、空列表不缓存、隔离 Cookie、懒激活、四 worker、首次失败/最小输入索引、三次重激活、
上海六个月截止与 UC 仲裁逐句等价。06C 已收窄的 `features` 不得为兼容旧仓外路径重新公开。

每个领域独立 focused test、敏感扫描与提交；依次删除 cgyy/judge/spoc baseline，features 根直属文件降至预算内。

### 阶段 08：FRB 手写读取 API

- `api/read.rs` 改为 `api/read/mod.rs`；全部 92 个公开 Rust DTO/Routed 类型继续物理定义在该模块，保持
  `api::read` canonical namespace，不以跨模块 re-export 改变 FRB 类型归属。
- 32 个公开读取 method 连同私有 `execute_read` helper 移到 `methods.rs`，50 个 DTO mapper 移到
  `mappers.rs`；
  `map_cgyy_order` 通过 crate-private re-export 保持 write API 消费路径，其余 mapper 使用最窄可见性。
- 先扩充 schema characterization，固定 6 个 enum、32 个读取方法和单一 `api/read.dart` 路径。FRB 2.13.0 会按
  私有函数定义 namespace 生成 skip 注释，因此纯移动预计只会删除现有 `api/read.dart` 中列出
  `execute_read`/mapper 的一行机械注释；“相对阶段前 HEAD 字节零差异”与真实子模块化不可同时满足。实施时必须
  由锁定 generator 首次生成并审查完整 diff，仅接受这项已解释的 skip 注释变化，不得手改生成文件；随后把
  source 与生成结果精确暂存，再运行 codegen 两次，均要求相对暂存结果零漂移。公开 wire 名、方法、DTO、
  import/export、schema snapshot 与其它生成文件必须无差异。
- 从 baseline 删除 read.rs。

### 阶段 09：Flutter 测试镜像

`widgets_test.dart`、`app_controller_test.dart` 和 `app_flow_test.dart` 继续作为各自唯一的 `_test.dart` library
root；根文件只保留 imports、相对 URI `part` 声明、`main`/binding 初始化和按原顺序调用的私有同步注册函数，
领域实现放入不以 `_test.dart` 结尾的 part。不得新增 `group`，现有 49/31/6 个测试名称、注册顺序与测试函数体
必须保持不变。

- UI 拆为 `goldens/accessibility/shell/feature_details/writes/queries/states`；当前没有真正跨 leaf 的 UI fake，
  因此不创建空 `fakes.dart`。
- App 拆为 `auth/lifecycle/read/write/race/fakes`，其中全部现有私有 test double 连同继承关系整体进入 `fakes`。
- integration 拆为 `auth/query/write/support`，三个私有 backend fake 整体进入 `support`。
- 拆分前后机械比较完整有序测试 ID；同时对 26 个 golden 固定相对文件名、字节长度与 SHA-256 manifest，并
  执行 golden 目录零 diff。禁止 `--update-goldens`、移动、重命名或重录 PNG。
- 当前源文件精确基线为 3216/1499/969 行；精确暂存并验证后删除三个对应 layout baseline 项。若产生任何
  FRB generated/codegen diff，直接判为 NO-GO。

### 阶段 10A：Dart domain/app/bridge

- 先新增 domain/app 公共面编译 characterization 和五项 BridgeBackend 行为 characterization：分别固定
  32/27 个 barrel 名字、BridgeBackend 的构造/open/client/route 签名、认证与路线调用顺序、全部读取参数与
  白名单投影、summary/view 归约、十项 prepare/commit 及稳定错误脱敏。它们在旧结构上应先 GREEN；结构 RED
  仍由 layout baseline 移除表达，不伪造业务失败。
- `models.dart` 作为薄兼容入口显式 export `common/{route,error,auth}`、`feature/{catalog,query,result}` 和
  `write/{inputs,intent}`；`ubaa_domain.dart` 继续导出该入口，类型身份与 32 个公开名字不变。
- `backend.dart` 作为薄兼容入口显式 export `contracts/{backend,routing,query,write,lifecycle}` 和
  `backend/{unavailable,demo}`；`app_controller.dart` 作为薄兼容入口显式 export
  `controller/{app_controller,error_mapper}`。`write_controller.dart` 本阶段不拆，也不提前实施 11K。
- Bridge 保持一个 Dart library：`bridge/bridge_backend.dart` 保留 imports、全部 implements、公开构造/open/client、
  route setter、factory 与薄委托；library-private 实现按 `common`、`read/{academic,assignments,bykc,libbook,cgyy,
  ygdk,evaluation}`、`write/{prepare,commit}` 使用 `part` 拆分，leaf 间不得反向调用。旧 `bridge_backend.dart` 只
  export 新入口；不得用 extension/mixin 改变接口满足关系，仅该 bridge library 可直接依赖 bindings。
- 原 4 个 domain、47 个 app 测试的名称和顺序不变，新增 characterization 后 app 为 53 个；逐步跑 focused，
  最后删除 bridge baseline，执行各 package format/analyze/test、全 Flutter 与 FRB generated 零 diff。

### 阶段 10B：共享宿主

RED：新增 `ubaa_host` package 内测试，仅证明共享 bootstrap、widget/callback wiring、backend factory、生命周期、
controller/backend 单次 dispose。官方 Flutter 与 OHOS 各自在自己的 `test/host_wiring_test.dart` 验证入口把 SDK、
平台能力与 `runApp` 委托给同一 `UbaaAppHost`；`ubaa_host` 不得依赖或 dev-depend 任一 app，避免测试依赖环。

实现：创建 `packages/ubaa_host` 的独立 `pubspec.yaml`/lock、barrel、source 与 tests；不新建根 Pub workspace。
两个 app 各自以 path dependency 接入并更新自己的 lock，host 加入官方 SDK 的 `flutter-workspace` package 清单。
共享包仅依赖 Flutter、app、UI、domain/platform，不依赖 bindings、原生插件或协议；两个 `main.dart` 保留各自
实际 `RustLib.init`/`bridgeHello`、平台能力工厂和 `runApp` 注入。严格保持
`ensureInitialized → RustLib.init → debug hello → create capabilities → runApp` 顺序；SDK 初始化或 debug hello
失败时不创建能力、不调用 `runApp` 且错误继续传播，“失败仍启动不可用 UI”不在本结构阶段。

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

11C 额外固定 CLI 版本边界：`checkin` 缺失不得再伪装为整数默认值，`canSign`/`canSignOut` 被含
`unknown` 的 `signEligibility`/`signOutEligibility` 取代，写请求到达边界后的不确定结果使用
`outcome_unknown`。这些变化会破坏 schema v2 消费者，因此所有 CLI 成功、失败、参数错误、聚合和诊断
envelope 统一显式升级为 schema v3，合同测试拒绝旧 v2；`session.json` schema v2 不在此次变更范围。

11D 再次显式提升公开版本：Signin `signStatus` 改为可空并加入 typed eligibility/target，Flutter bridge
contract 使用 v3；CLI 成功数据加入 Signin 写结果并将今日 DTO 改为 fail-closed 形状，envelope/schema 使用
v4。确定业务 `success=false` 保持外层成功、CLI 退出 0；`outcome_unknown` 仍退出 5。两者必须分别测试。

### 阶段 11B2：Bridge write 目录化

在 11C 继续扩展资格复核前，先把接近结构上限的 `api/write.rs` 与 `api/write/tests.rs` 机械拆分。公开 DTO 与
pending 类型留在 `write/mod.rs`，prepare、commit、验证/映射 helper 分别进入具名子模块；`write/tests.rs`
保留 facade 测试注入并向 contract、Bykc、intent 生命周期与输入验证叶模块提供封装 helper。不得改变
`crate::api::write::*` 公共路径、函数签名、错误语义、20 个写测试叶名称或生成绑定；以 Bridge 全部 24 项
测试、严格 Clippy、完整 `just check` 和 FRB 二次生成零漂移验收。

### 阶段 11K：唯一 WriteCoordinator

RED：覆盖 prepare、cancel、confirm once、重复确认、过期、commit 异常、outcome unknown、不自动重试、Cgyy
receipt/readback、领域刷新、刷新失败和 dispose 中断；证明生产 UI 目前未使用现有 controller。

实现：把现有 `WriteFlowController` 演进为 app 的 `write/{coordinator,receipt_verifier}.dart`；immutable
`WriteState/WriteOutcome` 属于 domain 的 `write/state.dart`。AppController 持有唯一 coordinator，UI 消费
其状态与安全命令；删除 `_pendingWrite/_writeError/_writeSubmitting` 等第二套状态。

### 阶段 12：UI 纯拆分

只移动已经稳定的实现：

- app：splash、login、shell、home、profile。
- common：feature detail、query controls、detail list、detail fields、pagination、error card。
- features：academic、assignments、bykc、libbook、cgyy、ygdk、evaluation。
- write：cgyy form、ygdk form、confirmation。

`widgets.dart` 只保留 library/part 与公共入口；不得修改任何逻辑表达式、回调顺序、文案、key、semantics 或
布局。运行全部 widget/golden/integration，确认 PNG 无变化并从 baseline 删除 widgets.dart。

### 阶段 12B：Core 入口职责整理

完成 UI 后独立提交最小机械整理：`features/mod.rs` 的共享 HTTP 函数原样移到 `features/http.rs`，
原内部调用路径与可见性保留；`ports/mod.rs` 留存 DTO/trait，把具体 Reqwest adapter、缓冲预算与既有
3 个测试原样移到 `ports/reqwest_transport.rs`。来源对照先于生产移动，逐块原文比较与定向行为测试
证明等价，不引入新的协议、通用抽象或公开边界。

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

### 阶段 14A：候选 CI 失败修复与重新验收

前次候选 `d43c177` 的本地 19 项门禁和原生 CI `33962021922` 五个 job 通过，但合同 CI `33962021960`
暴露工具链 stdout 提前关闭与 Windows stable 不支持的文件身份 API，整轮验收不能通过。
修复范围为 CLI `io/input.rs` 的本地照片检查、Flutter 工具链、OHOS 路径引用及 Shell 静态门禁与合同，
依赖固定为 `same-file 1.0.6`；不改变 Core 协议、公开版本、FRB 或 UI。

CLI 已提交 `4017edd7`，本地完整 `just check` 和 CLI 全目标 127 项通过；Shell `7b8eed3a` 的六项隔离合同、
完整 `just check` 及两个改动脚本的 ShellCheck 0.11.0 通过。其后 `23066064`、`c21a12dd` 完成全仓
ShellCheck 暴露的路径引用、source 静态解析、失败返回与断言修复，全仓 0.11.0、完整 `just check` 及独立复审通过。
加入 Shell 回归后，当前结构范围为 494 个手写文件、106960 行、135 个直属源码目录，仍无结构违例。

1. 隔离假 SDK/Git 回归覆盖完整长输出、首行错误或为空、错误 commit、原命令失败退出码和 OHOS；加入
   `just check`，不得关闭 pipefail 或把子进程失败转换为成功。新候选验收将 ShellCheck 0.11.0 加入 PATH，
   确认全仓 Shell 静态门禁实际执行，不能以 SKIP 代替。
2. CLI 以打开后持续存活的句柄比较文件身份，保留 Unix 设备/inode 检查、普通文件/符号链接拒绝、1 字节至
   10 MiB 和安全错误边界；测试覆盖同尺寸不同文件替换。本地 Unix 测试不作为 Windows 编译通过证据。
3. 修复与文档提交后，以本页所属提交的完整 SHA 从阶段 14 第 2 步重新执行 19 项本地门禁；全部日志、失败
   记录、产物摘要和发布报告保存到该 SHA 的独立尝试目录。
4. 同一 SHA 重新运行合同及五平台原生 workflow；Windows stable Rust job 必须实际编译并通过，两条 run
   与每个 job 都终态成功后才可记录最终 PASS。前次成功结果不继承到新候选。

## 4. 停止条件

- 冻结来源与实时证据冲突；
- 需要真实写入但没有逐操作、逐目标授权；
- 公开 schema、FRB 生成或 golden 出现无法解释的漂移；
- session、Cookie、token、验证码、个人数据或原始响应进入 diff；
- 最终 CI/head_sha 无法绑定或任一 required job 失败。

停止只针对具体边界；其它独立阶段继续推进。阻断必须记录可复核证据，不能以“计划完成”代替代码完成。
