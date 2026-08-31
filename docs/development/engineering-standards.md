# UBAA2 工程规范

本文是 Rust Core 和 CLI 工作的仓库级合同。Core 负责协议事实、路由、会话/Cookie 作用域、
密码学、解析、缓存和并发。宿主只能调用 facade，不得检查上游响应或会话存储。

每个 Direct 操作都必须有 source-parity 行，覆盖引导/服务 URL、重定向/最终 URL 规则、
Cookie/会话作用域、HTTP 方法和精确参数、Header/正文、加密/签名、DTO/解析字段、缓存/并发
以及错误/退出语义。证据顺序为真实上游观察、冻结 `ubaa_old`、固定版本
`examples/buaa-api`。冲突记录在 `docs/migration/decision-log.md`，不得猜测字段。

功能修改先添加会失败的脱敏 Fixture 或 Mock 请求，再做最小实现，运行 focused 测试、
`just check-sensitive` 和 `just check`。敏感输入（`ubaa_old`、`examples`、`.env.local`、
Session、Cookie、令牌、验证码图片和实时正文）只读，绝不暂存、记录或持久化。

只读操作必须能在 Direct、WebVPN 和 auto 路线上独立验证。实时验证绝不调用写操作。每个写
操作都必须有确定性的请求/解析证据，并在 CLI 默认阻止、要求显式 `--confirm-write`；确认
不能绕过 Core 校验或路线/会话所有权检查。

稳定 CLI 输出为 schema 版本 2：JSON 只写 stdout，诊断写 stderr，退出码限定于文档分类。
人工输出不得暴露凭据、Cookie、上游原始正文、完整 HTML 或验证码数据。

代码按 domain、ports、connection、session、auth、features、facade、commands、execution 和
render 分层。新逻辑应放在拥有其不变量的最小模块中；已有合适的功能模块或命令辅助模块时，
不要继续扩展数千行的宿主文件。

## 跨宿主交接规范

| 宿主 | 允许依赖 | 禁止依赖 | 输出与错误要求 |
|---|---|---|---|
| Rust Core | `domain`、`ports`、`connection`、`session`、`auth`、`features`、`facade` | 向宿主泄漏上游原始响应；绕过 facade 访问运行时状态 | 只返回稳定 DTO、结构化错误和路线元数据 |
| CLI | `facade`、`commands`、`execution`、`render` | 直接调用 `upstream`、读取 Cookie/Session、在 argv 放置密码或令牌 | human/JSON schema v2、稳定退出码、敏感字段脱敏 |
| Flutter/OpenHarmony/Node/Swift/Kotlin/ArkTS | 版本化 facade 契约或对应绑定层 | 依赖 Rust 私有模块、拼接上游 URL、保存业务令牌或原始 HTML | 与 CLI 相同的错误分类；平台日志不得包含认证材料 |
| MCP/Server | 经过授权的 facade 服务接口 | 暴露 `ubaa_old`、`examples`、实时 Cookie/Token、未审计写操作 | 读操作逐项可观测；写操作默认关闭并保留审计上下文 |

跨宿主新增能力必须先更新 `docs/contracts/` 与 `docs/migration/source-parity.md`，再添加脱敏 fixture/Mock 和绑定层测试。宿主不得以“已有兼容实现”为理由复制旧版内部协议；若冻结实现与实时上游冲突，应在 `decision-log.md` 记录证据并保留失败语义。本轮只交付 Rust Core + CLI，其他宿主仅维护契约和边界文档。
