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

## P2-B 所需路线登录与 Bridge 接线（实现前，2026-09-22）

再次直接核对冻结旧 `LocalConnectionAuth.kt:451` 的登录、表单、UC 验证及模式 Cookie，和示例 `src/api/sso/auth.rs`、`src/request.rs`、`src/store/{cookies,cred}.rs`。状态校验沿本文件开头九列。新 `login_required_route` 声明 caller-pinned 目标；App 只传入 Core 所需路线校验返回的目标，不重算 Auto，不在有效目标会话时提交密码。

| 操作 | CAS/bootstrap/service | 重定向/最终 URL | Cookie/会话 | HTTP/参数 | 头/编码 | 加密/签名 | DTO | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 指定所需路线登录 | 旧模式内 loginUrl/UC 激活；示例 direct SSO 与 login_vpn 分开，VPN service 不与旧模式随意混用；新出口调用现有 AuthWorkflow，不增加 URL | 保留当前 prepare/login_response/UC 最终验证，已有重定向、密码风险、未支持交互边界不变；示例只凭 status 的成功不足以替代 UC | 原 UbaaClient 持有所选路线 AuthWorkflow 和 DualSessionCoordinator，双槽所有权检查；不创建第二客户端 | 复用原 GET 登录页、既有 CAS form POST、UC activate/status/info；不新增字段；execution 和表单内容仍由原解析器确定 | 保留 application/x-www-form-urlencoded 及既有头；示例固定六字段不足以替代旧动态表单 | 无新常量，原表单加密/编码规则保持 | 原 UserProfile，加 caller-pinned route；不返回虚假的双路线 all_ready | 新调用仅持锁完成所需路线，归还后其他任务可执行；密码只用于获准且明确失效的路线 | 继承原细分错误，Bridge 附目标路线；全局冲突仍仲裁；旧 prepare_login/login/auth_status 的双路线语义与 CLI 不变 |

明确差异：旧 WebVPN 登录成功后附带 `establishDirectSsoSession`，而当前 Core 原本就由双路线 facade 显式协调两槽。已接受设计要求所需路线可先服务，因此新单路线出口不附带旧旁路 Direct 登录；其他路线通过其实际任务再恢复。保留旧双路线接口，不把旧旁路复制成持久客户端或让单路线调用暗中访问另一条路线。此为调度范围变化，不是学校协议字段变化。

身份补充核对：旧 `LocalConnectionAuth.kt:360` 使用 `user.schoolid ?: user.username` 建立本地会话身份。新单路线状态投影允许用实际返回的非空 schoolId 作为最小身份，再与本机索引核对；两字段都缺失仍失败，不以姓名、本机缓存或输入值填造上游身份。旧独立 userInfo 的严格投影合同保持不变，完整资料按需读取另行接入。

## P2-C 希冀可让位批次（实现前，2026-09-22）

直接对照旧 `LocalJudgeApi.kt:255-285`：课程索引、每课程作业索引、单详情分别通过已有 GET 序列取得；课程选择互斥范围覆盖 `selectCourse` 到相应正文解析。示例 `a63712fa` 无 Judge 模块，不能借用其他模块的游标、ETag、会话或错误。原四 worker 聚合接口保留，新接口不复用它的整批 Future 作为“可抢占”。

| 操作 | CAS/bootstrap/service | 重定向/最终 URL | Cookie/会话 | HTTP/参数 | 头/编码 | 加密/签名 | DTO | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 开始扫描/课程索引 | 原 Judge SSO service 与 get_courses_cached；前置 UC 核对缓存身份 | 继承原服务激活/重定向规则 | 同一 UbaaClient 的实际路线，绑定 runtime 状态对象及代次 | 原 courselist.jsp?courseID=0 | 原 browser GET 头，无正文 | 无新协议常量 | 原 Course 列表；内部计划不暴露 Cookie 或上游游标 | 一个有界索引步骤；原五分钟内存索引语义保留，本阶段不声称强制刷新/持久索引已完成 | UC 身份不符、退出/所有权冲突拒绝；完整请求及原认证仲裁结束才返回 |
| 单课程作业索引步骤 | 复用既有 Judge 服务方法 | 同上 | 串行主 runtime；不创建 worker 或复制 Cookie | 原 GET 选择 courseID，再 GET assignment/index.jsp，二者不能拆开让位 | 原 browser 头，无正文 | 无 | 原 Assignment 列表；原始锚点统计仍由既有诊断接口提供，本扫描暂不对外投影；课程来自本计划索引，不接受宿主任意拼接 URL | 完整选择/读取/解析后返回；步骤之间可以运行其他业务；下一步仍显式选课 | 普通课程读取失败标明该课程未完成，保留其他课程继续空间；认证/会话冲突先仲裁再终止 |
| 单详情步骤 | 复用既有 get_detail_cached | 同上 | 同一 runtime，无异步 worker 遗留；再次显式选课，允许其他任务在先前步骤后改变选课状态 | 原 GET courseID，再 GET assignment/index.jsp?assignID；ID 来自当前课程索引 | 原头/GET，无新参数 | 无 | 原 JudgeAssignmentDetail，仅 typed 内容 | 每次最多一个详情序列；原两分钟内存缓存保留；客户端计划不假设时间顺序，不遇旧即停 | 返回前后验证取消、账号缓存请求、客户端归属、路线变更和功能失效代次；不将取消声明为已经终止在途 HTTP |

新计划先提供真实短调用边界及完整度元数据；持久化索引、选择性详情、历史复查与筛选在 P3 接入。新路径逐项遍历，不依赖旧历史永久集合或单调时间假设；旧聚合的原行为暂不借本次重构改变。主 runtime 串行调用每次先显式选课，既有其他接口也显式选择自身目标，故可在序列完整收尾后归还 Bridge 网络锁；绝不在选择与详情之间解锁。

## P3 希冀持久化与选择性刷新（实现前，2026-09-22）

沿用上节同一 CAS、重定向、Cookie、GET 参数、头、解析 DTO 与认证仲裁；buaa-api 仍无对应协议，不能借用游标或 ETag。新增 `force_fresh` 仅控制客户端是否使用原内存 TTL，不增加任何上游参数，旧聚合入口始终保留原 TTL。持久条目的网络取得时间只能来自跳过内存缓存后成功完成的读取，持久复用保留原时间。

缓存策略与冻结旧版的明确差异：不继承永久历史集合，不因一个旧项而停止后续详情；以逐项严格可解析的开始/截止时间及提交状态判定低频历史项。开始时间超过六个月但截止未到、状态未知或日期不可解析均保留活跃核实路径。新增 ID、标题/课程名称改变、当前详情、未完成/临近截止和近期成绩复查优先；历史详情七天复查，历史课程索引一天复查，完整刷新绕过这些本地期限。页面顺序未证明单调，逐项检查后续项。

存储按账号库、实际路线、课程/作业 ID 分别发布课程索引、作业索引和详情；汇总仅在覆盖完整范围时成功替换，部分失败保留旧摘要与失败课程内容。每次子条目发布须在同一 SQLite 事务同时核对扫描父票据和本条目票据；父票据原子续租只能更新仍有效的原请求，不能用重新 begin 抢回较新请求，解决长扫描被请求回收阈值误伤。服务请求期间不持本地事务。历史复查元数据仅为只读同步策略，不承载学校写资格。

## P3-B Bridge/App 渐进接线（实现前，2026-09-22）

沿 P3-A 相同学校协议和串行主运行时，新增 Bridge 只转发 typed 刷新计划及逐批结果，不拼 URL、不复制 Cookie，也不新增第二持久会话。begin/next 沿 P2-C 写意图栅栏和锁序，返回后才允许下一批；取消仅设置标记。汇总混合缓存与在线内容时，逐项保留来源时间并输出汇总最早时间，不能把最后一批时间当作全部更新完成时间。App 任务队列只调度尚未发送的批次，写协调器既定回读拥有独立内部路径，不等待被自身写活动关闭的普通读取入口，也不借回读触发后台重认证。

## P2-E 按业务执行边界恢复目标路线（实现前，2026-09-22）

学校认证、密码提交条件和 caller-pinned 路线沿 P2-B 合同，不增加 URL/参数或推断另一条路线已就绪。调整 App 调用顺序：普通生产读取在获得执行机会后，仅为该功能恢复所需路线，再让出调度机会；不提前排入所有领域认证而挡住已就绪课表。写协调器既定回读仍跳过后台恢复。各领域错误从自己的恢复状态取值，不因其他路线的失败改写已就绪领域。

## P4-A：精确查询的本地只读投影（实施前）

沿 P3-A/P3-B 已核对的希冀详情 DTO、课程/作业标识和映射，开放已持久保存的详情；沿 P1-B/P1-C 已核对的今日课表与希冀摘要支持显式查询读取。此操作只读 Core 加密仓库，不调用学校、CAS、重定向、Cookie、请求头或加密签名流程，两份冻结来源均无同构加密离线仓库，不能从它们推断新上游字段。缓存键严格使用实际路线与 typed query；详情必须同时匹配课程和作业标识，摘要保留 include_expired，今日仍限定上海当前日期。页面投影只带内容、原时间和来源，不复原学校写动作或资格。App 的本地查询与网络队列独立，当前查询/账号/生命周期变化即丢弃迟到投影，在线结果优先于迟到磁盘。

## P4-B：学业与空教室持久读取（实施前）

本轮核对固定旧版 `api/feature/{ScheduleApi,GradeApi,ClassroomApi}.kt`、`api/local/{LocalScheduleApi,LocalGradeApi,LocalClassroomApi}.kt`、`model/dto/{Schedule,Grade,Classroom}.kt` 及 `LocalScheduleApiBackendTest.kt`、`LocalClassroomApiBackendTest.kt`；另一冻结来源为 `api/aas/{core,opt,data}.rs`、`request.rs`、`store/{cookies,cred}.rs`。提交仍为本文开头两个固定 SHA。以下只增加现有 Core typed 结果的本地持久化，使用已验证读取实现，不改变 CLI 或学校协议。

| 操作 | CAS/bootstrap、service | 重定向与终点 | Cookie/会话 | 方法与精确参数 | 头与编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 学期 | 旧版 currentUser 能力探测；另一来源 AAS CAS 专用 service，沿既有 Core 激活 | 原 AAS 最终 URL 前缀检查及本科能力判断 | 当前实际路线单会话 | GET schoolCalendars.do，无业务参数 | 原 AJAX Accept/X-Requested-With、schedule Referer，无正文 | 无新增 | Term itemCode/itemName/selected/itemIndex 原类型 | 新增账号/路线完整列表；无全学期预取 | 原认证/本科不支持/解析错误，失败不替换 |
| 教学周 | 同上 | 同上 | 同上 | GET getTermWeeks.do，termCode | 同上 | 无新增 | Week 日期、term、serialNumber、curWeek；响应 term 不强制等于请求 | 请求学期精确键，完整集合替换 | 同上 |
| 周课表 | 同上 | 同上 | 同上 | 旧版 POST getMyScheduleDetail.do 表单 termCode/type=week/week；另一来源使用 query 且有 campusCode，不借用差异 | 原 schedule 头与表单编码 | 无新增 | WeeklySchedule arrangedList/code/name；code 不要求等于请求学期 | 请求学期/正周次键，完整周保存；不声称整个学期覆盖 | 同上；非法周次请求前拒绝 |
| 考试 | 同 AAS 激活；旧版考试明确本科接口，另一来源无同构考试操作 | 原激活/最终 URL 与本科判断 | 当前考试实际路线 | GET exams.do，termCode | 原 AJAX 头、exam Referer | 无新增 | ExamArrangement 的 arranged/not_arranged，原 nullable 字段 | 完整学期原集合保存，已安排/未安排仅本地筛选 | 原错误，不以失败冒充空考试 |
| 成绩 | 旧版 GET buaascore/wap/default/index 激活；另一来源 AAS 不是同协议，不借用 | 原跟随跳转；SSO/401/登录 HTML 认证仲裁 | 当前成绩实际路线 | 同 URL POST，xq 与 year 来自原 yyyy-yyyy-semester 解析 | 页面 HTML Accept；查询 AJAX Accept、X-Requested-With、Referer；表单 | 无新增 | e/m/d→GradeData，termCode 源于请求，score/credit 等沿原映射 | 请求学期完整集合，有限 credit 才可无损 JSON 保存；持久投影不触发出分通知 | 原上游/解析/认证分类；非有限 credit 仅令保存失败，不改在线解析 |
| 空教室 | 旧版精确 classroomSyncUrl，另一来源 class 为 iClass、不等价 | 同步跟随跳转接受 200..399；业务查询不跟随 | 当前路线及既有同步状态 | GET search1，xqid/floorid 空串/date | 原长 UA、AJAX Accept/X-Requested-With/Referer，无正文 | 无新增 | e/m/d.list，楼栋→id/floorid/name/kxsds | 校区/严格日期保存完整集合；楼栋/节次只本地筛选 | 原认证/解析分类；非零 code 未有完整可用证据，不保存为完整缓存；在线返回保留旧合同 |

共用保存边界：认证返回身份与本机账号匹配后绑定已解析路线，发业务读取前领取精确范围票据；完整成功才替换，失败保留旧内容并更新尝试；本地磁盘不可用可继续返回在线内容与保存错误，但退出/被替代栅栏不可降级。两个参考均未提供本方案统一加密仓库，新增本地语义以已接受设计为依据，不推断 ETag、增量游标或分页。

## P4-C：学业缓存 Bridge/App 接线（实施前）

复用 P4-B 已逐操作核对的六个 Core 范围及全部原投影字段；不新增学校 URL、参数、认证方式或分页。Bridge 使用分别 typed 的本地记录与在线刷新返回值，避免宿主接触任意 CachePayload 或 raw JSON。在线入口仍在原客户端锁内，待确认学校写意图期间禁止隐式认证；本地读取沿独立仓库句柄，不取得网络锁。App 保存与展示分离，成绩磁盘投影不是在线出分观察，课表默认学期仅来自实际保存的学期索引，不能把缓存中的任意学期猜成当前学期。

## P4-D：首页待办持久范围与部分失败（实施前）

重新核对当前冻结 `ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 feature 接口、`LocalSpocApi/LocalSpocSupport`、`LocalSigninApi`、`LocalYgdkApi`、对应 DTO 及 BackendTest；另一来源为当前 `buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/spoc`、`api/class`、request/credential/cookie。签到按 2026-09-17 修正后的旧版入口，不采用主矩阵中过时的 8346 登录裁决，也不把旧记录中的 efb7976 当作本次冻结 SHA。

| 操作 | bootstrap/service | 重定向与最终 URL | Cookie/会话 | 方法/参数 | 头/正文 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| SPOC 当前列表 | 旧 CAS→sys/casLogin 角色，另一来源缺角色不等价 | 原手动8跳、精确token落点 | 当前路线内token/role；不持久化 | 固定当前学期param，课程kcmc空/xnxq；全局作业逐页原pageNum/pageSize | 原 JSON、XHR/Token/RoleCode | 原 DES、密钥和固定 SQL ID 不变 | 原 SpocAssignments、term、摘要；不缓存 raw 信封 | 缓存当前视图完整集合；新学期成功替换旧当前快照，不合并跨学期项目 | 课程补充 runCatching 原可选失败保留在线行为；新缓存记部分，必需页失败不替换 |
| SPOC 详情 | 同上；另一来源无同构双步骤 | 原业务认证重试/SSO仲裁 | 同路线 | 必需 GET queryKczyInfoByid 的 id；可选 GET queryXsSubmitKczyInfo 的 kczyid | 原 XHR/Token/RoleCode，无新增正文 | 无新增 | 原 id 校验、纯文本详情和 submittedAt；请求只有作业ID，不臆造课程/学期参数 | 精确作业ID，来源保留课程字段；可选步骤失败不覆盖旧完整详情 | 可选失败与合法空补充区分；旧公开返回语义保持 |
| 今日签到 | 旧8346 jumpMyCenter，业务登录8347 login.action；另一来源 login_buaa.do 不借用 | 原8跳 loginName，固定路线 | 原独立id/sessionId，不写缓存 | 原 GET id/dateStr=YYYYMMDD；日期捕获一次并复用于重试与缓存键 | sessionId 头；原登录精确字段，无业务新参数 | 无新增 | 只保存courseId/name/begin/end/signStatus，不保存 eligibility/target | 按上海日期隔离；午夜不把昨天当今天 | 原 STATUS/一次业务重试及主会话仲裁；不把失败当空 |
| 阳光概览 | 原 OAuth code 交换，另一来源无等价模块 | 原10跳/query/fragment提code；不猜主机集 | 原路线内uid/token与generation | 原分类、项目、getCount、Term/get顺序；项目page=1/limit=1000 | 原表单、query双传及XHR；不保存令牌 | 无新增 | 保留原统计、项目显示字段；独立缓存DTO没有submitEligibility/submitTarget | 可选统计/学期失败记部分；旧完整内容保留；不把部分回退零当新完整值 | -98与发送前guard仍失败/原一次重试；旧公开概览的可选容错保持 |

本轮不增加学校写入、密码提交或隐式预取。在线返回仍保留实时资格供既有 WriteCoordinator 复核链使用；持久载荷从类型层面剥离资格/写目标。当前列表/默认概览无显式学期或分类输入，缓存保存完整当前快照及其真实term/classify字段，不凭空新增上游参数。阳光记录分页与其分类归属将在后续独立接入，不以概览缓存冒充记录已覆盖。


P4-D 审查补充：阳光仅沿原 term_good_count_show/term_good_count/term_count_show/term_count 四字段顺序判断是否真的观察到次数；无字段时旧公开接口仍回退零，但新持久完整度为部分。SPOC 继续原空页/总页数停止边界，若停止时 hasNextPage 仍为真，新缓存不得标完整；不因此发明新的翻页请求或改变原 CLI 输出。

## P4-E：首页待办 Bridge/App 接线（实施前）

复用 P4-D 四个已对照操作，Bridge 只显式映射公开字段，不新增学校请求协议。缓存签到/阳光 DTO 不包含资格或写目标；仅本次在线返回保留原实时资格，仍交唯一 WriteCoordinator 的实时复核/prepare/确认/commit。新增签到既定回读的明确 backend 能力，继续调用原不带缓存恢复的读取入口，避免 pending 写流程被新增身份检查阻塞。SPOC/阳光不完整刷新以 complete 与 Stored/Preserved 分别展示；不得以保存成功或旧 signStatus 推断可提交。缓存签到筛选按上次状态展示，不称作实时“可签到”。

P4-E 实施复核：学校协议仍仅为 P4-D 原操作，未新增 URL/参数、Cookie 客户端、ETag 或增量游标。原 SPOC/签到呈现抽取至 home_projection 共用；缓存签到按旧状态分组而在线仍按本次 eligibility 分组。阳光概览只保存显示统计，本次同路线记录页不因旧统计合并丢失。首页跨日签到、部分成功无错误码、未知统计与待确认写回读均纳入脱敏测试。


## P4-F：博雅只读持久范围（实施前）

两源固定 SHA 与 P4-D 相同。重新读取旧版 `BykcApi.kt`、`LocalBykcApi.kt`、`LocalBykcCrypto.kt`、`model/dto/Bykc.kt` 及 `LocalBykcApiBackendTest.kt`；另一源为 `api/boya/{core,opt,data}.rs`、request.rs、store/{cred,cookies}.rs。当前 Core 的 get_profile/get_courses/get_course_detail/get_chosen_courses/get_statistics 为学校读取唯一实现，本次仅包装持久范围。

| 操作 | bootstrap/service、跳转 | Cookie/会话 | 方法及精确参数 | 头/正文、加密常量 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|
| 资料 | 旧 /sscv/cas/login 经 SSO 服务；另一源显式 noAutoRedirect 的 SSO URL，不替换现有入口；原8跳、final/Location、WebVPN还原/重包保持 | 原路线Cookie+业务内存token；不借用另一源持久token | POST getUserProfile {}；另一源无专用方法，universal_request 示例同路径 | 五项共用旧双 auth_token/authtoken、ak/sk/ts、JSON、Origin/Referer；AES128ECB/PKCS7、RSA PKCS1v1.5、公钥/keyChars沿旧常量，SHA1十六进制摘要；不修改 | 当前公开id/employee_id/real_name/student_no/college_name，不保存原响应 | 账号/实际路线/资料独立范围，加密存储 | 原信封/认证/解析分类，失败不写空 |
| 课程分页 | 同资料 | 同资料 | POST queryStudentSemesterCourseByPage {pageNumber,pageSize}；all仅原本地过滤 | 同资料；另一源单token/JSON字符串差异不借用 | 原课程显示字段、status/selected、原number/size/total；不落盘select/deselect eligibility | page/size/all三者完整隔离；一页完整不冒称全列表完整 | 原错误；非法持久范围在请求前拒绝；不添加翻页或推断游标 |
| 单课程 | 同资料 | 同资料 | POST queryCourseById {id}；另一源同id | 同资料 | 原公开BykcCourse；不新增旧版UI未迁入字段、不重算资格 | 精确正数id，响应id不匹配不能存为该详情 | 原在线解析保持，缓存保存失败单列，退出票据硬拒绝 |
| 当前已选 | 同资料 | 同资料 | POST getAllConfig {}，按原当前时间/最新结束学期规则后 POST queryChosenCourse {startDate,endDate}；另一源只取首学期，禁止借用 | 同资料 | 原记录id与内层course_id区分，日期/考勤/成绩/分类/作业；观察到的实际起止范围随快照保存；不长期存signInfo位置结果/写资格/签到点坐标 | 当前视图整集合替换，不拼跨学期；范围日期来自这次原请求选择，不能自行估计 | 学期缺失/配置失败不保存空；写前专用读取语义不变 |
| 修读统计 | 同资料 | 同资料 | POST queryStatisticByUserId {}；另一源同操作 | 同资料 | 原validCount/statistical类别映射，无任意JSON | 独立统计范围，不用课程页重新计数 | 原错误；失败保留旧统计 |

另一源 SignInfo 明确为 lng/lat/inSignArea，故其原字符串不是可长期保存的普通文字。本次持久已选 DTO 仅保留签到时间窗及是否有学校签到点，不保存用户位置结果/签到点坐标；在线公开值与学校写前校验仍完整。两个来源都没有本方案统一持久缓存，本地范围/完整替换/账号退出栅栏依已接受设计；不改变TLS校验或会话存储方式。本阶段先实现 Core，Bridge/App 待独立接线，不能声称本机首页博雅已可离线显示。


## P4-G：博雅 Bridge/App 接线（实施前）

复用 P4-F 五项逐操作矩阵，不新增学校协议、学期推断或课程预取。Bridge 缓存课程/已选类型不含资格、位置结果或签到坐标；在线仍使用原 DTO，并以独立状态携带实际学期范围与保存结果。App 共用原展示映射，课程分页恢复必须保留原 pagination，首页已选沿 bykcChosenCourses 查询上下文恢复，不能冒充默认课程列表。学校写后既定回读必须绕过新增缓存恢复入口，保留唯一 WriteCoordinator 管理与当前路线/生命周期屏障。

P4-G 实施复核：分页仍按 App 既有规范将 page<=0 收敛1、size限制1..100，all=true；查询缓存使用同一参数。资料、统计、单详情、已选的在线展示映射从原代码抽取复用，不新增上游字段。缓存已选有时间窗而无坐标，不构造假签到点来满足旧 DTO；地点个数保持未知。首页补充结果保留 evidence，写后回读显式绕过新增缓存认证。


## P4-G 审查修正：缓存类型不得扩大 Bridge 公开边界

核对研讨室时重新发现主对照文档 2026-09-02 的禁曝决定，以及 bindings/schema_snapshot_test 对 BridgeBykcChosenCourse 的既有禁曝断言。P4-G 的新 BridgeCachedBykcChosenCourse 虽没有资格与坐标，却额外包含 homework/homeworkAttachmentName，违反相同边界。先增加缓存 DTO 禁曝失败测试，再删除两字段及映射，升级合同 v19 并重生绑定。Core 加密缓存可保留已接受设计允许的业务文字，但它不等于宿主公开合同，禁止用统一序列化穿透既有收窄。学校请求、原在线 DTO、App 展示和写路径均不改变。


## P4-H：研讨室 Core 持久范围（实施前）

冻结 SHA 仍为 old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3 与 buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81。重新核对 CgyyApi/LocalCgyyApi、Cgyy DTO、LocalCgyySigner 及 BackendTest 的直接读取/用途回退/认证测试。另一来源没有 venue-zhjs-server 协议；其 api/srs/core/opt 是 byxk/xsxk 选课，不能借用 URL、token、数据模型或错误。request/credential/cookie 公共实现沿 P4-F 对照，无本次可借用的场馆协议。

| 操作 | bootstrap/service、重定向 | Cookie/会话 | 方法/精确参数 | 头/编码/签名 | DTO/解析 | 缓存与并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|
| 站点 | 原 manageLogin→SSO→api/login；原允许主机/最终URL、WebVPN Cookie同步与重包规则不变 | 原路线 sso_buaa_zhjs_token→Sso-Token→access_token，不复制Cookie | GET front/website/venues，page=-1/size=-1/reservationRoleId=3 | 原 Accept/Referer/app-key/timestamp/sign/cgAuthorization，GET nocache；MD5 prefix/path/排序标量/timestamp/空格/prefix，常量沿LocalCgyySigner | 原 siteList 展开及站点字段 | 独立账号/路线站点范围 | 原成功信封code=200；失败不替换 |
| 用途 | 同站点 | 同站点 | GET codes，仅nocache | 同站点 | 原递归key/name与Upstream/StaticFallback明确来源 | 动态成功完整替换；静态回退记部分，不能覆盖旧动态完整记录；不新建会话 | 原认证错误不回退，其他异常仍返回冻结静态表；不能称上游刚成功 |
| 日期空间 | 同站点 | 同站点 | GET reservation/day/info，searchDate/venueSiteId/nocache | 同站点 | 原day/date/空间/时段显示；不落盘reservation token、资格、target、交易号或占用审计材料 | 精确正站点/严格日期；无跨日借用或预取 | 原空对象合法、null/缺失/标量错误；未知状态保持未知 |
| 本人订单 | 同站点 | 同站点 | GET orders/mine，零基page/size/nocache | 同站点 | 原content及分页；只保存已公开显示字段，不含phone/joiners/交易号/审核内部文本/取消资格和target | 精确页/大小，单页完整不等于全订单遍历 | 原合法data=null空页仍可替换该页；失败保留旧数据 |
| 订单详情 | 同站点 | 同站点 | GET orders/{正id}，nocache | 同站点 | 原Order显示字段；空data原DTO默认id=0保留在线兼容 | 精确id，响应id不符不能写入该范围或证明删除 | 仅本地保存失败降级，账号/退出屏障硬拒绝 |
| 门锁状态 | 同站点 | 同站点 | 原 GET orders/lock/code | 同站点 | 仅原 available 布尔摘要，原始锁码不公开 | 维持按需实时读取，不进入长期缓存 | 不把旧门锁状态称为当前可用 |

签名常量沿已核对主矩阵：app-key=8fceb735082b5a529312040b58ea780b，prefix=c640ca392cd45fb3a55b00a63a86c618；不修改 TLS、重试或业务登录。新增持久类型以 Bridge 既有字段白名单为上限，先剥离资格与内部材料，禁止重复 P4-G 的字段越界。学校写链及 caller-pinned 回读保持；此阶段只接 Core，不声称 App/真实读取或大查询抢占通过。

P4-H 实施复核：新增类型仅显式复制既有 Bridge 公开字段（再剥离资格/target），不直接序列化内部 CgyyOrder/SlotStatus。原用途解析还要求名称包含“类”，脱敏测试据此使用“合成用途类”，没有修改解析规则。日期回退实际 date_key 与查询不一致、详情默认 id=0 均标未完成并拒绝保存，原 CLI/caller-pinned 接口保持不变。


## P4-I：研讨室 Bridge/App 接线（实施前）

复用 P4-H 已逐操作核对的五范围，学校请求仍使用原 Core 方法。新缓存 DTO 不含 reservation/cancel eligibility、target 或内部订单材料；站点/用途沿原公开映射。App 保留零基订单请求、原页信息、明确日期与站点；本地日期在一次查询开始时捕获，不能每个路线重新换日。用途静态回退、错日期/默认空详情的 complete=false 不当作新完整成功，已有同范围只读内容优先保留。取消 caller-pinned 双回读保持原方法；预约提交后的既定回读使用明确 backend 能力绕过新增缓存恢复。门锁不接长期缓存。

P4-I 实施复核：五查询共用原公开投影，日期/页码参数沿原 App 规范化。Cache DTO 和生成 schema 均排除内部材料及资格。取消固定路线两读函数未改；预约后显式能力调用原普通订单读取，不走新增 required-session 恢复。用途选项保留证据时间和完整度，首次本地静态 Partial 不混作保留旧动态数据；无真实学校写入。


## P4-J：图书馆 Core 持久范围（实施前）

核对 old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3 的 LibBookApi、LocalLibBookApi、model/dto/LibBook.kt 与 commonTest/api/LocalLibBookApiBackendTest。buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81 的 api.rs 无此协议；最近的 srs/core.rs 是 byxk/xsxk 选课，不能借用它的 URL、模型、token、加密或错误。两者公共请求/凭据/Cookie 对照沿前述 P4-F；本次不修改业务认证或解析器。

以下每项共用原 CAS service=https://booking.lib.buaa.edu.cn/v4/login/cas、最多8跳及 query/fragment/location/final URL 提取；POST login/user 的 cas 换 member.token。保持每路线原 Cookie 与内存 token、串行 runtime，不复制会话。请求均为 /v4 下 POST JSON，原 Accept、Chrome147 UA、X-Requested-With、路线 Origin/Referer、Authorization bearer<token>（无空格）不变；读取无加密签名。保留 TLS 验证，不采用冻结 JVM/Android 的宽松 TLS。原过期单次恢复及错误分类不变；无 ETag/增量游标依据。

| 操作 | 精确路径/参数 | DTO/解析及持久白名单 | 缓存/并发/错误退出 |
|---|---|---|---|
| 楼馆 | space/pcTopFor，day | id/name/free_num/total_num/storeys，沿原 list/children 解析 | 账号/路线/原样日期；成功替换单日，失败保留；原 runtime 串行 |
| 分区 | space/pick，premisesIds/categoryIds=[]/storeyIds/boutiqueIds=[]/date | 原 id/name/area_name/premises_id/storey_id/free_num/total_num | 完整楼馆、可选楼层、日期入键；None 与非空楼层不折叠；空白 Some 原实现与 old 不同，新缓存入口拒绝，原在线方法不改 |
| 分区详情 | Space/map，id | 原 id/name/available_dates/time_slots；无日期请求参数，不捏造日期范围 | 精确 area_id，返回 id 不匹配不保存；保留旧集合 |
| 座位 | Space/seat，id/day/label_id=[]/start_time/end_time/begdate=""/enddate="" | id/name/no/status/status_name；剥离 reserve_eligibility/target，不从旧状态恢复资格 | 分区、日期、起止时间原样入键（空时间合法）；不添加不存在的 segment 参数 |
| 预约记录 | member/seat，type="1"/page/limit | 原 bookings/page/limit/total；剥离 cancel_eligibility/target | 正页码/大小隔离；原普通读取可按请求补缺失分页，响应明确错页不缓存；合法空页仅替换本页，无独立详情接口 |

缓存发布仍使用账号/世代/请求修订栅栏。原在线 DTO、CLI 与 caller-pinned 写后回读保持；缓存不产生 prepare 或 commit。本阶段仅 Core，Bridge/App、实际路线与性能另行记账。

P4-J 实施前补充：冻结 LocalLibBookApi 的 dataList、当前 parser 的 list_value/array/filter_map 允许空回退或丢弃非对象项。新增观察入口只判断原响应集合与解析集合是否完整，不修改原解析容错/请求、也不把缺字段当新协议事实；缺失列表、丢项、详情日期缺失记 Partial，保留旧完整记录。合法显式空数组仍可替换。


## P4-K：图书馆 Bridge/App 接线（实施前）

复用 P4-J 五操作冻结矩阵和观察完整度，不新增上游协议。Bridge 只读座位/预约 DTO 与在线资格 DTO 分离，楼馆/分区/日期时段只复用既有公开映射。App 精确保留查询日期、楼馆/楼层、分区、起止时间和 page/limit；segment 是当前 UI 选中时段的上下文，不冒充学校座位请求参数。离线和 Partial 内容不得显示实时可预约/可取消字段，不生成动作。预约与取消的普通写后回读显式绕过新恢复/缓存入口，保留原 WriteCoordinator 调用与一次提交语义。先加本地锁/隔离、公开白名单与宿主只读投影测试再实现。

P4-K 实施复核：五操作没有新学校参数；原页规范化、DTO字段和写路径保持。缓存与Partial投影明确不显示实时可写字段。网络前 segment 校验与原入口一致；响应错页/错分区无旧快照时不展示错误范围。Bridge v21 公开缓存 schema 有资格禁曝断言，原生合成仅验证绑定执行，不作为学校协议或真实 App 验收。


## P4-L：跨范围响应保护复核（实施前）

延续 P4-F/H/J 的逐操作来源矩阵与固定SHA。重新读取 LocalCgyyApi.getMyOrders（182起）：size/number 缺省分别回退请求 size/page；实际 GET orders/mine page/size 与原签名、认证、Cookie、错误不变。当前 Core 通用 parser 默认20/0不能用于判断非首请求页；新增缓存专用观察沿冻结请求回退，不改 CLI/原 caller-pinned 输出。显式错 number/size 或畸形/缺失 content 不得覆盖旧完整页；合法 data=null 沿旧实现允许空页，归属于请求页。账号/路线/发布世代屏障保持。

LocalBykcApi.getCourses（66起）将 currentPage/pageSize 取自请求，raw.number 原样读取但不用于推断请求页映射；不凭猜测加入 number==page 或 number==page-1 校验。缓存仍由请求 page/size/all 隔离。课程详情按明确请求 id 核对，错ID不能生成学校动作。buaa-api 无 Cgyy 协议，boya API不提供可借用的页号换算；不改学校请求或原在线接口。

App 缓存分支对 Cgyy 日期/站点/订单详情和订单页核对归属：有旧值只读保留，无旧值显示未完整而不放入异范围内容。Bykc 错详情保留同查询旧缓存，否则返回稳定 UpstreamChanged，不能把保存失败当作可继续显示的完整成功。学业 grades 的 term_code 与逐行 term_code 由请求构造；SPOC detail 在 parser/detail 明确拒绝raw.id错配；这两处已有来源保护，不添加无证据新字段。

P4-L 分页展示补充：博雅 App 的 currentPage/pageSize 改为使用本次规范化请求，与 LocalBykcApi 明确输出一致；不将响应number猜作一基或零基，不修改Core/Bridge原DTO和CLI。总量与总页数仍沿响应字段，本次页内容仍按请求范围入缓存。


## P4-M：评教 Core 持久范围（实施前）

冻结 old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3：EvaluationService接口、LocalEvaluationService、EvaluationModel及LocalEvaluationServiceBackendTest的直接读取/最小过滤/ypjcs测试；另一源 buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81：tes/auth、opt、data。两源都支持同一pjxt读取链，但另一源只提取首task、并行取问卷课程且直接传播失败，不能替代old/current的全已取任务聚合和部分容错。

| 操作 | bootstrap/重定向与Cookie | 方法/精确参数 | 头/编码/加密 | DTO与范围 | 缓存/并发/错误 |
|---|---|---|---|---|---|
| 激活 | old GET https://spoc.buaa.edu.cn/pjxt/cas；tes 显式SSO service同地址；当前沿原重定向，最终必须spoc/pjxt根或子路径 | GET，无业务body | 沿现有Session Cookie/路线重包/default headers，不新增头或签名 | 无业务载荷 | old激活mutex/布尔；当前原runtime串行，不复制Cookie；非认证失败原空返回只记Partial，认证错误继续传播 |
| 任务 | 同一已激活路线Cookie，业务GET终点原严格校验 | GET personnelEvaluation/listObtainPersonnelEvaluationTasks，yhdm当前账号/pageNum=1/pageSize=10 | URL query，无读加密或ETag | 原result/content信封；task.rwid；仅本次固定页，不推断学期或历史列表 | 显式合法空集合可完整；缺字段/畸形/取满10项无更多页证据时Partial；不新增游标或翻页 |
| 问卷 | 同任务 | GET evaluationMethodSix/getQuestionnaireListToTask，rwid | 同任务 | wjid/msid，原课程上下文，不暴露内部authority | 每已取任务依次读取；old子错误空回退保留，新增观察不把失败当完整空 |
| 课程与进度 | 同任务 | GET evaluationMethodSix/getRequiredReviewsData，wjid | 同任务 | 当前公开id/kcmc/bpmc/is_evaluated与列表计算进度；剥离submit_eligibility/target、msid/评价人/学年学期/问卷题目等内部字段 | 当前原聚合排序/去重资格保护保持；缺身份/状态或丢行Partial，成功完整才替换旧完整快照 |

EvaluationCurrent 固定范围是当前任务第1页/每页10，账号和实际路线独立；不是全部学期历史评教。只读payload不得含提交目标和资格；旧在线DTO及strict fresh写authority流程不变，缓存不调用reviseQuestionnairePattern、getQuestionnaireTopic、submit或其他写验证。两源写字段/常量不得因缓存便利引入持久类型。大聚合的分段让位仍需独立实现，当前阶段不声称解决评教长读抢占。

P4-M实施复核：get_all和strict读取经共享观察实现后仍返回原DTO，只有新缓存facade使用complete。课程id沿既有公开不透明组合键，不额外落盘结构化submit_target。Bridge现有Evaluation映射核对的公开字段为id/kcmc/bpmc/is_evaluated，新增缓存只取这四项；msid/评价人/题目内部字段均排除。部分成功、激活失败、课程503、状态缺失、任务页满、认证401分别用合成backend覆盖。


## P4-N：评教 Bridge/App 接线（实施前）

复用P4-M当前任务固定1/10读取链和完整度观察，不新增学校请求。Bridge缓存DTO仅四展示字段和进度，无资格/target/问卷内部参数；App摘要/待评筛选复用同一当前任务快照，保留视图查询身份和取得时间。Partial保留同账号/路线旧内容，进度不得冒称本次全部核对，缓存无动作。原EvaluationSubmissionReadbackBackend仍用evaluationAllOnRoute固定路线回读，不进入新增恢复入口，不改唯一WriteCoordinator。

P4-N实施复核：Bridge缓存DTO仅id/kcmc/bpmc/is_evaluated及三项进度，schema禁曝覆盖资格、target和内部材料。App没有新增学校参数，evaluationPending只筛选同一响应。固定路线回读经脱敏backend验证调用原入口且不增加缓存恢复；Partial投影无动作，部分进度不输出全部完成结论。


## P4-O：阳光记录 Core 精确分类分页（实施前）

冻结old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3的YgdkApi、LocalYgdkApi.getRecords/fetchRecords/postForm/session、DTO及LocalYgdkApiBackendTest第2页5条查询用例已复核。buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81无ygdk/Clockin/appid200230221144501510实现，api/app是其他校园读取，不能借用其会话或字段。

| 操作 | bootstrap/会话/重定向 | 方法和精确参数 | 头/编码/签名 | DTO/解析 | 缓存/并发/失败 |
|---|---|---|---|---|---|
| 业务认证 | 原app OAuth index，redirect=https://ygdk.buaa.edu.cn/#/home，appid=200230221144501510/state=STATE/qrcode=1；最多10跳，query/fragment取code；GET campusAppLogin?code，终点严格相等 | 沿原GET与路线内uid/token及generation | 原Cookie，token URL decode；不复制会话，不改TLS | uid/token仅认证内存 | 原登录锁、发送入口及响应后代次核对保持，不写缓存 |
| 分类/项目上下文 | 同一凭据代次 | POST Classify/getList；Item/getList query+form page=1/limit=1000/classify_id；form追加uid/token | form-urlencoded;charset=UTF-8与X-Requested-With；无新增加密或ETag | 含体育名称优先、原fallback分类；项目item_id/name等原映射 | 新记录缓存沿当前Core get_overview_context（已有可选count/term），不扩大请求；可选统计失败不当作记录失败 |
| 本人记录 | 同一上下文uid与classify_id | POST Clockin/getList，query及form双写page/limit/classify_id/user_id；仅form追加uid/token | 同上；不存在已证实的term/date过滤参数 | 原record_id、item_id/name、起止时间、place、isopen/state/create_time_fmt；图片只存image_count，绝不存URL/bytes/上传材料 | 正分类/页码/大小精确键；丢行、缺list/total或矛盾计数记Partial保旧；合法空页只替换该范围 |

新增“上次观察分类”只读索引，用于离线解析当前记录入口到明确分类键，不作为新的业务会话/资格。数据页先发布、索引后发布；任一步账号/世代/修订失效均拒绝，崩溃最多留下不可由旧索引选中的新页，不把旧分类正文放进新分类。原始取得时间以数据页为准。学校查询不加入termId，学期/周统计范围仍需单独处理；本阶段不把当前概览key当作学期隔离已完成。

P4-O实施复核：原get_records共享同一上下文内的getList请求函数，旧DTO解析和网络参数不变；新缓存仅增加完整度观察。图片数量采用原Bridge相同的长度转i32规则。冻结测试第2页5条而total=1仍合法，未引入页偏移/总量推断。父索引票据用现有仓库guarded发布及失败观察核对，不通过复制会话并发访问学校。Bridge/App接线尚待下一阶段。


## P4-P：阳光记录 Bridge/App 与概览匹配（实施前）

复用P4-O逐操作矩阵，不新增学校参数。普通记录可按实际分类/分页缓存；概览组合读取须使用新的明确facade合同，先校验所需路线与概览一致再校验会话，取得分类上下文后校验classify_id一致，任一变化不得继续getList或拼接内容。不改旧ygdk_records_on_route/overview_on_route及写后双回读。

Bridge公开索引与精确页分开读取；索引不含时间，只有数据页报告取得时间，记录DTO只含原公开image_count等展示字段。App普通记录先用索引选定分类再读该分类页；离线概览记录直接按概览自己的分类读页，不能借用另一个最新索引。记录证据与概览证据分开，部分/失败保留同分类同页旧数据，首次部分不标成旧完整。UI分页累计除路线/大小/相邻页外还核对分类，分类变化清掉旧累计记录，避免失败时残留旧分类。


## P4-Q：资料最小化持久范围（实施前）

冻结旧版1f4b8f8：AuthApi.kt的UserServiceBackend/getUserInfo、LocalConnectionAuth.kt的LocalUserServiceBackend与共享Cookie客户端、UserInfo.kt DTO已逐项读取；ApiFactoryDispatchTest只证明本地后端分派，没有发现对应userinfo响应解析专用测试。独立源a63712fa的api/user/{auth,opt,mod}.rs、request.rs、store/{cookies,cred}.rs仅实现status原文读取和UC激活，没有userinfo或同等完整资料DTO。当前Core-live两路线user/info已通过，只证明既有在线链，不证明新缓存。

| 操作/边界 | 冻结事实与本轮合同 |
|---|---|
| CAS/bootstrap与service | 沿既有UC认证；旧激活/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin，资料读取自身不新增CAS请求；独立源相似UC激活但不借其未转义target写法改当前协议 |
| 方法与参数 | 旧GET https://uc.buaa.edu.cn/api/uc/userinfo，无新增query/body；另一源GET status?selfTimestamp=...仅为状态接口，不借时间参数给userinfo |
| 重定向/最终URL | 旧共享客户端跟随；userinfo检测401、SSO最终地址、HTML或登录表单文本为失效；当前Core保留既有有界重定向及user模块错误分类 |
| Cookie/会话 | 旧按ConnectionMode本地会话及Cookie共享客户端，失效清除；独立源共享Cookie与CredentialStore，不能用于替代本地归属；新读取仍在同一Core锁与runtime中执行 |
| headers/encoding/加密 | 旧资料GET无单独header或body；共享JSON插件/Cookie不变，无业务签名/加密常量；本轮不改变Core请求构造、TLS或传输默认头；持久内容继续AES-GCM |
| DTO/parser | 旧code/data包装和八个可空字符串；Core沿原parse_user_info，code!=0/无data失败；在线完整UserProfile不变。缓存仅遮罩username/name/schoolid，phone/email/idCardNumber/idCardType/idCardTypeName均不保存 |
| 缓存/并发 | 新MaskedProfile按账号库+实际路线保存；解析一次User路线、状态身份核对、建立票据再取userinfo；返回身份再次核对，退出/旧票据不可回写；不复制Cookie、不并发更新session |
| 错误/退出 | 既有认证/业务错误原样返回；请求失败保留旧快照。身份字段全缺失返回UpstreamChanged且保留缓存，明确不匹配才关闭该缓存并返回IdentityMismatch；磁盘保存失败与合法在线结果分开，旧CLI/userInfo及双路线认证语义不变 |

遮罩是本地展示规则而非上游字段推断：Unicode首尾各最多一字符，中间固定***；长度不足三字符全部***，空白变None。遮罩内容永不作为认证身份或资料完整性的证明，不恢复写资格。初步缓存仅供识别本机账号，完整资料仍需在线既有读取。后续Bridge/App需另接此只读类型并显示保存时间，不把当前Core阶段计为完成。


## P4-R：资料 Bridge/App 展示接线（实施前）

沿P4-Q逐操作对照；不新增学校参数或资料字段。Bridge本地DTO仅公开三个masked字段、实际来源与取得时间；新user_info_cached复用Core的User路线/状态和资料身份双核对，pending写意图禁止隐式恢复。旧userInfo及CLI双路线语义不变。App新增独立本地资料与在线缓存刷新合同，不将遮罩username传入认证判断、账号索引、凭据或写入协调器。

首页磁盘读取不阻挡首帧；资料作为独立只读展示恢复，实际身份仍来自安全账号索引/在线认证。认证成功后通过现有后台优先级队列补全完整资料，晚到缓存不得覆盖已取得在线资料，退出/切账号/路线代次保护同当前控制器。个人页区分保存来源，缺失联系方式不显示可揭示原文按钮；刷新失败保留旧资料。此阶段不得以确定性测试替代真实App和性能验收。


## P4-S：统一缓存用量与清理代次（实施前）

本阶段没有学校请求。旧版1f4b8f8的ScheduleRepository.kt/对应测试提供按账号保存完整学期、修订变化和失败保旧依据，ScheduleStore.forgetAccount只移除账号入口；LocalJudgeApi的内存列表/详情缓存没有统一SQL用量或跨连接清理合同。独立源a63712fa的store/{cookies,cred}.rs保存认证材料，并非业务仓库，不借其删除/过期机制清理业务缓存。以下新增均为已接受设计6.4的本地存储合同，CAS/service、重定向、Cookie、HTTP参数、headers/body、上游加密签名、DTO解析及CLI错误/退出语义全部不变。

用量仅报告条目数、密文内容字节、SQLite文件/可复用页字节和当前软硬限额，不解密业务正文。新清理入口保持当前账号活动状态，原子清除内容/请求并轮换持久句柄代次；调用方必须使用返回的新句柄，旧clone和另一连接均不能取新票据、激活或继续写回。旧clear/deactivate/activate合同保留，新入口用于设置中的仅清理缓存。

控制记录升级schema v2；v1在正确密钥下事务迁移，业务记录及索引算法不变。控制记录采用v2独立AAD，使已打开的旧格式连接也不能忽略新代次后写回旧控制结构；未知版本/错误密钥不得迁移。该AAD属于本地缓存格式，不修改任何学校加密常量。清除事务失败保留旧句柄和内容；事务成功后的空间压缩/统计失败独立报告，不能把内容清理和物理空间回收混为一项成功。

Bridge/App须后续接入用量、更新句柄、取消旧任务及设置页，不能把本阶段Core-only计为全部缓存管理完成。容量保留优先级与学期完整覆盖仍按活动合同继续。


## P4-T：缓存管理 Bridge 与宿主读取代次（实施前）

沿P4-S本地管理对照，不增加学校请求、参数、会话或写资格。Bridge只暴露数值用量、维护结果及新opaque缓存句柄；旧clear/deactivate/activate保持。App在原offline串行通道中替换句柄，失败不丢原句柄；清理先推进调用链代次，旧多步读取不得重新取得新句柄。Core持久generation仍是落盘防线，Dart调用链标记仅阻止尚未发送的后续步骤，不宣称网络抢占。

普通缓存读取与资料读取共享该代次；既定写后caller-pinned或useCache=false回读不改路由或认证语义。设置页/控制器随后须取消排队任务、保留登录与查询位置、区分清除事务失败和提交后的维护失败；当前接口接线不等于整个设置功能已验收。

## P4-U：控制器缓存管理（实施前）

沿P4-S/P4-T本地合同接控制器，不修改学校协议。仅清理业务缓存时保留认证与安全账号材料，确认携带账号标识；登录恢复、写准备/确认/提交/回读期间拒绝清理。清理前取消未发送读取、停止旧生命周期交付，成功清空内存业务投影但保留查询上下文，不自动补发同步；事务失败保留原内容并结束旧loading。控制器与设置UI证据分别验证，不能以backend通过代替页面位置与反馈验收。

## P4-V：容量保留策略（实施前）

冻结SHA沿本文件既有P4逐操作对照（ubaa_old 1f4b8f84；buaa-api a63712fa）。此次只调整本地容量压力下的条目选择，不新增或改变任何CAS/service、重定向、Cookie、HTTP参数/编码、请求头、签名或学校错误；原逐操作表继续适用。再次核对旧DTO Judge.kt/Spoc.kt的dueTime、Cgyy.kt的reservationDate、LibBook.kt的day、Exam.kt日期字段；Core只使用已白名单保存的对应字段。Judge parser/calendar与SPOC calendar已将有据格式规范为校园时间，新的缓存策略只接受严格日期/规范时间，不从开始时间推断截止、状态数字或列表顺序。

buaa-api的api.rs/aas/data.rs为近似教务来源，schedule Date/Time类型不能替代当前原样DTO；它没有相同Judge/研讨室/图书馆协议的可替代字段合同。SPOC原差异沿既有逐操作记录，不借另一源的接口或状态实现本地过期判断。新策略按账号库、实际路线独立读取已缓存的Terms.selected；必须唯一且24小时内新鲜，才能提升对应当前学期课表/考试，不猜第一项或从学期编码反推当前学期。

保留等级仅用于容量淘汰，不授权写入、不声称新鲜：当前学期/当日课表、未到截止的待办与将来订单优先；近90天已结束条目保留在软硬容量之间；稳定学业和希冀课程/作业索引、复查依据单独保护；已证实过期资源、超过90天的已结束详情/分页先淘汰，同级按访问时间。未知日期不标为过期，旧课程索引不能因含旧详情被永久排除。每次压力重新依据当前时间排序，不能把发布时priority永久固化。新条目超过硬限额且只能挤掉更重要条目时返回Capacity并回滚，在线读取仍可返回，不能声称已保存。

## P4-W：损坏缓存重建与数据库身份（实施前）

这是本地业务库维护，不新增学校操作；认证/只读协议的双冻结来源对照沿本文件既有各操作记录。examples、session.json、账号/凭据保险箱均不属于重建目标。可打开库仍按原事务清理；单行损坏继续只隔离该行。打不开的当前账号库需要独立显式入口，普通open不得自动清空或把密钥错误推断为损坏。

已核对锁定rusqlite 0.38.0的src/config.rs及SQLite官方SQLITE_DBCONFIG_RESET_DATABASE说明（https://www.sqlite.org/c3ref/c_dbconfig_defensive.html）：RESET_DATABASE配合VACUUM可重建严重损坏库；此机制不可逆，只用于设置确认后的业务缓存副本。实现前测试要覆盖独立连接、旧票据、未知版本、失败与会话文件不变；不能用删除文件后归零计数冒充代次安全。

控制记录增加随机数据库身份，持久格式升v3，v1/v2在正确密钥下事务迁移，业务条目/查询索引仍沿原编码。旧票据同时绑定数据库身份，防止重建后epoch/revision重合；旧格式AAD不能打开新控制记录。重建在SQLite独占连接内完成清空和新控制初始化，发布新句柄前释放独占连接。清空前错误与清空后初始化错误分别表达，不把不可用的空库当作已可离线保存。Bridge/App接线必须随后与新明确合同配套，不将Core能力算设置恢复闭环。


## P4-X：跨学期统计本地渐进读取（实施前，2026-09-22）

冻结SHA不变。复核旧版GradeApi/LocalGradeApi/Grade DTO、GradeViewModel及GradeViewModelTest：逐学期读取完整集合，旧内容在刷新期间保持，学期列表来自TermRepository；另一来源aas/opt.rs只有配置及周/学期课表，没有同构buaascore成绩操作。认证/bootstrap、service、重定向/终点、Cookie范围、POST xq/year、请求头/表单编码、e/m/d解析及原错误分类全部沿本文P4-B成绩行，不新增或修改学校请求，不从AAS借用成绩协议。

新增操作仅聚合既有精确账号/路线/学期的本地只读投影，不使用学校Cookie或认证锁。学期索引和每学期各保留原时间/完整度，缺项不能充当空学期，缓存不能触发成绩变化提醒。生产在线队列继续原逐请求调度；渐进回调先交付本地集合，最终完整成功优先，失败可保留同范围历史且明确未更新。退出、切换账号/路线、清理代次变化后不交付迟到缓存。两份冻结来源均无同构加密聚合仓库，不新增上游能力假定。


## P2-F：本地缓存打开与路线切换生命周期（实施前，2026-09-22）

本轮只调整App持有本地加密仓库的生命周期，不改任何学校读取/认证操作。双来源依据仍为P0-C账号归属、P1-B及P4-X的本地读取对照；旧ScheduleRepository在返回前核对账号，另一来源没有同构本地首页。CAS/bootstrap、service、重定向/终点、Cookie、方法/参数、头/编码、加密常量及学校DTO均不适用此次本地打开操作且不变。缓存加密与密钥读取沿现有合同，不能复制Cookie或建立并行会话。

同账号路线改变可以继续打开账号库；读取投影仍按最新实际路线重新获取。退出、删除账号、换账号、backend替换和dispose必须终止旧打开所有权。密钥迟到仍须清零，不能在同账号重新登录后复活旧打开。


## P4-Y：完整学期快照与日期投影（实施前，2026-09-22）

复核两份固定SHA：旧版api/feature/ScheduleApi.kt、api/local/LocalScheduleApi.kt、repository/ScheduleRepository.kt、ScheduleSnapshotStorage.kt及ScheduleRepositoryTest/ScheduleSnapshotStorageTest；另一来源api/aas/{core,opt,data}.rs。旧版本科importSemester逐学期列表→教学周→各周读取，全成功才发布账号名下学期集合，保留其他学期；WeeklySchedule.code本科实际是学号，不能误校验为学期。研究生旧版有专用适配，本阶段不新增Core未实现的研究生协议。另一来源type=term请求有campusCode/query差异，不代替旧版逐周表单。

本地完整导入为独立的账号/实际路线集合，其中每个学期显式携带termCode、学期元数据、完整周次及周课表映射和该学期取得时间。每次成功导入合并同一集合并原子发布，保留其他已导入学期及其原时间；不把普通逐周缓存拼成完整导入。该集合沿旧版单账号快照结构，仍经统一加密仓库、修订票据与容量限制；容量不足拒绝新保存，不由普通缓存压力淘汰已明确导入集合。

完整度校验沿旧版：学期存在、Week.term匹配、正且唯一周次、周次集合完全一致、合法规范化日期。用于按日期投影时额外拒绝同学期重叠周/超过七天的周范围，未知weekday不能推断当天无课；无覆盖日期返回未保存。跨学期重叠按旧版选开学更晚的覆盖学期，时间按对应学期保留。归属来自请求term和Week.term，不来自WeeklySchedule.code。

本阶段本地操作不涉及CAS/bootstrap/service、重定向/终点、Cookie、HTTP方法/参数、头/编码、加密签名或上游错误变更；以后分段导入的学校读取继续P4-B学期/教学周/周课表逐行合同，每周请求及会话维护完成后才能释放共享锁。原普通读取/CLI语义保持，不推断一次批量上游接口、增量游标或ETag。

P4-Y保守覆盖边界补充：旧普通教学周parser允许缺datas回退为空，无法据此证明一个已存在学期确实没有教学周。因此新完整导入拒绝空周索引，保留旧导入；原普通空查询返回不变。每个有效周内显式空课表仍可保存为真实无课，二者分开。


## P4-Z：完整学期分段导入 facade（实施前，2026-09-22）

逐操作复用P4-B表中学期、教学周、周课表的全部协议列：前置currentUser能力探测、必要时原AAS CAS service及落地检查、原路线Cookie、学期GET无参数、教学周GET termCode、周课表POST termCode/type=week/week三表单项、AJAX头/Referer和原DTO。与双冻结来源的差异仍沿P4-B及P4-Y：不借用buaa-api的type=term/query/campusCode，不新增研究生实现。每一批包含该操作必要的激活/重定向与业务返回，经runtime.request会话保存及finish_routed认证/会话冲突收尾后返回；边界在完整函数返回处，不拆单个重定向或复制会话。

计划仅持账号缓存票据、请求学期、实际路线、路线配置代次及原客户端功能状态弱引用/清理代次。认证先使用既有recover_required_session(Schedule)，之后每批只做学期索引、教学周索引或一周读取，全部成功才发布完整导入集合。取消、退出、换账号、会话替换、切路线、较新导入或清理使旧计划终止，失败不重发。原CLI和双路线读取不变。

完整度补充：旧版parseWeeks/parseWeeklySchedule与当前普通Core读取均容忍包装code；本方案不能把未知code宣称成功完整导入。保留普通读取的容错语义，导入入口只接受旧版成功Mock和固定脱敏fixture提供的code=0及有效载荷；其他值仅报告无法证明完整，不按数字推断学校业务错误。缺教学周/归属和日期不完整同样停止导入并保旧。

P4-Z并发审查补充：导入租约按实际路线和请求学期分离；集合发布时单独取得集合票据并在事务内验证学期父票据，避免不同学期互相取消或丢失已发布集合。周次索引及每周分别记录实际取得时间和数据库请求修订；读取精确范围按请求修订仲裁，不用墙钟比较先后，也不把整个导入收尾时间冒充每周取得时间。新完整度入口尚无本阶段Core-live证明。


## P2-G：辅助读取的明确账号冲突（实施前，2026-09-22）

沿P4-Q已核对的账号身份与P4-R统一CacheIdentityMismatch错误，不新增身份字段、学校URL或参数。双冻结来源的认证/bootstrap/service、重定向、Cookie、方法/编码/加密与DTO/error事实均沿既有对应操作；本轮只将App辅助读的明确冲突交给已有关闭账号流程。原普通页面读已经处理该标志，学期/周次/跨学期统计等辅助读之前仅转换UiError而遗漏它。普通认证失效继续保留缓存；明确账号不一致才关闭本机恢复和写入口。旧路线/旧账号迟到错误不能关闭当前身份。

## P4-AA：整学期导入的 Bridge 与宿主接线（实施前，2026-09-22）

冻结引用及逐操作协议完全沿 P4-B、P4-Y、P4-Z：学期、教学周、单周的 bootstrap/service、重定向终点、原路线 Cookie、HTTP 方法和精确参数、头和编码、DTO 及错误均不变。Bridge 仅公开既有 facade 的 begin/next/cancel，不新增学校 URL、字段、加密、增量或 ETag 假定。双来源都没有同构持久导入 FFI 合同；不得借 buaa-api 学期批量协议替换旧版本科逐周操作。

每次 next 在原客户端共享锁内完成一批和原会话收尾，返回后释放；取消为不持网络锁的原子标记。在同一锁下先检查待确认写意图，拒绝时不清除意图、不发请求。宿主分别管理固定学期任务与当前页面查询；每批经现有读取队列让位于交互读取，账号/路线/清理/退出代次失效后丢弃迟到进度。全部周完成且本地保存无错误才显示保存成功；半途失败保留既有完整学期，不自动提交任何学校写入。

## P4-AB：离线课表导航、周日期与学期索引退路（实施前，2026-09-22）

再次核对冻结旧版ScheduleRepository.kt的terms/weeks、normalizeDate及ScheduleRepositoryTest离线跨周/日期规范化用例；旧版本地学期索引来自完整快照，周次curWeek按当前日期重算。ScheduleViewModel按学期→周次→课表推进；当前实现保留既有唯一selected/唯一周次约束，不借旧版firstOrNull猜默认。buaa-api的aas/opt.rs仅有在线周/学期请求，不具备对应持久仓库或离线导航；不能从其type=term接口推导批量导入。

本轮只改变本地投影与UI推进，不改学校CAS/bootstrap/service、重定向终点、Cookie、HTTP方法/参数/头/编码、签名加密、DTO或业务错误；逐操作协议继续P4-B。离线完整内容可在网络挂起或失败时继续只读导航，部分索引不能据此自动挑选。普通保存的教学周也按校园当前日期重算当前周，非法日期不延续旧curWeek标志。完整导入提供学期索引退路，保留索引原取得时间与精确请求修订；不得用导入结束时间伪造索引刷新，也不能覆盖较新的普通学期索引。

## P4-AC：学校写入后关联缓存失效（实施前，2026-09-22）

冻结SHA不变。复核旧版BykcViewModel选退课成功后重读详情/已选/列表、LibBookViewModel预约与取消后的记录及资源读取、CgyyViewModel订单/资源重读、YgdkViewModel提交后refreshAll；签到与评教继续既有WriteCoordinator固定目标和回读合同。buaa-api只有部分对应在线API（包括tes），没有本项目同构加密业务缓存或写后跨查询失效，不借其接口扩展已有学校写入。

本轮新增本地操作，不改变任一学校操作的CAS/bootstrap/service、重定向终点、Cookie、HTTP方法/精确参数/头/编码、签名/加密或DTO/错误：各列沿此前相应领域逐操作对照和现有写合同。Core仓库在短事务内删除同账号、实际路线和影响范围的旧条目及在途读取票据，不能只删除已有条目而允许无旧条目的在途请求回填。未发生学校写入、未确认结果与确定成功仍由既有协调器区分；本地失效不是学校成功证据，也不能改变commit次数或自动重发。

影响范围：签到为原校园日列表；博雅为目标详情、课程列表分页、已选及统计；图书馆为订单分页和相关日期/区域资源（取消缺乏可信区域信息时仅在该路线图书馆领域保守扩大）；研讨室为订单分页、目标订单详情和对应站点/日期资源，缺材料时不猜字段；阳光为概览与目标分类记录分页；评教为当前任务集合。其他账号、另一条实际路线、成绩/课表等无关领域保留。请求范围需加密持久化以精确取消无旧条目的在途任务，schema升级须保留旧业务密文与退出状态并拒绝旧已打开句柄。

## P4-AD：单次commit后的缓存处理合同（实施前，2026-09-22）

学校协议、prepare和commit前实时资格读取全部沿P4-AC对应冻结对照及既有写合同，原commit_write接口保留；新缓存入口复用同一消费/分派实现，不增加第二次学校提交。原客户端锁在确定结果和本地失效收尾后释放，防止后续新读取先保存、又被延迟失效误删；SQLite工作进入阻塞池，不复制会话。

确定成功、部分评教已成功项目和未知提交结果可能改变学校状态，因此失效对应缓存；明确失败或发送前资格拒绝不当作成功清除。未知结果仍不自动重发。失效失败与原学校结果并列，不能把已成功提交改报学校失败。取消图书馆预约只有稳定订单ID、研讨室取消只有订单ID时，不从展示名称猜区域/日期；按P4-AC仅在同路线相关资源域保守扩大。缓存句柄由已打开本机账号持有，使用调用开始时的原句柄，不能在返回时绑定到新账号。

## P4-AE：阳光概览的已观察学期与本地周期范围（实施前，2026-09-22）

重新读取冻结旧版LocalYgdkApi.kt的getOverview、fetchCheckCount、fetchTerm、mapYgdkSummary与Ygdk.kt：Term/get只提供term_id/id/name；week_count是次数，week_num是目标，不是教学周。另一冻结buaa-api的api.rs和src/api模块没有阳光协议。沿P4-D/E及P4-O/P逐操作OAuth、跳转、Cookie/uid/token、HTTP表单/query/头、DTO、原一次认证重试和错误事实，不增加学校参数、ID、游标或ETag。

本次只扩大本地键：分类、已观察term_id（缺失单独隔离）、校园UTC+8日历观察周。周一是本地分桶边界，不声称学校统计周也如此划分；学校未提供教学周编号，不能从week_count/week_num推断。周选择索引只指向该周已保存范围，旧周与旧学期不会覆盖新范围；索引和业务内容原取得时间分开。跨日不把昨日day_count当今日，跨月不把旧month_count当当月；缺学期组合结果只算部分；跨校园日期的组合不发布，旧完整范围仍保留。旧无周期单例不改写、不猜归属，保留到正常清理但不作为新周期索引读取。写后失效同时覆盖同分类周期与选择索引，仍不执行真实写入。

## P2-H：前台恢复退避与本地网络变化唤醒（实施前，2026-09-22）

会话检查、必要路线登录、资料与退出逐操作继续P0-A/P1-A/P2-A/B既有九列；重新核对旧App.kt自动登录/splash条件和buaa-api/error.rs的Auth/Network/Server分类。双方没有本项目相同的离线首页退避协调器，不借另一来源原始错误日志或凭据TTL策略。CAS/bootstrap/service、跳转和终点、Cookie/持久会话、方法/参数/头/编码、加密及DTO均不改；宿主只按既有稳定错误代码调度新一轮完整会话检查，不叠加到Core单次内部重试中。

按接受设计4.4采用30秒、60秒、5分钟封顶前台退避。仅临时网络/超时/服务不可用且未明确retryable=false可自动重试；凭据、交互、解析、账号冲突及客户端内部失效不能据此提交密码。网络接口集合变化只作为等待任务的唤醒提示，不宣称校园服务或认证已恢复；系统接口枚举为本机只读，无学校请求，地址只在内存比较不进日志。后台、写活动、清理/重建和退出沿原协调器屏障；前台和手动重试合并同键，自动恢复仍不自动提交学校写入。

## P2-I：无持久缓存的希冀逐批读取（实施前，2026-09-22）

沿P2-C/P3-A逐操作九列，再读冻结LocalJudgeApi.kt的getCourses/getAssignments/getAssignmentDetail与getAssignmentDetailsResponse：courselist.jsp?courseID=0读取索引，每个作业索引或详情前必须完整selectCourse，随后GET assignment/index.jsp及可选assignID；两步受课程选择锁保护。认证/bootstrap/service、跳转与最终URL、路线Cookie、参数/头/编码、解析及错误仲裁全部保持当前已对齐的scan实现。buaa-api没有Judge模块，不能借SPOC/其他课程接口推导字段或会话行为。

新增不依赖OfflineCache/密钥的在线计划，仍绑定原客户端功能状态、路线代次与取消标记，不创建第二持久会话、不复制Cookie。复用同一选课+索引/详情步骤，完整收尾后返回；每批固定原路线，退出/清会话/换路线及取消拒绝迟到返回。显式目标必须在课程与作业索引中核实，不因目标缺失遍历无关课程。新计划强制读取已验证步骤以便提供真实取得时间，不将内存TTL返回时间冒充网络时间。

旧六个月规则不是新增功能；无顺序证据不能遇旧项早停。新全量计划逐项核实，仅按已实现P3历史条件筛选展示（已提交、明确旧开始且截止已过去14天），不永久排除旧课程、长周期或未知日期。旧CLI/聚合/双路线接口保留原合同，新公开分段入口的Bridge/App接线随后完成。

P2-I身份补充：有本机账号但缓存密钥不可用时，新在线计划仍接收可选期望身份，只与原UC状态白名单username/school_id核对。冲突在课程请求前返回既有IdentityMismatch，不绑定旧账号展示；缺少本机账号的普通在线场景沿原会话所有权。期望身份不写入磁盘、日志或学校参数。
