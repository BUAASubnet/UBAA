# Rust Core 路线边界精简

日期：2026-10-30。本文记录 facade 操作收尾和旧会话写入路径的整理。

## 冻结来源与范围

开始修改生产代码前，已经通过 `just refs` 校验两个冻结提交：旧版 UBAA 为
`1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api 为
`a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

本轮读取的旧版来源为 `LocalConnectionAuth.kt`、`ConnectionRuntime.kt`、
`LocalAuthSessionStoreTest.kt` 和 `ConnectionRuntimeTest.kt`，目录均位于冻结
`examples/ubaa_old/shared/src/`。对照 buaa-api 的 `src/context.rs`、`src/request.rs`、
`src/api/user/auth.rs`、`src/store/cookies.rs`、`src/store/cred.rs` 和 `src/error.rs`。
具体业务操作继续使用[来源对照索引](source-parity.md)中的既有九列结论，本轮不修改任何
feature 请求、解析、DTO 或上游常量。

| 操作 | CAS/引导 URL 与 service | 重定向与最终 URL | Cookie/Session/Token 范围 | 方法与精确参数 | 请求头与正文编码 | 加密/签名常量 | DTO 与解析 | 缓存/并发/重试 | 错误/退出与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| 会话所有权预检 | 本地操作，不发送引导请求。两来源没有进程 CAS 协议。 | 不发请求。 | 旧版按 `ModeScopedSessionStore` 隔离路线；示例 Context 持有 Cookie/凭据。继续保留 Core 的双路线槽位和进程 CAS。 | 不发 HTTP。 | 不发 HTTP。 | 不涉及。 | 不改会话格式、字段或 revision。 | 合并紧邻的重复预检；最终非幂等发送前的 revision 检查保留。发现外部变更不采用外部快照。 | 冲突后清内存并返回原错误，保留旧版认证失效的清理范围。 |
| 普通读取收尾 | 不改变原 feature 的 URL/service。 | feature 内原逻辑保留。 | 旧版业务认证失败通过 `resolveLocalBusinessAuthenticationFailure` 仲裁主会话；示例没有等价仲裁。仅 `authentication_required` 清当前路线，网络及解析错误保留会话。 | 原委托不变。 | 原委托不变。 | 原委托不变。 | 原委托不变。 | 不增加读取、缓存或重试。共享收尾保留原错误优先级。 | 保留普通路由元数据和固定路线 `FeatureResult` 两种公开结果。 |
| 学校写入收尾 | 不改变原 feature 的 URL/service。 | feature 内原逻辑保留。 | 复用当前路线，保留发出前 fresh authority 和会话 CAS。 | 原委托不变。 | 原委托不变。 | 原委托不变。 | 原委托不变。 | 两冻结来源没有 Core 的 non-idempotent 结果保护；继续采用现有更严格规则。跨发送边界后禁止重放。 | 发送后的确定结果或 `outcome_unknown` 不能被清理失败覆盖，读取核对和公开错误保持原合同。 |
| 旧格式磁盘写入 | 本地操作，两来源均不适用 Core schema-v1/v2。 | 不发请求。 | 生产仅写双路线 schema-v2。旧格式加载迁移继续保留。 | 不发 HTTP。 | JSON 编码不变。 | 不涉及。 | 测试构造器仍可生成旧格式；生产不保留独立旧格式写 API。 | 继续使用同一文件锁、原子替换和 CAS。 | 旧格式迁移失败保持原安全错误。 |

buaa-api 传输构造器允许调用方关闭 TLS，且错误日志支持原始内容。这些行为与本项目安全规则冲突，
本轮不采用。旧版和示例均没有等价的 Core 文件 CAS、只读工作实例代次和写发送边界，因此这些机制
继续由现有合同与确定性测试验证。

## 实现与验证

`UbaaClient` 和 `RouteClient` 现在共用 `RouteExecution` 的路线所有权检查、认证失效清理和
写发送边界收尾。普通 facade 继续拥有双路线全局清理，固定路线客户端继续在操作收尾时核对本路线
revision。两种公开结果和所有公开操作签名保留。

原审查用 `RouteClient` 的 1126 行说明重复维护范围，其中也包括必要的公开签名、文档和固定路线
结果转换，不能把这 1126 行全部计为可删除代码。本轮集中共享安全逻辑，没有引入通用命令注册表
或改变 feature 的协议所有权。

新反例证明，未完成认证的固定路线客户端在 `InternalError` 后仍保留登录过程取得的 `SESSION`
Cookie。该反例先失败，随后通过共用普通 facade 已有的完整内存清理规则修复。初次失败与通过日志
分别保存在本地忽略目录 `.ubaa_local/core_simplification/` 的 `boundary-red.log` 和
`boundary-green.log`。

旧 `FileSessionStore` 单路线写入实现仅在 `test` 或 `test-contract` 构建中存在。生产继续加载并迁移
旧格式，只通过双路线协调器写 schema-v2。两种格式复用同一个带长度限制的 JSON 编码器。

`RouteClient` 的紧邻重复预检已经移除。`ClientRuntime::request_non_idempotent_with_pre_send_check`
仍在交给 transport 前核对 revision，之后的传输错误和清理失败仍保留已发送结果。
场馆取消原有测试按“第 3 次检查”注入故障，受重复预检次数影响。本轮改为在 fresh 详情读取完成后
注入会话存储错误，继续要求保留原错误、读取详情一次、取消请求零次。该测试保留发送前失败覆盖，
不再绑定内部检查次数。

聚焦检查结果：

- Core 默认关闭 `test-contract` 的 `cargo check --locked -p ubaa-core` 通过。
- Core lib，以及 facade、session、route_matrix、cgyy、libbook、bykc、evaluation、signin、ygdk
  九个 integration test 目标共 652 项通过，1 项按既有设置忽略。
- 本次差异空白检查通过。完整工程验收由本轮主记录汇总。

本节聚焦验证使用合成 transport，没有发起学校请求。完整确定性验收和整合后的真实双路线只读
验证结果见[本轮主记录](2026-10-30-core-simplification.md)。
