# UBAA 2 Rust Core + CLI + 只读业务迁移执行合同

状态：扩展执行合同；阶段 0-6 为已完成基线，阶段 7-12 为本次必须完成的工作。

目标：在已完成的 Rust Core/CLI 认证基线上，增加用户不可见的自动路由、Direct/WebVPN 双路会话、按功能配置的路由策略，并迁移和真实验证课表、考试、成绩、空闲教室、SPOC 作业和希冀作业的只读能力。

执行者：Codex 或其他能够读写本仓库并运行本地命令的开发 Agent。

> 本文件是执行合同，不是建议清单。执行者必须按本文件工作、验证和汇报。仓库中的代码、文档、测试和报告必须互相一致；不能用聊天中的未记录决定替代本文件或仓库文档。

## 1. 目标与完成定义

完成本合同后，仓库必须满足以下条件：

1. 根仓库是一个可复现的 Rust workspace，具有固定工具链、统一命令、基础 CI、代码规范、文档入口和 Agent 接手说明。
2. `crates/ubaa-core` 提供不依赖 Flutter、Node.js、Kotlin、Android、iOS、HarmonyOS 或 Ktor Server 的 Rust Core。
3. Rust Core 内部支持 Direct 和 WebVPN 两条相互隔离的连接路线；宿主只选择 `auto`、`direct` 或 `webvpn` 路由策略，普通用户不需要选择内部模式。
4. 一次用户登录操作必须分别尝试建立 Direct 和 WebVPN 两套独立会话；每套会话拥有独立 Cookie、认证时间和持久化槽位，并在当前进程内拥有独立 CAS execution、验证码/风险状态，任一辅助路线失败不得破坏已经成功的路线。
5. `apps/ubaa-cli` 提供名为 `ubaa` 的 CLI，能够自动选择路线、交互式登录，并以人类可读格式或结构化 JSON 展示用户信息和以下只读业务数据：课表、考试、成绩、空闲教室、SPOC 作业、希冀作业。
6. CLI 不接受命令行明文密码，不把密码、Cookie、验证码图片、完整身份证号或其他敏感响应写入日志、fixture、Git 或普通终端输出。
7. 脱敏 fixture、Mock HTTP、解析器测试、会话测试、CLI 端到端测试全部通过。
8. 使用本地 `.env.local` 中的 `UBAA_TEST_USERNAME` 和 `UBAA_TEST_PASSWORD`，Direct 与 WebVPN 两条真实登录路线均完成验收；每个只读功能都必须在真实验收矩阵中至少有一个已证实可用的路线，并验证 `auto` 能按该矩阵选择路线。冻结证据未证明的另一条路线必须明确记录为未证实，不得用 Mock 成功替代。真实验收失败或无法执行时，不得声称本合同完成。
9. 每个只读功能都有旧版接口、DTO、实现和测试证据表；若冻结旧版缺少接口级测试（成绩接口就是已知例子），必须明确记录缺口，并由 Rust 脱敏 fixture/parser 测试和真实验收补足。所有路由、字段、请求参数、分页/学期语义和错误分类均可追溯，禁止凭经验补全。
10. 文档明确当前已完成范围、未迁移范围、旧版参考基线、配置格式、会话迁移、每个命令和每个验证门槛，另一位开发者或 Agent 可以从干净 checkout 继续工作。

本合同完成后，只表示“Rust Core + CLI 认证/用户信息 + 指定只读业务”完成，不表示 Flutter、MCP、服务器中转或任何写操作业务已经迁移。

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
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ScheduleApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalScheduleApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Schedule.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Exam.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalScheduleApiBackendTest.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/GradeApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalGradeApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Grade.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/GradeScoreCacheStore.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/GradeScoreCacheStoreTest.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ClassroomApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalClassroomApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Classroom.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalClassroomApiBackendTest.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/SpocApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalSpocApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalSpocSupport.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Spoc.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalSpocApiBackendTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalSpocSupportTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/SpocApiTest.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/JudgeApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalJudgeApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Judge.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalJudgeApiBackendTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/JudgeApiTest.kt`
- `ubaa_old/shared/src/jvmTest/kotlin/cn/edu/ubaa/api/LocalJudgeRealIntegrationTest.kt`
- `examples/buaa-api/Readme.md`
- `examples/buaa-api/src/context.rs`
- `examples/buaa-api/src/api/sso/auth.rs`
- `examples/buaa-api/src/api/user/auth.rs`
- `examples/buaa-api/src/api/user/opt.rs`
- `examples/buaa-api/src/request.rs`
- `examples/buaa-api/src/store/cookies.rs`
- `examples/buaa-api/src/store/cred.rs`
- `examples/buaa-api/src/error.rs`
- `examples/buaa-api/src/utils/net.rs`
- `examples/buaa-api/src/api/class/core.rs`
- `examples/buaa-api/src/api/class/data.rs`
- `examples/buaa-api/src/api/spoc/core.rs`
- `examples/buaa-api/src/api/spoc/data.rs`
- `examples/buaa-api/src/api/spoc/opt.rs`
- `examples/buaa-api/src/api/aas/core.rs`
- `examples/buaa-api/src/api/aas/data.rs`
- `examples/buaa-api/src/api/aas/opt.rs`
- `examples/buaa-api/src/api/app/core.rs`
- `examples/buaa-api/src/api/app/data.rs`
- `examples/buaa-api/src/api/app/opt.rs`
- `examples/buaa-api/src/api/class/opt.rs`

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
- `ubaa-core` 的领域模型、错误模型、HTTP/存储端口、双路 Cookie 会话、Direct/WebVPN URL 转换、三态网络探测、按功能路由策略、CAS/SSO 登录和 User Center 用户信息查询。
- 交互式 CLI 自动登录、验证码处理、双路会话复用、状态查询、用户信息展示、注销、路由配置和 JSON 输出。
- 只读业务 Core 与 CLI：
  - 课表：学期、教学周、指定周课表、今日课表；
  - 考试：指定学期考试安排；
  - 成绩：指定学期成绩列表；
  - 空闲教室：校区和日期的空闲教室查询（本合同中“空调室查询”按旧版 `ClassroomApi` 解释）；
  - SPOC：作业列表和作业详情；
  - 希冀（旧版 `JudgeApi`）：作业列表、单个详情和批量详情查询。
- 每个只读业务的 DTO、解析器、Mock transport、脱敏 fixture、Core facade 方法、CLI 命令、JSON Schema 和真实验收脚本。
- 脱敏 fixture 与真实环境登录验收脚本。
- 供后续业务迁移使用的模块边界、功能路由矩阵、配置/会话迁移说明和 Agent 工作规范。

### 3.2 本次明确不做

- Flutter、OpenHarmony、Node.js、Swift、Kotlin、ArkTS 绑定。
- MCP Server。
- 任何写操作业务，包括签到、作业提交、SPOC 提交、希冀提交、评教提交、研讨室预约/取消、空调控制或其他会改变上游状态的操作。
- 评教、图书馆、通知、云盘、WiFi、服务器中转和其他未列入 3.1 的业务 API。
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
domain/       UserProfile、只读业务 DTO、路由策略等值对象
error/        稳定错误分类、错误码、可序列化错误详情
ports/        HTTP、时间、持久化 Cookie、秘密输入等端口
session/      按路线隔离的 Cookie、认证状态、会话持久化和清理
connection/   Direct/WebVPN URL 转换、允许的主机、网络探测和连接策略
config/       版本化的用户路由配置；不保存密码、Cookie 或验证码
auth/         CAS/SSO 登录状态机、验证码、密码风险提示
features/     user、schedule、exam、grade、classroom、spoc、judge 只读服务
upstream/     北航 SSO、User Center 和各只读业务的请求、响应和解析细节
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
- 每个 `UbaaClient` 拥有独立的 Direct/WebVPN 双路线会话集合；需要多个账号就创建多个 client。
- Direct 和 WebVPN 的 Cookie、CAS execution、风险确认、业务 token、缓存和失效状态必须按路线隔离；不得因为两个 URL 指向同一上游主机就跨路线复用。
- 功能路由策略与实际解析路线分离：`auto` 是用户策略，`direct`/`webvpn` 是解析结果或诊断 override。
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
- 跨进程会话只持久化 Direct/WebVPN 两个路线槽位中的 Cookie、实际路线和必要的非秘密元数据；默认文件名为 `session.json`。现有单模式 `session.json` 必须可迁移为版本化的双路线格式，不保存用户名密码。
- 用户路由策略单独存储在版本化、仅当前用户可读写的配置文件中；默认策略为 `auto`，配置只允许已注册功能名和 `auto|direct|webvpn` 值，不允许任意 URL、主机或请求头。
- `auto` 的网络信号由可注入探测器提供：对 `gw.buaa.edu.cn:80` 做 TCP 连通性测试；从开始解析主机名到尝试所有已解析地址的总预算固定为 500ms，任一连接成功表示 `Campus`。普通的解析失败、无地址、连接拒绝、不可达或总预算超时都表示 `OffCampus`；只有探测器自身的内部故障或注入的诊断失败表示 `Unknown`。结果只在当前进程缓存 60 秒；缓存到期必须重新探测。不得发 HTTP/TLS 请求、读取凭据、硬编码地址或 IP 段，也不得把 `Unknown` 永久当作外网。此行为以 `examples/buaa-api/src/utils/net.rs` 的目标主机、端口和 500ms TCP 连接为来源；“总预算”和三态错误边界是本合同的产品约束。
- `auto` 的基础解析必须是 `Campus -> Direct`、`OffCampus -> WebVPN`，以解决外网登录后部分业务无法直连的问题；功能证据矩阵可以声明强制例外（例如旧实现明确要求始终 Direct 的功能）或把某路线记录为未证实。`Unknown` 不得猜测为外网，必须使用该功能的已验证默认路线并在诊断信息中标记探测未知。
- 登录页准备可以分别执行，但每条路线的 execution 和凭据提交必须锁定在同一路线；不能将一次登录 POST 重放到另一条路线。
- 仅当功能矩阵把该操作标记为业务幂等且允许 fallback 时，才可在网关探测、连接失败、请求超时或 HTTP 502/503/504 后向另一条已就绪路线重放一次。显式 `direct`/`webvpn` 策略、认证提交、token 建立、任何写操作、HTTP 4xx、认证跳转/失效、权限拒绝、2xx 解析失败或未知错误一律不得自动换路；不能只按 HTTP method 推断幂等性。
- 不记录 `Cookie`、`Set-Cookie`、`Authorization`、密码、完整验证码 data URL 或原始认证 body。

## 6. 固定 Core 公共契约

公开名称可以在实现中微调，但语义和字段必须保持以下合同；任何改名或字段变化要同步更新 `docs/contracts/auth-and-user.md`、CLI JSON Schema 和测试。

```rust
pub enum RoutePolicy {
    Auto,
    Direct,
    WebVpn,
}

pub enum NetworkState {
    Campus,
    OffCampus,
    Unknown,
}

pub enum ReadonlyFeature {
    Schedule,
    Exam,
    Grades,
    Classroom,
    Spoc,
    Judge,
}

pub enum ConnectionMode {
    Direct,
    WebVpn,
}

pub struct UbaaClient { /* owns route-scoped Direct/WebVPN sessions */ }

pub struct LoginInput {
    pub username: String,
    pub password: SecretValue,
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

pub enum LoginReadiness {
    AllReady,
    Partial,
    NoneReady,
}

pub enum RouteLoginState {
    Ready,
    Failed,
}

pub struct SafeError {
    pub code: String,
    pub kind: String,
    pub retryable: bool,
    pub message: String,
}

pub struct RouteLoginResult {
    pub route: ConnectionMode,
    pub state: RouteLoginState,
    pub error: Option<SafeError>,
}

pub struct LoginOutcome {
    pub readiness: LoginReadiness,
    pub routes: Vec<RouteLoginResult>,
    pub profile: Option<UserProfile>,
}
```

`SafeError` 表示现有稳定错误的可公开部分；实现可以复用现有 `UbaaError` 或调整名称，但不能扩大暴露面。`LoginOutcome.routes` 必须恰好各含一个 Direct 和 WebVPN 项，顺序固定为 Direct、WebVPN。登录结果必须同时包含成功解析的 `UserProfile`（若任一路线成功）以及两条路线各自的 `ready|failed` 安全状态；失败状态只包含稳定错误码和脱敏消息，不包含密码、execution、Cookie、交互验证材料或原始 body。

`RoutePolicy` 是用户配置和宿主输入，`ConnectionMode` 是 Core 内部的实际路线；普通 CLI 不得要求用户传入 `ConnectionMode`。普通宿主只向 Core facade 提供配置目录和业务参数；facade 负责加载/校验配置、执行或复用网关探测、解析路线、检查目标槽位并返回安全诊断。CLI 只能解析参数、调用 facade 和渲染结果，不能自行实现选路。配置文件必须使用以下语义（具体序列化格式固定为版本化 TOML，文件名为 `config.toml`）：

```toml
schema_version = 1

[route]
default = "auto"

[route.features]
schedule = "auto"
exam = "auto"
grades = "auto"
classroom = "auto"
spoc = "auto"
judge = "auto"
```

配置解析必须拒绝未知字段、未知功能名和非法策略值；缺失功能使用 `route.default`，未提供配置时使用 `auto`。配置只保存路由策略和版本信息，不保存账号、密码、Cookie、execution、验证码、业务 token 或原始响应。

`auth login` 始终尝试建立两条路线，不受单个功能策略限制；`user show` 和未单列的只读入口使用 `route.default`。六个业务功能先读取自己的 feature policy，再回退到 `route.default`。

自动路线解析顺序固定为：显式 feature policy 为 `direct`/`webvpn` 时严格使用该路线且不 fallback；`auto` 先使用本次探测的 `Campus -> direct` 或 `OffCampus -> webvpn` 目标；`Unknown` 使用该操作矩阵唯一的 `unknown_default`（初始六个功能均为 `direct`，因为冻结实现/fixture 仅证明该路线，不能由此推断 WebVPN 不可用）。若目标路线槽位未就绪，而该操作矩阵标记 `allow_ready_route_fallback=true` 且另一槽位已就绪，则使用另一槽位；否则在发请求前返回 `authentication_required`。发请求后的 fallback 只按第 5.3 节的错误白名单最多一次。所有解析结果都必须把策略、探测状态、初始目标、最终路线和是否 fallback 写入诊断元数据，但不得写入 Cookie 或原始响应。

`session.json` 必须升级为版本化双槽位格式，保留当前单模式文件的迁移读取能力。逻辑结构必须等价于：

```json
{
  "schemaVersion": 2,
  "sessions": {
    "direct": { "cookies": [], "authenticatedAt": 0, "lastActivity": 0 },
    "webvpn": { "cookies": [], "authenticatedAt": 0, "lastActivity": 0 }
  }
}
```

槽位可以缺失，时间字段和 Cookie 结构沿用当前合同；`execution`、密码风险页面和其他登录进行时状态必须只存在于当前进程内存。双槽位的加载、保存、清理和 revision CAS 必须在同一个文件锁合同内完成，旧单槽位迁移不得覆盖新路线会话。

旧文件迁移规则必须固定：旧格式中的 `mode`、Cookie 和时间元数据只迁移到对应的 `direct` 或 `webvpn` 槽位，另一槽位保持缺失；不得把同一 Cookie 复制到两条路线。旧 `mode` 非法、缺失或结构损坏时，必须返回安全持久化错误或执行可恢复的清理，不能猜测路线。迁移成功后使用新 schema 原子替换文件，并保留现有 revision/CAS、锁、权限和无符号链接约束。

Core 至少提供这些行为：

- `prepare_login() -> Result<()>`：按当前路线读取 SSO 登录页，识别已有会话、execution 和提示信息。若页面出现冻结实现中的交互式验证码/验证步骤，立即返回 `upstream_changed`；不得下载图片、创建 challenge 或等待用户输入。
- `login(LoginInput) -> Result<LoginOutcome>`：由宿主调用的登录编排必须在内部按 Direct、WebVPN 固定顺序分别提交普通表单，处理 CAS 重定向和密码风险页面，激活 User Center 会话，验证成功后返回 `LoginOutcome`。内部必须存在路线限定的 login input/state；第二路线失败只形成部分成功状态，不得清除第一条成功路线。`AllReady` 表示两条均就绪，`Partial` 表示恰好一条就绪，`NoneReady` 表示两条均未就绪。
- `get_user_info()`：由宿主调用的无参数方法按功能策略解析路线，请求 `https://uc.buaa.edu.cn/api/uc/userinfo` 或当前 WebVPN 对应地址，解析 `code/data` 包装，返回 `UserProfile`；内部可以有路线限定实现。
- `auth_status()`：由宿主调用的无参数聚合方法分别验证两个已存在的路线槽位并返回 Direct/WebVPN 两项状态；缺失槽位报告 `not_authenticated`，有效会话刷新该路线最后活动时间，明确失效时只清理该路线，认证服务 5xx 或超时不得误删任一路线会话。
- `logout()`：分别尽力访问两条路线的旧实现确认的 SSO logout 地址，然后无条件清理当前 client 的两条内存状态。持久化清理必须按已加载 revision 做同一锁内 CAS；若其他进程已经写入更新会话，必须保留新会话、返回不含快照内容的安全冲突错误，不能重试无条件删除。
- `query_*` 只读方法：为六个 `ReadonlyFeature` 提供稳定 facade DTO。只读按业务语义定义，旧实现中用于查询的 POST（例如课表详情、成绩表单、SPOC 分页、希冀批量详情）可以迁移，但不得加入提交、预约、取消、签到或其他写操作。

宿主可见的方法不接受 `ConnectionMode` 参数；路线由功能策略解析。内部可测试 override 必须位于 facade 之外或明确标记为诊断 API。至少提供以下稳定语义（Rust 命名可按现有风格调整，但不能减少能力）：

```text
schedule_terms()
schedule_weeks(term_code)
schedule_week(term_code, week)
schedule_today()
exam_arrangement(term_code)
grades(term_code)
classroom_search(campus_id, date)
spoc_assignments()
spoc_assignment(assignment_id)
judge_assignments(include_expired)
judge_assignment(course_id, assignment_id)
judge_assignment_details(keys)
```

每次调用都返回解析后的稳定 DTO、实际解析路线和可安全展示的错误；不得将上游 HTML、加密 token、Cookie 或原始响应暴露给宿主。

交互式验证码功能已从 UBAA2 公共合同中删除。登录页若出现冻结实现中的 `config.captcha` 或其他需要人工交互的验证步骤，Core 返回 `upstream_changed`，两条路线分别记录安全失败；CLI 不提供验证码参数、图片文件、提示、重试或跨进程 challenge 存储。不得发送 `captcha`、`captchaResponse` 或任何未由当前表单证据证明的验证码字段。该行为差异必须记录在 `docs/migration/source-parity.md` 和 `docs/migration/decision-log.md`，并在真实矩阵中把出现验证码视为不支持的上游变化，而不是成功证据。

`SecretValue` 必须在 Debug、Display、Serialize 和错误打印中隐藏内容。成功返回的用户信息必须来自真实解析的 User Center response；不得从用户名推导姓名或学号。

错误必须有稳定机器字段：

```text
invalid_input
authentication_required
invalid_credentials
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
ubaa auth login
ubaa auth status
ubaa auth logout
ubaa user show
ubaa schedule terms
ubaa schedule weeks --term <term-code>
ubaa schedule current --term <term-code> --week <week>
ubaa schedule today
ubaa exam list --term <term-code>
ubaa grades list --term <term-code>
ubaa classroom search --campus <campus-id> --date <yyyy-mm-dd>
ubaa spoc assignments
ubaa spoc assignment show --id <assignment-id>
ubaa judge assignments [--include-expired]
ubaa judge assignment show --course-id <course-id> --id <assignment-id>
ubaa judge assignment details --key <course-id>:<assignment-id> [...]
```

全局选项：

- `--json`：成功和失败都只向 stdout 输出结构化 JSON；提示和诊断只能向 stderr。
- `--config-dir <path>`：测试和临时环境可注入配置目录；该目录同时包含 `config.toml`、`session.json` 和锁文件，默认使用当前用户配置目录，不使用仓库目录。
- `--no-color`：测试环境关闭颜色。

`auth login` 选项：

- 普通用户命令不得暴露 `--mode` 或要求选择 Direct/WebVPN；路线由 `config.toml` 的功能策略和 `auto` 探测决定。
- 仅测试、真实验收和故障诊断允许使用隐藏的内部 route override；该 override 不出现在普通 `--help`、README 或稳定用户合同中，并且不能改变 `config.toml`。
- `--username <value>` 可选；未提供时交互读取。
- `--password-stdin` 可选；使用时从 stdin 读取一行密码，不写入命令历史。
- 未使用 `--password-stdin` 时通过不回显交互读取密码。
- 登录命令不提供验证码选项。检测到交互式验证时按 `upstream_changed` 失败，不提示、不下载图片、不创建临时验证码文件，也不把上游验证字段写入请求或持久化会话。

只读命令参数和行为必须与旧版公开接口对齐：

- `schedule terms|weeks|current|today` 对应 `ScheduleApi` 的 `getTerms`、`getWeeks`、`getWeeklySchedule`、`getTodaySchedule`；`current` 的 `term` 和 `week` 参数必须明确传入。
- `exam list --term` 对应 `getExamArrangement(termCode)`。
- `grades list --term` 对应 `GradeApi.getGrades(termCode)`；term code 必须按旧版 `yyyy-yyyy-semester` 解析。
- `classroom search --campus --date` 对应旧版 `ClassroomApi.queryClassrooms(xqid, date)`；本合同的“空调室”按“空闲教室”实现。
- `spoc assignments` 和 `spoc assignment show --id` 对应 `SpocApi` 列表/详情；只读查询可以使用旧版加密 POST，不得实现作业提交。
- `judge assignments`、`judge assignment show` 和 `judge assignment details` 对应 `JudgeApi` 列表、单个详情和批量详情；`--include-expired`、课程 ID 和作业 ID 语义必须与旧版一致，不得实现题目提交。

成功输出的用户信息至少包括 `name`、`schoolId`、`username` 中实际存在的字段；可选字段按旧 DTO 解析。人类输出默认遮蔽手机号和身份证号；`--json` 默认也输出遮蔽后的敏感字段。完整敏感字段不得通过普通命令输出；若后续确有需求，必须单独设计确认机制。

Rust 字段可以使用 snake_case，但 CLI JSON 必须使用固定的 camelCase 字段名（例如 `schoolId`、`idCardNumber`），并在 serde 配置或显式属性中测试确认。

JSON envelope 固定为：

```json
{
  "schemaVersion": 2,
  "ok": true,
  "data": {},
  "meta": {
    "routePolicy": "auto",
    "resolvedRoute": "direct",
    "feature": "schedule"
  }
}
```

单路线的 `user show` 和只读业务成功 envelope 使用上述 `resolvedRoute`。聚合的 `auth login|status|logout` 不伪造单一路线：`meta` 使用 `resolvedRoutes: ["direct", "webvpn"]`，`data.routes` 恰好按 Direct、WebVPN 顺序分别给出状态；此时不得同时出现 `resolvedRoute`。失败使用 `ok: false`，并包含 `error.code`、`error.kind`、`error.message`、`error.retryable`；不包含 challenge、图片或验证码字段。`meta.routePolicy` 是用户配置策略，解析路线字段是本次请求的诊断结果，均不能被解释为用户必须选择的模式。JSON Schema 存于 `docs/contracts/cli-json.schema.json`，所有普通命令、隐藏诊断命令、成功、失败和参数错误都只允许输出 schema version 2；不得保留或产生 CLI schema v1 envelope。schema version 2 必须用 `oneOf` 或等价约束区分单路线和聚合 envelope，并由正反例测试校验。此规则不改变 `config.toml` 的磁盘格式版本 `1` 或 `session.json` 的磁盘迁移版本。

`auth login` 的 CLI 退出语义固定：`AllReady` 返回 0；`Partial` 返回 0，但人类和 JSON 输出必须明显报告未就绪路线；`NoneReady` 按主要稳定错误返回 3、5、6 或 7。检测到验证码或其他交互式验证时使用 `upstream_changed` 对应的退出码 6；部分成功不是静默成功，已成功槽位在任何返回路径都必须保留。

退出码固定为：

| 退出码 | 含义 |
|---:|---|
| 0 | 成功 |
| 2 | 参数或输入错误 |
| 3 | 未认证或凭据失败 |
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
- `docs/contracts/auth-and-user.md`：认证状态机、DTO、错误、双路线会话和安全规则。
- `docs/contracts/route-policy.md`：`auto|direct|webvpn` 配置、三态 TCP 网关探测、功能路由矩阵、fallback 和内部 override。
- `docs/contracts/readonly-features.md`：六类只读功能的 facade DTO、参数、上游证据、路由和错误合同。
- `docs/contracts/cli-json.schema.json`：CLI JSON 合同。
- `docs/development/setup.md`：从干净 checkout 安装工具和初始化参考目录。
- `docs/development/commands.md`：`just` 命令、预期输出、常见失败处理。
- `docs/development/testing.md`：单元、fixture、Mock、CLI 和真实集成测试区别。
- `docs/migration/references.md`：旧版和示例的提交基线及引用位置。
- `docs/migration/status.md`：已迁移能力、未迁移能力和下一步切片。
- `docs/migration/decision-log.md`：所有不能从参考实现直接确定的决策。
- `docs/migration/readonly-feature-matrix.md`：每个功能/操作/上游 URL/Direct/WebVPN/auto/真实证据状态。
- `docs/runbooks/live-auth-verification.md`：真实登录验收、脱敏证据和失败分类。
- `docs/runbooks/live-readonly-verification.md`：六类只读功能真实验收、无数据处理和脱敏证据。
- `docs/adr/0001-rust-core-cli-first.md`：Rust Core、CLI 优先和旧项目冻结的决策。

每个文档必须写“当前事实”，不要复制旧项目已经失效的服务器中转、KMP 或 UI 描述。每个未来能力都要标注“未实现”，不能用空目录冒充完成。

## 9. 分阶段执行顺序与门槛

执行者必须按阶段推进；每阶段完成后先运行门槛，再创建独立 Git commit。失败不得通过删除测试、降低警告级别或跳过检查来解决。

阶段 0-6 是当前仓库已经完成的认证基线。执行 Agent 必须先核对 `docs/migration/status.md`、当前 HEAD 和工作树；基线已经满足时不得重写或回退其实现，只能补充本合同要求的阶段 7-12。若基线验证失败，先修复基线并在状态文档记录，不得把失败隐藏在新业务提交中。

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
- 识别 `config.captcha` 或其他交互式验证页面并返回 `upstream_changed`；不得获取图片、提交 captcha/captchaResponse 或尝试绕过验证。
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

### 阶段 5：真实双模式验收（已完成基线）

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

本阶段的 `mode=direct|webvpn` 命令是历史基线验收；扩展合同必须在阶段 11 使用 `route=direct|webvpn|auto` 和 `feature=...` 的新矩阵命令重新验证。

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

### 阶段 7：自动路由、配置和网络探测

先写失败测试和合同文档，再实现最小路由层。产物：`RoutePolicy`、三态 `NetworkState`、可注入 `NetworkProbe`、版本化 `config.toml`、功能路由矩阵、隐藏的测试/真实验收 route override。

必须覆盖：

- `gw.buaa.edu.cn:80` TCP 任一地址连接成功、解析失败、无地址、连接失败、500ms 总预算超时、探测器内部故障和缓存过期的测试；探测不读取或输出用户凭据，不发送 HTTP/TLS，不硬编码地址或 IP 段。
- `Campus -> Direct`、`OffCampus -> WebVPN`、`Unknown -> 功能已验证默认路线` 的解析规则；`Unknown` 必须在诊断元数据中可见。
- 配置缺失使用 `auto`，显式 `direct`/`webvpn` 严格使用指定路线；未知字段、未知功能名和非法值返回 `invalid_input`。
- 六个功能的初始矩阵：`schedule`、`exam`、`grades`、`classroom`、`spoc`、`judge`；矩阵每一行必须记录操作、`unknown_default`、Campus/OffCampus 目标、是否允许在目标槽位未就绪时使用另一已就绪路线、是否允许网络错误 fallback、证据来源、已验证路线和未验证路线。没有明确行记录的操作不得自动执行。
- 普通 `--help` 不显示 `--mode`；内部 route override 只能被测试、`just verify-live` 和诊断调用使用。

提交：`feat: add feature route policy and campus probe`

### 阶段 8：Direct/WebVPN 双路线会话

先为持久化和生命周期写失败测试，再扩展现有 `SessionStore`/CAS 实现。产物：双槽位 `session.json`、旧单槽位迁移、路线隔离的 runtime/auth workflow、部分成功登录状态和双路线注销。

必须覆盖：

- Direct 与 WebVPN 各自独立的 Cookie jar、execution、验证码、风险确认、业务 token 和失效状态。
- 旧单模式 JSON 只迁移到其 `mode` 对应槽位；非法 mode、损坏文件和符号链接按现有安全合同处理；不得复制 Cookie 到另一槽位。
- 一次登录操作必须顺序准备和提交两条路线；一条路线验证码或风险失败不清除另一条成功路线；两条均失败才返回登录失败。
- `auth status` 必须聚合验证两条路线；`user show` 和每个只读功能只验证/使用解析后的目标路线。一条路线 5xx/timeout 不清除另一条路线。
- `auth logout` 对两条路线分别 best-effort 远端注销，然后无条件清理两槽位、内存状态和路线级缓存。
- 双槽位保存、清理、迁移和 revision CAS 在同一 OS 锁内原子执行；并发旧进程不能复活或删除另一条路线的新会话。
- execution、密码风险页面和密码永远不写入 `session.json` 或 `config.toml`。

提交：`feat: persist isolated direct and webvpn sessions`

### 阶段 9：只读 Core 业务切片

每个子切片都必须遵循“先读旧接口/DTO/实现/测试，先写失败 fixture/Mock 测试，再实现，再运行 focused test”。不得把 Relay API 的路径、字段或响应结构当作本地上游事实；本地 URL、表单、HTML、加密和错误分类必须以冻结证据为准。

#### 阶段 9a：课表、考试和成绩

依据：`ScheduleApi.kt`、`LocalScheduleApi.kt`、`Schedule.kt`、`Exam.kt`、`GradeApi.kt`、`LocalGradeApi.kt`、`Grade.kt`、`LocalScheduleApiBackendTest.kt`、`GradeScoreCacheStoreTest.kt`。

冻结旧版没有 `LocalGradeApiBackendTest.kt`；不得把 `LocalScheduleApiBackendTest.kt` 或缓存测试冒充成绩接口请求/解析测试。Rust 必须新增成绩专用的脱敏请求/响应 fixture、term 解析和错误行为测试，并在真实矩阵中补足协议证据。

必须实现并测试：

- 学期、教学周、指定周课表、今日课表和指定学期考试安排；保留本科教务门户的登录探测、研究生/不支持分类和旧版参数语义。
- 成绩 term code 的 `yyyy-yyyy-semester` 解析、成绩激活页、表单字段和 `e/m/d` 响应映射；不得把另一种旧 `GradeResponse` 结构误用于 Local 成绩接口。
- DTO 只包含有证据的字段，缺失/空值/非预期 code 有稳定错误分类。
- Direct/WebVPN URL 按当前 route 转换；在 route lock 内完成本科门户登录和查询，不能在 POST 查询中途切换。
- 只读请求可按操作幂等性和明确网络错误有限 fallback；不能按 HTTP method 粗略判断。

提交：`feat: migrate schedule exam and grade read APIs`

#### 阶段 9b：空闲教室查询

依据：`ClassroomApi.kt`、`LocalClassroomApi.kt`、`Classroom.kt`、`LocalClassroomApiBackendTest.kt`。本合同把用户所称“空调室查询”解释为“空闲教室查询”；空调控制、预约和其他写操作明确不做。

必须实现并测试：

- `queryClassrooms(xqid, date)` 的校区、日期格式、`e/m/d` 包装和楼层/教室 DTO。
- 旧版 CAS 同步页、无重定向查询、User-Agent、Referer、`X-Requested-With` 和会话失效分类。
- 同一路线的同步状态并发保护；Direct/WebVPN Cookie 不混用。
- 无数据、非法日期、未认证、SSO HTML、5xx 和 timeout 的稳定错误。

提交：`feat: migrate empty classroom read API`

#### 阶段 9c：SPOC 作业

依据：`SpocApi.kt`、`LocalSpocApi.kt`、`LocalSpocSupport.kt`、`Spoc.kt`、`LocalSpocApiBackendTest.kt`、`LocalSpocSupportTest.kt`、`SpocApiTest.kt`，并以 `examples/buaa-api/src/api/spoc/core.rs`、`data.rs`、`opt.rs` 作为补充加密/只读证据。

必须实现并测试：

- 当前学期作业列表和作业详情；保留 CAS token/role 建立、AES 参数、分页、HTML 纯文本化和提交状态映射的已证实行为。
- 旧版查询用 POST 时仍按业务只读处理，但 token 建立和查询序列必须锁定路线；不得在请求中途跨路线重放。
- 空列表、分页终止、认证失效一次 refresh、加密参数错误、HTML 内容和未知状态的固定 fixture。
- 不迁移作业提交、文件上传、评分修改等写操作。

提交：`feat: migrate spoc readonly assignments`

#### 阶段 9d：希冀作业

依据：`JudgeApi.kt`、`LocalJudgeApi.kt`、`Judge.kt`、`LocalJudgeApiBackendTest.kt`、`JudgeApiTest.kt`、`LocalJudgeRealIntegrationTest.kt`。希冀作业在 Rust 中统一命名为 `judge`，不得误称为 SPOC。

必须实现并测试：

- 作业列表（含 `includeExpired`）、单个详情和批量详情；课程/作业 ID 语义与旧版一致。
- SSO 激活、课程列表和作业 HTML 链接解析、多行链接、并发上限 4、六个月历史 cutoff、按用户/路线隔离的缓存和详情缓存。
- Direct 与 WebVPN route lock；沿用旧测试中 WebVPN batch details 的 gateway host 断言。
- 空输入批量详情、登录页重新激活、认证失效、历史课程跳过、详情不存在和上游错误的稳定分类。
- 不迁移题目提交、答案上传或任何 Judge 写操作。

提交：`feat: migrate judge readonly assignments`

### 阶段 10：只读 CLI 和 JSON 合同

产物：六类只读命令、自动路线展示、schema version 2、用户配置加载、部分成功登录输出和每功能错误映射。

必须覆盖：

- 本合同第 7 节列出的命令、参数校验、默认策略和空结果行为。
- 人类输出可以显示当前实际路线和“部分路线未就绪”，但不得显示 Cookie、execution、token、原始 HTML 或完整个人信息。
- JSON stdout 严格为一个 schema version 2 envelope；单路线响应包含 `routePolicy`、`resolvedRoute` 和功能标识，聚合认证响应包含 `routePolicy`、`resolvedRoutes` 和 `feature="auth"`，错误包含稳定 code/kind/retryable。
- 双路线登录的 `all_ready`、`partial`、`none_ready` 三种状态；检测到交互式验证时返回 `upstream_changed`，不能把验证材料持久化。
- 移除所有 CLI schema v1 输出分支；普通与隐藏诊断输出一律为 schema version 2，且不得继续把 `connectionMode` 当成用户输入。磁盘配置/会话迁移版本不受此项影响。

提交：`feat: expose readonly feature cli and json contracts`

### 阶段 11：真实只读业务矩阵验收

扩展现有 live 验收脚本，仍只读取当前工作区 `.env.local`，不复制、不打印、不写入 artifact。建议命令接口固定为：

```bash
just verify-live feature=auth route=direct
just verify-live feature=auth route=webvpn
just verify-live feature=all route=auto
just verify-live feature=schedule route=auto
just verify-live feature=exam route=auto
just verify-live feature=grades route=auto
just verify-live feature=classroom route=auto
just verify-live feature=spoc route=auto
just verify-live feature=judge route=auto
```

脚本必须：

- 检查环境变量存在但不输出值；密码只通过 stdin/安全内存传递。
- 首先确保两条路线的认证状态，并按功能矩阵选择/建立所需路线；不把一次路线成功当成所有功能成功。
- 每个功能至少完成一次真实请求和真实解析；无数据是有效响应时记录“空结果已验证”，不是伪造样例。
- 课表验收先调用 `terms`，优先选择唯一 `selected=true` 的学期；若没有或不唯一，选择上游返回顺序中的第一条合法 `itemCode`，并把选择写入脱敏摘要。随后调用 `weeks`，优先选择唯一 `curWeek=true` 的周；若没有或不唯一，选择返回顺序中的第一条合法 `serialNumber`，再验证指定周和今日接口；没有可用学期/周时记录真实空结果和上游返回分类，不猜造参数。考试和成绩复用该真实返回的 term；成绩仍必须验证旧版 `yyyy-yyyy-semester` 语义。空闲教室默认使用旧版有证据的 `xqid=1`（学院路校区）和 `Asia/Shanghai` 日历的当前日期，脚本允许通过非敏感 `UBAA_VERIFY_CAMPUS_ID`、`UBAA_VERIFY_DATE` 覆盖；SPOC/希冀验证列表，非空时再验证一个详情。
- 只写脱敏摘要：功能、策略、解析路线、成功/失败、稳定错误码、耗时、计数和是否存在数据。不得写课程名、作业标题、完整学号、姓名、手机号、身份证号、邮箱、Cookie、token、验证码或原始响应。
- 对尚未被真实证据证明的另一条路线写入矩阵为“未证实”，不得用 fixture/Mock 代替。
- `unsupported_portal`、研究生账号不支持本科接口或缺少必要账号能力属于真实失败：命令返回非零，状态文档记录“不适用/未完成”及重新运行条件，不能用空 fixture 代替。真正的上游空列表/空教室/无作业是成功解析的有效空结果。其他要求的真实查询失败也返回非零；外部上游阻断必须在 `docs/migration/status.md` 记录命令、错误分类和重新运行条件。

提交：`test: verify automatic routes and readonly features live`

### 阶段 12：文档、门禁和持续开发交接

产物：`route-policy.md`、`readonly-features.md`、`readonly-feature-matrix.md`、live runbook、更新后的 architecture/contracts/status/README/AGENTS，以及 CI/敏感扫描/锁定依赖门禁。

必须做到：

- `just refs`、`just check-sensitive`、`just check`、CLI binary E2E 和阶段 11 的 live 命令全部实际运行并记录摘要。
- `just check` 覆盖双槽位迁移、TCP 网关探测三态与 500ms 总预算、部分成功登录、每个只读 parser/fixture、路由矩阵和唯一的 schema version 2 CLI 输出。
- CI 只运行脱敏 fixture/Mock/CLI deterministic tests，不读取 `.env.local`，所有 Cargo 依赖解析使用 `--locked`。
- `docs/migration/status.md` 必须把课表、考试、成绩、空闲教室、SPOC、希冀逐项列出实现状态和真实证据；只有对应硬门槛通过后才能标记为已迁移，未完成项必须明确标记为未迁移/未验证及阻断原因。
- 最终报告明确每个功能的已验证路线、未验证路线、空结果/不支持账号状态和剩余写操作范围。

提交：`docs: complete readonly migration and route handoff`

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
6. 未迁移能力清单：Flutter、MCP、服务器中转、评教、图书馆、通知、云盘、WiFi、所有写操作及其他未列入本合同的业务；课表、考试、成绩、空闲教室、SPOC、希冀必须分别列出真实证据状态，不得笼统写成已完成。
7. 双路线会话迁移、配置策略、TCP 网关探测和每个只读功能的已验证/未验证路线。
8. 下一步建议必须引用旧版文件和测试位置，不得只写抽象愿望。

如果任意硬门槛未通过，报告结论必须是“未完成”，并列出失败命令、错误分类、是否为外部上游阻断，以及重新运行条件。不能以 fixture 通过替代真实登录，也不能以某一种连接模式通过替代另一种。

## 12. 执行启动顺序

执行 Agent 必须按以下顺序开始：

1. 阅读本文件全文和 `UBAA2.md`。
2. 检查 `git status --short --branch`，确认不覆盖既有用户修改。
3. 验证参考目录 HEAD 与本文件的固定提交一致，只读检查 `.env.local` 变量名，不读取或输出变量值。
4. 创建并更新执行计划；确认阶段 0-6 基线后，从阶段 7 开始逐阶段推进，不得回退已完成基线。
5. 在写入代码前先写阶段 7 的路由/配置/安全合同；在每个阶段结束运行门槛并提交。
6. 遇到参考实现未覆盖的行为时，停止猜测，记录决策日志和需要人工确认的事实。

不得先搭建 Flutter、MCP、服务器或其他未纳入本合同的宿主。不得先批量复制旧 Kotlin 代码再补边界。不得在没有测试和文档的情况下宣称“框架完成”，也不得用一次 Direct 或 WebVPN 登录成功替代六个只读功能的真实矩阵验收。

## Ready-to-paste Codex goal prompt

执行 `/Users/moorefoss/Code/UBAA/goal.md` 全部内容。先完整阅读该文件、`UBAA2.md`、冻结的 `ubaa_old` 参考实现和固定提交的 `examples/buaa-api`，检查工作树与 `.env.local`，确认阶段 0-6 基线后，继续完成阶段 7-12：三态 `gw.buaa.edu.cn:80` TCP 连通性探测（含解析和全部地址尝试的总预算 500ms）、`auto|direct|webvpn` 功能策略、Direct/WebVPN 双槽位登录与会话迁移、课表/考试/成绩/空闲教室/SPOC/希冀六类只读 Core/CLI/JSON/fixture、功能路由矩阵、真实 auto 验收、文档和最终门禁。Core facade 必须拥有配置加载、探测和选路，CLI 只解析与渲染；所有 CLI JSON 只输出 schema version 2。所有协议行为必须以参考代码、参考测试或真实上游证据为依据，禁止猜测；禁止修改或提交 `ubaa_old/`、`examples/`、`.env.local` 及任何敏感数据。普通用户命令不得暴露或要求 `--mode`；Direct/WebVPN 仅作为内部 route override、测试和诊断维度。必须通过 `just refs`、`just check-sensitive`、`just check`、CLI binary E2E，以及 `just verify-live feature=auth route=direct`、`feature=auth route=webvpn`、`feature=all route=auto` 和六个只读 feature 的真实矩阵命令。每阶段小步提交并更新文档和 `docs/migration/status.md`。任一硬门槛未通过都不得声称完成，最终报告必须列出每个功能的实际命令、证据、已验证/未验证路线、剩余写操作范围和下一步引用位置。
