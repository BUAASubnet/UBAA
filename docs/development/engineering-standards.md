# UBAA2 工程规范

本文供修改 Rust Core/CLI、Flutter/FRB/OHOS、测试、脚本和 CI 的贡献者使用，规定各层的所有权、依赖方向、写入边界和变更方式。结构调整必须保持既有协议、公开合同、用户行为与安全边界。

## 权威与来源

Rust Core 负责协议事实、路由、会话/Cookie 作用域、密码学、解析、缓存和并发。生产宿主只能调用 facade 或专用 bridge，不检查上游响应、不读取内部 Session、不拼接 URL、不保存业务 Token。

认证、读取或写入功能变更按 [AGENTS 来源对照门禁](../../AGENTS.md#来源对照门禁)执行；固定提交见[冻结参考](../protocol/references.md)，不能从历史记录继承版本或授权。

## TDD 与变更边界

- 行为修改先增加会失败的脱敏 Fixture、Mock 请求、解析或状态测试，再做最小实现。
- 机械目录移动不得顺手改变条件、顺序、默认值、公开类型、文案、key、semantics、golden 或网络调用。
- 机械结构提交与行为敏感提交分开；FRB 生成刷新、golden 更新和证据文档也应独立可审查。
- 新逻辑放在拥有其不变量的最小领域模块；`lib.rs`、`mod.rs`、Dart barrel 和 composition root 只声明、组合与导出。
- 受版本控制的手写代码文件不超过 1000 行，一个目录直属手写源码不超过 16 个。既有例外只由结构棘轮 baseline 管理，不新增。

目录树与组织约束见[代码与目录组织](../architecture/code-organization.md)和 [ADR 0006](../adr/0006-explicit-dart-modules.md)。

`just module-check` 补充 library 聚合规模、part 归属与依赖环检查；内部 Controller 操作使用 `@internal`，宿主不得绕过公共 API。独立测试不依赖聚合入口注册；原生入口必须登记到可执行清单。

## 跨宿主边界

下表是各层的所有权约束。输出/退出策略属于 CLI；Core 私有实现与测试注入面不能成为跨 facade 的生产依赖。Core 根部的稳定 `domain/error` 旧路径只用于类型兼容，不是宿主入口。

| 层/宿主 | 允许依赖 | 禁止依赖 | 输出与错误要求 |
|---|---|---|---|
| Rust Core | domain、ports、connection、session、auth、features、facade 内部依赖 | 向宿主泄漏上游原始响应；拥有 CLI 进程/展示策略 | 只经 facade 返回稳定 DTO、结构化错误和路线元数据 |
| CLI | Core facade 与 CLI 自有 command/backend/execute/io | 直接调用 upstream/runtime；读取 Cookie；argv 明文密码 | human/JSON 输出符合 [CLI 合同](../contracts/auth-and-user.md)、稳定 stdout/stderr/退出码、敏感字段脱敏 |
| FRB bridge | Core facade 与专用 bridge DTO | 暴露 Core 私有类型、URL、Cookie、业务 Token 或原始 HTML | 版本锁定、typed error/DTO、生成 schema 零漂移 |
| Dart domain/app/UI | bridge/backend 稳定合同与平台 typed 能力 | 自行处理协议/路线；从中文展示字段推断写资格 | 明确 loading/empty/failure/stale；写入一次性确认和未知结果保护 |
| 平台宿主 | 共享 app/UI、平台路径/权限/安全存储接口 | 复制业务状态机；以明文文件替代安全存储 | 缺少原生 handler 时安全返回 unavailable，不冒充设备能力 |
| 测试支持 | facade testing 边界、脱敏 fixture、Mock transport | 将测试构造器暴露给生产宿主；记录请求敏感正文 | 精确请求/解析/并发证据，不打印凭据或正文 |

共享 Dart 的依赖方向：

- 平台 app → `ubaa_host` → `ubaa_app`/`ubaa_ui`/`ubaa_platform`。
- `ubaa_app` 经唯一的 `BridgeBackend` 使用 bindings；`ubaa_ui` 生产代码只消费 domain 与 Flutter。
- `ubaa_domain` 定义不可变的 `WriteState/WriteOutcome`。
- `ubaa_app` 的 `WriteCoordinator` 是唯一的写入状态机，独占待确认意图、提交和失效状态；`WriteReceiptVerifier` 只编排只读核对和安全结果提示。
- Host 注入状态和 prepare/cancel/confirm 三个命令。缺少任一命令或领域能力时，UI 关闭写入口。

### 合同版本

CLI 公开 envelope 的版本与本地持久化版本分别治理：

- 破坏性 DTO/错误合同变化必须显式提升 CLI `schemaVersion`，由 JSON Schema 与真实序列化合同共同验证；不在旧版本号下静默改变字段。
- 当前 CLI 版本见 [CLI 合同](../contracts/auth-and-user.md)，Bridge 版本见 [Bridge 合同](../contracts/flutter-bridge.md)。
- 本地 `session.json` 为 schema v2，`config.toml` 为版本 1，与 CLI 版本独立。

### 写资格的来源

各写操作只从 Core 签发的 typed 资格与目标形成 action，展示字段、primitive ID、默认项或中文文案都不能兑换写权限：

| 领域 | 规则 |
|---|---|
| Ygdk | 只允许 fresh overview 派生的 typed `submitEligibility/submitTarget` 形成写 action |
| LibBook 座位 | 只通过可空整数 `status`、typed 资格和稳定目标开放预约 |
| LibBook 预约记录 | 只通过可空整数 `status` 与 typed `cancelEligibility/cancelTarget` 开放取消，不恢复或从展示文案推导写资格。取消 action 的 `page/limit` 只绑定 fresh 同页 authority/readback，最终 wire 只发送 `{id}` |
| Cgyy 时段 | 只通过可空整数 `reservationStatus`、typed `reservationEligibility/reservationTarget` 开放预约，不恢复 `isReservable`，不从状态文案反推资格 |
| Cgyy 预约输入 | Flutter 只接收一至两个同站点、日期、空间和空间组、唯一且 raw ordinal 相邻的 action；App、Bridge 与 Core 在各自边界失败关闭 |
| Cgyy 取消 | 只从 Core typed `cancelEligibility/cancelTarget` 构造 action，状态文本与时间字段只展示。最终 commit 的路线匹配与写发送在 Core 单次解析中原子完成；写后只在原路线消费本次列表/详情的 `cancelledTarget` 证明，不从全局 snapshot 或展示字段推断已取消 |
| Evaluation | 只由 Core fresh 读取中 `allowed` 且完整一致的 typed target 形成 action，完整问卷 authority、题目和答案不跨 facade。批量提交按输入顺序返回四态逐项结果，unknown 后停止后续发送；任一结果或异常只允许在 intent 原路线回读一次，回读不升级 outcome，也不自动重发 |

## 写入与发布

通用规则：

- CLI 写操作默认拒绝，要求 `--confirm-write`。Flutter 使用 typed prepare → 一次性确认 → 单次 commit → 读取核对。
- Core 校验始终是最终权威。
- 写请求可能到达上游后不自动重试；`outcome_unknown` 必须提示先读取核对。

LibBook 预约：

- 确定的业务拒绝保持 `success=false`。
- 发送后的 `outcome_unknown` 保留 Core 的稳定 code/kind/安全 message，强制 `retryable=false`，触发一次预约记录刷新，不重放写请求。

LibBook 取消遵守相同的发送边界：

- prepare 与 commit 都按 action 的同一页复核唯一 allowed 目标，最终 non-idempotent cancel 只发送一次。
- authority 分页元数据必须完整且无冲突，公开结果只使用固定安全文案。
- 成功或 unknown 后只刷新同一预约页，不用读取结果自动重放写入。
- 取消 authority 的列表错误不透传上游 message。Core 专用路径、CLI 和 Bridge 分别用固定文案做纵深收敛，普通只读列表的错误合同不变。

Cgyy 预约：

- prepare 与 commit 都 fresh 复核唯一 allowed target。
- 验证码获取/校验最多重试三次，且必须在最终发送前结束；最终 reservation submit 只越过一次 non-idempotent 边界。
- 确定成功至多附带安全收据；发送后的不确定结果统一为不可重试的 `outcome_unknown`。
- 公开写结果和错误不包含验证码、完整订单、上游 raw message 或个人信息。

真实写入不属于普通测试或 CI，授权规则见 [AGENTS 真实账号与验收范围](../../AGENTS.md#真实账号与验收范围)。无签名 Debug/HAP、Mock、golden、simulator 或 CI artifact 不能证明签名、安装、实体设备、硬件安全存储或正式发布。

## 安全与提交

`examples/`、`.env`、Session、Cookie、Token、验证码、真实响应、个人资料、签名材料和构建缓存只读，不进入 diff；完整清单与暂存步骤见 [AGENTS 安全边界](../../AGENTS.md#安全边界)和[开发循环](../../AGENTS.md#开发循环)。不以关闭 TLS、放宽 parser/lint、删除测试或手改生成文件换取通过。

## 日志与日常约定

日志字段和敏感材料按[日志与诊断脱敏](conventions.md#日志与诊断脱敏)处理，命名、语言、依赖、版本和 ADR 按[开发约定](conventions.md)执行。旧任务文档不能授权新的网络请求。
