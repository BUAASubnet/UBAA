# 连接与会话合同

本合同供修改 Core 连接、WebVPN 地址转换、Cookie 与会话持久化的开发者使用，列出每项行为的冻结证据、Rust 覆盖和持久化规则。

## 证据映射

| 行为 | 冻结证据或本地安全规则 | Rust 覆盖 |
|---|---|---|
| Direct URL 保持直连 | `LocalWebVpnSupport.kt::localUpstreamUrl` | `tests/connection.rs` |
| WebVPN 网关为 `d.buaa.edu.cn` | `LocalWebVpnSupport.kt`、`VpnCipher.kt`、`examples/buaa-api/src/api/sso/auth.rs` | `tests/connection.rs` |
| 无端口使用协议名，有端口使用 `scheme-port` | `LocalWebVpnSupport.kt::toWebVpnUrl`、`VpnCipher.kt::toVpnUrl` | HTTP、HTTPS、默认端口和自定义端口测试 |
| 主机编码使用 AES/CFB/NoPadding，协议常量 `wrdvpnisthebest!` 同时作密钥和初始向量 | `LocalWebVpnSupport.kt`、平台 AES 实现、`VpnCipher.kt` | URL 往返测试 |
| 保留路径、查询和片段 | 两份冻结 WebVPN 实现及测试 | 路径/查询/片段往返测试 |
| 已包装 URL 保持不变 | 两份冻结 WebVPN 实现 | 幂等测试 |
| 绝对、协议相对、根相对和路径相对跳转均从当前 URL 解析 | `LocalConnectionAuth.kt::resolveRedirectUrl` | 跳转表测试 |
| 认证跳转仅允许 SSO、用户中心和网关主机 | 本地安全策略 [AuthHostPolicy](../../crates/ubaa_core/src/connection.rs)，不从阶段目标继承协议事实 | [主机允许列表及未验证主机拒绝测试](../../crates/ubaa_core/src/connection/contract_tests.rs) |
| 主机校验后只接受 HTTP 或 HTTPS 认证跳转 | `LocalConnectionAuth.kt::resolveRedirectUrl`、WebVPN 协议段测试 | 非 HTTP 跳转拒绝测试 |
| Cookie 过滤域名、路径、Secure、过期时间并处理替换 | `LocalConnectionAuth.kt::PersistentLocalCookieStorage`、`LocalCookieStoreTest.kt`、`examples/buaa-api/src/store/cookies.rs` | `tests/cookies.rs` |
| 显式失效清理会话，超时/5xx 保留会话 | `validateLocalConnectionSession`、`getAuthStatus` | `tests/session.rs` 策略测试 |

自动路由选择同样属于 Core 所有的连接状态：

- 生产探测器只连接 `gw.buaa.edu.cn:80` 解析出的 `10.0.0.0/8` IPv4 地址的 TCP。
- 单个 500 ms 总期限包含域名解析和所有地址尝试。
- 三态结果在 facade 进程内以 single-flight 方式缓存 60 秒。
- 探测器不发送 HTTP/TLS 正文，也不读取 Cookie 或凭据。

完整策略和错误映射详见[路由策略合同](route-policy.md)。

## 持久化

每个聚合 facade 在 `<config-dir>/session.json` 中保存一个 schema-v2 双路线快照。Direct 与 WebVPN 槽位相互独立，包含过滤后的 Cookie、路线、认证时间和最后活动时间；不持久化用户名、密码、CAS execution、风险页面、不支持的交互步骤材料或业务令牌。旧版单路线快照只迁移到其记录的路线槽位。

旁车文件 `.session.lock` 串行化访问并保存定宽单调 revision：

- 初始双路线快照与 revision 在同一个临界区加载。
- 共享协调器拥有内存双路线快照和 revision；每次路线替换或聚合清理构造完整候选，并且只执行一次 compare-exchange。
- 过期进程返回安全的可重试冲突，不重新加载或采用外部 revision 来重试。
- 聚合注销尽力请求两条远程路线，清除两个内存 runtime 和路线功能状态，随后尝试一次双槽持久化清理；冲突时保留更新后的两个槽位。

文件写入与权限：

- 写入使用同目录唯一且独占创建的临时文件，并在替换前同步。
- 会话、锁和配置目标拒绝符号链接及非普通文件；最终打开会话/锁文件使用平台 no-follow 标志。
- Unix 确定性测试覆盖符号链接拒绝、并发唯一临时写入、原子替换和 `0700`/`0600` 权限。
- 会话读取上限为 1 MiB。
- Windows 使用继承的目录 ACL；自定义配置目录的所有者 ACL 仍是发布审计项。

HTTP 传输：

- 原始 HTTP 传输保持 TLS 校验和手动重定向，完整缓冲的正文默认限制为 8 MiB。
- 希冀 GET 作业详情在还原 Direct/WebVPN 地址后，只有精确主机 `judge.buaa.edu.cn`、路径 `/assignment/index.jsp` 且含非空数字 `assignID` 时使用 16 MiB；详情中的长代码文本需要完整 HTML 解析。
- 正文预算同时检查声明长度和解压后的累计长度。会话文件与 HTTP 正文的限制都是内部资源预算，依据见[希冀来源对照](../protocol/parity/coursework.md#希冀作业详情正文预算)。
- 固定认证端点使用 HTTPS。重定向只在主机策略校验后保留冻结客户端对 `http` 和 `https` 的兼容；Secure Cookie 不通过 HTTP 发送。

Cookie 值是敏感 runtime 状态，虽然会话文件需要保存它们，但公共格式化、错误和日志绝不返回 Cookie 值。显式单路线失效只通过共享协调器替换对应槽位。只有 facade 仍持有加载时的 revision 时，聚合注销才会删除文件；冲突只清理当前进程内存，并保留更新后的完整持久化快照。

### 业务会话缓存

只读 worker 共用 `<config-dir>/business_session.json`，按经 SSO 核验的账号名、实际路线和业务范围保存 schema 2 条目。每条保存 Unix 时间戳 `saved_at` 和一种材料：

| 范围 | 材料 | 可复用时间 |
|---|---|---|
| Byxt、Portal | 过滤后的业务 Cookie | 沿用 Cookie 的过期规则 |
| 学生身份 | `StudentKind`：`undergraduate` 或 `graduate` | 7 天 |
| SPOC | `SpocCredential { token, role }` | 3 小时 |
| 阳光打卡 | `YgdkCredential { uid, token }` | 12 小时 |

核验账号前，worker 跳过播种、写回和缓存拒绝处理。条目自 `saved_at` 起超过可复用时间即不再播种。若 `saved_at` 晚于当前时间，内存将该条目按空处理，磁盘条目在下次写入或清理时移除。坏 JSON、未知 schema、超过 256 KiB 或账号不符按空缓存处理。读到 schema 1 同样按空缓存处理，下次成功写入时以 schema 2 覆盖。旁车不改变 `session.json`、双槽 CAS 或会话修订号。

Direct 按精确域名识别 Byxt 和 Portal。WebVPN 仅接收 `d.buaa.edu.cn` 中路径包装为对应业务主机 HTTPS 默认端口的 Cookie。SSO、用户中心及网关通用 Cookie 不进入旁车。Portal Cookie 只从课表、考试、成绩等只读 worker 的学业身份查询复用，无法识别的学生身份不写回。签到和博雅的业务凭据不进入旁车。

主客户端不播种、不写回业务会话缓存。主客户端的门户资料、校园指标、校园账户刷新、调用方固定路线的读取及阳光打卡提交沿用原会话，阳光打卡提交不因业务认证拒绝而重登或重放。

worker 派生和同步时采用同一账号、同一路线的材料。如果 worker 已修改某个范围，下一批继续使用该 worker 的材料。学生身份播种使用 worker 当前的生命周期代次；SPOC 和阳光打卡播种使用各自 `CredentialState` 的设置路径和代次检查。上游要求业务认证时，仅丢弃仍与被拒绝材料匹配的缓存条目，并清理本 worker 对应的 Cookie 或业务凭据。SPOC 和阳光打卡概览沿原有边界最多重新激活一次。SPOC 重登后仍被拒时，淘汰仍匹配的缓存条目并清除当前凭据，保留原错误及不完整详情的处理规则。阳光打卡记录页 `/Clockin/getList` 被拒时清理缓存和内存凭据，原样返回错误，不新增重试。

成功读取只提交实际在线路线中发生变化的材料。只采用其他读取者的离线记录时不产生新的写回路线。SPOC 单批只报告该批的在线路线；整次首页列表或详情刷新累计所有在线成功的路线，每条路线各写回一次。末批复用离线记录时，前面各批已成功的在线路线仍会写回。

材料按顺序后台落盘。主会话修订预检只在取得 `.business_session.lock` 前执行，尽力丢弃已知过期的任务，不改变协调器状态。跨进程的缓存失效以清理令牌为准。同账号正常核验、刷新活动时间或保存新修订不轮换令牌，已通过预检的任务仍可写回同账号材料。

旁车锁内不得获取主会话文件锁、协调器互斥锁或缓存互斥锁。写回持旁车锁合并最新文件，只替换变化的业务范围，并在落盘前核对路线生命周期和缓存内存代次。内存种子记录来源 worker 所属的路线生命周期代次，播种时淘汰来源已失效的材料。磁盘操作失败只记录脱敏诊断，在线结果继续返回。文件及锁拒绝符号链接和非普通文件。Unix 目录权限为 `0700`，缓存文件及锁为 `0600`。写入使用同目录独占临时文件，同步完成后原子替换。

每条路线有独立的 128 位随机清理令牌，旧 schema 2 缺少令牌时按无令牌处理。worker 播种时记下路线令牌，后续发现令牌已变就从磁盘重载该路线。写回和拒绝操作持旁车锁比对令牌，清理前派生的任务不能恢复或删掉清理后的条目。拒绝操作删掉仍匹配的条目时，同时轮换该路线的令牌，保留同路线其他范围和另一路线的条目。发起拒绝的 worker 按队列顺序使用拒绝完成后的令牌写回重新激活的材料。

整体清理按影响范围处理：

- **全量撤销**：已通过权属校验的注销、全量内存失效、有效路线配置变化（含功能覆盖项）、设置清理和交互式登录准备都轮换两条路线的令牌。聚合注销在第一个远端请求之前写入墓碑，不依赖远端成功或调用方继续等待。远端请求结束后，主会话槽按原规则做双槽 CAS；只有 CAS 成功才再次轮换，拦住远端等待期间派生的任务。交互式准备清除双槽后写入墓碑，设置清理同时弃用旧读组。
- **换号**：本次核验账号与此前核验的主会话账号不一致，或此前账号未知，均轮换两条路线的令牌。是否存在旁车文件或账号字段不影响清理；无账号的墓碑不能用来确认同账号。
- **同账号单路线登录**：仅在此前核验的主会话账号与本次核验账号一致时，只清空目标路线并轮换该路线的令牌，保留另一条路线。
- **单路线会话槽撤销**：SSO 明确失效、已知身份不符或其他入口成功清除磁盘主会话槽位时，只清空并轮换该路线。固定路线诊断客户端注销也遵守此规则。若没有剩余材料，旁车只保留 schema 和路线令牌；否则保留另一条路线的材料及其账号归属。

全量撤销和换号原子写入只含 schema 与两条路线新令牌的墓碑。失效事件只在发生源头处理。会话冲突使协调器进入终态，并弃用冲突客户端的内存种子，不写旁车、不轮换令牌。入口已失去权属的注销请求也不能改动新所有者的旁车。仅因父路线代次变化而过期的只读组由读取池弃用，不撤销其他读组的材料。

业务令牌在 Debug 输出、tracing 日志和普通诊断报告中隐藏。用户主动导出的完整诊断沿既有合同保存原始响应正文，但任何诊断导出都不收集 `business_session.json`。

业务协议沿[第一阶段来源对照](../protocol/parity/auth-session.md#只读-worker-的-byxt-与-portal-cookie)和[学生身份与业务令牌来源对照](../protocol/parity/auth-session.md#学生身份与业务令牌准入)。
