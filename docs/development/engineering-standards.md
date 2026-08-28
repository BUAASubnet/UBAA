# UBAA2 Engineering Standards

This document is the repository-wide contract for Rust Core and CLI work. Core owns
protocol facts, routing, session/cookie scope, crypto, parsing, caching and concurrency.
Hosts call only the facade and may not inspect upstream responses or session storage.

Every direct operation must have a source-parity row covering bootstrap and service URLs,
redirect/final URL rules, cookie/session scope, method and exact parameters, headers/body,
crypto/signatures, DTO/parser fields, caching/concurrency, and error/exit semantics. Evidence
order is live upstream observation, frozen `ubaa_old`, then pinned `examples/buaa-api`.
Conflicts are recorded in `docs/migration/decision-log.md`; fields are never guessed.

Feature changes use a failing sanitized fixture or Mock request first, then the smallest
implementation, focused tests, `just check-sensitive`, and `just check`. Sensitive inputs
(`ubaa_old`, `examples`, `.env.local`, sessions, cookies, tokens, captcha images and live
bodies) are read-only and never staged, logged or persisted.

Read operations must be verifiable independently on Direct, WebVPN and auto routes. Live
verification never invokes a write. Every write has deterministic request/parser evidence and
is blocked by default at the CLI with an explicit `--confirm-write` gate; confirmation does
not bypass Core validation or route/session ownership checks.

Stable CLI output is schema version 2: JSON goes only to stdout, diagnostics to stderr, and
exit codes are limited to the documented taxonomy. Human output must not expose credentials,
cookies, raw upstream bodies, complete HTML or captcha data.

Code is organized by domain, ports, connection, session, auth, features, facade, commands,
execution and render. New logic belongs in the smallest owning module; do not extend a
multi-thousand-line host file when a feature module or command helper is appropriate.

## 跨宿主交接规范

| 宿主 | 允许依赖 | 禁止依赖 | 输出与错误要求 |
|---|---|---|---|
| Rust Core | `domain`、`ports`、`connection`、`session`、`auth`、`features`、`facade` | 向宿主泄漏上游原始响应；绕过 facade 访问运行时状态 | 只返回稳定 DTO、结构化错误和路线元数据 |
| CLI | `facade`、`commands`、`execution`、`render` | 直接调用 `upstream`、读取 Cookie/Session、在 argv 放置密码或令牌 | human/JSON schema v2、稳定退出码、敏感字段脱敏 |
| Flutter/OpenHarmony/Node/Swift/Kotlin/ArkTS | 版本化 facade 契约或对应绑定层 | 依赖 Rust 私有模块、拼接上游 URL、保存业务令牌或原始 HTML | 与 CLI 相同的错误分类；平台日志不得包含认证材料 |
| MCP/Server | 经过授权的 facade 服务接口 | 暴露 `ubaa_old`、`examples`、实时 Cookie/Token、未审计写操作 | 读操作逐项可观测；写操作默认关闭并保留审计上下文 |

跨宿主新增能力必须先更新 `docs/contracts/` 与 `docs/migration/source-parity.md`，再添加脱敏 fixture/Mock 和绑定层测试。宿主不得以“已有兼容实现”为理由复制旧版内部协议；若冻结实现与实时上游冲突，应在 `decision-log.md` 记录证据并保留失败语义。本轮只交付 Rust Core + CLI，其他宿主仅维护契约和边界文档。
