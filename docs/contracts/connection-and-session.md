# 连接与会话合同

状态：确定性实现已完成；聚合原子协调器和过期写入者注销行为已有本地覆盖，修正后的
2026-08-26 HEAD 已通过 Direct/WebVPN 实时认证验证。

## 证据映射

| 行为 | 冻结证据 | Rust 覆盖 |
|---|---|---|
| Direct URLs remain direct | `LocalWebVpnSupport.kt::localUpstreamUrl` | `tests/connection.rs` |
| WebVPN gateway is `d.buaa.edu.cn` | `LocalWebVpnSupport.kt`, `VpnCipher.kt`, `examples/buaa-api/src/api/sso/auth.rs` | `tests/connection.rs` |
| Protocol segment is scheme for no/default port, otherwise `scheme-port` | `LocalWebVpnSupport.kt::toWebVpnUrl` and `VpnCipher.kt::toVpnUrl` | HTTP, HTTPS, default and custom-port tests |
| Host encoding uses AES/CFB/NoPadding with protocol constant `wrdvpnisthebest!` as key and IV | `LocalWebVpnSupport.kt`, platform AES implementations, `VpnCipher.kt` | URL round-trip tests |
| Path, query and fragment are retained | both frozen WebVPN implementations and tests | path/query/fragment round-trip tests |
| Already wrapped URLs are unchanged | both frozen WebVPN implementations | idempotence test |
| Absolute, protocol-relative, root-relative and path-relative redirects resolve from the current URL | `LocalConnectionAuth.kt::resolveRedirectUrl` | redirect table tests |
| Authentication redirects are restricted to SSO, User Center and gateway hosts | `goal.md` security contract plus observed auth URLs | rejection tests for unverified hosts |
| Authentication redirects accept only HTTP or HTTPS after host validation | `LocalConnectionAuth.kt::resolveRedirectUrl`, WebVPN protocol-segment tests | non-HTTP allowed-host rejection tests |
| Cookie filters include host/domain, path, Secure, expiration and replacement | `LocalConnectionAuth.kt::PersistentLocalCookieStorage`, `LocalCookieStoreTest.kt`, `examples/buaa-api/src/store/cookies.rs` | `tests/cookies.rs` |
| Explicit invalidation clears a session; timeout/5xx preserve it | `validateLocalConnectionSession` and `getAuthStatus` | `tests/session.rs` policy test |

自动路由选择同样属于 Core 所有的连接状态。生产探测器只连接 `gw.buaa.edu.cn:80` 的 TCP；单个 500 ms 总期限包含域名解析和所有地址尝试。三态结果在 facade 进程内以 single-flight 方式缓存 60 秒。它不发送 HTTP/TLS 正文，也不读取 Cookie 或凭据。完整策略和错误映射见 `docs/contracts/route-policy.md`。

## 持久化

每个聚合 facade 在 `<config-dir>/session.json` 中保存一个 schema-v2 双路线快照。Direct 与 WebVPN 槽位相互独立，包含过滤后的 Cookie、路线、认证时间和最后活动时间；不持久化用户名、密码、CAS execution、风险页面、不支持的交互步骤材料或业务令牌。旧版单路线快照只迁移到其记录的路线槽位。

旁车文件 `.session.lock` 串行化访问并保存定宽单调 revision。初始双路线快照与 revision 在同一个临界区加载。共享协调器拥有内存双路线快照和 revision；每次路线替换或聚合清理构造完整候选并且只执行一次 compare-exchange。过期进程返回安全的可重试冲突，绝不重新加载/采用外部 revision 来重试。聚合注销尽力请求两条远程路线，清除两个内存 runtime 和路线功能状态，随后尝试一次双槽持久化清理；冲突会保留更新后的两个槽位。

写入使用同目录唯一且独占创建的临时文件，并在替换前同步。会话、锁和配置目标拒绝符号链接及非普通文件；最终打开会话/锁文件使用平台 no-follow 标志。Unix 确定性测试覆盖符号链接拒绝、并发唯一临时写入、原子替换和 `0700`/`0600` 权限。会话读取上限为 1 MiB。Windows 使用继承的目录 ACL；自定义配置目录的所有者 ACL 仍是发布审计项。

原始 HTTP 传输保持 TLS 校验和手动重定向，并将完整缓冲的认证/用户中心正文限制为 8 MiB。两项限制都是内部安全预算，不是从上游协议推断的事实。固定认证端点使用 HTTPS。重定向只在主机策略校验后保留冻结客户端对 `http` 和 `https` 的兼容；Secure Cookie 绝不通过 HTTP 发送。

Cookie 值是敏感 runtime 状态，虽然会话文件需要保存它们，但公共格式化、错误和日志绝不返回 Cookie 值。显式单路线失效只通过共享协调器替换对应槽位。只有 facade 仍持有加载时的 revision 时，聚合注销才会删除文件；冲突只清理当前进程内存，并保留更新后的完整持久化快照。
