# 旧版只读业务 CLI 迁移实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保持 Core facade 边界的前提下，将冻结 `ubaa_old` 中尚未迁移的纯查询业务逐项接入 UBAA2 CLI，并为后续 SDK、Flutter 和 MCP 保留稳定 DTO 接口。

**Architecture:** 每个业务域在 `ubaa-core` 中拥有独立 domain、upstream、feature 和 facade 方法；业务 Cookie、令牌和缓存挂在路线隔离的客户端状态中。CLI 只解析参数并调用 facade，所有人类输出和 JSON 输出遵循现有 schema v2。写操作、验证码和照片上传不进入本计划。

**Tech Stack:** Rust 2024、Tokio、Serde、Reqwest transport、Clap、现有 Mock transport 与 Cargo 测试。

---

### Task 1: 课堂签到今日查询

**Files:**
- Create: `crates/ubaa-core/src/features/signin.rs`
- Modify: `crates/ubaa-core/src/domain/mod.rs`, `crates/ubaa-core/src/facade/mod.rs`, `crates/ubaa-core/src/features/mod.rs`
- Modify: `apps/ubaa-cli/src/lib.rs`
- Test: `crates/ubaa-core/tests/signin.rs`, `apps/ubaa-cli/tests/cli_contract.rs`

- [ ] **Step 1: Write the failing parser and facade tests**

  使用冻结 `SigninClassDto` 的 `courseId`、`courseName`、`classBeginTime`、`classEndTime`、`signStatus` 字段，断言 `STATUS=0` 和 `result` 数组映射；无本地主会话时断言零次 HTTP 请求并返回稳定未认证错误。

- [ ] **Step 2: Run the focused tests and verify the expected missing-feature failure**

  Run: `cargo test --locked -p ubaa-core --test signin`

  Expected: FAIL because `SigninClass` domain and `UbaaClient::signin_today` do not exist.

- [ ] **Step 3: Implement the minimal route-owned read path**

  增加 `SigninClass`/`SigninStatus` 稳定 DTO、`Signin` feature 请求接口和 facade 方法；只实现冻结查询所需的业务会话建立、`get_stu_course_sched.action` GET、日期参数和一次失效重试，不实现 `performSignin`。

- [ ] **Step 4: Add CLI command and schema-v2 rendering**

  增加 `signin today` 子命令，参数只允许可验证的日期覆盖选项；普通模式输出脱敏 DTO，`--json` 输出 feature=`signin` 的 schema-v2 envelope。

- [ ] **Step 5: Run focused and full deterministic gates**

  Run: `cargo test --locked -p ubaa-core --test signin`, `cargo test --locked -p ubaa-cli --test cli_contract`, `just check`。

- [ ] **Step 6: Commit the completed feature**

  `git add crates/ubaa-core apps/ubaa-cli docs/migration/source-parity.md docs/migration/status.md && git commit -m "feat: 迁移课堂签到查询"`

### Task 2: 阳光打卡概览与记录查询

**Files:** `crates/ubaa-core/src/features/ygdk.rs`, `crates/ubaa-core/src/domain/mod.rs`, `crates/ubaa-core/src/facade/mod.rs`, `apps/ubaa-cli/src/lib.rs`, focused tests and parity docs.

- [ ] **Step 1:** 依据 `LocalYgdkApi.kt` 写失败 fixture/parser 测试，覆盖概览、记录分页和 `hasMore`。
- [ ] **Step 2:** 运行 `cargo test --locked -p ubaa-core --test ygdk`，确认缺少 DTO/facade 方法而失败。
- [ ] **Step 3:** 实现 OAuth 业务会话的 route-owned 状态与只读请求链，不实现 `submitClockin` 或照片上传。
- [ ] **Step 4:** 增加 `ygdk overview`、`ygdk records` CLI 命令及 schema-v2 输出。
- [ ] **Step 5:** 运行聚焦测试、CLI 合约和 `just check`。
- [ ] **Step 6:** 提交 `feat: 迁移阳光打卡查询`。

### Task 3: 图书馆只读查询

**Files:** `crates/ubaa-core/src/features/libbook.rs`, domain/facade/CLI/tests/docs。

- [ ] **Step 1:** 写失败测试覆盖 libraries、areas、area detail、seats、bookings 查询 DTO。
- [ ] **Step 2:** 运行 focused test，确认功能缺失。
- [ ] **Step 3:** 按冻结 `/v4/` 请求、CAS 会话和加密响应解析实现 route-owned 只读链；不实现 reserve/cancel。
- [ ] **Step 4:** 增加 `libbook libraries|areas|area|seats|bookings` 命令。
- [ ] **Step 5:** 运行所有相关门禁。
- [ ] **Step 6:** 提交 `feat: 迁移图书馆查询`。

### Task 4: 场馆预约系统只读查询

**Files:** `crates/ubaa-core/src/features/cgyy.rs`, domain/facade/CLI/tests/docs。

- [ ] **Step 1:** 写失败测试覆盖 venue sites、purpose types、day info、my orders、order detail、lock code 的解析和错误分类。
- [ ] **Step 2:** 运行 focused test 确认缺失。
- [ ] **Step 3:** 实现 token/签名业务会话和只读接口；验证码、预约提交、取消操作保持不可调用。
- [ ] **Step 4:** 增加 `cgyy sites|purposes|day|orders|order|lock-code` CLI 命令。
- [ ] **Step 5:** 运行聚焦测试、CLI 测试和 `just check`。
- [ ] **Step 6:** 提交 `feat: 迁移场馆查询`。

### Task 5: 博雅课程只读查询

**Files:** `crates/ubaa-core/src/features/bykc.rs`, domain/facade/CLI/tests/docs。

- [ ] **Step 1:** 写失败测试覆盖 profile、courses 分页、detail、chosen courses、statistics。
- [ ] **Step 2:** 运行 focused test 确认缺失。
- [ ] **Step 3:** 按冻结 AES/签名常量和 `LocalBykcApi.kt` 动态 apiName 规则实现只读请求；不实现选课、退选和签到。
- [ ] **Step 4:** 增加 `bykc profile|courses|course|chosen|statistics` CLI 命令。
- [ ] **Step 5:** 运行完整确定性门禁。
- [ ] **Step 6:** 提交 `feat: 迁移博雅课程查询`。

### Task 6: 文档、矩阵与最终验收

**Files:** `docs/migration/source-parity.md`, `docs/migration/status.md`, `docs/contracts/`, `README.md`。

- [ ] **Step 1:** 为每个新增 operation 补齐九列 source-parity 证据和未验证路线说明。
- [ ] **Step 2:** 更新 CLI 命令参考、JSON schema、SDK facade 扩展说明和未迁移写操作清单，所有新增说明使用中文。
- [ ] **Step 3:** 运行 `just refs`、`just check-sensitive`、`just check`、CLI E2E 和 verifier 回归。
- [ ] **Step 4:** 使用 `.env.local` 安全运行可执行的 Direct/WebVPN 真实查询矩阵，不输出凭据或原始响应；失败时记录安全摘要。
- [ ] **Step 5:** 审计 `git diff --cached`，确认无冻结目录、凭据、Cookie、令牌、验证码或原始 body。
- [ ] **Step 6:** 提交最终文档与验收记录。
