# 离线恢复逐操作来源对照

日期：2026-09-17。P0/P2 认证增量合同实施前记录。冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，已通过 `just refs`。

## 本阶段操作：所需路线会话校验

来源：旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` 的 `getAuthStatus`、`validateLocalConnectionSession`、`LocalAuthSessionStore`、`PersistentLocalCookieStorage`；测试 `LocalAuthServiceBackendTest.kt`、`LocalAuthSessionStoreTest.kt`。独立参考 `src/api/user/auth.rs`、`src/api/sso/auth.rs`、`src/request.rs`、`src/store/cookies.rs`、`src/store/cred.rs`。

| 项目 | 冻结旧版 | buaa-api | 新合同决策 |
|---|---|---|---|
| CAS/bootstrap/service | 状态检查不登录；UC `/api/uc/status` | User login 先按凭据 TTL 触发 SSO，再 status + UC 激活；不是只校验合同 | 新 `recover_required_session(feature)` 只校验所需路线，不提交密码，不激活其他路线 |
| 重定向/最终 URL | 非 JSON 或无有效用户导致失效；SSO 页面不能算成功 | SSO 使用最终 URL 和状态，User login 无等价状态结果 | 复用当前 `user::auth_status`；不修改已固定解析和重定向策略 |
| Cookie/会话 | 当前模式存储，域/path/secure/过期过滤；失效清理当前模式 | 共享 context/store，由调用方管理 | 同一 UbaaClient/DualSessionCoordinator；检查双槽所有权；不创建第二持久客户端，不复制 Cookie |
| HTTP/精确参数 | GET status，无查询参数 | GET status 带 selfTimestamp，然后 GET activate | 保留当前无参数 status；不借用示例时间戳或激活序列 |
| 头/编码 | Accept JSON，X-Requested-With，GET 无正文 | reqwest GET | 保留现有 transport/request 合同；本阶段仅改变调用范围，无新增头或正文 |
| 加密/签名 | 状态接口无额外加密 | 状态接口无额外加密 | 无新增常量 |
| DTO/解析 | code=0、data 用户，保留 authenticatedAt，刷新 lastActivity | 无等价 AuthStatus DTO | 返回 Routed<AuthStatus>，实际路线 + 完整现有用户类型；不伪装双路线 all_ready |
| 缓存/并发 | 当前模式的本地会话不是业务缓存；调用验证状态 | 凭据 TTL | Core 使用现有功能路由矩阵和探测规则；Bridge 单次锁只包一条路线检查，归还锁后才能补另一条 |
| 错误/退出 | 缺会话直接未认证；5xx 暂时故障不清会话；明确失效清当前模式 | 不提供同等细分状态，禁止套用 | RoutedError 保留具体 resolution/code/kind/retryable；全局会话冲突仍清全部内存；CLI 原聚合顺序/退出语义不变 |

旧 `auth_status`、`prepare_login`、`login` 继续固定 Direct 后 WebVPN，返回两条结果。新入口只服务 App 所需路线恢复，未执行路线不能显示已核实。Auto 沿 Core 功能矩阵/网关/已就绪候选规则选择；宿主不猜路线。

## 尚未批准为已完成的其他范围

持久缓存和 Judge 分段/刷新必须分别补齐逐操作记录后再改动生产实现。当前原生安全凭据 handler 在六个平台均未接线（现行平台文档和源码一致）；不能把 Dart Mock 的 capability 当作实际密钥可用。业务缓存需专属随机密钥接口，不能将密码当作加密密钥、将业务正文塞进凭据或降级明文。此事实是实施工作项，尚未证明任何平台缓存可用。
