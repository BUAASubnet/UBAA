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

## P0-B 本地仓库基础：课表与希冀不可写载荷

本步骤只实现本地存储、无上游请求；在线读取接线另记，不能声称十二领域缓存已完成。旧版 `ScheduleRepository.kt` 的 `onlineOrSaved`/`update` 和 `ScheduleRepositoryTest.kt` 证明按账号隔离、完整导入后替换、失败/取消/账号变化不覆盖、跨日按周日期投影。旧版 `LocalJudgeApi.kt` 的课程/作业/详情缓存键按 mode+username+course+assignment，列表 5 分钟、详情 2 分钟，历史课程集合另存；本步骤仅提供这些 typed 载荷的安全持久容器，不改变其线上刷新/早停行为。buaa-api 没有等价 Judge 或全功能离线仓库；AAS `core.rs/opt.rs/data.rs` 仅为独立协议参考，不能借用其 `campusCode` 查询参数。

| 操作 | URL/service | 跳转/最终 URL | Cookie/会话 | HTTP/参数 | 头/编码 | 加密/签名 | DTO | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 保存/读本地今日课表 | 无网络；不修改今日 rq | 不适用 | 无 Cookie；内部账号独立库 | 不适用；日期进入精确键 | 本地 typed 序列化 | 新客户端 AES-GCM，非上游协议常量 | TodayClass，只有展示字段 | 完整成功替换、部分失败保旧，实际路线和日期隔离 | 损坏/密钥/容量明确错误，不改认证或 CLI |
| 保存/读本地周课表 | 无网络；不修改 termCode/type/week | 不适用 | 同上 | 不适用；学期+周进入键 | 同上 | 同上 | WeeklySchedule，不含写资格 | 不借用 code 推断学期，按请求归属 | 同上 |
| 保存/读课程/作业索引 | 无网络；不新增上游游标 | 不适用 | 同上 | 不适用；课程进入键 | 同上 | 同上 | 已解析 Course/Assignment，无 HTML | 不推断详情未变或历史永久失效 | 同上 |
| 保存/读希冀摘要/详情 | 无网络；不修改 assignID | 不适用 | 同上 | 不适用；课程+作业/包含历史进入键 | 同上 | 同上 | 现有 Summary/Detail，仅展示，无 action | 来源路线、请求修订、账号代次校验；失败不重写 fetchedAt | 同上 |

新存储与冻结实现的明确差异：业务内容通过独立事务仓库认证加密，随机账号别名不暴露账号正文，索引采用密钥摘要，载荷/查询依据一起加密；本地读取不等待网络锁。退出先关闭仓库并增加代次，清理缓存也推进代次，旧句柄/迟到 ticket 不可回写。不会把冻结旧版 Settings 明文持久化或历史永久集合直接复制进新实现。

## P0-C 平台安全材料与账号索引

本步骤不修改 CAS、URL、请求体、Cookie 或学校错误语义。旧 `CredentialStore.kt` 和当前 `Credential` 的 username/password/autoLogin 结构保留；旧 autoLogin=false 原样读取，不因迁移自动提交密码。新的安全索引仅保留随机账号别名、已核实身份、允许恢复标记和代次；密码独立 namespace，业务正文仅归 Core 数据库。退出先持久关闭恢复；清除账号先关闭恢复再删除密钥；密钥缺失不自动生成替代密钥覆盖旧缓存。索引最多 16 个本机账号，超过范围明确失败，不静默淘汰账号。

平台依据：[固定安全存储插件](https://pub.dev/packages/flutter_secure_storage/versions/10.0.0)；[OpenHarmony HUKS 官方加解密流程](https://github.com/openharmony/docs/blob/master/en/application-dev/security/UniversalKeystoreKit/huks-encryption-decryption-arkts.md) 和本机 API26 声明。HUKS 使用随机 12 字节 nonce、材料键为 AAD、16 字节认证标签；包装密钥不导出，Preferences 只保存密文。未引用示例代码中的日志或固定 nonce。五端插件和 HUKS 不替代学校协议来源。

macOS 实测发现 darwin 0.2.0 原生解析 `useDataProtectionKeyChain`，Dart 默认输出 `usesDataProtectionKeychain`；未适配会得到 -34018。适配后实际调用系统登录钥匙串，保留沙箱，未关闭 TLS、未降低到明文、未要求更改用户证书。

## P1-A 本地首页与恢复时序（生产改动前）

本阶段调整宿主调用时序，不修改学校请求参数。会话校验、凭据登录、资料与注销逐项继承上文及主矩阵“准备/登录”“用户资料”“双路线加载/保存/退出”的九列合同。旧版 Settings 的记住密码/自动登录分离，当前安全 Credential 保留 autoLogin；新账号索引允许先展示无写资格的本地首页。首帧后必须检查会话；旧 autoLogin=false 仅禁止旧密码自动提交。暂时网络错误不得触发密码登录，身份不符停止旧账号投影；退出先写本机禁止恢复状态，迟到回调按生命周期代次丢弃。

P1 可以暂用旧双路线聚合 backend 的 authStatus/login（设计 4.2 已明确允许），此时不声称所需路线提前就绪；P2 再以新 facade/Bridge 合同接线。没有本机索引的旧宿主测试继续保持旧接口兼容，生产组合根随后显式注入索引。认证中页面不切回 splash，写操作仍由唯一 WriteCoordinator 管理，本地展示不使 canStart 为真。

### P1 聚合认证错误投影修正

当前 Dart `_authStatus` 将所有 `none_ready` 投影成 signedOut，丢失每条路线已有 code/kind/retryable；这会使恢复流程把网络故障误当作允许提交密码的明确失效。冻结 `getAuthStatus` 和 Core `validate_status` 均区分临时故障与缺会话；新投影只有所有路线均为 authentication_required 才返回 signedOut，其余沿原安全路线错误抛出。无 HTTP/URL/参数/加密/存储/并发变化，不改变 CLI 双路线结果或错误码，修复仅在 Bridge→App 的认证分类。

## P1-B 今日课表在线保存出口（实现前）

新增缓存 facade 显式校验目标路线 UC 身份，再沿原本科教务门户探测/激活和今日读取；旧 schedule_today/CLI 出口不改语义。该阶段额外 UC 校验用于保证缓存归属，不能计作请求成本优化已完成；P2 再合并已核实路线恢复。缓存本地读取使用独立短锁，不经过网络客户端。

| 操作 | CAS/bootstrap/service | 重定向/最终 URL | Cookie/会话 | HTTP/参数 | 头/编码 | 加密/签名 | DTO | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 带缓存的今日课表 | 旧 LocalScheduleApi 的 currentUser.do、AAS 专用 CAS（主矩阵课表条目）；buaa-api aas/core.rs 同服务 | 继承原门户判别、SSO 与研究生不支持分类 | 原 UbaaClient 的目标路线，前置 UC 验证与安全本机身份一致；不复制 Cookie | 原 GET teachingSchedule/detail.do，rq=一次捕获的上海日期，lxdm=student；新出口让请求和缓存键共享同一日期，旧出口保持原调用时机 | 原 Accept/X-Requested-With/Referer，无正文；不借用示例 campusCode | 学校端无新增加密；本地按已有 AES-GCM 仓库 | 仅 TodayClass 字段，带 scope/fetchedAt/save_error；无学校写资格 | mint ticket 后不持仓库锁等待网络；完整在线成功替换，失败只记尝试，保存失败与在线成功分开 | 身份不符在业务请求前停止；注销使 ticket 失效；保留原 RoutedError，不改 CLI 退出码；单独 typed 缓存错误不冒充学校错误 |

## P1-C 待办缓存与 P2/P3 希冀分段边界核对（实现前）

本轮直接核对当前冻结旧版 `1f4b8f84` 的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/JudgeApi.kt`、`model/dto/Judge.kt`、`api/local/LocalJudgeApi.kt` 与 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalJudgeApiBackendTest.kt`。冻结示例 `a63712fa` 的 `src/api.rs` 无 Judge 模块，不能借用其 SPOC 请求、Cookie 或令牌；主矩阵中更早提交号的记录仅为历史记录。本轮下述出口先复用既有聚合读取及错误收尾，不把聚合缓存保存说成分段/选择性刷新已完成。

| 操作 | CAS/bootstrap/service | 重定向/最终 URL | Cookie/会话 | HTTP/参数 | 头/编码 | 加密/签名 | DTO | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 保存/恢复希冀摘要 | 旧 `judgeServiceLoginUrl` 为 SSO service=`http://judge.buaa.edu.cn/`；业务 HTTPS Judge；示例无对应模块 | 旧 `followJudgeActivationRedirectIfNeeded`、`resolveJudgeRedirectUrl`；当前 Core 保留既有安全重定向与实际路线规则，不从缓存推断最终 URL | 旧按 mode+username 的主会话和隔离课程 worker；本轮使用原客户端，UC 身份核实后执行既有聚合；不增加持久会话客户端 | 原 GET `courselist.jsp?courseID=0`，课程选择 GET 同路径 `courseID=<id>`，列表 GET `assignment/index.jsp`，详情 GET 同路径 `assignID=<id>`；`includeExpired` 仅客户端筛选，不新增 HTTP 参数 | 保留旧 browser Accept、zh-CN Accept-Language、固定 User-Agent，GET 无正文 | Judge 无新加密/签名；仅业务缓存沿 AES-GCM | 课程/作业索引仍为 courseId/courseName/assignmentId/title；摘要含起止时间、分数、题数、提交计数及枚举/文字状态，不持久写资格或原始 HTML | 旧列表 5 分钟、详情 2 分钟和四 worker 已存在；本步骤只增加按账号/实际路线/includeExpired 隔离的摘要持久化；聚合有任一必需失败不替换旧集合 | 原有最多三次业务重新激活及主 UC 仲裁保留；结束全部 worker/处理会话冲突后才返回；退出栅栏拒绝迟到发布；CLI 语义不改 |

边界事实：旧 `getAssignmentSummaries` 确实在读到六个月前开始项时 break，并记录整个课程为历史；Core `summarize_course` 继承该行为。测试证明的是该优化已经存在，不证明上游按开始时间单调排列。后续 P3 将按已接受设计修正客户端筛选与历史复查，不能称为新加六个月早停。当前聚合 worker 在完成/失败后会等待所有子任务收尾并执行 `resolve_required_judge_result`，这是新批次返回候选安全边界；尚未证明单个详情请求内部可释放锁，不在其内部让位，不复制 Cookie 绕过共享锁。

## P2-A 生命周期恢复与写流程收尾（实现前）

此步仅调整前台恢复触发及排队，不修改上文认证九列合同或学校请求。既有会话/密码校验仍沿原 backend、原路线与错误分类；不因 resumed 新建持久会话客户端。写准备、待确认、提交及回读都由唯一 WriteCoordinator 拥有，期间恢复请求合并等待；只有活动完全收尾才能开始认证。退出/销毁取消等待，不自动确认或重发。这里只解决生命周期触发与安全等待，所需路线优先及网络长批次让位仍需后续明确合同。
