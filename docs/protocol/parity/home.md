# 首页

本文件收录首页状态、读取编排、待办、日程投影、并发与加载性能的来源对照。

## 当前规则

### 首页状态与读取编排

本轮冻结引用为旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。核对旧版 `HomeBootstrapCoordinator.kt` 及并发、取消测试，`LocalConnectionAuth.kt` 的会话校验和分路线 Cookie 存储，以及 `LocalScheduleApi.kt` 的学期、教学周和日课表读取。核对 buaa-api 的 `api/user/auth.rs`、`api/aas/{core,opt,data}.rs`、`request.rs` 和 `store/{cookies,cred}.rs`。旧版统一启动来源、分别交付结果；示例没有首页编排或同等的共享账号代次。示例的 Cookie 简化、认证有效期和 TLS 设置不作为当前实现依据。

展示日期课表的首屏预读从完整本机学期、教学周和周课表投影，和当前周预读共用账号、查询、实际路线及完整度核对。首次显示可直接采用该日期的课程或明确空结果，随后在线更新保留这份内容。预读缺少任一范围即交付缺失，不联网补齐；在线操作继续使用下表既有协议。

日程页复用首屏预读确认的当前学期和实际路线，按校园日期匹配教学周，不等待在线教务刷新才能读取已有课程缓存。缓存只补充尚未确定的日程范围，不能覆盖同一会话已确认的在线学期。首页其他来源和本地日程更新时保留签到操作；签到来源、读取代次或账号路线范围变化时撤销旧操作，再由现有投影核对资格。上述本机行为对照旧版 `HomeBootstrapCoordinator.kt`、`ScheduleApi.kt`、`LocalScheduleApi.kt`、`ScheduleSnapshotStorage.kt`、`ScheduleViewModelTest.kt`、`LocalSigninApi.kt` 和 `Schedule/Signin` DTO，以及 buaa-api 的 `api/aas`、`api/class` 模块。两份来源均无同等的 UBAA2 日程范围恢复与待办操作失效机制，这两项本地操作的上游协议列不适用；学校认证、读取、写入沿用既有逐操作对照。

同账号、同路线的客户端重建保留首页已显示的只读待办、补充来源和展示日期课表，同时撤销旧签到操作及在途读取。账号、路线策略或业务缓存范围变化时清空内容。客户端恢复与内容归属分别判断，不改变既有认证、缓存格式或上游请求。

| 操作 | CAS/引导与 service | 跳转与最终地址 | Cookie/会话作用域 | 方法与参数 | 请求头与编码 | 加密/签名 | DTO/解析 | 缓存/并发/重试 | 错误与产品语义 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 首页主来源、博雅已选及研讨室订单 | 沿用各来源既有对照 | 原有最终地址检查 | 原账号和路线隔离 | 原精确请求，无新增端点 | 原请求头和正文 | 无新增 | 原 typed 结果 | App 统一编排，局部重试仅更新目标来源；八业务组及组内串行保持 | 首批可显示与后台补全分开；内部取代只在原请求仍有效时继续 |
| 当前周与展示日期课表 | 沿既有教务及研究生分流 | 沿 Core 校验 | 原缓存账号、查询与路线来源 | 旧版学期 GET、教学周 GET termCode、周表 POST termCode/type/week；示例 currentUser 和 campusCode 不借用 | 原教务头与表单 | 无新增 | 原学期/周 DTO，缓存周按当前校园日期选取 | 本地缓存先交付，在线刷新仍走原调度；不新增缓存格式 | 缺学期、周范围或部分结果保持未知，完整空集合可替换旧内容 |
| 本地待办投影与首页同步状态 | 本地操作，两源上游列不适用 | 不适用 | 同账号、读取范围和操作资格检查 | 不发学校请求 | 不适用 | 不适用 | 复用 Core 待办投影及本地完成标记 | 合并重复输入，保留时间变化触发；不持久化派生待办列表 | 刷新和失败保留适用内容，账号切换与失效动作及时撤销 |
| 同一轮所需路线身份校验复用 | 沿 SSO 独立验票记录；两冻结源无相同验票流程 | 原取票与验票校验 | 每个实际路线独立，账号及会话代次变化失效 | 原 SSO GET 取票和 GET 验票参数 | 原头与编码 | 无新增 | 原已核实身份 DTO | 仅复用明确有效范围的成功校验，不延长持久会话期限，不并行提交登录；功能路线仍逐项解析 | 业务认证失败重新校验，身份不符、退出和路线变化撤销旧结果 |

### 首页读取与日程学校缓存

2026-11-05 核对冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ScheduleApi.kt`、`api/local/{LocalScheduleApi,LocalSigninApi}.kt`、`api/storage/CredentialStore.kt` 和 `model/dto/Schedule.kt`，以及冻结 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/api/aas/{core,opt,data}.rs`、`src/api/class/data.rs`、`src/store/{cred,cookies}.rs`。当前操作沿用既有 Core 协议，逐操作差异如下。

| 操作 | CAS/service 与引导 | 重定向与最终 URL | Cookie/Session/Token | 方法与精确参数 | 请求头与正文编码 | 加密/签名 | DTO 与解析 | 缓存/并发/重试 | 错误与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| 当前学期与教学周 | 旧版本科教务和既有研究生分支；示例 AAS 通过 `currentUser.do` 取得当前配置，不能替代旧版学期索引 | 保留现有 Core 教务跳转及最终地址校验 | 保留账号和 Direct/WebVPN 隔离，示例共享 Cookie 不作为放宽依据 | 旧版 GET `schoolCalendars.do`，GET `getTermWeeks.do` 携带 `termCode`；不借用示例配置字段补齐学期 | 沿用教务请求头，无新正文 | 无新增 | 唯一 `selected` 学期和同学期唯一 `current` 周；保留现有 DTO | 复用首页补充读取和缓存，不把今日摘要当作周课表 | 缺学期仍可查询签到等独立缓存来源 |
| 当前周完整课表 | 沿用上述教务会话；无新引导 | 沿用 Core 校验 | 同账号、路线及读取代次 | 旧版 POST `student/getMyScheduleDetail.do`，表单 `termCode`、`type=week`、`week`；示例另带 `campusCode`，本次不借用 | 旧版 `applyScheduleHeaders` 与表单编码，保持现有 Core 实现 | 无新增 | 使用完整周表课程身份、时间和教学周索引；`TodayClass` 摘要缺少稳定身份，不构造学校事项键 | 当前周补充读取成功后通过现有调度和缓存入口取得周表，保留完整学期导入标记的独立含义 | 周表失败不隐藏首页已读结果；成功保存后刷新日程投影 |
| 签到等已缓存待办与日程合并 | 本机操作，两源无对应上游协议，不适用 | 不适用 | 缓存账号别名必须与日程一致，查询范围继续绑定路线 | 不适用，无新增学校请求 | 不适用 | 不适用 | 复用现有公开缓存 DTO 和 Core 学校投影，不生成签到写资格 | 未知学期不阻断独立日期来源；缓存发布后使旧日程投影失效 | 本地标记、损坏分类、退出及账号切换隔离保持 |

自动路线的日程查询采用当前代教学周实际读取路线，双路线均已登录时也不改选 Direct；固定 Direct/WebVPN 策略继续使用明确指定的路线，每次投影只查询一个路线范围。

日程学校刷新在 App 编排六个主来源、博雅已选、研讨室预约和当前教学周，宿主的刷新回调直接接入该入口。宽屏日程不依赖首页挂载。App 入口先推进读取代次，再合并同代补充请求，等待当前周完整课表缓存和研讨室后续页读取结束。普通首页补充查询仍先交付周次和预约第一页。窄屏保活首页时，现有界面可能在主来源首批可显示后结束指示器，后台缓存完成仍会刷新日程投影；日程界面需直接等待完整刷新回调。Auto 各次读取可能选择不同路线，投影按原有精确路线范围报告缺口。

本机刷新编排另核对上述冻结旧版 `ScheduleApi.kt`、`LocalScheduleApi.kt`，以及 `LocalBykcApi.kt` 的当前学期已选列表、`LocalCgyyApi.kt` 的 `getOrders(page,size)`。固定 buaa-api 的 `src/api/aas/{core,opt,data}.rs` 提供现有周表证据，`src/api/boya/opt.rs` 提供已选列表证据，没有相同研讨室协议，研讨室对此来源记为不适用。各来源继续使用既有 Core 的 CAS/service、重定向和最终 URL、路线隔离的 Cookie/Session/Token、请求头、编码、加密与 DTO；周表沿用 `termCode/type=week/week`，研讨室沿用零基 `page` 和 `size=20`，不借用示例的额外字段。刷新等待、请求合并及生命周期检查是本机操作，两源无同等协议，其余协议列不适用。不增加认证重试或学校写入。

日程按来源和范围读取缓存。完整空集合表示读取成功；未读取的学期、周、日期、路线或分页表示缓存缺口。SPOC 可选课程信息、希冀部分课程、阳光可选统计缺失时保留现有 Partial 语义。`lastAttemptSucceeded=false` 同时覆盖请求失败与结果不完整，单凭此字段不能确定失败原因；核验时间保留实际来源时间。

首页分段读取另核对旧版 `api/local/{LocalConnectionAuth,LocalSpocApi,LocalJudgeApi}.kt`、`shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalAuthSessionStoreTest.kt`，以及示例 `src/api/user/{auth,opt}.rs`、`src/request.rs` 和 `src/store/cred.rs`。SPOC、希冀和认证各自的 CAS/service、重定向与最终 URL、Cookie/Session/Token、HTTP 方法与参数、请求头与编码、加密常量、DTO 和错误解析沿用现有逐操作对照。本次仅在当前恢复范围已核验、成功重新登录后重新准备本机读取计划；两源均无 UBAA2 双路线读取池和分段计划，因此该本机操作的上游协议列不适用。读取池绑定双路线修订，任一路线登录替换读取池时，准备中和已准备的分段计划均重新准备。已知登录事件引起的重建不占用鉴权失败最多恢复一次的次数；普通 `operation_conflict` 不自动重试，账号、路线策略和生命周期变化仍取消旧读取，Core 修订校验保持。

## 专项记录

### 2026-11-06：首页同键读取冲突恢复

冻结来源仍为旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。旧版 SPOC 通过客户端与登录互斥管理会话；希冀通过课程选择互斥和进程内 TTL 缓存管理读取。固定 buaa-api 没有希冀模块，也没有与当前加密离线缓存读取票据等价的跨读取恢复机制。此处本机同键并发协调对两个来源均不适用。

本次只在账号、缓存生命周期和查询键仍有效时恢复被更新读取取代的 SPOC 选择或希冀摘要：存在较新的完整提交时复用它，否则为同查询分配新读取票据并完成一次读取。取消、账号变化、清理、退出、仓库替换和学校写入失效仍拒绝旧任务。SPOC 零页终态由 Bridge 作为终态交付。学校请求 URL、方法、参数、请求头、正文、加密、解析字段及错误合同不变；本地回归使用合成数据，不请求学校服务。

### 2026-11-01：首页待办迁入 Core

本次使用冻结 `ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/HomeTodo.kt`、`composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/HomeTodoTest.kt`，并复用[日程学校投影决定](../decision-log.md#2026-10-31学校日程投影沿首页规则并保留完整日程状态)及[首页逐来源对照](../../archive/protocol/source-parity-ui-home.md)。固定 `buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 最近的 `src/api/class/{mod,core,data,opt}.rs`、`src/api/spoc/{mod,data,opt}.rs` 提供读协议和 DTO，没有等价首页聚合、阳光提醒或本地日程覆盖，这些本地操作记为不适用。

| 操作 | 引导、重定向与会话 | 方法、参数、Header、编码与加密 | DTO、缓存、并发、错误与产品语义 |
|---|---|---|---|
| 七来源首页投影 | 纯本地，不适用网络引导与 Cookie/Token | 不适用 HTTP 请求或加密常量 | 复用 Core 已解析的 typed 字段和 1b 学校投影；不反解析展示字段，不新增请求或持久新鲜度。原逐组读取和并发上限保持。空、缺失、部分失败与学校错误继续由原快照表达。 |
| 完成、隐藏、重新挂起 | 本机账号日程，不适用学校会话 | 不适用学校写入 | Core 读取覆盖决定首页可见性，重新挂起作业仍检查时间条件，学校原状态保留。 |
| 签到动作关联 | 沿已有在线读取与固定路线写协调器 | 无新增学校请求或重试 | 仅关联同次唯一 allowed action，核对课程、在线目标、校园日期及账号/路线/读取代次；本地投影和持久缓存没有写资格。 |

原学校操作的 URL、字段、签名、Cookie、重定向和错误合同没有修改，继续按各来源记录判断。本轮不运行真实账号验证。

### 首页分业务并发

用户明确要求解除不同业务之间的全局串行。冻结引用仍为 `references.md` 的 ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

已检查旧版 HomeBootstrapCoordinator 及并发、取消测试，以及 LocalConnectionAuth、LocalScheduleApi、LocalSigninApi、LocalSpocApi、LocalJudgeApi、LocalYgdkApi、LocalBykcApi、LocalCgyyApi 的客户端和会话范围。旧首页会同时启动来源，业务模块分别保护 Token 或会话缓存。希冀的 WebVPN 课程共享状态冲突仍以 [10 月 23 日真实修复](coursework.md#希冀获取修复实施前来源对照) 为准，不恢复跨课程并行。

buaa-api 的 `context.rs`、`request.rs`、`store/{cookies,cred}.rs` 采用共享 HTTP 客户端和独立业务凭据。它不实现 Judge、当前首页调度器及相同本地会话 CAS 协调器；不借用其 Cookie 简化、unsafe Sync 或 TLS 设置。端点、参数、模型、加密和错误分类沿 [总来源对照](../README.md) 及对应功能记录。

#### 实施边界

并行范围包括八个读取组：教务（课表、考试、成绩、空教室）、签到、SPOC、希冀、阳光、博雅、研讨室及用户资料。组内一次一个完整批次，组间最多四批在途。其他尚未评估的操作继续独占。Dart 调度器和 Rust Bridge 均执行限制。资料刷新使用独立组，避免排队中的后台资料独占任务挡住其他业务。

每组使用主客户端派生的只读运行时，复用连接池，独立保存 CookieJar、业务 Token、缓存与希冀当前课程。Token 可能依赖对应 Cookie，因此读取实例的 Token 不交给主写客户端复用。派生运行时不写入或清除持久会话，不提交登录凭据，不允许学校非幂等写入；主客户端独占执行认证恢复、登录、注销、路线切换和学校写入。主客户端的正常会话校验只同步修订，账号/路线/实例变化则使旧任务失效。读取请求发送前和收到响应后均检查原主实例的路线代次及会话修订。写方等待当前批次结束，等待中的写方阻止后续读取插队。

| 操作 | CAS/bootstrap 与 service | 重定向/最终地址 | Cookie/会话 | 方法/精确参数 | 头/正文编码 | 加密/签名 | DTO/解析 | 缓存/并发变化 | 错误/退出 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 认证与用户中心身份校验 | 沿 auth-2026-10-21 的 UC 嵌套 service | 原有界跳转、最终地址与身份核对 | 主实例持久化；只读实例可校验已有会话但不竞争文件 CAS | 原状态 GET、凭据 POST 仅主实例 | 原 Accept/XHR/form | 原认证常量 | 原用户资料白名单 | 认证、注销与写入独占 | 原失败分类；迟到结果仍受账号/路线代次检查 |
| 课表、考试、成绩、空教室 | 原 AAS CAS 与本科 currentUser 探测，研究生保持原分流 | 原业务成功/登录页检查 | 同教务读取组 | 原学期/周次/日期/termCode GET 或原研究生请求 | 原 Referer/XHR/JSON | 原签名规则 | 原 typed 学业模型 | 同业务串行，可与签到/作业并行；TTL 不变 | 原部分、失败和保存错误 |
| 签到 | 原 iclass 激活与登录 | 原 Direct/WebVPN 还原与登录参数 | 独立签到读取组，写入归主协调器 | 原当天课程和待签到查询 | 原 form/JSON | 原常量 | 原课堂状态和资格 | 与考试并行，组内串行 | 原未知/失败与写后回读保护 |
| SPOC | 原 CAS Token 激活 | 原最终 URL 和 Token 校验 | 独立 SPOC 读取组 | 原学期、课程、分页及详情参数 | 原 Token 与 param JSON | 原 AES 常量 | 原页完整性与作业 DTO | 逐页仍让位，与其他组并行 | 原页失败保旧、取消和身份检查 |
| 希冀 | 原 HTTPS Judge service | 原登录页识别，重新认证后重选课程 | 唯一 Judge 读取组保护服务端当前课程 | 原 courselist、索引和 assignID GET | 原浏览器头 | 无新增 | 原解析规则与摘要 | WebVPN 同组串行，组间允许并行；TTL 不变 | 原认证仲裁、部分课程失败与取消 |
| 阳光、博雅、研讨室补充 | 各自已有来源记录中的激活流程 | 原业务重认证与最终地址 | 各自组内串行，写入主实例独占 | 原概览/已选/订单参数和分页 | 原 Token/form/JSON | 原功能常量 | 原 typed 数据和写资格边界 | 不新增请求，不扩大缓存期限 | 原稳定错误、缓存身份与写意图限制 |
| 用户资料后台刷新 | 原 UC service 和身份检查 | 原 UC 最终地址、登录页检测 | 单独资料读取组 | 原 status/userinfo GET | 原 Accept/XHR | 无新增 | 原完整在线资料和遮罩持久投影 | 与首页业务并行，仍核对本机账号 | 原资料失败保旧、串号拒绝和保存错误 |

#### 反例及当前验证

实施前，阻塞考试的 Bridge 测试中签到等待超时；App 测试中课表阻塞会阻止其他首页业务开始。修改后这些反例通过。新增覆盖包括四组上限、同组互斥、等待写方不被插队、退出后并行结果不回填、业务 Cookie/Token 与主写客户端隔离、只读身份校验不改写会话文件，以及正常主认证更新修订后继续使用原业务状态。

当前聚焦读取测试 34 项、Bridge 测试 157 项通过。完整 Rust/Shell 检查通过，包含严格 Clippy、Core/Bridge/CLI 回归、CLI 端到端、构建及文档；新增运行时反例验证主会话失效后在途响应被拒绝。原生复测仍在进行。用户说明校园网当前无法直连，后续真实验证只运行 WebVPN，Direct 真实并发暂未验证；确定性检查继续覆盖两条路线。

#### WebVPN 真实对照

使用锁文件固定的依赖和同一 facade，先认证一次，再分别以并发上限 1 和 4 读取五组、六项首页来源。两轮都使用空持久缓存，希冀显式全量刷新，网络正文只存在于内存。两轮结果的完整 DTO 逐字段相等，各组均完整且保存成功。

| 来源 | 串行时完成 / 秒 | 并行时完成 / 秒 |
| --- | ---: | ---: |
| 教务：今日课表、学期及考试 | 8.016 | 7.489 |
| 签到 | 9.732 | 1.535 |
| SPOC | 11.978 | 2.015 |
| 阳光 | 120.333 | 2.605 |
| 希冀 | 116.648 | 103.223 |
| 全部来源 | 120.333 | 103.223 |

这是一轮真实网络对照，两个版本均启用 gzip，主要验证业务重叠及返回结果一致。当前网络下希冀单组强制全量分别为 104.669 秒和 103.222 秒，主导总耗时。其他业务完成时间显著提前，不能将这一组数据外推为固定冷启动或 P95 指标。正常首页仍可使用已有持久缓存，实际 iOS 表现另行记录。

WebVPN 全功能真实只读矩阵 50 PASS、0 FAIL；七包 Flutter 静态分析及 1519 项测试通过（60、95、683、478、20、102、81）。FRB 生成零漂移，敏感扫描通过。证据位于仓库外私有目录 `~/.local/share/ubaa-private/home_parallel_20261029/`。

### 首页加载性能优化

#### 第二轮：传输和首批等待的实施前对照

2026-10-29 再次验证两份冻结引用。读取旧版 `LocalConnectionAuth.kt` 的 HTTP 构造、`LocalJudgeApi.kt` 的课程和详情请求、DTO 与 BackendTest，以及 `HomeBootstrapCoordinator.kt` 和对应并发/取消测试。旧首页同时启动来源，HTTP 层未显式约定跨平台 gzip 策略，不能从单个平台引擎推断其他引擎行为。读取 buaa-api 的 `request.rs`、`Cargo.toml`、`api.rs` 与 SPOC `core.rs`；它没有首页调度器或 Judge 协议，Reqwest 特性中未显式开启 gzip。

当前 BridgeClient 持有全局 Core 锁，ReadScheduler 每次只运行一个批次。两分钟内的详情缓存已生效，当前没有证据支持扩大有效期。首页渐进任务从第一个 `next()` 就使用后台优先级，因此尚无作业内容时也要等待考试及其他普通首页来源。拟保留网络串行及每批让位，在首个可发布结果前给准备步骤与首批保留首页优先级，随后降为后台；用户主动读取与写回读始终优先。

隔离诊断沿原 facade 认证和 Judge 查询，临时传输仅增加 `Accept-Encoding: gzip` 并在内存解压。WebVPN 96 份详情全部返回 gzip，解压前 1,876,773 字节、解压后 14,514,785 字节，最终 96 项完整摘要解析成功。日志只记录分类、数量、耗时与字节数；没有保留响应正文。正式实现应采用锁定 Reqwest 的流式解码，并继续限制解压后累计正文为 8 MiB。

| 操作 | CAS/bootstrap、service | 重定向/最终地址 | Cookie/会话 | 方法/参数 | 头/正文编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 全部 HTTP 传输，包括首页认证及读取 | 沿用各功能已核对的地址，不增加端点 | 继续禁用自动跳转，由原工作流处理 | 原 CookieJar、会话修订、单客户端互斥不变 | 原 GET/POST、查询和请求正文不变 | 在未显式设置时协商 gzip；上游不压缩时接受原文；解压后再交解析器 | 原常量及请求字节不变 | 只交付完整解压正文，保留状态、地址及 Cookie 头 | 复用原连接池，不增加请求或缓存期限 | 保留网络/超时/正文超限错误，损坏 gzip 不交付半段正文 |
| SPOC 首页逐页读取 | 沿用已有 SPOC 来源对照 | 原跳转及 Token 检查 | 原 runtime，恢复仍串行 | 原学期、课程及作业分页请求 | 同上 | SPOC 原 AES 参数不变 | 原准备步骤不发布、首个合法批次发布 | 仅调整首批之前的调度顺序，后续仍分批让位 | 原部分失败、取消、账号和路线保护不变 |
| 希冀首页索引及详情 | 沿用本页及 10 月 23/24 日对照 | 原 HTTPS service、登录页检测和重新选课 | WebVPN 当前课程不交错 | 原课程目录、课程选择、索引及 assignID GET | 同上，已取得真实 gzip 证据 | 无新增 | 字段和待更新索引投影不变 | 不删除详情、不延长 TTL，后续仍逐批串行 | 原分类、失效及完整性不变 |

压缩是明确新增的传输优化，并非宣称冻结参考已有该行为。全量协议门禁与真实 Direct/WebVPN 复验用于检查跨功能影响。

#### 实施前来源对照

本轮使用 `references.md` 固定的 `ubaa_old`提交 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和 buaa-api 提交 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，冻结校验通过。

核对旧版 `api/feature/JudgeApi.kt`、`model/dto/Judge.kt`、`api/local/LocalJudgeApi.kt` 及 `LocalJudgeApiBackendTest.kt`。旧版解析器从 HTML 提取时间、题数、成绩和提交状态；本轮仅复用编译后的正则表达式及 CSS 选择器，保持当前 DOM 解析和全部匹配规则。现有 HTTPS service、原生登录页识别及 WebVPN 串行依据沿用 [10 月 23 日逐操作对照](coursework.md#希冀获取修复实施前来源对照) 和 [10 月 24 日选课复用记录](coursework.md#希冀读取去重实施前双来源核对)。

核对 buaa-api 的 `src/api.rs`、`api/spoc/{core,data}.rs`、`request.rs`、`context.rs`、`store/{cookies,cred}.rs`。该参考没有 Judge 协议，其 SPOC JSON、Token 和加密流程不能用于 Judge HTML。此次不借用其地址、字段、Cookie 简化规则或 TLS 配置。

| 操作 | CAS/bootstrap、service | 重定向与最终地址 | Cookie/会话 | 方法与参数 | 头和正文编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 课程目录解析 | 沿用现有 HTTPS Judge service | 沿用有界跳转和登录页检测 | 所属路线 runtime | GET `courselist.jsp?courseID=0` | 现有浏览器头、无正文 | 无新增 | 保持数字课程 ID、名称、排除 0、去重顺序 | 只复用静态解析器对象，不缓存解析结果 | 保持原分类及 CLI 退出语义 |
| 每课作业索引解析 | 同上 | 同上，选课后读取索引 | 保留服务端当前课程保护 | GET `courselist.jsp?courseID=<id>`、GET `assignment/index.jsp` | 同上 | 无新增 | 保持大小写兼容、内部链接过滤、原始计数、标题及去重 | 原索引 TTL、选课复用和串行规则不变 | 保持原分类 |
| 作业详情与摘要解析 | 同上 | 同上，失效后重选课程 | 同一 runtime，WebVPN 仍串行 | GET `assignment/index.jsp?assignID=<id>` | 同上 | 无新增 | 时间/成绩字符串、题数整数、状态枚举及纯文本内容不变；正则文本逐字保留 | 原详情 120 秒及历史复查策略不变；静态解析器不包含账号或业务内容 | 保留缺失字段默认值、错误和取消边界 |

#### 修改前证据

此前 iOS Debug 热重启中，首页状态出现后约 38.5 秒完成六项主要来源刷新，最后完成希冀。该观测含其他功能排队，不是希冀单接口耗时。

仓库外临时程序通过 facade 和 `.env.local` 的凭据进行隔离认证，依次执行空持久缓存扫描、重建客户端后再次扫描。WebVPN 两轮为 18.837 秒和 1.348 秒，Direct 为 9.641 秒和 1.141 秒；首轮各读取 96 份详情，第二轮均复用 96 份详情，两轮 59 条摘要逐字段一致，无标题不匹配或保存错误。说明现有持久缓存确实生效。

纯本地合成基准重复解析 96 份各含 40 题的 HTML，修改前 Debug 耗时 5208 毫秒。代码在每份详情及每道题中重复编译相同正则。该优化不改变行为，沿用已有解析反例和协议测试；显式忽略的基准只用于比较耗时，不设依赖机器速度的测试断言。


#### 实现与复测

希冀课程目录、作业索引及详情的正则表达式和 CSS 选择器改为进程内 `LazyLock`，首次使用时编译，后续复用。字面量提交标记使用等价的字符串匹配。静态对象只包含解析规则，每份 HTML 仍独立构建 DOM，不保存业务响应。没有扩大缓存期限、跳过作业或增加 WebVPN 并发。

相同合成基准从 5208 毫秒降至 240 毫秒，减少约 95.4%。11 项解析/服务回归（含显式基准）和 32 项 facade 希冀回归通过。复现基准命令为 `cargo test --locked -p ubaa-core --lib 首页批量详情解析基准 -- --ignored --nocapture`。

| 路线与场景 | 修改前 / 秒 | 修改后 / 秒 |
| --- | ---: | ---: |
| Direct 空缓存扫描 | 9.641 | 13.375 |
| Direct 重建客户端后复用缓存 | 1.141 | 1.330 |
| WebVPN 空缓存扫描 | 18.837 | 12.187 |
| WebVPN 重建客户端后复用缓存 | 1.348 | 1.732 |

每个单元格是一轮独立网络样本。两轮扫描的摘要逐字段一致，每次完整返回 59 项，详情数量均为 96。WebVPN 空缓存样本缩短约 35%，Direct 样本反而更慢，因此不能据此声称所有路线的网络总耗时稳定下降。可重复的优化证据是本地解析基准与不变的请求/解析回归。

iPhone 17 Pro（iOS 26.5）使用仓库外诊断入口运行相同生产宿主：SDK 初始化 96 毫秒，平台能力初始化累计 965 毫秒，首次栅格化回调累计 1417 毫秒。首次运行的读取队列在约 36.4 秒排空，紧接着热重启的队列约 16.0 秒排空。队列还包含补充来源与后台成绩/资料读取，计时起点及范围与初步排查不同，不能直接计算前后提速比例；热重启受两分钟详情缓存影响。

临时按功能计时发现考试安排单次约 6.2 秒，其他来源会等待串行队列。独立 WebVPN 复查中，学期读取为 406/164 毫秒，考试读取为 5903/2011 毫秒；会话恢复主要为 53–100 毫秒。该证据不支持为缩短首页加载而跳过认证校验或将新鲜考试结果替换成旧缓存。临时计时代码已移除，运行入口恢复 `lib/main.dart`。

Direct 和 WebVPN 完整真实只读矩阵分别 50 PASS、0 FAIL、0 BLOCKED。隔离验证目录在读取完成后清理，未保存原始响应或个人业务正文。原始耗时日志与模拟器截图留在仓库外。


#### 验收范围与现存问题

性能改动在独立工作树中验证，未带入主目录六个未提交的界面文件。七包静态分析和 1512 项 Flutter 测试通过（Domain 60、Platform 95、App 676、UI 478、Bindings 20、Host 102、官方 App 81）。`just check` 完整 Rust/Shell、严格 Clippy、Bridge/CLI 测试、CLI 端到端、冻结引用、布局、敏感扫描和差异格式检查通过。

主目录全量检查受既有 UI 修改影响：`shell.dart` 为 1002 行，超过结构限制，UI 组件测试有 17 项失败。隔离工作树中这两类问题未复现，性能提交不包含这些界面修改。

额外的 `just flutter-codegen-check` 未通过：锁定 FRB 2.13.0 生成器会删除原有 `BridgeClient.dispose()` 上的 `@override`，其余生成内容没有差异。本轮没有修改 Bridge API；生成变更已撤销，不能将该检查记为通过。

### 首页日程与临近待办来源核对

2026-10-25，实施前 `just refs` 通过：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本轮复用现有学期、周次与周课表公开接口，不新增或猜测日期查询协议。

#### 双源逐操作比较

旧版核对 `ScheduleApi.kt`、`LocalScheduleApi.kt`、`model/dto/Schedule.kt`、`ScheduleRepository.kt` 及 `ScheduleRepositoryTest.kt`、`ScheduleViewModelTest.kt`；buaa-api 核对 `src/api/aas/{core,opt,data}.rs`、`src/request.rs` 与 `src/store/{cookies,cred}.rs`。认证恢复、跳转终点、WebVPN 映射、Cookie／凭据及加密细节沿[既有课表矩阵](academic.md#课表默认下载整学期)、[离线来源](offline-cache.md#离线恢复逐操作来源对照)和[认证修复](auth-session.md#sso-传输协议与-uc-激活链对照)，不修改其常量或规则。

下表相对路径均以 `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/` 为基准。

| 操作 | 认证、跳转及会话 | 请求、参数、头与编码 | DTO、缓存并发、错误 |
|---|---|---|---|
| 学期 | 既有本科门户校验；CAS service 为 `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp`；保持现有精确终点验证和账号／实际路线会话 | GET `student/schoolCalendars.do`，无参数；旧版 Accept `application/json, text/javascript, */*; q=0.01`、X-Requested-With `XMLHttpRequest`、映射后的 `homeapp/index.html` Referer | 仅唯一 selected 学期；共享现有读取合并，未知学期不取第一项 |
| 教学周 | 同上述门户会话，无新 Cookie、加密或签名 | GET `getTermWeeks.do`，query `termCode`，同 AJAX 头 | 以 requestTerm/responseTerm、number、startDate/endDate 定位目标日期；周次歧义、日期非法或缺失不推断周号 |
| 周课表 | 同上述门户会话，现有受调度的只读操作 | POST `student/getMyScheduleDetail.do`，form-urlencoded：`termCode`、`type=week`、`week`；同 AJAX 头，不加入 campusCode | arrangedList 的 dayOfWeek、beginTime/endTime、课程名称与地点；选出目标星期后投影为单日课程，保留完整度、实际路线及错误 |
| 单日展示 | 只对公开 DTO 做本地日期／时间判断 | 不调用新 URL，不改今日接口 rq；旧版在线今日入口固定读取今日，不能将其结果标成明日 | 沿旧版 Repository 的日期所属周与 dayOfWeek 过滤方式；新增用户要求的明日切换。按账号／路线／读代次／目标日期隔离，迟到响应不覆盖新日期；未知结束时间不判已结束 |

buaa-api 使用相同周课表路径，但通过 query 传递 POST 参数且含 campusCode；其学期查询 type=term，与旧版表单路径不同，不采用。buaa-api 没有同构学期／周次索引和首页明日切换；不借用 currentUser 的 week 值推断明日。研究生沿现有 Core 适配输出，不新增研究生协议。认证、网络重试和稳定错误码保持，新增的日期不可确定错误只用于首页展示，不改变 CLI 退出语义。

单日展示默认先查当前账号、路线、精确查询且完整的本地课表；缺失才走现有受调度读取。该本地优先策略用于首页的新增日期预览，复用旧版 offlineOnly 能力与完整学期投影；不改变课表页的在线优先策略。强制刷新读取线上，失败保留同日期已显示内容并提供重试。日期请求合并限定当前读取代次，学期／周次读取复用现有协调器，退出或切路线后的迟到结果拒绝发布。

#### 本轮边界

首页入口仅保留真实最近使用记录，无记录时不伪造常用入口。待办沿原投影资格与排序，只增强相对时间和临近 48 小时的视觉提示，不能授予写资格。星期按校园日期计算；教学周来自真实覆盖日期；课程状态由完整合法时间区间决定。今日有课程且全部结束后显示明日，今日无课或时间未确定时保留今日。

#### 实现与验证

- 首页移除校园生活和默认常用入口，仅显示已有最近使用记录；没有记录时不展示入口区。
- 待办保持原资格与时间排序，距截止或开始时间大于 0 且不超过 48 小时使用暖色时间；今天／明天保留精确时刻，不叠加重复倒计时。颜色在浅／深卡片上的对比度分别为 6.11:1／8.75:1。
- 课表显示校园日期、星期、确有日期覆盖的教学周和未开始／进行中／已结束／时间待定。今日有课程、结果完整且所有结束时间明确并已到达后显示明日；无课或未知时间继续显示今日。
- 单日结果带确切日期和教学周。跨午夜复用同日期课表并重新命名为今日；日期不符、周次歧义、无日期覆盖、周次索引不完整或排课缺少星期均不当作无课。显示路线随当前日程来源更新。
- 刷新保留同日期内容；失败可重试，账号／路线／读取代次失效后的结果丢弃。只有当前可见首页按分钟更新状态，不增加每分钟学校请求。

实施前反例分别复现了临近作业仍使用绝对日期、课程缺少结束状态、周次索引完整度被丢弃、缺失星期被误判为空日；均已修复。宽窄窗口用例改为在确实需要滚动的视口中验证主滚动；最近访问排序和下拉刷新覆盖保持。成绩提醒夹具使用未知结束时间，使成绩用例不随本机运行时刻自动切换日程，其原课程保留、提醒顺序、忽略和查看行为断言全部保留。日程切换由独立日历用例覆盖。

最终检查：`just check`、`just flutter-check`、`just flutter-codegen-check` 通过。七包分别为 Domain 60、Platform 87、App 674、UI 435、Bindings 20、Host 101、官方应用 78 项，共 1455 项。新增覆盖跨周／年界、午夜、时间边界、48 小时边界、读取合并、缓存账号／路线／查询／完整度拒绝、强制刷新、迟到结果、错误日期及显示路线。

`just verify-live mode=direct feature=schedule` 与 WebVPN 对应命令均退出 0，验证既有课表只读协议；未提交学校写入。明日日期选择与投影由上述确定性用例验证，未将既有接口成功扩大为所有日期数据均完整。

macOS 与 iPhone 17 Pro 模拟器各 16 个原生合成场景通过，分别导出 56 张 PNG，已目视核对明暗日程、状态、暖色时间与最近使用。媒体和真实只读日志均在仓库外私有目录：`UBAA-private-evidence/home-calendar-20261025-*`。模拟器已恢复关闭。用户解锁后已完成实际用户窗口重启与检查。

最终 macOS Debug 构建与产物结构、签名及权限检查通过。用户解锁后，使用完整应用路径重启实现提交 `85b6ebe7` 对应的新构建；实际首页显示“明日课表”和“10月26日 · 星期一 · 第8周”，课程显示“未开始”，临近截止时间显示暖色“明天 23:59 截止”。页面底部已核对为最近使用功能网格，未显示校园生活栏。检查后应用停留在首页顶部，本次窗口检查未执行真实业务写操作。

### 首页考试待办

#### 实施前来源核对

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`：核对 `shared/.../api/local/LocalScheduleApi.kt`、`api/feature/ScheduleApi.kt`、DTO `model/dto/Exam.kt`、`LocalScheduleApiBackendTest.kt` 和 `composeApp/.../screens/exam/ExamViewModel.kt`、`ExamScreen.kt`。考试安排所属列表区分 arranged/notArranged，旧时间轴按结束时刻划分；当前 `ExamPresentation.calendarDate/isFinishedAt` 已复刻日期和结束规则，首页复用该判断。首页新增考试待办是用户明确要求的展示扩展。

冻结 `buaa-api` 的 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`：核对 `api/app/opt.rs/core.rs/data.rs`。其考试来自 `https://app.buaa.edu.cn/exam/wap/default/index` 的 HTML 内嵌 JSON，采用 App CAS 入口、专用 UA、exame_start_time/exame_end_time 字段；与旧版本科教务 JSON 协议不同，不借用字段、URL、会话或错误语义。学期和 AAS 激活继续沿主来源表。

| 操作 | CAS/bootstrap、重定向与最终地址 | 会话与请求 | 头、编码和加密 | DTO/缓存/并发/错误 |
| --- | --- | --- | --- | --- |
| 当前学期 | 既有 SSO service 指向 `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp`；沿现有已知主机跳转、UC/currentUser 业务校验 | 当前账号、Direct/WebVPN 隔离 Cookie；复用 schoolCalendars.do GET 和现有学期选择，不推断学期编码 | 沿 LocalScheduleApi 与 Core 请求器的 Accept/XHR/Referer，无新签名或加密 | 保留 selected/code 与既有缓存；缺少当前学期保持原空结果/错误语义 |
| 考试安排 | 同上，不新增登录入口 | GET `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/exams.do?termCode=原学期编码`，无正文 | Accept=`*/*`、XHR=`XMLHttpRequest`、Referer=`https://byxt.buaa.edu.cn/jwapp/sys/homeapp/home/index.html`，按路线包装；无加密 | 原课程名/号、日期、开始/结束时间、地点、座位、周次、状态、类型、taskId；原 code=0、datas 数组解析和本科不支持/网络错误语义。复用账号/路线/学期缓存与读取调度，不新增并发学校协议；不改 CLI 退出码 |

实现范围：考试加入首页默认来源与离线恢复。仅 arranged 且有效日期、尚未结束的考试生成待办；显示课程、时间、地点和座位，按开始时间排序，时间缺失时明确待定。点击进入考试安排。历史学期查询不覆盖首页默认来源；失败不清除已显示的缓存。没有新增公开合同或学校写操作。

#### 验证

反例先行：Domain 期望三项未结束考试但实际得到空列表；首页加载测试期望考试来源但实际默认列表缺少考试，两者均失败。实现后领域日期/排序、默认读取、缓存恢复、来源替换与时钟推进、卡片跳转通过。补充当前学期首页与历史学期查询互不覆盖用例通过。

七包分包全量测试通过：Domain 54、Platform 87、App 663、UI 386、Bindings 20、Host 101、Flutter App 73；随后新增学期隔离用例及相关认证回归 11 项通过。原先考试首次打开才加载的宿主场景改为自动首页加载和卡片跳转；原惰性读取合同继续由成绩、博雅、教室、图书馆、研讨室和评教覆盖，认证与刷新期望同步加入考试。

macOS 明暗主题各一项完整首页原生流程通过，覆盖七来源排序、考试点击跳转、其他待办与合成签到准备后取消。正式 Debug 重建、产物结构及签名权限通过；真实账号首页已观察到考试待办，点击进入考试安排后返回首页。截图不纳入仓库，记录不含课程名称或考场等个人信息。

Direct/WebVPN `verify-live feature=exam` 均通过 prepare/login/status、学期、周次、课表和考试安排。没有学校写入。`just refs`、敏感扫描、布局及完整 `just check` 通过。检查先发现既有 iHome 测试 transport 函数超出 Clippy 行数限制；仅将空响应构造提取为辅助函数后完整复跑通过，独立提交该机械测试整理。

### 2026-09-17 首页加载调度

当前冻结来源、逐操作九列与 RED 见[首页性能专项](#首页加载性能修复来源对照与验证)。
仅调整预载范围与顺序，保留请求协议、Bridge 会话锁、待办来源和成绩检查。

### 首页加载性能修复：来源对照与验证

#### 范围与实施前事实

本轮只处理用户反馈的首页加载慢；当时暂停的[完整 UI/UX 计划](../../archive/history/goal-2026-09-17-before-offline-home.md)不恢复，该历史范围不提供当前授权。
起始分支 `ubaa2`，保留既有 UI 与引用管理未提交修改。
`just refs` 通过：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，
`buaa-api` 为 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

确认的代码原因：

- `AppController._refreshHome` 默认遍历十二个 `FeatureId`。考试、成绩默认页、博雅可选课程、空教室、图书馆楼馆、研讨室站点和评教并非首页展示数据，却在启动和下拉刷新时读取。
- Bridge `api/read/methods.rs::execute_read` 持有同一个 `inner` 互斥锁直到网络返回。Dart 的 `Future.wait` 不能使这些请求真正并行；枚举顺序将签到排在第九项，无关慢请求和失败超时会阻塞后续首页来源。
- 首页另有博雅已选、研讨室订单、当前学期/周次及成绩变化检查；默认成绩读取还会重复查询学期和成绩。

#### 冻结来源核对（生产代码修改前）

已读旧版 `composeApp/.../ui/navigation/HomeBootstrapCoordinator.kt`、同名测试及
`MainAppScreen.kt::startHomeBootstrap`：首页仅调度今日课表、签到、SPOC、希冀、博雅已选、
研讨室订单、阳光提醒、成绩变化检查，不遍历所有功能；测试确认各来源独立启动和失败隔离。

`buaa-api/src/context.rs`、`src/api/{class,spoc,boya}/`、请求、存储与错误模块没有等价首页聚合器；
其共享上下文不构成删除 UBAA Core 互斥保护的依据。
与旧矩阵固定提交只读比较：旧版相关本地 API 仅课表和签到有变化，SPOC、希冀、博雅、场馆、阳光未变；
示例相关差异在课堂 API 与上下文网络刷新。已读课表/签到差异及当前函数：研究生课表回退不在本轮范围；
签到严格 sessionId 与示例 loginName 的分歧继续以[签到专项](signin.md#2026-09-17-课堂签到修复对照)为准。

以下逐操作列明九个协议维度。本次仅调整应用层触发范围和顺序；原协议依据为
[基础矩阵](../README.md)和[首页六来源投影](../../archive/protocol/source-parity-ui-home.md)，不借本轮调度变更补猜协议。

| 操作 | CAS/bootstrap 与 service | 重定向/最终 URL | Cookie/会话 | HTTP 与参数 | 请求头/编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误语义 |
|---|---|---|---|---|---|---|---|---|---|
| 今日课表 | 原课表矩阵；示例无等价本科门户 | 原 Core 校验 | 原路线会话 | 原 today、rq/lxdm | 原教务头 | 无新增 | 原 TodayCourse | 仍为第一项 | 原分类/stale |
| 今日签到 | 签到专项；不借示例分歧 | 原跳转限制 | 原业务 sessionId | 原 today、id/dateStr | 原 sessionId 头 | 无新增 | 原 DTO/action | 第九项提前至第二项 | 原鉴权与资格 |
| SPOC 作业 | 原 SPOC 认证矩阵 | 原 Core 校验 | 原 SPOC 会话 | 原 assignments | 原编码 | 原实现 | 原作业投影 | 保留默认读取 | 原分类/stale |
| 希冀作业 | 原 Judge 矩阵；示例不等价 | 原 Core 校验 | 原 Judge 会话 | 原 assignments | 原编码 | 原实现 | 原作业投影 | 保留批量与缓存 | 原分类/stale |
| 阳光概览 | 原阳光矩阵；示例无对应 | 原 Core 校验 | 原阳光会话 | 原 overview，不读记录 | 原编码 | 原实现 | 原 YgdkOverview | 保留默认读取与固定路线回读隔离 | 原分类/stale |
| 博雅已选 | 原博雅矩阵；示例不完整等价 | 原 Core 校验 | 原博雅会话 | 原 chosen | 原编码 | 原实现 | 原已选 DTO | 保留补充缓存；取消可选课程预载 | 原局部错误 |
| 研讨室订单 | 原场馆矩阵；示例无对应 | 原 Core 校验 | 原场馆会话 | orders，page=0/size=20 | 原编码 | 原签名 | 原订单 DTO | 保留补充缓存；取消站点预载 | 原局部错误 |
| 当前学期/周次 | 原课表矩阵 | 原 Core 校验 | 原教务会话 | terms→weeks(term) | 原教务头 | 无新增 | 唯一 selected/current | 保留同代合并 | 原缺失/失败 |
| 成绩变化检查 | 原成绩矩阵 | 原 Core 校验 | 原教务会话 | 原当前学期成绩 | 原教务头 | 无新增 | 原成绩/变化投影 | 保留专用检查，取消默认成绩页重复预载 | 原检查/通知 |
| 考试、空教室、图书馆楼馆、评教及上述默认页 | 各自原矩阵 | 原 Core 校验 | 原路线隔离 | 原默认查询 | 原编码 | 原实现 | 原 DTO | 首次打开经已有 idle 加载，保留显式重试 | 未访问为 idle，不伪造空结果 |

保留 Bridge/Core 锁、会话修订、账号/路线生命周期边界；不复制客户端或 Cookie，不并发改写会话。

#### RED 证据

锁定 SDK 下在 `packages/ubaa_app` 执行 `flutter test test/home_loading_test.dart --reporter expanded`，
实际退出 1，三项全部预期失败：启动与刷新读取十二项而非五项；每项一秒的串行合成网络到第二秒时，
签到仍为 loading。虚拟时间仅复现排队，不代表校园网络测速。

#### 验收记录

首轮完整 Flutter 回归发现首次从成绩提醒进入时，既有导航器的 idle 帧回调晚于指定学期查询，
会多发默认读取并覆盖查询；既有 `home_grade_notice_test.dart` 第 95 行出现 null query，已保留 RED。
导航器同时检查当前本地帧仍为 idle 且无指定查询才自动加载，避免旧宿主快照覆盖直达操作。
另两项失败是旧测试要求首页刷新隐藏的图书馆楼馆和研讨室站点，按本轮按需加载合同更新断言，
保留首页研讨室订单 page=0/size=20 与隐藏页不扩展子查询的检查。

最终当前工作区验证：

- 新增三项首页加载测试：初始与刷新只读取五来源、未访问功能 idle、显式单项仍可读取、串行队列中签到第二项完成。RED 后 GREEN。
- 新增七项宿主实际点击回归：考试、成绩、博雅、空教室、图书馆、研讨室、评教首次打开自动读取，返回重进不重读。既有首页六来源与成绩提醒测试继续通过。
- `just flutter-check` 退出 0：Domain 54、Platform 59、App 273、UI 249、Bindings 15、Host 30、Flutter 宿主 54，共 734 项，锁定 SDK 分析与格式检查通过。
- `just check` 退出 0，包含 CLI 端到端 16 项；最终 `just refs`、`just layout-check`、`just check-sensitive`、`git diff --check` 通过。
- `just verify-live mode=direct` 与 `mode=webvpn` 均退出 0，各 40 PASS、0 FAIL；日志仅安全状态、路线、数量和耗时。认证通过既有 `.env.local`→stdin 路径，不复制凭据或修改默认运行会话。
- macOS 原生生产入口 `integration_test/ui_home/live_readonly_test.dart`，新建 Sandbox 私有隔离目录（700，配置 600），显式只读开关和预期路线。Direct/WebVPN 各 1 PASS；五个默认来源、三个补充来源与实际路线都成功/明确空，七个未访问领域保持 idle，业务写入 0，不截取真实个人页面。
- 原生只读验证结束后执行 `just flutter-build platform=macos mode=debug`，正常 `lib/main.dart` 入口构建成功，产物为 `apps/ubaa_flutter/build/macos/Build/Products/Debug/ubaa_flutter.app`；不把集成测试入口留作交付应用。

##### 原生计时与限制

下表为一次启动样本，从生产 bootstrap 开始用 Stopwatch 计时，`observed_ms` 为测试首次观察到
结果的时间（含轮询间隔），不是单接口精确耗时；不包含构建时间，也不是冷启动统计基准。
Direct 在最后导航时序保护前取得（该保护不改变首页启动读取），WebVPN 在最终生产代码取得。

| 观察点 | Direct / ms | WebVPN / ms |
|---|---:|---:|
| 首页容器显示 | 1267 | 1168 |
| 今日课表完成 | 1272 | 1747 |
| 今日签到完成 | 1891 | 1752 |
| SPOC 完成 | 1892 | 2308 |
| 希冀完成 | 15677 | 28308 |
| 阳光概览完成 | 16749 | 29375 |

可确定减少的是默认加载任务由 12 降至 5，且签到从第 9 项提前至第 2 项。
没有真实旧版本同条件对照，因此不宣称真实整体提速百分比。希冀聚合读取仍为明显长尾；
本次两路线返回数量不同，不能将两组耗时直接当作网络路线性能对比。Bridge 锁与上游协议保持原样，
首页容器/已有来源先行可用不代表全部来源已完成。

本轮提交包含导航器已有的首次访问加载片段及新增直达保护，因为缩减预载依赖该行为；
其余既有 UI、冻结引用管理和文档改动保留在工作区，不混入本轮提交。
