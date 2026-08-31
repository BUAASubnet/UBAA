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

### 5.1 结构目标

保持并逐步收敛到以下职责层次：

```text
crates/ubaa-core/src/
  domain/       领域模型和值对象
  ports/        HTTP、存储、时钟、日志等可替换端口
  connection/   Direct、WebVPN、重定向、探测和请求上下文
  session/      Cookie、Session、持久化和并发协调
  auth/         CAS/SSO 认证工作流
  features/     每个业务的协议、解析、状态和操作
  facade/       面向宿主的稳定公共 API

apps/ubaa-cli/src/
  commands/     参数和命令定义
  execution/    Core 调用编排
  render/       人类输出、JSON 和错误展示
```

实际没有行为或合同的目录不得创建。`mod.rs` 只做模块声明、组合和公开导出，不承载完整业务实现。一个测试文件只负责一个领域或一个明确跨模块合同，测试结构应镜像生产结构。

### 5.2 格式和重构规则

- Rust 使用锁定工具链、rustfmt 和 Clippy；Shell 保持 `bash -euo pipefail` 约束并通过语法检查。
- 新增生产文件原则上不超过 500 行；超过 800 行时，下一次触碰必须先拆分职责。单个函数原则上不超过 80 行，超过 120 行必须记录原因。
- 第一批重点检查大文件：`apps/ubaa-cli/src/lib.rs`、`crates/ubaa-core/src/facade/mod.rs`、`domain/mod.rs`、`session.rs`、`features/spoc.rs`、`features/judge.rs`、`features/state.rs`、`features/bykc.rs` 及大型测试文件。
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
