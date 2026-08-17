# UBAA 2 Rust Core + CLI 登录基础建设合同

状态：执行合同

目标：完成 UBAA 2 的可持续开发仓库骨架、Rust Core 首个可用闭环，以及可通过真实环境验证的 CLI 登录与用户信息展示。

执行者：Codex 或其他能够读写本仓库并运行本地命令的开发 Agent。

> 本文件是执行合同，不是建议清单。执行者必须按本文件工作、验证和汇报。仓库中的代码、文档、测试和报告必须互相一致；不能用聊天中的未记录决定替代本文件或仓库文档。

## 1. 目标与完成定义

完成本合同后，仓库必须满足以下条件：

1. 根仓库是一个可复现的 Rust workspace，具有固定工具链、统一命令、基础 CI、代码规范、文档入口和 Agent 接手说明。
2. `crates/ubaa-core` 提供不依赖 Flutter、Node.js、Kotlin、Android、iOS、HarmonyOS 或 Ktor Server 的 Rust Core。
3. Rust Core 支持 `DIRECT` 和 `WEBVPN` 两种连接模式，能够完成北航 SSO 登录、验证码流程、密码风险提示继续登录、会话验证、注销和用户信息查询。
4. `apps/ubaa-cli` 提供名为 `ubaa` 的 CLI，能够交互式登录，并以人类可读格式或结构化 JSON 展示用户信息。
5. CLI 不接受命令行明文密码，不把密码、Cookie、验证码图片、完整身份证号或其他敏感响应写入日志、fixture、Git 或普通终端输出。
6. 脱敏 fixture、Mock HTTP、解析器测试、会话测试、CLI 端到端测试全部通过。
7. 使用本地 `.env.local` 中的 `UBAA_TEST_USERNAME` 和 `UBAA_TEST_PASSWORD`，Direct 与 WebVPN 两种真实登录验收都成功；真实验收失败或无法执行时，不得声称本合同完成。
8. 文档明确当前已完成范围、未迁移范围、旧版参考基线、每个命令和每个验证门槛，另一位开发者或 Agent 可以从干净 checkout 继续工作。

本合同完成后，只表示“Rust Core + CLI 认证/用户信息基础”完成，不表示 Flutter、MCP、课表、成绩、考试或其他业务已经迁移。

## 2. 当前事实与不可变参考

执行前必须先阅读：

- `UBAA2.md`
- `ubaa_old/README.md`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Auth.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/UserInfo.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/AuthApi.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalAuthServiceBackendTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalAuthSessionStoreTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalWebVpnSupportTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/NetworkUtilsTest.kt`
- `examples/buaa-api/Readme.md`
- `examples/buaa-api/src/context.rs`
- `examples/buaa-api/src/api/sso/auth.rs`
- `examples/buaa-api/src/api/user/auth.rs`
- `examples/buaa-api/src/api/user/opt.rs`
- `examples/buaa-api/src/request.rs`
- `examples/buaa-api/src/store/cookies.rs`
- `examples/buaa-api/src/store/cred.rs`
- `examples/buaa-api/src/error.rs`

参考基线必须记录在 `docs/migration/references.md`：

| 参考 | 固定提交 |
|---|---|
| `ubaa_old/` | `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` |
| `examples/buaa-api/` | `efb7976bf513f38364b88aeb83d704586cff9b2a` |

目前这两个仓库都带有自己的 `.git`，且旧仓库中没有现成的 `ubaa-v1-reference` 标签。不要伪造该标签，不要将嵌套仓库直接 `git add` 到新仓库，也不要修改两个参考目录。新仓库应：

- 将 `ubaa_old/` 和 `examples/` 作为本地只读参考目录加入 `.gitignore`；
- 在 `docs/migration/references.md` 写入远端 URL、固定提交、用途和读取规则；
- 提供不会覆盖脏工作树的 `scripts/ensure-references.sh` 或等价 `just refs` 命令，在目录不存在时按固定提交获取参考仓库；
- 在脚本检测到参考目录存在未提交修改、HEAD 不匹配或来源不是预期远端时直接失败；
- 不把账号、密码、Cookie、真实用户响应、验证码图片或真实 HTTP body 纳入参考目录以外的任何提交。

来源优先级固定为：

1. 本地真实上游的实际响应，用于确认当前行为；
2. 冻结的 `ubaa_old` 当前实现和测试；
3. 固定提交的 `examples/buaa-api`；
4. `UBAA2.md` 和本合同中的架构约束。

如果这些来源冲突，执行者必须停止相关实现，写入 `docs/migration/decision-log.md`：冲突内容、具体文件和提交、已观察到的响应、选择及理由。禁止凭经验猜接口路径、表单字段、加密常量、重定向规则或响应结构。

若参考代码被实质复制或改编，必须保留 `examples/buaa-api/License` 的 MIT 版权要求，并在 `THIRD_PARTY_NOTICES.md` 记录来源文件和改编范围；不得把参考仓库的免责声明误写成 UBAA 2 的产品声明。

## 3. 固定范围

### 3.1 本次必须完成

- Rust workspace 基础结构、工具链、格式化、Lint、测试、文档构建和 CI。
- `ubaa-core` 的领域模型、错误模型、HTTP/存储端口、Cookie 会话、Direct/WebVPN 连接策略、CAS/SSO 登录和 User Center 用户信息查询。
- 交互式 CLI 登录、验证码处理、会话复用、状态查询、用户信息展示、注销和 JSON 输出。
- 脱敏 fixture 与真实环境登录验收脚本。
- 供后续业务迁移使用的模块边界、扩展方法、迁移矩阵和 Agent 工作规范。

### 3.2 本次明确不做

- Flutter、OpenHarmony、Node.js、Swift、Kotlin、ArkTS 绑定。
- MCP Server。
- 课表、考试、成绩、签到、SPOC、希冀、评教、研讨室、图书馆或其他业务 API。
- 服务器中转、旧 Ktor Server、JWT、Redis、Relay API。
- 有副作用的业务操作。
- 明文密码持久化、自动上传真实响应、遥测和远程日志。
- 通过关闭 TLS 证书校验、跳过 SSO、硬编码账号或伪造成功响应来通过验收。

## 4. 仓库目标结构

最终至少包含以下真实文件或目录；禁止创建只为“看起来完整”而没有行为或文档的空模块：

```text
.
├── Cargo.toml
├── Cargo.lock
├── rust-toolchain.toml
├── rustfmt.toml
├── justfile
├── .gitignore
├── .editorconfig
├── AGENTS.md
├── README.md
├── CONTRIBUTING.md
├── SECURITY.md
├── THIRD_PARTY_NOTICES.md
├── UBAA2.md
├── goal.md
├── crates/
│   ├── ubaa-core/
│   │   ├── Cargo.toml
│   │   ├── src/lib.rs
│   │   └── src/
│   └── ubaa-test-support/
│       ├── Cargo.toml
│       └── src/lib.rs
├── apps/
│   └── ubaa-cli/
│       ├── Cargo.toml
│       └── src/main.rs
├── fixtures/
│   └── auth/
├── docs/
│   ├── index.md
│   ├── architecture/
│   ├── contracts/
│   ├── development/
│   ├── migration/
│   ├── adr/
│   └── runbooks/
├── scripts/
└── .github/workflows/ci.yml
```

不要求首轮拆成很多 crate。先在 `ubaa-core` 内保持清晰模块边界；只有当模块有独立消费者、独立发布节奏或经过测试证明需要独立依赖边界时才拆 crate。

## 5. 固定公共架构

### 5.1 Core 模块

`ubaa-core` 内部必须至少有以下职责边界：

```text
facade/       UbaaClient、Builder、对外服务入口
domain/       UserProfile、LoginChallenge、连接模式等 DTO/值对象
error/        稳定错误分类、错误码、可序列化错误详情
ports/        HTTP、时间、持久化 Cookie、秘密输入等端口
session/      Cookie、认证状态、会话持久化和清理
connection/   Direct/WebVPN URL 转换、允许的主机和连接策略
auth/         CAS/SSO 登录状态机、验证码、密码风险提示
features/     user 服务；后续业务按同样边界加入
upstream/     北航 SSO 和 User Center 的请求、响应和解析细节
```

依赖方向必须保持：

```text
宿主 -> facade -> auth/features/session -> upstream -> connection/ports
                         \-> domain/error
```

硬性约束：

- `domain` 不依赖 HTTP、文件系统或平台 UI。
- 宿主不得直接调用 `upstream`。
- Core 不使用隐式全局客户端、全局 Cookie 或全局账号。
- 每个 `UbaaClient` 拥有独立会话；需要多个账号就创建多个 client。
- 绑定层未来只能消费 facade 的稳定 DTO，不暴露 Rust 内部 trait、泛型或上游结构。
- 网络层默认校验证书；任何不安全 TLS 选项不得成为默认值，本目标中不得为了真实验收开启它。

### 5.2 依赖与工具链

- 工具链固定为仓库可复现的 Rust stable 版本；当前本地可用版本为 `1.95.0`，执行者应在 `rust-toolchain.toml` 固定该版本并以构建结果为准。
- edition 固定为 2024。
- 参考实现已经使用 `reqwest`、`tokio`、`serde`、`serde_json`、`base64`；优先沿用这些库的当前兼容版本并提交 `Cargo.lock`。
- CLI 使用 `clap`；密码交互使用不回显输入的实现；密码不得作为普通命令行参数。
- 只增加能在代码或文档中解释用途的依赖；每个新增网络、Cookie、凭据、HTML 解析或序列化依赖都在 `docs/adr/` 记录选择理由。
- 禁止为首个闭环引入大型 Web 框架、数据库、服务端运行时或与目标无关的 UI 框架。

### 5.3 HTTP、重定向与 Cookie

Core 必须控制业务正确性，不把重定向、Cookie 或认证失效判断交给不同宿主自行实现：

- 原始 HTTP transport 提供状态码、最终请求 URL、响应头和 body；测试可以替换 transport。
- 登录请求使用可审计的手动重定向流程；允许绝对、协议相对、根相对和路径相对 Location，并按旧实现测试其解析结果。
- Direct 请求使用 `https://sso.buaa.edu.cn`、`https://uc.buaa.edu.cn` 等旧实现确认的主机。
- WebVPN 将上游 URL 转换为 `https://d.buaa.edu.cn/...`，转换和逆转换规则必须以 `LocalWebVpnSupport.kt` 的测试与实现为依据，并保留端口、路径、查询和 fragment 行为。
- 不得把 Direct URL 和 WebVPN URL 混用到同一请求；所有重定向都重新应用当前连接策略，并拒绝未在允许集合中的认证跳转。
- Cookie 过滤至少覆盖 host/domain、path、Secure、过期和 Set-Cookie 更新；持久化格式必须可测试、可清理，文件权限为仅当前用户可读写。
- 跨进程会话只持久化 Cookie、连接模式和必要的非秘密元数据；默认配置文件名为 `session.json`，不保存用户名密码。CLI 的 `--config-dir` 直接决定该文件位置，默认路径由平台用户配置目录决定。
- 登录、验证码和认证失败不允许自动重试提交密码；网络层只对明确幂等且不会重复副作用的请求采用有限重试。
- 不记录 `Cookie`、`Set-Cookie`、`Authorization`、密码、完整验证码 data URL 或原始认证 body。

## 6. 固定 Core 公共契约

公开名称可以在实现中微调，但语义和字段必须保持以下合同；任何改名或字段变化要同步更新 `docs/contracts/auth-and-user.md`、CLI JSON Schema 和测试。

```rust
pub enum ConnectionMode {
    Direct,
    WebVpn,
}

pub struct UbaaClient { /* owns one independent session */ }

pub struct LoginInput {
    pub username: String,
    pub password: SecretValue,
    pub captcha: Option<String>,
}

pub struct LoginChallenge {
    pub id: String,
    pub execution: String,
    pub image_data_url: Option<String>,
}

pub struct UserProfile {
    pub id_card_type: Option<String>,
    pub id_card_type_name: Option<String>,
    pub phone: Option<String>,
    pub school_id: Option<String>,
    pub name: Option<String>,
    pub id_card_number: Option<String>,
    pub email: Option<String>,
    pub username: Option<String>,
}
```

Core 至少提供这些行为：

- `prepare_login()`：读取 SSO 登录页，识别已有会话、execution、验证码和提示信息。
- `login(LoginInput)`：提交普通表单或验证码表单，处理 CAS 重定向和密码风险页面，激活 User Center 会话，验证成功后返回 `UserProfile`。
- `get_user_info()`：请求 `https://uc.buaa.edu.cn/api/uc/userinfo` 或当前 WebVPN 对应地址，解析 `code/data` 包装，返回 `UserProfile`。
- `auth_status()`：验证 `https://uc.buaa.edu.cn/api/uc/status` 或当前 WebVPN 对应地址；有效会话刷新最后活动时间，明确失效时清理会话，认证服务 5xx 或超时不得误删会话。
- `logout()`：尽力访问旧实现确认的 SSO logout 地址，然后无论远端结果如何清理本地 Cookie 和认证状态。

验证码状态规则固定为：同一个 `UbaaClient` 内，`prepare_login()` 产生的 execution、Cookie 和 `LoginChallenge` 必须可供后续 `login()` 使用；人类 CLI 在同一进程内循环获取验证码并提交。`--json` 模式不进行隐藏交互，遇到验证码只输出结构化 `captcha_required` 并以退出码 4 结束；它不得声称登录成功，也不得把 challenge 自动写入长期会话文件。

`SecretValue` 必须在 Debug、Display、Serialize 和错误打印中隐藏内容。成功返回的用户信息必须来自真实解析的 User Center response；不得从用户名推导姓名或学号。

错误必须有稳定机器字段：

```text
invalid_input
authentication_required
invalid_credentials
captcha_required
password_risk_confirmation_failed
permission_denied
network_error
timeout
upstream_unavailable
upstream_changed
parse_error
internal_error
```

错误还必须包含错误分类、可重试标志和安全的展示消息。错误消息可以本地化或调整，但机器错误码和 JSON 结构不能无记录变化。

## 7. 固定 CLI 契约

二进制名为 `ubaa`，workspace package 名为 `ubaa-cli`。README 必须给出安装和本地运行方式。

命令集合：

```text
ubaa auth login --mode direct
ubaa auth login --mode webvpn
ubaa auth status
ubaa auth logout
ubaa user show
```

全局选项：

- `--json`：成功和失败都只向 stdout 输出结构化 JSON；提示和诊断只能向 stderr。
- `--config-dir <path>`：测试和临时环境可注入配置目录；默认使用当前用户配置目录，不使用仓库目录。
- `--no-color`：测试环境关闭颜色。

`auth login` 选项：

- `--mode direct|webvpn`，必须明确或使用已保存模式；不得默认为服务器中转。
- `--username <value>` 可选；未提供时交互读取。
- `--password-stdin` 可选；使用时从 stdin 读取一行密码，不写入命令历史。
- 未使用 `--password-stdin` 时通过不回显交互读取密码。
- `--captcha <value>` 可选；验证码缺失时人类模式保存临时图片并提示输入，JSON 模式返回 `captcha_required` 和挑战字段后退出。

成功输出的用户信息至少包括 `name`、`schoolId`、`username` 中实际存在的字段；可选字段按旧 DTO 解析。人类输出默认遮蔽手机号和身份证号；`--json` 默认也输出遮蔽后的敏感字段。完整敏感字段不得通过普通命令输出；若后续确有需求，必须单独设计确认机制。

Rust 字段可以使用 snake_case，但 CLI JSON 必须使用固定的 camelCase 字段名（例如 `schoolId`、`idCardNumber`），并在 serde 配置或显式属性中测试确认。

JSON envelope 固定为：

```json
{
  "schemaVersion": 1,
  "ok": true,
  "data": {},
  "meta": {
    "connectionMode": "direct"
  }
}
```

失败使用 `ok: false`，并包含 `error.code`、`error.kind`、`error.message`、`error.retryable`；验证码错误另外包含 `error.challenge`。JSON Schema 存于 `docs/contracts/cli-json.schema.json`，并由测试校验。

退出码固定为：

| 退出码 | 含义 |
|---:|---|
| 0 | 成功 |
| 2 | 参数或输入错误 |
| 3 | 未认证或凭据失败 |
| 4 | 需要验证码，等待补充输入 |
| 5 | 网络、超时或上游暂不可用 |
| 6 | 上游响应变化或解析失败 |
| 7 | 内部错误 |

## 8. 文档与 Agent 接手要求

必须创建并保持以下文档：

- `README.md`：项目定位、快速开始、CLI 示例、当前限制、验证命令。
- `AGENTS.md`：项目地图、权威来源、禁止事项、开发循环、完成前检查。
- `CONTRIBUTING.md`：分支、提交、代码审查、fixture 脱敏、如何添加业务模块。
- `SECURITY.md`：凭据、Cookie、日志、报告安全问题的规则。
- `THIRD_PARTY_NOTICES.md`：参考代码版权和依赖声明。
- `docs/architecture/overview.md`：目标架构和当前实现边界。
- `docs/architecture/core-boundaries.md`：Core 依赖方向和宿主边界。
- `docs/contracts/auth-and-user.md`：认证状态机、DTO、错误、会话和安全规则。
- `docs/contracts/cli-json.schema.json`：CLI JSON 合同。
- `docs/development/setup.md`：从干净 checkout 安装工具和初始化参考目录。
- `docs/development/commands.md`：`just` 命令、预期输出、常见失败处理。
- `docs/development/testing.md`：单元、fixture、Mock、CLI 和真实集成测试区别。
- `docs/migration/references.md`：旧版和示例的提交基线及引用位置。
- `docs/migration/status.md`：已迁移能力、未迁移能力和下一步切片。
- `docs/migration/decision-log.md`：所有不能从参考实现直接确定的决策。
- `docs/runbooks/live-auth-verification.md`：真实登录验收、脱敏证据和失败分类。
- `docs/adr/0001-rust-core-cli-first.md`：Rust Core、CLI 优先和旧项目冻结的决策。

每个文档必须写“当前事实”，不要复制旧项目已经失效的服务器中转、KMP 或 UI 描述。每个未来能力都要标注“未实现”，不能用空目录冒充完成。

## 9. 分阶段执行顺序与门槛

执行者必须按阶段推进；每阶段完成后先运行门槛，再创建独立 Git commit。失败不得通过删除测试、降低警告级别或跳过检查来解决。

### 阶段 0：保护参考和建立仓库底座

产物：`.gitignore`、`rust-toolchain.toml`、`Cargo.toml`、`justfile`、`AGENTS.md`、基础 README/安全文档、参考基线文档、参考初始化脚本、workspace 空壳、CI 骨架。

必须做到：

- `.env.local`、`.env.*`（保留 `.env.example`）、`target/`、运行时配置、live artifacts、`ubaa_old/`、`examples/`、`.DS_Store` 都被忽略。
- `.env.example` 只包含 `UBAA_TEST_USERNAME=` 和 `UBAA_TEST_PASSWORD=` 两个空变量名。
- `git add -A` 不会把任何嵌套参考仓库或 `.env.local` 纳入暂存区。
- `just refs` 检查并固定两个参考提交。
- `cargo metadata --locked`、`cargo fmt --all -- --check`、`cargo test --locked --workspace`、`git diff --check` 可运行。

提交：`chore: establish ubaa2 repository foundation`

### 阶段 1：契约、错误和测试设施

先写测试再实现最小代码。产物：Core 公共 DTO、错误模型、SecretValue、Mock transport、JSON Schema、fixture 读取工具。

必须覆盖：

- DTO 对应旧版 `UserInfo`、`UserInfoResponse` 和认证成功/挑战结果。
- 错误码、退出码和 JSON envelope。
- SecretValue 的 Debug/Display/Serialize 不泄露。
- fixture 路径和测试数据不含真实学号、姓名、手机号、密码、Cookie 或 token。

提交：`feat: define core auth contracts and test fixtures`

### 阶段 2：连接、Cookie 和会话

先将 `LocalWebVpnSupport.kt` 与 `examples/buaa-api` 的 WebVPN 使用方式转为表格和测试，再写实现。产物：Direct/WebVPN URL 转换、允许主机、手动重定向、Cookie jar、会话持久化和清理。

必须覆盖：

- HTTP、HTTPS、默认端口、显式端口、路径、查询和 fragment 的 WebVPN 转换。
- 已经是 WebVPN URL 时不重复转换。
- Domain、host-only、path、Secure、过期和 Set-Cookie 替换。
- 认证状态失效清理；认证服务 5xx/timeout 保留会话。
- 配置目录和 Cookie 文件仅当前用户可读写；测试检查权限或在不支持的平台记录可验证替代方式。

提交：`feat: add connection and session runtime`

### 阶段 3：SSO 登录和 User Center

必须以旧版 `LocalConnectionAuth.kt`、`LocalCasParser`、`LocalAuthServiceBackendTest` 和示例 `sso/auth.rs` 为行为依据。产物：Direct/WebVPN 登录状态机和 User Center profile 查询。

必须覆盖：

- 已有 SSO Cookie 时的状态探测和 User Center 激活。
- 登录页 execution 读取；hidden input 保留；submit/button/image 字段过滤方式有测试。
- 普通用户名密码提交。
- 识别 `config.captcha`，获取图片，返回 `captcha_required`，提交 captcha/captchaResponse。
- 识别 `continueForm`、`ignoreAndContinue`、密码过期或安全风险页面，并只允许一次继续提交。
- 绝对、协议相对、根相对和路径相对重定向。
- Direct 与 WebVPN 的每个认证 URL、重定向和 Cookie 都使用当前连接策略。
- `uc/status` 的有效、失效、HTML SSO、非 JSON、5xx 和 timeout 行为。
- `uc/userinfo` 的 `code/data` 解析和缺失字段行为。
- 登录成功后 CLI 可展示真实解析的用户姓名和学号；不从 username 猜测字段。

旧版在 WebVPN 登录后为 CGYY 建立额外 Direct SSO 会话；CGYY 不在本合同范围内，因此本阶段不得为未使用的未来业务添加该副作用，但必须在 `docs/migration/status.md` 记录为后续迁移事项。

提交：`feat: implement direct and webvpn sso authentication`

### 阶段 4：CLI 宿主

产物：`ubaa-cli`、命令帮助、交互式认证、JSON 输出、稳定退出码和配置路径。

必须覆盖：

- 无密码命令行参数。
- 人类模式可输入用户名、隐藏密码和验证码。
- JSON 模式 stdout 无日志污染，错误为可解析 envelope。
- 登录成功后立即显示用户信息。
- `auth status` 验证持久化会话；`user show` 获取最新信息；`auth logout` 清理本地状态。
- 再次运行 CLI 能复用有效 Cookie；失效会话不会被当成成功。
- 终端输出遮蔽手机号和身份证号，日志不包含敏感 header/body。

提交：`feat: add ubaa authentication cli`

### 阶段 5：真实双模式验收

只使用当前工作区的 `.env.local`，不得将其复制到仓库或测试 artifact。创建 `scripts/verify-live.sh` 和 `just verify-live mode=direct|webvpn`，脚本必须：

- 检查两个环境变量存在但不打印值；
- 将密码通过 stdin 或安全内存路径传给 CLI，不能拼接到命令行；
- 运行登录并调用 `user show`；
- 只写脱敏摘要：模式、成功/失败、错误码、耗时、存在的非敏感字段；
- 不保存原始 HTTP 响应、Cookie、验证码图片、完整姓名、完整学号、手机号、身份证号、邮箱或密码；
- 返回非零状态表示失败。

必须分别运行：

```bash
just verify-live mode=direct
just verify-live mode=webvpn
```

每种模式的成功证据至少包含：CLI 退出码为 0、User Center 响应被成功解析、姓名和学号字段真实存在、`auth status` 可验证会话。证据中只写脱敏值，例如姓名首字或学号末两位。验证码需要人工输入时可以暂停等待输入，但不得把验证码写入报告。

提交：`test: verify live direct and webvpn authentication`

### 阶段 6：持续开发就绪

产物：完整文档、CI、贡献指南、迁移状态、下一切片模板。

`just check` 必须串行执行：

```bash
cargo fmt --all -- --check
cargo clippy --locked --workspace --all-targets --all-features -- -D warnings
cargo test --locked --workspace
cargo build --locked --workspace
cargo doc --locked --workspace --no-deps
git diff --check
```

CI 至少覆盖 Rust stable 固定版本下的上述检查、JSON Schema 测试、敏感信息扫描和参考基线检查。CI 不得访问真实账号，不得因没有 `.env.local` 而失败；真实验收只在本地显式运行。

提交：`docs: make ubaa2 ready for continuous development`

## 10. 代码、文档和提交规范

- Rust 使用 `rustfmt`，所有 warning 按错误处理；公共类型、错误和模块必须有 Rustdoc。
- 新增行为先写失败测试，再写最小实现，再运行针对性测试和完整门槛。
- 测试名称说明行为和边界，不使用无意义的 `test_login`。
- 解析器测试优先使用固定字符串 fixture；真实网络测试必须显式标记并排除普通 CI。
- 日志使用结构化事件，但默认不记录请求 body、Cookie、token、密码、验证码和完整用户信息。
- 代码注释解释协议原因或安全边界，不写重复代码的注释。
- 文档中用“已实现 / 未实现 / 仅 fixture / 真实已验证 / 真实未验证”准确标记证据，不把编译成功写成协议成功。
- 每个阶段一个小 commit；commit 前运行 `git diff --check` 和与阶段对应的门槛。
- 不使用 `git reset --hard`、`git checkout --` 或删除用户已有文件来清理工作树。
- 不修改 `ubaa_old/` 和 `examples/buaa-api/`；如果它们有脏改动，停止并报告，不要覆盖。

## 11. 最终验收报告

完成前必须创建或更新 `docs/migration/status.md`，包含：

1. 当前新仓库 HEAD 和各阶段 commit。
2. 旧版、示例固定提交。
3. 完整命令和实际输出摘要。
4. 单元、fixture、Mock、CLI、真实 Direct、真实 WebVPN 的通过状态。
5. 真实验收使用的模式和脱敏字段证明，不包含密码、Cookie、原始响应或完整敏感个人信息。
6. 未迁移能力清单：Flutter、MCP、服务器中转、课表、考试、成绩及其他业务。
7. 下一步建议必须引用旧版文件和测试位置，不得只写抽象愿望。

如果任意硬门槛未通过，报告结论必须是“未完成”，并列出失败命令、错误分类、是否为外部上游阻断，以及重新运行条件。不能以 fixture 通过替代真实登录，也不能以某一种连接模式通过替代另一种。

## 12. 执行启动顺序

执行 Agent 必须按以下顺序开始：

1. 阅读本文件全文和 `UBAA2.md`。
2. 检查 `git status --short --branch`，确认不覆盖既有用户修改。
3. 验证参考目录 HEAD 与本文件的固定提交一致，只读检查 `.env.local` 变量名，不读取或输出变量值。
4. 创建并更新执行计划，先完成阶段 0，再逐阶段推进。
5. 在写入代码前先写阶段 0 的文档和安全边界；在每个阶段结束运行门槛并提交。
6. 遇到参考实现未覆盖的行为时，停止猜测，记录决策日志和需要人工确认的事实。

不得先搭建 Flutter、MCP、服务器或其他未纳入本合同的宿主。不得先批量复制旧 Kotlin 代码再补边界。不得在没有测试和文档的情况下宣称“框架完成”。

## Ready-to-paste Codex goal prompt

执行 `/Users/moorefoss/Code/UBAA/goal.md` 全部内容。先完整阅读该文件、`UBAA2.md`、冻结的 `ubaa_old` 参考实现和固定提交的 `examples/buaa-api`，检查工作树与 `.env.local`，然后按阶段 0 到阶段 6 建设 Rust workspace、`ubaa-core`、`ubaa-cli`、文档、CI、脱敏 fixture 和真实验收脚本。所有协议行为必须以参考代码、参考测试或真实上游证据为依据，禁止猜测；禁止修改或提交 `ubaa_old/`、`examples/`、`.env.local` 及任何敏感数据。必须支持 Direct 与 WebVPN 登录、验证码、密码风险提示、会话验证、注销和用户信息展示；必须通过 `just check`、完整测试、CLI 端到端测试以及 `just verify-live mode=direct` 和 `just verify-live mode=webvpn`。每阶段小步提交并更新文档和 `docs/migration/status.md`。任一硬门槛未通过都不得声称完成，最终报告必须列出实际命令、证据、未迁移范围和下一步引用位置。
