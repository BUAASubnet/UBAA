# UBAA2 工程规范

本文适用于 Rust Core/CLI/Test Support、Flutter/FRB/OHOS、测试、脚本、文档与 CI。当前产品范围是已完成的
Flutter 六平台无签名执行目标；正式签名、实体设备、原生安全存储和商店发布仍是后置条件。当前结构治理
必须保持现有协议、公开合同、用户行为和安全边界不变。

## 权威与来源

Rust Core 负责协议事实、路由、会话/Cookie 作用域、密码学、解析、缓存和并发。生产宿主只能调用 facade
或专用 bridge，不得检查上游响应、读取内部 Session、拼接 URL 或保存业务 Token。

每个认证、读取和写入操作都必须在 `docs/migration/source-parity.md` 记录：引导/服务 URL、重定向/最终 URL、
Cookie/Session/Token 作用域、HTTP 方法和精确参数、Header/正文、加密/签名、DTO/缺失值、缓存/并发/重试、
错误/退出和产品语义。证据顺序是安全实时观察、冻结 `ubaa_old`、固定 `examples/buaa-api`；参考没有等价协议
时记录“不适用”，发生冲突时停止该边界并写入 decision log。

## TDD 与变更边界

- 行为修改先增加会失败的脱敏 Fixture、Mock 请求、解析或状态测试，再做最小实现。
- 机械目录移动不得顺手改变条件、顺序、默认值、公开类型、文案、key、semantics、golden 或网络调用。
- 机械结构提交与行为敏感提交分开；FRB 生成刷新、golden 更新和证据文档也应独立可审查。
- 新逻辑放在拥有其不变量的最小领域模块；`lib.rs`、`mod.rs`、Dart barrel 和 composition root 只声明、组合与导出。
- 受版本控制的手写代码文件不得超过 1000 行，一个目录直属手写源码不得超过 16 个；临时例外只由
  结构棘轮 baseline 管理，不得新增。

详细目标树、迁移顺序与例外见[代码与目录组织设计](../architecture/code-organization.md)和
[实施计划](../superpowers/plans/2026-09-03-code-organization.md)。

## 跨宿主边界

下表是本轮结构治理的终态约束。当前 CLI/bridge 仍有直接导入部分 Core 公共类型、Core 仍拥有 CLI 输出/退出
策略等已登记例外；它们由实施计划阶段 04、06C 关闭，不得被新代码继续扩大。

| 层/宿主 | 允许依赖 | 禁止依赖 | 输出与错误要求 |
|---|---|---|---|
| Rust Core | domain、ports、connection、session、auth、features、facade 内部依赖 | 向宿主泄漏上游原始响应；拥有 CLI 进程/展示策略 | 只经 facade 返回稳定 DTO、结构化错误和路线元数据 |
| CLI | Core facade 与 CLI 自有 command/backend/execute/io | 直接调用 upstream/runtime；读取 Cookie；argv 明文密码 | human/JSON schema v4、稳定 stdout/stderr/退出码、敏感字段脱敏 |
| FRB bridge | Core facade 与专用 bridge DTO | 暴露 Core 私有类型、URL、Cookie、业务 Token 或原始 HTML | 版本锁定、typed error/DTO、生成 schema 零漂移 |
| Dart domain/app/UI | bridge/backend 稳定合同与平台 typed 能力 | 自行处理协议/路线；从中文展示字段推断写资格 | 明确 loading/empty/failure/stale；写入一次性确认和未知结果保护 |
| 平台宿主 | 共享 app/UI、平台路径/权限/安全存储接口 | 复制业务状态机；以明文文件替代安全存储 | 缺少原生 handler 时安全返回 unavailable，不冒充设备能力 |
| 测试支持 | facade testing 边界、脱敏 fixture、Mock transport | 将测试构造器暴露给生产宿主；记录请求敏感正文 | 精确请求/解析/并发证据，不打印凭据或正文 |

CLI 公开 envelope 的版本与本地持久化版本分别治理。破坏性 DTO/错误合同变化必须显式提升 CLI
`schemaVersion` 并由 JSON Schema 与真实序列化合同共同验证；不得在旧版本号下静默改变字段。当前 CLI
envelope 为 schema v4，`session.json` 仍为 schema v2，`config.toml` 仍为版本 1。

## 写入与发布

CLI 写操作默认拒绝并要求 `--confirm-write`；Flutter 使用 typed prepare→一次性确认→单次 commit→读取核对。
Core 校验始终是最终权威。写请求可能到达上游后不得自动重试，`outcome_unknown` 必须提示先读取核对。

真实写入不属于普通测试、CI 或代码组织计划；每次必须有具体操作、目标、路线和时间授权。无签名 Debug/HAP、
Mock、golden、simulator 或 CI artifact 不能证明签名、安装、实体设备、硬件安全存储或正式发布。

## 安全与提交

`ubaa_old/`、`examples/`、`.env.local`、Session、Cookie、Token、验证码、真实响应、个人资料、签名材料和构建
缓存只读且不得进入 diff。提交前使用明确 pathspec 暂存，人工检查 staged 文件和内容，再运行
`just check-sensitive`。禁止关闭 TLS、放宽 parser/lint、删除测试或手改生成文件来获得通过。
