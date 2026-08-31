# UBAA Core + CLI 收口、验证与交接执行目标

状态：执行中
周期：2026-08-31 起
项目根目录：`/Users/moorefoss/Code/UBAA`

本文件是本周期 Codex 的唯一活动目标和执行合同。Codex 必须持续推进到本文件的完成条件满足；不能只完成分析、列出建议或只提交局部修复。每个阶段都要留下可审查的代码、测试、文档和提交记录。

本周期的最终目标是：整理并稳定 Rust Core 与 CLI，修复 Cgyy 的统一路由行为，建立可复核的 Direct/WebVPN 真实只读验证，清理无用内容，完成一次完整代码审查，并把文档整理到可以开始 app、SDK 和 MCP 开发的状态。

本周期不实现 app、SDK、MCP、Flutter、Server 或其他宿主；只为这些后续宿主提供稳定、文档化的 Core facade 和 CLI 合同。

## 1. 当前基线和变更管理

1. 当前工作区中已经存在的未提交代码改动作为本周期基线，不把它们当作已经验收通过的代码。
2. 不要求在工作树中保留旧版 `goal.md` 的副本；替换后的本文件立即成为活动合同。旧内容如已存在于 Git 历史，不需要再复制到文档目录。
3. 开始任何功能改动前必须执行：

   ```text
   git status --short --branch
   just refs
   just check-sensitive
   just check
   ```

   如果基线检查失败，必须在 `docs/migration/status.md` 记录具体失败，不得通过删除测试、放宽门禁或伪造结果来“修复”基线。
4. 当前基线应尽快拆成可审查提交；格式整理、结构重构、Cgyy 路由、测试入口、清理和文档不得全部混在一个不可审查的提交中。
5. 每个阶段完成后都要检查 `git diff --check`、暂存文件和敏感信息。禁止使用会把嵌套参考仓库或运行时文件一起加入的宽泛 `git add .`。
6. `ubaa_old/`、`examples/`、`.env.local`、运行时 session、Cookie、Token、验证码图片和真实响应始终只读，不能修改或提交。

## 2. 范围、非目标和安全底线

### 2.1 本周期必须完成

- 统一 Rust、Shell、测试和文档相关的格式、目录职责和命名；保持目录有真实职责，不创建空模块。
- 清理确认无用、无引用或被等价合同完全替代的测试、脚本和临时文档。
- 将 Cgyy 接入与其他功能相同的 Direct/WebVPN/auto 路由语义，不再在 WebVPN 主路线下强制使用 Direct 业务传输。
- 完成 Core 确定性测试、Core-live 真实只读测试、CLI 合同测试、CLI 二进制端到端测试和启动器安全测试。
- 完成当前功能清单中所有读操作的 Direct 与 WebVPN 逐操作真实证据；auto 只通过确定性路由测试，不做额外真实登录矩阵。
- 完成当前 Core 与 CLI 已纳入范围的读写能力实现检查。写操作只实现、只做 Fixture/Mock/向量/阻止路径测试，绝不在真实账号上执行。
- 对完整代码和文档差异进行独立审查，修复审查发现的问题。
- 整理 `docs/` 中的项目文档和 Rust/Shell 代码注释，使维护性说明使用中文、职责清晰、没有重复结论，并补齐后续宿主所需的公共合同说明。

### 2.2 明确不做

- 不在本周期实现 app、SDK、MCP、Flutter、OpenHarmony、Node、Swift、Kotlin、ArkTS、Server 或旧 API 兼容层。
- 不在真实上游执行签到、选课、退选、打卡提交、照片上传、图书馆预约/取消、场馆预约/取消、评教提交或任何其他业务写操作。
- 不增加跨多个独立 CLI 进程的全局客户端、常驻 daemon 或 CLI 会话，也不持久化 Cgyy 业务令牌。Core-live 的内部验证批次例外允许复用一个客户端，但不向普通 CLI 扩展该能力。
- 不关闭 TLS 校验，不绕过 CAS/SSO，不硬编码账号，不把凭据放进命令行参数、Fixture、日志或文档。
- 不通过猜测补齐 URL、参数、Header、Cookie、加密常量、DTO 字段或错误语义。
- 不以编译通过、Fixture/Mock 通过或单个聚合命令通过替代逐操作真实只读证据。

### 2.3 不可变参考和证据优先级

协议事实按以下顺序取得：

1. 当前真实上游的安全只读观察；
2. `docs/migration/references.md` 固定提交中的 `ubaa_old/` 实现和测试；
3. 固定提交中的 `examples/buaa-api/`，但仅在协议确实等价时使用；
4. 已记录的架构决策和合同。

每个认证、读操作和写操作都必须在 `docs/migration/source-parity.md` 或链接的决策记录中逐操作记录以下九类事实：业务 CAS/Bootstrap URL 和 Service、重定向与最终 URL、Cookie/Session/Token 作用域、方法与参数、Header 与 Body 编码、加密/签名常量、DTO 与解析、缓存/并发/重试、错误和退出语义。

如果参考来源冲突，先在 `docs/migration/decision-log.md` 记录具体文件、提交、实时观察和选择理由，再改生产代码。`examples/buaa-api/` 没有等价协议时必须明确写“不适用”，不能类比借用。

## 3. Core、CLI 和路线合同

### 3.1 Core 与宿主边界

- `facade` 是 CLI、未来 app、SDK、MCP 唯一允许依赖的 Core 公共边界。
- 宿主不能访问 raw upstream client、DTO、Cookie、连接实现、内部 Feature 状态或 Session Store。
- Core 不读取 `.env.local`，不打印终端，不决定 CLI 退出码；凭据由外层安全注入，输入、渲染、退出码由 CLI 负责。
- Session 文件只保存允许持久化的路线 Cookie、时间戳和版本信息；业务访问令牌、验证码和原始响应不落盘。
- `UbaaClient` 是可由宿主持有的客户端实例，但本周期不引入隐式进程全局单例。一个 Core-live 批次可以持有同一个 `UbaaClient` 并连续调用多个方法。

### 3.2 统一路线语义

- `direct`：只使用 Direct runtime、Direct transport 和 Direct 会话。
- `webvpn`：只使用 WebVPN runtime、WebVPN transport 和 WebVPN 会话；不得因 Cgyy 特殊处理而转用 Direct。
- `auto`：使用现有统一探测和路由解析逻辑选择 Direct 或 WebVPN；本周期只用确定性测试覆盖，不执行独立真实 auto 矩阵。
- 显式路线失败时不得在 Feature 内部偷偷切换另一条路线；如需回退，只能由统一 `auto` 策略决定并在结果中记录。
- 两条路线的主 Cookie、业务令牌、认证工作流、失效清理和重试状态必须隔离。

## 4. Cgyy WebVPN 改造合同

1. Cgyy 的所有公共读写方法都必须使用 facade 解析出的路线 runtime；不得继续调用固定的 `direct_runtime` 或无视 runtime 的原始直连 URL。
2. WebVPN 路线下，Cgyy 的 SSO 引导、业务登录、业务请求、重定向、Cookie、Header、Referer、签名和响应解析都必须经过 WebVPN transport/URL 策略。若上游实际协议要求某个字段或路径不同，必须由当前只读证据证明并记录。
3. Direct 路线保持现有已验证行为；本次变更只取消 Cgyy 对 WebVPN 强制走 Direct 的特殊决定，不把旧版特殊路线规则继续当作当前产品要求。
4. Cgyy 业务令牌只在选定路线和当前 `UbaaClient` 生命周期内缓存；正常同一批次复用一次业务登录，明确的业务认证失效最多执行一次清理、重新登录和请求重放。
5. 必须先增加失败的 WebVPN-only 测试：只有 WebVPN 会话、没有 Direct 会话时，Cgyy 仍能构造并发送 WebVPN 请求；然后实现最小修复并保留 Direct、WebVPN、auto Mock 回归。
6. 如果真实 WebVPN 上游不支持某项操作，记录为该路线的真实失败或不适用，不得静默改走 Direct，也不得伪造成功。
7. Cgyy 写协议仍需完成实现、请求顺序、签名/验证码向量和 CLI 显式确认测试，但本周期不得用真实写请求验证。

## 5. 代码格式和目录结构

本节定义的是可执行的职责边界和迁移目标，不要求一次性把每个文件拆成目录。现有文件只有在职责确实分离、测试可以跟随迁移且公共 API 不变时才移动；候选文件名是建议，不得为了“看起来整齐”创建空模块或只转发一行代码的文件。

### 5.1 设计原则

1. **按依赖方向分层。** 领域类型不依赖网络和宿主；协议实现不依赖 facade；CLI 只依赖 facade、稳定输出类型和错误合同。上层只能调用下层公开的窄接口，不能通过 `pub` 或路径绕过边界。
2. **按行为聚合文件。** 一个文件应围绕一个可测试的责任（例如路由解析、Cookie 持久化、Cgyy 读操作），而不是按“工具函数”随意堆放。跨多个业务的函数必须放在真正拥有其不变量的层，禁止继续增加无主的 `utils.rs`、`helpers.rs`。
3. **公共面与内部实现分离。** `mod.rs` 和 crate 根只声明模块、组合实现和导出稳定类型；请求 URL、上游 DTO、Cookie、业务 Token、验证码和重试状态保持 `pub(crate)` 或私有。
4. **垂直切片优先。** 大型业务按“入口/协议、读、写、解析、认证、密码学”拆分，相关测试与脱敏 Fixture 同步归位。跨业务共享的只有已证明稳定的基础设施，不为未来 app、SDK、MCP 预先抽象空接口。
5. **重构与行为修改可区分。** 文件移动和纯格式化必须能单独编译、测试和回滚；Cgyy WebVPN 行为、Core-live 入口和测试矩阵修改不得隐藏在大规模重排提交中。

Rust 的同名模块不得并存。例如将 `connection.rs` 变为目录时，必须把它迁移为 `connection/mod.rs`（同理处理 `config`、`session`、`output` 以及 `features/<name>`），不能同时保留 `connection.rs` 和 `connection/`。迁移采用保留历史的 `git mv`，完成一个模块的声明、导出、编译和测试后再处理下一个模块；过渡期只能在父模块保留明确的兼容 `pub use`，不能复制一套实现。

### 5.2 Core 目标树和每层职责

目标树如下。标注“可选拆分”的文件只有在现有文件被触碰、职责边界已经由测试证明时才创建。

```text
crates/ubaa-core/
├── src/
│   ├── lib.rs                         # crate 根；只声明公共模块和版本
│   ├── domain/                        # 路线无关的领域模型、值对象和结果类型
│   │   ├── mod.rs                     # 声明与 re-export，不放业务逻辑
│   │   ├── auth.rs
│   │   ├── route.rs
│   │   ├── schedule.rs
│   │   ├── grades.rs
│   │   ├── classroom.rs
│   │   ├── signin.rs
│   │   ├── spoc.rs
│   │   ├── judge.rs
│   │   ├── ygdk.rs
│   │   ├── libbook.rs
│   │   ├── bykc.rs
│   │   ├── cgyy.rs
│   │   └── evaluation.rs
│   ├── ports/                         # 可替换边界：HTTP、存储、时钟、日志
│   │   ├── mod.rs                     # trait 和公共端口类型的总入口
│   │   ├── http.rs                    # 可选拆分：请求、响应、Transport trait
│   │   ├── storage.rs                 # 可选拆分：Session 存储 trait
│   │   ├── clock.rs                   # 可选拆分：时间注入
│   │   └── logging.rs                 # 可选拆分：脱敏诊断接口
│   ├── adapters/                      # 可选：具体外部适配实现，不污染 ports 抽象
│   │   ├── mod.rs                     # 可选拆分：适配器声明
│   │   └── http/reqwest.rs            # 当前 ReqwestTransport 的迁移位置
│   ├── config/                        # 路线策略和安全的配置文件读写
│   │   ├── mod.rs                     # 配置公共入口
│   │   ├── types.rs                   # 可选拆分：RouteConfig 等类型
│   │   ├── validation.rs              # 可选拆分：字段和 TOML 校验
│   │   └── store.rs                   # 可选拆分：安全文件持久化
│   ├── connection/                    # Direct/WebVPN 的传输和路由机械
│   │   ├── mod.rs                     # RouteResolution 等入口的组合
│   │   ├── direct.rs                   # 可选拆分：Direct URL/请求策略
│   │   ├── webvpn.rs                   # 可选拆分：WebVPN URL/请求策略
│   │   ├── redirect.rs                 # 可选拆分：有界重定向和主机白名单
│   │   ├── probe.rs                    # 可选拆分：探测和诊断
│   │   ├── policy.rs                   # 可选拆分：路线选择与认证主机规则
│   │   └── codec.rs                    # 当前 connection_codec.rs 的私有实现
│   ├── session/                       # Cookie、Session 文件和并发协调
│   │   ├── mod.rs                     # SessionStore/Coordinator 组合入口
│   │   ├── cookies.rs                 # Cookie jar 与作用域
│   │   ├── types.rs                   # Session 快照、版本和安全字段
│   │   ├── storage.rs                 # 文件读写、权限和原子更新
│   │   ├── ports.rs                   # Session 专用端口适配
│   │   ├── coordinator.rs             # 双路线协调、锁和 stale writer 处理
│   │   └── validation.rs              # 可选拆分：快照校验和敏感字段拒绝
│   ├── auth/                          # CAS/SSO、重定向和用户中心激活工作流
│   │   ├── mod.rs                     # AuthWorkflow 公共入口
│   │   ├── cas.rs                     # 可选拆分：CAS 表单和票据步骤
│   │   ├── redirect.rs                # 可选拆分：登录重定向规则
│   │   ├── activation.rs              # 可选拆分：用户中心激活编排
│   │   └── status.rs                  # 可选拆分：认证状态和失效分类
│   ├── runtime/                        # crate-private 客户端运行时与请求上下文
│   │   ├── mod.rs                     # 运行时组合入口
│   │   ├── client.rs                  # 可选拆分：单 client 生命周期
│   │   ├── request.rs                 # 可选拆分：统一请求/刷新
│   │   └── state.rs                   # 可选拆分：中性路线状态容器
│   ├── upstream/                      # crate-private 上游常量、表单和解析器
│   │   ├── mod.rs                     # 私有适配入口
│   │   ├── auth.rs                    # 可选拆分：认证表单/解析
│   │   ├── user.rs                    # 可选拆分：用户信息解析
│   │   ├── redirect.rs                # 可选拆分：上游跳转解析
│   │   └── parsers.rs                 # 可选拆分：共享 HTML/JSON 解析
│   ├── features/                      # 业务协议、解析、状态和操作
│   │   ├── mod.rs                     # 业务入口和共享小函数
│   │   ├── state/                     # crate-private、按路线隔离的业务状态
│   │   │   └── mod.rs                 # 状态聚合入口
│   │   ├── schedule.rs                # 当前同时承载 Schedule/Exam；拆分前先记录边界
│   │   ├── grades.rs
│   │   ├── classroom.rs
│   │   ├── signin.rs
│   │   ├── user.rs
│   │   ├── cgyy/                      # 重点垂直切片，见 5.3
│   │   ├── judge/                     # 大文件按读/解析/认证拆分
│   │   ├── spoc/                      # 大文件按读/解析/认证/密码学拆分
│   │   ├── bykc/                      # 大文件按协议/读/写/解析拆分
│   │   ├── libbook/                   # 大文件按认证/读/写/解析拆分
│   │   ├── ygdk/                      # 大文件按认证/读/写/上传拆分
│   │   └── evaluation/                # 任务读取、本地派生和写保护
│   ├── facade/                        # 唯一面向宿主的稳定 API
│   │   ├── mod.rs                     # 声明、组合和 re-export
│   │   ├── client.rs                  # UbaaClient 生命周期
│   │   ├── route_dispatch.rs          # mode→runtime 的统一解析/借用
│   │   ├── diagnostic.rs              # RouteClient 和诊断 API
│   │   ├── auth.rs                    # 登录、状态、退出委托
│   │   ├── user.rs                    # 用户资料委托
│   │   ├── schedule.rs、exam.rs、grades.rs、classroom.rs
│   │   ├── spoc.rs、judge.rs、signin.rs、ygdk.rs、libbook.rs
│   │   ├── bykc.rs、cgyy.rs、evaluation.rs # 每个业务的路由解析与委托
│   │   ├── types.rs                   # facade 专用请求/结果类型
│   │   ├── aggregate_helpers.rs       # 聚合读取的共享编排
│   │   └── session_lifecycle.rs       # 会话刷新、清理和失效处理
│   ├── output/                        # 稳定结果 envelope、错误和校验
│   │   ├── mod.rs                     # 公共导出
│   │   ├── envelope.rs                # 可选拆分：JSON/聚合 envelope
│   │   └── validation.rs              # 可选拆分：Schema 和安全字段校验
│   └── error/                         # 稳定错误码、错误种类和退出语义
│       ├── mod.rs                     # 公共导出
│       ├── codes.rs                   # 可选拆分：ErrorCode/ExitCode
│       └── types.rs                   # 可选拆分：UbaaError/ErrorKind
└── tests/                             # Core 边界和合同测试（见 5.5）
```

各层的职责和禁止事项如下：

| 层 | 允许负责的内容 | 不得出现的内容 |
|---|---|---|
| `domain` | DTO、值对象、路线无关的业务结果、稳定枚举 | HTTP、Cookie jar、文件读写、CLI 输出、上游 URL |
| `ports` | trait、请求/响应等可替换抽象 | 具体业务 URL、重试循环、文件路径和终端交互 |
| `config` | 路线策略、TOML 解析和配置文件安全读写 | 主机白名单/重定向决策、认证 Cookie、业务 Token、网络请求 |
| `connection` | Direct/WebVPN URL、请求上下文、探测、主机白名单、重定向和路线锁定 | 业务解析、业务登录、跨路线隐式回退 |
| `session` | Cookie 作用域、文件快照、并发协调、失效清理 | Cgyy/Judge 等业务参数和协议解析 |
| `auth` | CAS/SSO 步骤、票据、用户中心激活编排和认证错误分类 | 用户资料 DTO、CLI 凭据读取、业务功能请求、终端输出 |
| `features` | 某一业务的请求、解析、状态、缓存、重试和读写保护 | 调用另一个业务的私有状态、直接暴露给宿主 |
| `runtime` | 单个 `UbaaClient` 的生命周期、路线上下文、统一 request | 公共宿主 API、进程全局单例、CLI 逻辑 |
| `facade` | 路线解析、认证前置、业务委托、稳定返回类型 | 上游细节、原始响应、终端打印 |
| `output` | Core 可序列化的稳定 envelope 和安全校验 | HTTP 请求、Session 文件、CLI 样式 |
| `upstream` | crate-private 常量、表单编码、上游解析 | `pub` 宿主接口、猜测的协议字段 |
| `adapters` | `ReqwestTransport` 等具体外部实现 | 领域规则、公共宿主合同和业务解析 |

`domain` 可以继续使用 `serde` 派生，因为这些类型构成稳定 DTO/JSON 合同；“领域无网络依赖”不等于禁止序列化。当前 `ports/mod.rs` 中的 `ReqwestTransport` 是历史布局，目标是将具体实现移到 `adapters/http/reqwest.rs`（或经审查后放入 `connection/transport/`），并在 `ports` 暂时保留兼容导出，直到所有调用方完成迁移。`SessionStore` 等 trait 留在 `ports`/`session` 的抽象面，`FileSessionStore` 属于 Core 的具体存储实现，不应被 CLI 业务代码直接使用。

生产宿主边界与测试注入边界必须区分：CLI、未来 app、SDK、MCP 只能依赖 `facade`；Core 集成测试和 `ubaa-test-support` 可以在 `dev-dependencies`/测试合同中使用 `features` 的解析器、`session` 的测试存储和 `ports` 的 Mock。当前 `features`、`session` 的部分符号因跨 crate 测试仍为 `pub`，本周期不得直接收窄造成编译破坏；先迁移测试到稳定的 test-support 接口，记录 API 快照和版本策略，再在单独的兼容变更中隐藏或移除。任何兼容 re-export 都必须标注不属于宿主稳定 API，并有对应的可见性测试。

### 5.3 大型业务的垂直切片

目录拆分必须保留一个窄的 `mod.rs` 入口，并让每个子模块有明确的输入、输出和测试。以下是本周期的首选边界：

```text
features/cgyy/
  mod.rs             # 对 features 暴露的操作入口
  protocol.rs        # 业务登录、请求构造、URL/参数和重试策略
  auth.rs            # manageLogin/api/login 等业务认证步骤
  read.rs            # 站点、用途、日期、订单、详情、锁码读取
  write.rs           # 预约/取消请求链；只由显式写 API 调用
  captcha.rs         # 验证码挑战、校验和失败分类
  parser.rs          # envelope、列表、详情、动作响应解析
  crypto.rs          # 当前 cgyy_crypto.rs 的实现
  sign.rs            # 当前 cgyy_sign.rs 的实现
  diagnostics.rs     # 脱敏日志和诊断摘要

features/judge/
  mod.rs  read.rs  parser.rs  status.rs  auth.rs  diagnostics.rs
features/spoc/
  mod.rs  read.rs  parser.rs  auth.rs  protocol.rs  crypto.rs
features/bykc/
  mod.rs  read.rs  write.rs  parser.rs  auth.rs  protocol.rs  crypto.rs
features/libbook/
  mod.rs  read.rs  write.rs  parser.rs  auth.rs  crypto.rs
features/ygdk/
  mod.rs  read.rs  write.rs  parser.rs  auth.rs  upload.rs
features/evaluation/
  mod.rs  read.rs  write.rs  parser.rs  projection.rs
```

其中：

- `read.rs` 只包含只读请求和读取结果；`write.rs` 只包含写请求链、确认前置和默认阻止逻辑，便于静态审查真实写风险。
- `parser.rs` 不发请求，密码学模块不决定路线；这两类纯函数优先使用 Fixture/向量测试。
- `auth.rs` 只处理该业务的二次认证或业务会话建立；顶层 CAS/SSO 仍归 `auth/`。
- Cgyy 的业务 Token 必须由路线作用域的状态容器管理，不能由 `parser`、全局静态变量或 Session 文件持久化。
- `schedule` 当前同时承载 Schedule 与 Exam 操作；拆成 `schedule.rs`/`exam.rs` 前先用测试和 parity 记录两者的共享请求及不同语义，不能只按命令名机械移动。`grades`、`classroom`、`signin`、`user` 当前规模较小，可先保持单文件；只有出现第二个独立协议阶段或超过行数阈值时才拆目录。
- `features/state.rs` 与 `state_cache.rs` 应合并为私有 `features/state/`，按业务拆分状态结构。若拆分后 `runtime` 与业务模块形成循环，先把不透明状态容器上移为私有 `runtime_state`，不得让业务模块互相读取私有状态。

### 5.4 现有文件到目标结构的迁移映射

以下映射是重构顺序和审查边界，不表示现在立即执行所有 `git mv`：

| 当前文件/模块 | 目标位置 | 拆分边界和优先级 |
|---|---|---|
| `config.rs` | `config/mod.rs`、`types.rs`、`validation.rs`、`store.rs` | 先分离纯配置类型，再分离安全文件写入；低风险基础设施 |
| `ports/mod.rs` | `ports/mod.rs` 加 `http`/`storage`/`clock`/`logging` 抽象；`ReqwestTransport` → `adapters/http/reqwest.rs` | 先保留 `ports::ReqwestTransport` 兼容导出，确认没有宿主依赖后再收窄 |
| `connection.rs`、`connection_codec.rs` | `connection/` 下的 `direct`、`webvpn`、`redirect`、`probe`、`policy`、`codec` | 路线解析和 URL 转换先保持行为不变；Cgyy 协议改动不得混入机械移动 |
| `session.rs` 与现有 `session/*` | `session/mod.rs`、`coordinator.rs`、`cookies.rs`、`storage.rs`、`types.rs`、`ports.rs` | 先抽协调器和安全校验，再移动文件存储；保留并发/stale writer 测试 |
| `auth/mod.rs` | `auth/mod.rs` 加 `cas`、`redirect`、`activation`、`status` | 每次只移动一个认证阶段，保留 CAS/SSO 顺序测试；用户资料仍由 `features/user` 负责 |
| `runtime.rs` | `runtime/mod.rs`、`client.rs`、`request.rs`、`state.rs` | 先抽出中性 `RouteFeatureState`/状态接口，再拆请求流程；保持 `pub(crate)` |
| `upstream/mod.rs`、`upstream/tests.rs` | `upstream/` 私有子模块与对应测试 | 常量、编码器、解析器分离；不提升可见性 |
| `features/state.rs`、`state_cache.rs` | `features/state/` | 状态结构与缓存策略分开；状态必须仍按路线和客户端实例隔离 |
| `features/cgyy.rs`、`cgyy_crypto.rs`、`cgyy_sign.rs` | `features/cgyy/` | 本周期首要拆分对象；先写 WebVPN-only 失败测试，再做行为变更 |
| `features/judge.rs`、`spoc.rs` | 各自目录的 `read/parser/auth/diagnostics` | 第二批大文件；先保证只读解析和诊断行为不变 |
| `features/bykc.rs`、`libbook.rs`、`ygdk.rs` | 各自目录的 `read/write/parser/auth` | 写请求与读请求物理分离，方便真实写禁止审查 |
| `features/evaluation.rs` | `features/evaluation/` | 将本地 pending 投影与上游任务读取分开，不增加额外请求 |
| `features/schedule.rs`、`grades.rs`、`classroom.rs`、`signin.rs`、`user.rs` | 暂留原位置 | 小模块暂不为拆分而拆分；触碰且超过阈值时再迁移 |
| `facade/mod.rs`、`types.rs`、`aggregate_helpers.rs`、`session_lifecycle.rs` | `facade/client.rs`、按业务的 facade 文件及现有辅助模块 | `mod.rs` 只组合；每个业务 facade 文件只做路线解析、前置和委托，不做协议解析 |
| `apps/ubaa-cli/src/lib.rs` | `backend.rs`、`execution/`、`input/`、`render/`、`args/` | 首要 CLI 拆分对象；先保留 `lib.rs` 作为 crate 根和 re-export，避免改变二进制合同 |
| `commands.rs` 与各 `*_args.rs` | `commands.rs` 加 `args/` | Clap 定义与运行逻辑分离；参数类型不持有 Core runtime |
| `input.rs`、`render.rs`、`execution.rs` | `input/`、`render/`、`execution/` 子模块 | 输入、调用编排、展示和退出码分离；禁止在 render 层发请求 |

迁移 `config.rs`、`connection.rs`、`runtime.rs`、`output.rs` 或某个 `features/<name>.rs` 时，目标目录的 `mod.rs` 必须先接管原模块内容，再逐步把真实实现移入子文件；不得在同一次提交中留下同名文件和目录。若外部测试暂时依赖旧路径，使用父模块的兼容 re-export，并在下一阶段更新调用方和可见性合同。

### 5.5 CLI 目标树和宿主边界

```text
apps/ubaa-cli/
├── src/
│   ├── main.rs                         # 进程启动、日志初始化、配置和一次性 client 组装
│   ├── lib.rs                          # crate 根、公共 trait/re-export；保持薄
│   ├── commands.rs                     # 顶层 Clap 命令和子命令组合
│   ├── args/                           # 可选目标目录；由现有 *_args.rs 迁入
│   │   ├── mod.rs                     # 参数模块组合和 re-export
│   │   ├── auth.rs  user.rs  schedule.rs  exam.rs
│   │   ├── grades.rs  classroom.rs  spoc.rs  judge.rs
│   │   ├── signin.rs  libbook.rs  bykc.rs  cgyy.rs
│   │   ├── ygdk.rs  evaluation.rs
│   │   └── common.rs                   # 只有确实共享的参数
│   ├── backend.rs                      # CliBackend/RoutedCliBackend 适配
│   ├── execution/
│   │   ├── mod.rs                      # 命令分派和错误汇总
│   │   ├── auth.rs                     # 登录、状态、退出流程
│   │   ├── readonly.rs                 # 只读命令编排
│   │   ├── writes.rs                   # 写命令确认和阻止门
│   │   └── feature.rs                  # 可选：业务 runner（仅在文件过大时拆）
│   ├── input/
│   │   ├── mod.rs                      # 安全输入入口
│   │   ├── credentials.rs               # stdin/受控输入，不把凭据放参数
│   │   ├── payloads.rs                  # 业务 JSON/表单输入
│   │   └── write_guard.rs               # 写操作确认、默认拒绝
│   ├── render/
│   │   ├── mod.rs                      # 展示入口
│   │   ├── human.rs                    # 人类可读输出
│   │   ├── json.rs                     # 稳定 JSON envelope
│   │   └── error.rs                    # 错误映射和退出码
│   ├── routing.rs                      # CLI 路线参数到 Core RoutePolicy 的转换
│   ├── connection_mode.rs              # CLI 参数类型
│   └── command_output.rs               # 命令级中间结果
└── tests/
    ├── cli_contract.rs                 # 参数、JSON、错误和安全合同
    ├── binary_e2e.rs                   # 真实进程边界
    └── launcher_contract.rs            # Shell 启动器合同（如适用）
```

CLI 的依赖只允许是 `ubaa_core::facade`、`domain`、`output` 和稳定错误类型。CLI 不得导入 `runtime`、`session`、`upstream`、`features::*` 的内部模块，也不得自行拼接上游 URL、Cookie 或业务 Token。`main.rs` 不保存跨进程状态；每个进程创建一个 client 属于当前合同，跨命令全局复用仍是本周期非目标。

### 5.6 测试、Fixture 和证据的镜像结构

生产代码移动时，测试按“被证明的合同”而不是按历史文件名归位：

```text
crates/ubaa-core/tests/
├── contracts.rs                    # facade、输出、错误码和可见性合同
├── domain.rs                       # 可选：纯领域不变量
├── auth.rs
├── connection.rs
├── route_policy.rs
├── session.rs  cookies.rs
├── facade/                         # 可选目录；按业务拆分现有 facade.rs
│   ├── auth.rs  schedule.rs  ...
│   └── cgyy.rs
├── features/                       # 可选目录；按业务和行为拆分
│   ├── cgyy.rs  judge.rs  spoc.rs
│   └── bykc.rs  libbook.rs  ygdk.rs
└── parsers/                        # 纯解析/加密向量，不发网络请求

crates/ubaa-test-support/
├── src/
│   ├── lib.rs                      # 公开最小测试 API
│   ├── fixtures.rs                 # 脱敏 Fixture 加载
│   ├── transport.rs                # 精确请求/响应 Mock
│   ├── assertions.rs               # 路线、Cookie、敏感字段断言
│   └── sessions.rs                 # 临时 Session 和并发测试辅助
└── tests/
    ├── auth.rs  readonly.rs  writes.rs  security.rs
    └── support.rs

apps/ubaa-cli/tests/
├── cli_contract.rs                 # 参数、渲染、JSON、退出码
├── binary_e2e.rs                   # 进程、stdin、Session 文件和 facade 边界
└── launcher_contract.rs            # verify-live/core-live 参数转发和安全

fixtures/
├── auth/  connection/  session/
├── schedule/  exam/  grades/  classroom/  spoc/  judge/
├── signin/  ygdk/  libbook/  bykc/  cgyy/  evaluation/
└── README.md                       # 脱敏规则和来源说明
```

现有的 `readonly.rs`、`auth.rs` 等大型测试可以渐进拆分，但每次移动必须保留原有断言并在提交说明中列出覆盖映射。真实验证结果放在 `docs/migration/` 的状态或证据记录中；`fixtures/` 永远只含脱敏请求、响应和向量，不放原始 live body、Cookie、Token、验证码或完整个人资料。

测试目录也遵守同名模块规则：如果把 `facade.rs` 或 `readonly_parsers.rs` 拆成目录，先将原文件迁为该目录的唯一入口（例如 `facade/mod.rs`，或保留一个明确命名的 `facade_contract.rs` 测试入口），再添加子模块；不能让 Cargo 同时发现两套同名测试目标。测试辅助目录中的 `mod.rs` 只组合测试模块，不复制生产实现。`ubaa-test-support` 只提供脱敏 Fixture、精确 Mock、断言和临时 Session，不提供真实登录快捷路径。

脚本按“入口薄、职责单一”整理：

```text
scripts/
├── ensure-references.sh             # 固定参考提交检查
├── check-sensitive.sh               # 敏感文件/内容扫描
├── core-live.sh                     # Core-live 的安全网络入口（如采用脚本封装）
├── verify-live.sh                   # 仅参数校验、凭据注入和 Core-live 转发
└── test-verify-live.sh              # verify-live 薄封装的 Shell 合同
```

脚本不得各自实现登录、请求、解析或重试；需要共享的检查应调用一个已审查的实现并测试参数转发。脚本重命名或合并前，先更新 `justfile`、CI 和 `docs/` 的引用。

### 5.7 依赖方向和可见性门槛

```text
CLI
  -> facade
facade -> config + connection + session + auth + features + domain/error/output
auth -> runtime + upstream + domain/error
       └─> features::user（仅在保留现有用户中心适配时）
features -> runtime + domain + error + ports + crate-private upstream helpers
runtime -> connection + session + ports + runtime_state（均为 Core 内部）
connection -> config + domain + error + ports + adapters
session -> domain + error + ports/std
adapters -> ports
upstream -> domain + error（纯表单/文本解析，crate-private）
domain -> std/serde 等无网络依赖
```

必须同时满足以下规则：

- `domain`、`output` 和 `ports` 不得反向依赖 `features`、`facade` 或 CLI。
- 业务 Feature 不得调用另一个 Feature 的私有函数；需要共享时先提升为有合同的 Core 基础设施并补测试。
- `facade` 是唯一向宿主公开业务操作的层；`pub(crate)` 不能通过 re-export 间接泄露给 CLI。
- `runtime` 可以持有路线作用域的状态容器，但不能变成进程全局单例；若状态拆分引入循环，使用私有中性模块解决，不降低可见性。
- 任何需要 `HttpRequest`、Cookie、重定向或上游常量的代码都必须位于 Core 内部；CLI 和公共 `domain` 不能出现这些依赖。
- 模块重命名后用编译器、API 快照和合同测试确认可见性没有扩大；禁止以“方便测试”为由把内部协议类型改成 `pub`。

### 5.8 结构迁移顺序和完成标准

按以下顺序执行，每一步都保持行为中性并单独提交：

1. 记录当前模块图、公共 API、命令和测试基线；用 `git mv` 保留历史，先不改协议。
2. 拆分 `config`、`connection`、`session`、`output` 等基础设施，先跑对应单元/合同测试，再跑 `just check`。
3. 将 `facade/mod.rs` 按认证、用户和业务委托拆开；确认所有宿主仍只依赖 facade。
4. 将 CLI `lib.rs` 分为参数、backend、execution、input 和 render；保持命令、JSON 和退出码不变。
5. 先拆 Cgyy，再拆 Judge/SPOC/Bykc/LibBook/Ygdk/Evaluation；每个业务的读、写、解析和认证边界分别有测试。
6. 最后整理测试和 Fixture 目录，删除无覆盖映射的重复内容；清理不能与行为修改混在同一提交。

结构阶段的完成标准是：没有空目录或无主的“工具”模块；每个公共类型有唯一归属；大文件达到阈值或有书面例外；依赖方向和可见性测试通过；`cargo fmt --check`、Clippy、敏感扫描、Core 合同测试和 CLI 测试通过。若某次拆分无法在不改变行为的情况下完成，保留原文件并在 `docs/migration/status.md` 记录原因，不得为了满足树形图强行移动。

### 5.9 格式和重构规则

- Rust 使用锁定工具链、rustfmt 和 Clippy；Shell 保持 `bash -euo pipefail` 约束并通过语法检查。
- 新增生产文件原则上不超过 500 行；超过 800 行时，下一次触碰必须先拆分职责。单个函数原则上不超过 80 行，超过 120 行必须记录原因。
- 第一批重点检查大文件：`apps/ubaa-cli/src/lib.rs`、`crates/ubaa-core/src/facade/mod.rs`、`session.rs`、`features/cgyy.rs`、`features/spoc.rs`、`features/judge.rs`、`features/state.rs`、`features/bykc.rs` 及大型测试文件；`domain/mod.rs` 只做结构性瘦身，不以行数为理由拆分领域文件。
- 纯格式化、行为保持的结构重构和协议行为修改分别提交；不得用全仓库无关格式化掩盖功能差异。
- 保持现有 facade、CLI 命令、JSON Schema 和错误码的向后兼容。新增能力优先使用增量字段、命令或版本；破坏性变化必须更新合同、测试和决策记录。

## 6. 完整测试矩阵

### 6.1 证据层级

| 层级 | 证明内容 | 是否访问真实上游 |
|---|---|---|
| Core 单元/合同 | 领域模型、错误、URL、Cookie、Session、路由和稳定输出 | 否 |
| Fixture/解析 | 脱敏响应解析、请求构造、加密/签名向量 | 否 |
| Core Mock 集成 | 登录顺序、精确请求、路线锁定、缓存、重试和写保护 | 否 |
| Core-live | Core facade 与当前上游的真实认证和读协议 | 是，仅只读 |
| CLI 合同 | 输入、渲染、JSON Schema、错误分类、敏感信息脱敏 | 否 |
| CLI 二进制 E2E | 真实 CLI 进程、参数边界、facade-only 依赖、会话文件行为 | 否，使用 Fixture/Mock |
| 启动器/Shell 合同 | `verify-live` 参数转发、stdin 凭据、锁定构建、输出安全 | 否 |
| 写操作合同 | 精确请求链、向量、响应、确认和默认阻止 | 否，严禁真实写 |

普通 `cargo test`、`just check` 和 CI 必须保持离线。Core-live 必须是显式 opt-in 的独立入口；外层命令可以安全读取 `.env.local` 并通过 stdin 或受控输入注入凭据，Core 不直接读取该文件。

### 6.2 Core-live 真实矩阵

真实验证只跑两条路线：

```text
route=direct   -> 一个 Core client、一次登录批次、串行执行全部必需读操作
route=webvpn   -> 一个 Core client、一次登录批次、串行执行全部必需读操作
```

每条路线的证据按“操作 × 路线”单独记录，不能用一次聚合 `all` 覆盖单项失败。至少覆盖当前功能清单中的以下读操作：

- Auth/User：登录准备、登录状态、用户信息；
- Schedule：学期、教学周、周课表、今日课表；
- Exam：指定学期考试安排；
- Grades：指定学期成绩；
- Classroom：校区和日期的空闲教室；
- SPOC：作业列表、诊断信息、作业详情；
- Judge：当前列表、包含过期列表、诊断信息、单项详情、批量详情；
- Signin：今日签到状态；
- Ygdk：总览、记录分页；
- LibBook：馆列表、区域、区域详情、座位、预约记录；
- Cgyy：站点、用途、日期、订单、订单详情、锁码；
- Bykc：用户资料、课程列表、课程详情、已选课程、统计；
- Evaluation：全部任务和本地派生的待评教任务。

依赖操作必须显式记录条件状态：没有有效 ID 时详情为 `NOT_APPLICABLE` 并说明原因；依赖失败导致的后续操作为 `BLOCKED`；认证、网络或协议错误为 `FAIL`。状态只允许 `PASS`、`FAIL`、`BLOCKED`、`NOT_APPLICABLE`、`FORBIDDEN`。任何必需读操作出现未解决的 `FAIL` 或 `BLOCKED`，本周期不能完成。

`Evaluation pending`、SPOC/Judge 诊断等本地派生或复用链不得虚增上游请求，但必须在证据中说明其依赖关系。Schedule 选出的学期必须被 Exam/Grades 一致使用；Cgyy 日期、订单、详情和锁码必须逐项记录，即使上游返回暂时性错误。

### 6.3 真实禁止项

Core-live、`verify-live`、手工真实验收和 CI 都不得调用：

- 签到执行；
- 打卡提交或照片上传；
- 图书馆预约、取消；
- Cgyy 预约、验证码提交、取消；
- Bykc 选课、退选、签到；
- 评教提交；
- 其他会改变真实账号状态的操作。

这些操作只能通过脱敏 Fixture、Mock、向量测试和 CLI 默认阻止/显式确认路径验证。

### 6.4 `core-live` 与 `verify-live`

- `core-live` 是唯一拥有真实网络逻辑的验证入口，建议提供明确的 `route=direct|webvpn` 和 `feature=all|<feature>` 参数。
- Core-live 必须在一次路线批次内复用同一 `UbaaClient`；不能为每个 operation fork CLI 进程。
- `verify-live` 只保留兼容和便利调用功能，负责参数校验、凭据安全注入和调用 Core-live，不得包含另一套请求、解析、登录或业务重试逻辑。
- `scripts/test-verify-live.sh` 应改为验证该薄封装的安全合同；如果更名，必须保留等价覆盖并更新所有引用。
- Core-live 的真实输出只允许安全摘要：路线、操作、阶段、稳定错误码、耗时、数量或存在性标志；禁止输出凭据、Cookie、Token、验证码、原始响应和完整个人数据。

### 6.5 确定性和 CLI 门槛

至少保持并扩展以下测试：

```text
just refs
just check-sensitive
just check
cargo test --locked -p ubaa-cli --all-targets
```

新增或修复行为必须先添加失败的脱敏测试，再实现最小改动，运行 focused test，最后运行完整门槛。auto 只在 Core 路由解析、Mock facade 和 CLI 路由输出中验证，不进入真实账号矩阵。

## 7. 测试和脚本清理

1. 先列出每个测试、Fixture、脚本的被测合同、调用方和替代覆盖；没有覆盖映射不得删除。
2. 保留安全、写保护、路由隔离、Session 并发、Cgyy 单批次业务登录复用和 CLI/facade 边界测试，即使它们在不同层看起来相似。
3. 清除无引用、仅重复旧实现且已有等价覆盖的脚本和测试；删除前更新 `justfile`、CI、文档和运行手册中的所有引用。
4. `verify-live` 的旧网络实现必须删除或彻底改为 Core-live 薄封装，不能两套逻辑并存。
5. `ubaa_old/`、`examples/`、固定证据、ADR、迁移状态和必要的决策记录不能因“清理冗余”删除。已完成且无证据价值的临时计划可以合并或删除，但不能删除唯一的协议依据。

## 8. 完整代码审查

代码审查在 Cgyy、Core-live、结构整理和清理完成后进行，审查基线为本周期全部提交相对于基线提交的完整差异。审查至少覆盖：

- facade 是否仍是唯一宿主边界；
- Direct/WebVPN Cookie、Session、业务 Token 和失效清理是否隔离；
- Cgyy 是否存在隐藏 Direct 回退或路线错配；
- 并发、缓存、重试、版本冲突和 stale writer 行为；
- URL、Header、Body、签名、解析和错误分类；
- 敏感数据是否进入日志、stdout、错误、Fixture、Session 或命令参数；
- CLI 输入校验、JSON Schema、退出码和写操作确认；
- Core-live 是否可能执行真实写操作；
- macOS/Linux/Windows 锁定构建、测试和文档命令；
- 文档、代码、测试和状态证据是否一致。

审查发现的问题必须分类、修复并重新运行相关测试。未解决的高严重度问题、敏感泄漏、真实写风险、协议猜测和硬门槛失败都禁止宣布完成；低严重度问题若暂不修复，必须在状态或决策文档中说明理由和后续任务。

## 9. 文档整理和中文要求

### 9.1 语言范围

- `docs/**` 的维护性说明、表格、运行手册、迁移记录和 ADR 使用中文；
- Rust、Shell 代码注释使用中文，注释解释原因和不变量，不复述代码；
- 命令、代码标识符、JSON key、Schema 字段、URL、HTTP 方法/字段、上游固定值、许可证和必要的原文保持准确，不为中文化而改名；
- `README.md`、`AGENTS.md`、`SECURITY.md`、`CONTRIBUTING.md` 等根目录文件不纳入本次语言范围，但涉及本周期命令或安全合同的内容必须同步更新。

### 9.2 文档职责和去重

统一文档职责：

- `docs/contracts/`：稳定的 Core/facade/CLI/JSON 合同；
- `docs/architecture/`：架构和边界；
- `docs/development/`：开发、测试和命令；
- `docs/migration/`：逐操作 parity、状态、证据和冲突决策；
- `docs/runbooks/`：真实验证和故障排查；
- `docs/adr/`：长期架构决策；
- `docs/superpowers/`：工作计划和设计草案，完成后只保留仍有引用或证据价值的内容。

必须删除重复的完成定义、过时的“六项功能”或旧 `verify-live` 唯一入口表述，统一改为全量操作、Core-live、Direct/WebVPN 双路线和逐操作证据。保留历史失败和上游不稳定记录，但明确其日期、范围和是否仍为当前阻塞项。

## 10. 分阶段执行顺序

### 阶段 0：基线提交

- 执行基线命令，检查工作树、参考提交和敏感文件；
- 审阅当前未提交改动，把实现改动作为本周期基线及时提交；
- 不把基线提交描述为功能验收通过。

### 阶段 1：合同、清单和测试设计

- 核对当前功能清单和每个 operation；
- 更新 source parity、decision log 和只读矩阵的旧入口/旧路线表述；
- 固化 Cgyy 统一路由语义、Core-live/verify-live 边界、状态分类和写操作禁止规则；
- 为缺失行为先写失败测试。

### 阶段 2：格式和结构

- 运行格式化、Clippy 和现有测试；
- 做行为保持的模块拆分和 CLI 分层；
- 单独提交格式/结构变更，确保功能差异可单独审查。

### 阶段 3：Cgyy 路由修复

- 增加 WebVPN-only、Direct、auto Mock 和路线隔离测试；
- 删除 Cgyy 固定 Direct runtime/URL 特例；
- 实现统一 runtime、Cookie、业务令牌、重试和错误清理；
- 运行 Cgyy focused tests、facade tests 和 CLI contract tests。

### 阶段 4：Core-live 和全量测试矩阵

- 实现 Core-live 一次路线批次内的共享客户端和逐操作安全证据；
- 将 `verify-live` 改为薄封装并补齐其 Shell 合同测试；
- 先完成所有确定性门槛，再分别运行 Direct 和 WebVPN 的完整只读矩阵；
- 失败、阻塞和不适用操作逐项写入 `docs/migration/status.md`。

### 阶段 5：清理

- 按覆盖映射删除无用测试、脚本和无引用计划；
- 删除重复实现而不是删除唯一证据；
- 更新 `justfile`、CI 和全部命令文档。

### 阶段 6：代码审查和修复

- 审查完整差异和安全边界；
- 修复所有高严重度问题及可复现的行为缺陷；
- 每项修复遵循失败测试、最小实现、focused test、全量门槛。

### 阶段 7：文档和交接

- 完成 `docs/**` 中文化、去重和链接检查；
- 补齐 app、SDK、MCP 所需的 facade、JSON、错误、路线、Session 生命周期和版本兼容说明；
- 复核代码、测试、状态、parity、决策和命令文档一致。

### 阶段 8：最终门槛

- 运行所有确定性门槛、CLI E2E、敏感扫描和 Direct/WebVPN Core-live 矩阵；
- 检查没有真实写请求、敏感泄漏、未提交生成物或错误引用；
- 只有所有必需读操作通过、所有写操作有确定性实现证据、审查问题已处理、文档一致且工作区可交接时，才能报告本周期完成。

## 11. 最终验收和报告格式

最终报告必须区分：

1. 已实现的 Core/CLI 读操作和写操作；
2. Direct 与 WebVPN 的逐操作真实只读结果；
3. auto 的确定性路由测试结果；
4. 写操作仅有 Mock/向量/阻止证据，未在真实账号执行；
5. 确定性门槛、CLI E2E、敏感扫描和代码审查结果；
6. 仍未完成、被上游阻塞或明确不适用的项目；
7. 面向 app、SDK、MCP 的可用公共合同和已知限制。

不得使用“全产品完成”“所有平台完成”或其他超出本周期范围的表述。任何真实写操作、凭据泄漏、参考仓库修改或未记录的协议猜测都属于硬失败，必须立即停止并记录。
