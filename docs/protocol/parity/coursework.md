# SPOC 与希冀作业

本文件收录 SPOC 与希冀（Judge）作业列表、详情、批量缓存和读取去重的来源对照。

## 当前规则

### 作业列表字段与详情复用

2026-11-05 核对冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `api/feature/{JudgeApi,SpocApi}.kt`、`api/local/{LocalJudgeApi,LocalSpocApi,LocalSpocSupport,LocalConnectionAuth}.kt`、`model/dto/{Judge,Spoc}.kt` 和 `LocalJudgeApiBackendTest`、`LocalSpocApiBackendTest`。固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 对照 `src/api.rs`、`api/spoc/{core,opt,data}.rs`、`api/sso/auth.rs`、`request.rs`、`store/{cred,cookies}.rs`。当前实现对照 Core `features/judge/{parser,service,scan}.rs`、`facade/judge_refresh/`、`features/spoc/{list,parser,detail,scan}.rs` 与 `facade/home_cache/spoc_scan/`。

| 操作 | CAS/service 与引导 | 重定向与最终 URL | Cookie/Session/Token | 方法与精确参数 | 请求头与正文编码 | 加密/签名 | DTO 与解析 | 缓存/并发/重试 | 错误与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| Judge 课程与作业索引 | 沿用[希冀来源裁决](#希冀获取修复实施前来源对照)的 HTTPS service；固定 buaa-api 无 Judge，各协议列不适用 | GET `courselist.jsp?courseID=0` 取得课程，选课后 GET `assignment/index.jsp`；保持原路线内跳转 | 旧版按用户、路线缓存；Core 按账号、路线与代次隔离，Direct worker 独立 Cookie | GET，无正文；选课参数 `courseID`；无服务端分页 | 沿用旧版浏览器 Accept、Accept-Language、User-Agent | 无 | 课程链接支持 `courseID` 与名称；作业链接支持数字 `assignID` 与锚点标题，排除 `problemContent`、`judgeDetails`，按作业 ID 去重 | 旧版列表 TTL 五分钟且不缓存空列表；Core 主动学校刷新强制取得当前索引，保留历史课程索引复查规则 | 原索引错误、认证重激活、课程失败保旧保持；列表消失的作业从该课程摘要移除 |
| Judge 单项详情与批量补全 | 沿用同一 Judge 激活；固定 buaa-api 不适用 | 选课后 GET `assignment/index.jsp?assignID=<列表作业编号>` | 同一账号、路线、课程与作业范围；不扩大 Cookie 作用域 | GET，精确参数 `assignID`，无正文 | 同上，HTML 全文解析；详情解压预算 16 MiB | 无 | 开始/截止时间、最高分/本人分数、题目数量、提交数量、提交状态、题目表与纯文本来自详情；列表 DTO 中这些摘要字段由详情投影 | 旧版详情 TTL 两分钟；批量接口保留跨课程隔离 worker；渐进读取复用父会话，同课程最多四份详情并发，选课与认证恢复不与在途详情交错；Core 保留现有认证重激活及取消/代次检查 | 完整范围包含复用详情仍可为 Complete；详情复用保留原详情来源与核验时间，列表读取成功只更新索引时间 |
| SPOC 当前学期全局列表 | 旧版 `/spocnewht/cas` 获取 token，再 POST `/sys/casLogin` 初始化角色；示例省略旧版角色初始化，继续采用旧版流程 | 原路线内有界 CAS 跳转，当前学期 POST `/inco/ht/queryOne`，可选课程 GET `/jxkj/queryKclb`，权威列表 POST `/inco/ht/queryListByPage` | 旧版及 Core 使用路线内 token、RoleCode 与 Cookie；示例共享 `Spoc` credential 不作为放宽依据 | 课程参数 `kcmc=""`、`xnxq`；列表明文 `pageSize=15,pageNum,sqlid=1713252980496efac7d5d9985e81693116d3e8a52ebf2b,xnxq,kcid="",yzwz=""`；示例按课程 GET `/kczy/queryXsZyList?flag=1&sflx=2&sskcid=...` 不等价 | 旧版及 Core JSON `{param}`、XHR、`Token: Inco-…`、`RoleCode`；示例仅设置 Token | 旧版 AES-128-CBC 零填充、Base64；密钥 `inco12345678ocni`、IV `ocni12345678inco`；示例对齐明文填充差异仍按既有裁决处理 | 全局列表必需字符串 `zyid/zymc`，可选字符串 `sskcid/xnxq/tjzt/mf/kcmc/zykssj/zyjzsj`；教师来自可选课程元数据；示例 `id/sfzysjn` 不加入全局列表解析 | 分页直到既有终止条件；课程失败仍读全局列表；学校首页和日程刷新只推进此列表，不遍历全部 SPOC 详情 | 保持缺失分页回显、课程元数据和其他读取完整度规则；解析错误不重放，真实全局空页按既有规则发布 |
| SPOC 显式单项详情及提交补充 | 沿用上述认证，无新引导 | 必需 GET `/kczy/queryKczyInfoByid?id=<作业编号>`，可选 GET `/kczy/queryXsSubmitKczyInfo?kczyid=<作业编号>`；示例仅实现同一正文端点，提交查询只有注释 | 同一路线 token、RoleCode 与 Cookie | GET，无正文，先由完整列表确认目标 | 旧版及 Core XHR、Token、RoleCode；示例仅 Token | GET 不加密 | 必需详情 `id/zymc`，可选 `zynr/zyfs/zykssj/zyjzsj/sskcid`；提交补充 `tjzt/tjsj`；Core 校验详情 ID 等于目标 | 旧版每次显式详情先读列表，再读正文和提交状态；当前分段入口复用已扫描列表，学校列表刷新不调用此入口 | 正文失败保旧，补充失败保留 Partial；缺目标失败；沿用现有状态合并和主会话仲裁 |

Judge 可用于列表变化比较的有据字段为 `(course_id, assignment_id, course_name, title)`。冻结解析器 `LocalJudgeHtmlParsers.parseAssignments` 和 Core `parse_assignment_list` 均只从链接取得这些字段；两者未证明列表存在截止时间、提交状态、分数或更新时间。因此不能将详情投影出的摘要字段当作本轮列表观察，也不能推断列表不变即可证明正文、截止或提交结果不变。

SPOC 的全局列表可观察身份、标题、课程、开始/截止时间、提交状态和 `mf`，但两冻结来源均未提供正文修订时间或正文版本。`mf` 在冻结夹具中为“满分:…”文本，不能推断为本人得分。SPOC 学校刷新已经只读取分页列表，本次“列表后逐项详情”的性能问题集中在 Judge；显式打开 SPOC 详情继续读取正文及提交状态。

Judge 增量比较使用上述字段的直接相等关系，避免另存重复摘要或计算无用途的散列。详情复用必须同时满足现有缓存范围、完整度、成功状态与时效要求。新作业或列表字段变化时读取该项详情；列表未变时按下列详情时效复用。

| 详情范围 | 复查期限 | 本机依据 |
|---|---|---|
| 普通作业，截止时间可解析且不在截止前后一天内 | 六小时 | 列表持续发现新项及改名；以后台刷新预算限制重复下载大正文，同时将列表不可见的正文、截止及评分变化延迟限制在六小时内 |
| 截止前后 24 小时内，包含两个边界；或截止时间缺失、无法解析 | 15 分钟 | 临近截止时提交状态更影响待办；缺少可用截止时间时采用同一较短复查期限 |
| 满足原有历史判据的已提交作业 | 七天 | 沿用原历史策略：开始早于六个月前且截止早于 14 天前；避免历史大正文反复下载 |
| 主动刷新的非历史详情、显式打开的目标详情、`full_refresh` | 立即读取 | 用户明确要求核对当前详情时取得新正文和提交状态 |

六小时、15 分钟和截止前后一天均为本机刷新取舍，不是上游缓存协议或正文不变证明。它们针对已观察到单项详情超过 10 MiB 的重复下载成本，并保留对列表不可见变化的定期复查。复用详情不得刷新其 `fetched_at/last_verified_at`，最终摘要时间由所包含详情的实际来源时间保守汇总；成功取得当前完整列表并覆盖全部项时，复用本身不降低完整度。

本次真实只读验收仅获 Direct 授权，凭据只读自 `.env.local`，本机材料保存在被忽略且权限为 700 的 `.ubaa_local/judge_incremental/`。WebVPN 真实路线验收待该路线授权后重跑，固定 Fixture/Mock 与 Direct 结果不替代该路线证据。

### 希冀作业详情正文预算

2026-11-05 核对冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `JudgeApi.kt`、`model/dto/Judge.kt`、`LocalJudgeApi.kt`、`LocalJudgeApiBackendTest.kt`，以及 `LocalConnectionAuth.kt` 与平台 `ApiClient`。旧版通过 `bodyAsText()` 完整读取详情，上述客户端没有设置应用层响应字节上限。固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/api.rs` 无 Judge 模块；另核对最邻近 `api/spoc/{core,data}.rs`、`api/sso/auth.rs`、`request.rs` 和 `store/{cred,cookies}.rs`，其 token/AES/JSON 协议不适用于 Judge。

| 操作 | CAS/service 与引导 | 重定向与最终 URL | Cookie/Session/Token | 方法与精确参数 | 请求头与正文编码 | 加密/签名 | DTO 与解析 | 缓存/并发/重试 | 错误与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| 课程目录与作业索引 | 沿用[希冀来源裁决](#希冀获取修复实施前来源对照)的 HTTPS service | 原路线内重定向，目录 `courselist.jsp?courseID=0`，选课后 `assignment/index.jsp` | 原账号、路线与 worker 隔离 | GET；先选 `courseID`，无服务端分页；`includeExpired` 仅本地筛选 | 旧版浏览器头与空正文保持 | 无新增 | 原课程与数字作业锚点解析 | 原索引缓存、选课及分段重准备保持；批量 Direct 最多四个课程 worker，WebVPN 串行 | 仍使用默认 8 MiB 解压正文预算；固定 buaa-api 各协议列不适用 |
| 作业详情 | 同上，不新增认证操作 | 选课后 `assignment/index.jsp?assignID=<数字编号>`；WebVPN 按既有规则还原端点 | 同上，不复制或扩大 Cookie 作用域 | GET，参数保持 | 浏览器头、HTML 编码和空请求正文保持 | 无新增 | 旧版全文解析时间、分数、题目和纯文本；Core DTO 与解析保持 | 原缓存、分段继续、认证重激活及 Partial 保旧保持 | 本机按精确 Judge 主机、详情路径和数字 `assignID` 将解压正文预算设为 16 MiB；超限仍失败。固定 buaa-api 各协议列不适用 |

本会话 Direct 只读观察中，登录与主会话核验成功，一项作业详情返回 HTTP 200、解压正文 10,875,793 字节，其中大量内容为 `pre` 代码文本。生产传输在接收阶段触发原 8 MiB 上限，随后该课程产生 `CourseFailure`，最终缓存为 Partial 并保留旧核验时间。逐批诊断完整读取 6 门课程、96 项作业，未发现该课程权限或解析错误。16 MiB 是覆盖此正常 HTML 的本机预算，不作为上游最大值；其他请求继续使用 8 MiB。原始响应仅保存在私有任务目录。WebVPN 本会话未授权，真实路线证据待获得该路线授权后补验。

#### App 与 core-live 的刷新路径

2026-11-05 对照同一冻结旧版的 `LocalJudgeApi.kt` 与 `LocalConnectionAuth.kt`：旧版按课程最多四路并发，课程内逐项读取，列表与详情的 TTL 分别为五分钟、两分钟。TTL 仅决定缓存复用，不会中断已取得列表的遍历。单请求期限为 30 秒，连接期限为 10 秒。旧版没有整体刷新期限、服务端分页或读取完整度 Partial；DTO 中的 `PARTIAL` 表示作业提交状态。固定 buaa-api 没有 Judge 模块，最邻近 SPOC 的 token/AES/JSON 各协议列仍不适用。

课程目录、索引与详情的九列协议规则沿用上表。App 的学校日程刷新调用首页来源刷新，经 `BridgeBackend`、FRB 的 `begin_judge_refresh`／`next_judge_refresh` 和 Core facade 逐批读取；相同查询可加入首页在途计划。Judge 组内串行，跨业务最多八组并行，首批后降低调度优先级仍继续读取。core-live 的一次性批量接口在 Direct 最多并发四门课程。两者共用 16 MiB 详情预算及 30 秒单请求期限，没有额外的 App 总刷新期限或分页上限。App 持久详情按本页“作业列表字段与详情复用”的六小时、15 分钟和七天规则复查，满足修订与复查条件的历史课程索引一天；强制完整刷新禁用这些复用。

Core 在扫描期间保存索引与单项详情，完整范围的摘要及日程观察元数据在最终批次发布。非致命读取错误形成 `CourseFailure`，最终失败课程数大于零时为 Partial，并保留已有摘要的来源与核验时间。扫描期间看到旧 Partial 不能确定本轮读取失败。确定性 App 测试覆盖学校刷新新建计划、加入首页在途计划、详情推进与完整收尾，Rust 既有扫描测试覆盖逐批保存、来源时间和 Partial 保旧。

同日 iOS Simulator 已安装库的详情预算分支为 16,777,216 字节。运行中 App 的日程结果显示希冀保存/核验时间为 21:49:20，完成尝试为 21:50:09，完整度 Complete、尝试成功；打开中的数据面板仍持有保存/核验 19:15:45、失败尝试 21:26:53 的旧 Partial 来源对象。生产传输的独立 Direct 只读 worker 使用默认渐进计划读取 6 门课程、96 项详情，失败课程为零、最终 Complete。数据面板持有旧对象属于展示刷新问题，学校请求与缓存结果已完成；已打开的面板需要重新打开才能取得当前来源状态。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### SPOC 认证

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**GET `https://spoc.buaa.edu.cn/spocnewht/cas`，再 POST `/spocnewht/sys/casLogin`。**示例：**只有 GET `/spocnewht/cas`，没有 `sys/casLogin`/角色设置，认证不完整且不等价。**决策：**旧版本地流程是唯一权威。 | **旧版：**最多手动跟随 8 次路线转换跳转，只从 `/spocnew/cas?token=...&refreshToken=...` 提取令牌；`sys/casLogin` 的原始 SSO 跳转表示认证过期。**示例：**客户端跟随跳转并读取第一个 `token` 查询项。**决策：**保留旧版上限，并在状态解析前识别不跟随传输返回的 SSO Location。 | **旧版：**路线 Cookie jar；按缓存客户端用户名保存内存令牌和角色码。**示例：**共享 Cookie 存储和 3 小时凭据令牌。**决策：**令牌、角色和登录锁只存在路线业务状态，并随会话清理。 | **旧版：**GET CAS；向 `sys/casLogin` POST JSON `{token}`。**示例：**没有等价角色 POST。 | **旧版：**JSON、`X-Requested-With: XMLHttpRequest`、`Token: Inco-<token>`，后续请求增加 `RoleCode`。**示例：**只有 `Token: Inco-<token>`。**决策：**保持旧版角色建立步骤。 | **旧版/示例：**CAS 登录本身无加密。 | **旧版：**URL 中的令牌/可选 refreshToken；`code/content` 角色字段 `jsdm`、`rolecode`、`jsdmList`；content 为空或找不到角色即认证失败。**示例：**只有令牌。**决策：**角色是必需项，不从示例推断字段。 | **旧版：**登录互斥锁、令牌/角色复用，业务认证失败后强制刷新一次。**示例：**凭据过期刷新。**决策：**每路线串行登录且恰好刷新/重试一次；可选课程/提交调用保留旧版 `runCatching` 边界。 | **旧版：**业务认证耗尽后调用 `resolveLocalBusinessAuthenticationFailure` 校验用户中心：只有明确 Invalid 才清选定主会话，Valid、瞬时或不确定结果保留会话并返回 `spoc_error`。**示例：**无等价主会话仲裁。**决策：**必需操作执行同样校验；只有 `authentication_required` 清所选路线，其它结果返回可重试 `upstream_unavailable` 且不清理。

### SPOC 列表

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**认证当前学期后 POST `/inco/ht/queryOne`；可选课程元数据 GET `/jxkj/queryKclb`；权威全局作业 POST `/inco/ht/queryListByPage`。**示例：**当前周/课程接口不同，作业列表是按课程 GET `/kczy/queryXsZyList`，协议不等价。**决策：**即使课程查询失败或为空，也使用旧版全局列表。 | **旧版：**路线转换且不跨路线跳转/重放。**示例：**普通同主机请求。**决策：**整个学期/列表序列锁定一条路线。 | **旧版：**同一令牌、RoleCode 和路线 Cookie；课程元数据失败可选。**示例：**共享令牌状态。**决策：**使用路线内 SPOC 状态。 | **旧版：**queryOne POST 加密 `param`；课程 GET 参数 `kcmc=""`、`xnxq`；列表 POST JSON `{param}`，明文顺序为 `pageSize=15`、`pageNum`、固定 `sqlid=1713252980496efac7d5d9985e81693116d3e8a52ebf2b`、`xnxq`、`kcid=""`、`yzwz=""`。**示例：**GET `flag=1`、`sflx=2`、`sskcid=<course>`，不等价。 | **旧版：**JSON、XHR、`Token`、`RoleCode`。**示例：**query 加 `Token`，无 RoleCode。**决策：**采用旧版精确编码/请求头。 | **旧版：**AES-128-CBC 零填充并 Base64，密钥 `inco12345678ocni`，IV `ocni12345678inco`；对齐明文不增加额外块，`LocalSpocSupportTest` 有固定向量。**示例：**虽确认常量，却总是追加 1-16 个零字节，对齐明文也追加整块。**决策：**使用冻结本地无额外块行为，覆盖对齐和未对齐向量；示例仅作补充。 | **旧版：**当前学期 `dqxq/mrxq`；分页整数 `total/pageNum/pageSize/pages`、布尔 `hasNextPage` 和列表，默认 `0/1/15/1`、false、空列表；作业必需字符串 `zyid/zymc`，可选字符串 `tjzt/zyjzsj/zykssj/sskcid/xnxq/mf/kcmc`；课程元数据可选。**示例：**不同的按课程 `Homework` 字段。**决策：**保留默认值和可选性，但已出现字段类型错误时拒绝。 | **旧版：**从第 1 页开始直到 `!hasNextPage`、达到上限或列表为空；路线客户端缓存，课程查询使用 `runCatching`。**示例：**调用方循环课程，无等价全局分页。**决策：**保留旧版分页和可选元数据；即使课程为空也必须发送全局列表请求。 | **旧版：**业务认证触发一次刷新；畸形 JSON 分支扫描原文，可能因出现 `token` 一词误判认证。**示例：**类型化 JSON 错误，无等价全局列表。**决策：**当前合同禁止重放解析/未知失败，畸形 JSON 始终为 `parse_error`；有证据的认证信封仍刷新一次；真实全局空页算成功。

### SPOC 安全诊断

| 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**无诊断 API，始终执行上述当前学期/全局列表操作。**示例：**无等价全局列表诊断。**决策：**诊断不增加 URL 或请求。 | **旧版：**同一条路线锁定的 SPOC 流程。**示例：**列表协议不等价。**决策：**复用普通最终 URL 和原始 SSO 检查。 | **旧版：**同一条路线 Cookie/令牌/角色状态。**示例：**不等价。**决策：**不暴露凭据或会话状态。 | **旧版：**同样的 `kcid=""` 加密分页 POST，无诊断参数。**示例：**按课程 GET，不等价。**决策：**普通读取和诊断读取共用一次操作，不发送证据专用请求。 | **旧版：**同样的 JSON/XHR/Token/RoleCode 请求头和加密正文。**示例：**不等价。**决策：**不变。 | **旧版：**同一 AES-CBC 操作。**示例：**仅提供常量。**决策：**不变。 | **旧版：**无诊断 DTO。**示例：**不适用。**决策：**只返回 `globalPageCount` 和普通 `result`；计数只在权威全局页成功解析后递增，至少为 1 才能区分真实空页和跳过请求；不暴露原始分页、参数、令牌或新作业字段。 | **旧版：**普通路线状态和分页。**示例：**无等价。**决策：**复用同一序列和状态；诊断不增加缓存或并发行为。 | **旧版：**全局页认证/上游/解析错误仍失败。**示例：**不适用。**决策：**使用同一路线错误；计数只是证据元数据，不能单独建立实时成功。

### SPOC 详情

2026-09-08 文档归属修正：本节旧首表误放了 Judge 的 `assignment/index.jsp?assignID`、worker Cookie 和两分钟缓存描述；同一协议已完整记录于下方“Judge 详情”，现删除这里的重复错置表并恢复真实 SPOC 逐操作表。此为文档纠错，不是协议迁移或新实时结论，旧错置事实保留于本段和 Git 历史。

本次直接读取两冻结 HEAD，分别仍为 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`、`efb7976bf513f38364b88aeb83d704586cff9b2a`。具体来源：旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalSpocApi.kt` 的 `getAssignmentDetailResponse/getAssignmentDetail/getSubmission/getEnvelope`、`LocalSpocSupport.kt`、`model/dto/Spoc.kt` 和 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalSpocApiBackendTest.kt`；示例 `src/api/spoc/{opt,core,data}.rs`；当前 Core `features/spoc/{detail,parser,auth,list}.rs`。Judge 归属另由旧 `LocalJudgeApi.kt:278` 的详情 URL 直接确认。

| 操作 | 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|---|
| 作业详情必需读取 | **旧版：**先取当前列表摘要，再 GET `https://spoc.buaa.edu.cn/spocnewht/kczy/queryKczyInfoByid`。**示例：**`query_homework_detail` 是同一端点，但前置课程/列表及角色流程不等价。**当前：**复用上述 SPOC 认证，不引入 Judge URL/service。 | **旧版：**沿 SPOC 已认证调用。**示例：**通用请求流程。**当前：**路线锁定，业务 SSO Location/HTML 按 SPOC 认证边界处理，不套 Judge 选课跳转。 | **旧版：**当前模式 SPOC token/role。**示例：**Spoc credential，缺旧版角色初始化。**当前：**路线内业务状态，不使用 Judge worker Cookie。 | **两源：**GET query `id=<assignmentId>`，无正文。**当前：**先从权威列表匹配同 ID，详情原始 id 必须相同。 | **旧版/当前：**XHR、`Token: Inco-<token>`、`RoleCode`。**示例：**通用请求只设置 `Token`，不能据此删除当前已验证角色头。 | GET 不加密；前置列表仍沿列表章节 AES 规则。示例仅在 JSON payload 分支加密，不对本 GET 引入 param。 | **旧版/当前：**id、zymc 必需 String；zynr/zyfs/zykssj/zyjzsj/sskcid 可空 String。标题/课程身份来自列表摘要，详情补得分/时间/纯文本。**示例：**HomeworkDetail 只解析 zynr/xzwjlx/xztjcs，不是等价完整 DTO；不新增附件或提交限制到公开 DTO。 | **旧版/当前：**详情先取列表，再顺序详情与提交补充；复用业务登录锁，无 Judge 两分钟详情缓存。**示例：**复用 Spoc credential，不提供同一聚合详情缓存依据。 | **当前：**空 ID invalid_input，列表未找到为 upstream_changed，ID 不一致拒绝。必需详情认证重试耗尽沿 UC 仲裁，只在明确主会话失效时清所选路线；权限信封不无条件重放。旧 not-found 表达与当前稳定错误映射分别保留，不改 CLI 退出语义。 |
| 可选提交信息 | **旧版/当前：**GET `https://spoc.buaa.edu.cn/spocnewht/kczy/queryXsSubmitKczyInfo`。**示例：**未提供同一只读补充流程；其 submit_homework 是写操作，不能替代。 | 旧版与当前复用同一 SPOC 业务响应检查和有界认证恢复；示例此操作无等价证据。 | 与上行同路线 token/role，补充失败不凭空清兄弟会话；示例 N/A。 | **旧版/当前：**GET query `kczyid=<assignmentId>`，无正文；示例 N/A。 | 与上行旧版/当前 XHR/Token/RoleCode 相同；示例 N/A。 | 无新增加密；示例 N/A。 | **旧版/当前：**tjzt/tjsj 可空 String；用于 submissionStatus/submittedAt；content 为可选信封。原始 HTML 只在解析层，公开 contentPlainText。示例 N/A。 | **旧版：**runCatching 可选；**当前：**with_spoc_auth_retry 后 `.ok().flatten()`，完成在必需详情之后，无独立结果缓存。示例 N/A。 | 补充失败保留必需详情并按既有合并规则回退/未知状态，不把提交补充当成真实作业提交成功；示例 N/A。 |

2026-08-24 的确定性 SPOC 实现证据：CAS 引导最多跟随八次不自动跳转且受主机白名单限制的
重定向，只接受 HTTPS `spoc.buaa.edu.cn` 主机精确 `/spocnew/cas` 路径中的令牌，并要求最终
表示与 Direct 或 WebVPN 路线一致；不会请求令牌落地页。原语和数组角色形态遵循冻结
`JsonPrimitive` 行为。凭据只在单一路线状态内序列化和缓存，`Debug` 已脱敏，状态生成号失效后
不能重新写入，每个业务调用至多刷新一次认证。必需学期/页面/详情操作第二次认证失败时会校验
主 UC 会话：明确失效只清理选定路线，有效或不可用 UC 保留主会话及兄弟槽位并返回非认证类
SPOC 可用性错误。即使传输不跟随重定向，解析到 SSO 的业务 Location 也触发同一有界刷新。
`sys/casLogin` 的原始 SSO Location、空 content 和缺角色进入同一主会话仲裁。课程元数据即使
重试耗尽仍为可选。冻结客户端独立的“权限”认证标记与当前禁止无条件重试的合同冲突，UBAA 2
已在决策日志记录，不重放 code-403 权限信封。

列表传输测试会捕获第 1 页和第 2 页的真实 JSON POST 正文，只在测试进程内解密 Base64 AES-CBC
的 `param`，并断言包含空 `kcid`、`yzwz` 的完整有序明文；同时证明多个课程共用一条分页序列，
课程元数据为空或不可用时仍会继续翻页。解析测试覆盖整数分页字段、可选字符串 `xnxq`、必需
字符串详情字段 `zymc`、可选字符串 `sskcid`，以及包含 `token` 但不得触发隐藏重登录的畸形
JSON。详情测试保留上游 ID 校验、摘要回退、可选提交信息、纯文本解码和不暴露原始 HTML。
这些只是确定性协议结果，当前 Direct/WebVPN/auto 的实时证据另行记录。

### Judge 列表

2026-10-23 当前实现覆盖说明：下表保留冻结旧版事实；HTTPS service、原生登录页识别、逐项历史过滤、WebVPN 串行和重新认证后选课恢复，以[最新逐操作对照](#希冀获取修复实施前来源对照)为准。旧的整课跳过不再用于当前诊断计数。

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** SSO `https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F`，随后访问 `judge.buaa.edu.cn/courselist.jsp?courseID=0`。**示例：** 不适用且不等价，固定提交中没有 Judge 模块。**决策：** 旧版是唯一冻结协议来源。 | **旧版：** 解析一次激活跳转后再做路线转换；SSO 页面最多触发 3 次重新激活。**示例：** 不适用。**决策：** 所有跳转和地址均锁定当前路线。 | **旧版：** 按用户/模式使用客户端；独立 worker 从非 Judge 父客户端复制 Cookie，并保持 Judge Cookie 本地。**示例：** 不适用。**决策：** 状态归路线和客户端所有，不混用全局缓存或 Cookie。 | **旧版：** GET 课程列表；GET `courselist.jsp?courseID=<id>` 选择课程；GET `assignment/index.jsp`；`includeExpired` 只影响本地截止时间，不是上游参数。**示例：** 不适用。 | **旧版：** 浏览器 `Accept`、`Accept-Language: zh-CN,zh;q=0.9` 和精确 Chrome 58 UA，无正文。**示例：** 不适用。**决策：** 保持不变。 | **旧版/示例：** 不适用。 | **旧版：** 解析排除课程 0 的课程链接；按 `assignID` 解析作业链接，排除 `problemContent` 和 `judgeDetails`，并去重。**示例：** 不适用。**决策：** 实时对齐前必须保留完整过滤规则。 | **旧版：** 列表缓存按用户和路线分组，作业处理最多 4 个并发 worker，列表 TTL 5 分钟；除非 `includeExpired`，只保留六个月内课程。**示例：** 不适用。**决策：** 状态由路线客户端拥有并随会话生命周期清理。 | **旧版：** 本地未登录、SSO 重激活失败、非 200、无权限或不存在均映射为稳定错误。Judge 业务认证重试耗尽后先校验 UC，仅 UC 明确 Invalid 才清理主会话；Valid、5xx、网络或不确定结果保留会话并返回业务失败。**示例：** 不适用。**决策：** 顶层沿用该仲裁，保留会话时使用 `upstream_unavailable`；列表退出 0 或数量本身不能证明解析一致，Direct/WebVPN 数量差异继续保留。 |

| **旧版：**无诊断 API，使用上述 Judge 列表引导。**示例：**不适用且不等价。**决策：**诊断不增加上游请求或 URL。 | **旧版：**同一列表激活和有界重激活。**示例：**不适用。**决策：**复用精确列表链和路线解析。 | **旧版：**同一用户/模式客户端及独立 worker。**示例：**不适用。**决策：**facade 只公开计数，不暴露 worker/会话状态。 | **旧版：**同一课程、选择、作业列表和详情 GET，无诊断参数。**示例：**不适用。**决策：**普通和诊断读取共用同一路径与缓存。 | **旧版：**同一浏览器请求头和空正文。**示例：**不适用。 | **旧版/示例：**不适用。 | **旧版：**先匹配数字 `assignID` 锚点，再排除 `problemContent`/`judgeDetails`，拒绝空标题并去重；没有计数 DTO。**示例：**不适用。**决策：**`courseCount` 为跳过历史课程前的课程数；`rawAnchorCount` 汇总操作触达的作业列表中数字 `assignID` 的 `a[href]` 匹配（新取或缓存均可），在排除、标题过滤、去重前统计；创建 worker 前跳过的历史课程不贡献任何计数；`filteredUniqueCount` 汇总最终非空唯一作业列表；`summaries` 与普通 `includeExpired` 结果完全一致。不增加原始 HTML、新 ID、现有摘要之外的标题、Cookie 或令牌。 | **旧版：**列表 TTL 5 分钟，空作业列表不缓存。**示例：**不适用。**决策：**每个非空作业列表解析时原子缓存两个安全计数，普通读取后诊断不重复请求或推断；保留四 worker 上限和生命周期失效。 | **旧版：**列表认证/上游错误不变。**示例：**不适用。**决策：**诊断 facade 返回与普通 Judge 列表相同的错误和路线语义；计数是证据元数据，不能单独证明实时成功。

| 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**激活/选课后 GET `assignment/index.jsp?assignID=<id>`。**示例：**不适用且不等价。** **决策：**使用冻结列表发现的 ID。 | **旧版：**SSO 页面重新激活并重试，路线保持不变。**示例：**不适用。** **决策：**详情仍锁定所选路线。 | **旧版：**选课互斥锁和独立 worker Cookie。**示例：**不适用。** **决策：**只使用同一路线/客户端状态。 | **旧版：**GET，使用列表发现的数字/字符串课程和作业 ID。**示例：**不适用。 | **旧版：**Judge 浏览器请求头，无正文。**示例：**不适用。 | **旧版/示例：**不适用。 | **旧版：**解析开始/截止时间、最高/本人分数、总数/提交数、题目表、每题分数/上限/状态、`PARTIAL`、提交数回退和纯文本。**示例：**不适用。** **决策：**字段和状态语义都必需，固定空 `problems`/`myScore` 不是 parity。 | **旧版：**选课锁；详情缓存 2 分钟，按用户+路线+课程+作业分组。**示例：**不适用。** **决策：**不设全局缓存，会话重置清理。 | **旧版：**缺少作业/课程为 not found，认证页会重激活，非 200/认证耗尽返回稳定错误；业务认证最终失败时先校验用户中心。** **决策：**只在顶层详情执行一次仲裁，不在每个内部请求中执行；历史退出 0 在完整解析断言前不构成语义证据。

### Judge 详情

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** 激活/选课后 GET `assignment/index.jsp?assignID=<id>`。**示例：** 不适用且不等价。 | **旧版：** SSO 页面重新激活并重试，路线保持不变。**示例：** 不适用。 | **旧版：** 选课互斥锁和独立 worker Cookie 状态。**示例：** 不适用。**决策：** 使用同一路线/客户端范围。 | **旧版：** GET，使用列表发现的精确数字/字符串课程和作业 ID。**示例：** 不适用。 | **旧版：** Judge 浏览器请求头，无正文。**示例：** 不适用。 | **旧版/示例：** 不适用。 | **旧版：** 解析开始/截止时间、最高/本人分数、总数/提交数、嵌套或顶层题目表、每题分数/上限/状态、`PARTIAL`、提交数回退和纯文本。**示例：** 不适用。**决策：** 所有字段和状态语义均为必需，固定空 `problems`/`myScore` 不算对齐。 | **旧版：** 选课锁；详情缓存 2 分钟，键为用户+路线+课程+作业。**示例：** 不适用。**决策：** 不设全局缓存，会话重置时清理。 | **旧版：** 缺少作业/课程为不存在，认证页会重激活，非 200 或认证耗尽返回稳定错误。业务认证最终失败后先校验 UC，再决定主会话是否失效。**决策：** 该仲裁只包住顶层详情操作，不在每个内部请求重复执行；完整解析断言通过前，历史详情退出 0 不构成语义证据。 |

### Judge 批量与缓存

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** 复用 Judge 激活、列表和详情地址，没有单独的批量上游 API。**示例：** 不适用且不等价。 | **旧版：** 每个 worker 激活后保持在自己的路线。**示例：** 不适用。 | **旧版：** 缓存范围为 `(mode,username)`；worker Cookie 隔离 Judge 会话；重置清理 `LocalJudgeApiCache`。**示例：** 不适用。**决策：** 使用运行时拥有的 `RouteFeatureState`，绝不使用进程全局状态。 | **旧版：** 规范化非空 `(courseId,assignmentId)` 键，去重后按课程分组，执行同样的详情 GET 序列。**示例：** 不适用。 | **旧版：** 使用相同的浏览器请求头。**示例：** 不适用。 | **旧版/示例：** 不适用。 | **旧版：** 分组遍历返回完整详情 DTO 和公开的 `historicalCutoffCourseIds`；规范化输入为空时返回空详情。**示例：** 不适用。**决策：** UBAA 2 将截止课程 ID 保留在路线状态内部，分组处理后恢复规范化后的调用方顺序。 | **旧版：** 最多 4 个并发课程 worker；列表 TTL 5 分钟、详情 TTL 2 分钟；不缓存空作业列表；截止范围保留当天时分并钳制目标月份日期；重置清空全部状态。**示例：** 不适用。**决策：** 在所属 facade 内复现并发上限、缓存键和生命周期。 | **旧版：** 一个课程/作业不存在会使批量操作返回不存在；认证/上游错误不会隐藏。业务认证最终失败仍先经过 UC 仲裁再清理主会话。**示例：** 不适用。**决策：** 顶层批量操作共享 Judge 仲裁边界，注销或账号/路线变更后不得复用旧状态。 |

## 专项记录

### 希冀读取去重：实施前双来源核对

冻结引用：ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，本轮 `just refs` 通过。

已读旧版 `shared/.../api/feature/JudgeApi.kt`、`model/dto/Judge.kt`、`api/local/LocalJudgeApi.kt`、`commonTest/.../LocalJudgeApiBackendTest.kt` 及服务端 `JudgeClient.kt`。旧实现将课程选择与索引/详情置于同一互斥区，客户端激活复用；课程 worker 隔离业务 Cookie。每份详情都先选课，未做同课程选择去重。

已读 buaa-api 的 `api.rs`、最接近的 `api/class/core.rs`、`context.rs`、`request.rs`、`store/{cred,cookies}.rs`、`crypto/mod.rs` 和 `error.rs`。它没有 Judge 协议；课堂模块的 token、URL 和 DTO 不适用于希冀。本轮不借用示例的 TLS 配置或凭据规则。

当前 Core 分批扫描每项详情再次 GET 选课，同课程连续 2 项详情也重复选择。本轮只在同一 runtime 已成功选择、功能代次相同且期间没有课程入口、重新激活或其他 worker 使用时省略重复选择。跨批持有的是已确认课程标识，不复用 Cookie 或复制客户端；不同课程仍须选择。保留 WebVPN 整课程串行和 Direct 的既有隔离 worker 上限。

| 操作 | CAS/bootstrap、service | 重定向/最终地址 | Cookie/会话 | 方法和精确参数 | 头/编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误语义 |
|---|---|---|---|---|---|---|---|---|---|
| 激活/课程目录 | 现有 HTTPS SSO service=HTTPS Judge 根地址，沿既有在线认证证据 | 原 get_with_redirects 和业务登录页检测 | 原路线 runtime；激活清除已选课程 | GET courselist.jsp?courseID=0 | 原浏览器头，无正文 | 无新增 | 原 Course | 原目录 TTL；真实目录请求清除选课标识 | 原三次业务重激活与 UC 仲裁 |
| 课程作业索引 | 沿用激活 | 原校验 | 同 runtime 选课上下文 | GET courselist.jsp?courseID=ID，再 GET assignment/index.jsp | 同上 | 无新增 | 原 AssignmentList | 相同课程且状态有效才去重选课；索引读取与缓存语义不变 | 请求失败使选课记忆失效 |
| 作业详情/批量 | 沿用激活 | 原校验 | 相同课程复用选课；跨课程重新选择 | GET assignment/index.jsp?assignID=ID，参数不变 | 同上 | 无新增 | 完整 detail、题目、成绩和状态均不变 | 原详情 TTL；分批强制读取仍强制取详情；派生 worker 时父状态失效 | 重激活后必须重新选课；原错误分类、取消、账号与路线代次保持 |

这是对旧版重复请求的显式优化，不宣称旧版已实现去重。上线前必须通过选课状态严格校验的 Mock、跨计划交错与失效回归，并以两条真实路线确认完整读取结果。未从缓存列表推断服务端当前课程。

#### RED、实现与保留覆盖

生产代码修改前，`segmented_cached_scan_reuses_activation_without_skipping_selection_or_data` 将课程 12 的选课请求期望改为 1，实际为 3，退出 101。完整日志保存在仓库外本轮私有性能目录的 `judge-red.log`。

选课记录属于 ClientRuntime，不进入共享 RouteFeatureState 或持久会话；记录同时保存 Judge 功能代次。派生 worker 撤销父记录并从空记录开始，既有 Cookie 过滤不变。课程入口、激活和请求错误清空记录；重激活后的重试仍恢复目标课程。不同计划交错时以 runtime 的当前课程为准，不以计划游标推断服务器状态。

新增交错扫描回归，继续通过传输层的课程 Cookie 检查验证每份详情归属；为同课程详情去掉旧测试中多余的选课请求期望，保留激活、索引、详情、历史过滤、主登录失效、网关地址与完整队列耗尽断言。没有删除业务测试。分批扫描 30 项、readonly 中 Judge 31 项通过。

#### 实时前后样本

同一隔离验证入口 `just verify-live mode=<route> feature=judge`，每条路线修改前后各一次。均为新进程、新隔离会话；依次认证、包含过期的完整集合、当前集合、详情和批量详情。

| 路线 | 修改前到当前列表就绪 / ms | 修改后 / ms | 完整集合 / 当前集合 |
|---|---:|---:|---:|
| Direct | 7070 | 4833 | 96 / 42 |
| WebVPN | 17744 | 15744 | 96 / 42 |

两路线各步骤 PASS，课程数均为 6，解析原始锚点数 104。累计时间包含认证及前置集合读取；这是单次网络样本，不作为 P95 或原生首页完整加载时间。确定性收益是同课程连续索引与详情只选课一次；示例两课程三详情的选课请求从 5 次降为 2 次，索引和详情数量保持。

完整 Flutter 格式、分析和七包测试通过：domain 53、platform 87、app 660、UI 380、bindings 20、host 101、官方应用 79，共 1380 项。FRB 生成零漂移，macOS Debug 构建通过。

最终全功能真实只读 `just verify-live mode=direct` 和 `mode=webvpn` 均退出 0，各 40 PASS、0 FAIL。首次 Rust 全量检查发现三个 Bridge 脚本仍期望冗余选课，已只删除详情前的重复请求期望，保留批次让位、写意图保留、取消零请求、数据保存与队列耗尽断言，随后重新执行完整门禁。

最终 `just check` 退出 0，包含 Rust/Shell、CLI 端到端、布局、模块与文档门禁；`just flutter-check`、`just flutter-codegen-check`、`just refs`、敏感扫描和 `git diff --check` 全部通过。Bridge 四项扫描回归通过，所有原业务断言保留。最终生产逻辑已包含于本轮构建的 macOS Debug；本轮没有测量完整原生首页冷启动分位数。

### 希冀获取修复实施前来源对照

日期：2026-10-23；UBAA2 基线 `01ab4f59`。本文件在生产代码改动前建立。

#### 来源与冲突裁决

- 冻结旧版 `examples/ubaa_old`：`1f4b8f8412272b6a423d4ad92b396e3db721e6f3`。核对 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/JudgeApi.kt`（接口）、`model/dto/Judge.kt`、`api/local/LocalJudgeApi.kt`（请求、解析、Cookie worker、缓存与错误）、`shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalJudgeApiBackendTest.kt` 和 `JudgeApiTest.kt`。
- 固定 `examples/buaa-api`：`a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。`src/api.rs` 无 Judge 模块；最邻近的 `api/spoc/{core,data}.rs` 使用 SPOC token/AES JSON 协议，与希冀 HTML 不等价。另核对 `api/sso/auth.rs`、`request.rs`、`context.rs`、`store/{cookies,cred}.rs` 的认证、重定向、凭证及错误边界；不能借用 SPOC URL、加密常量、字段或错误语义，TLS 仍严格验证。

> 本段的聊天与 `docs/_audit/` 属于当时的仓库外补充材料，当前克隆无法复现；只保留历史来源说明，不将其登记为新的冻结引用。可复现的协议依据仍按[冻结参考](../references.md)与本页实际受跟踪的测试定位核对。

- 用户引用的聊天 `01a15d06-1f02-7723-a877-ffbccbceb335` 已实际读取。其 UBAA 工作区审计 `docs/_audit/2026-10-21-judge-login-har.md` 记录 HTTPS service、原生登录页误判、历史整课排除与 WebVPN 网关共享课程状态。另仓库 HEAD 为 `d6dd8f2e5c8121e43f22cd1fbf15152ae87100e9` 且含未提交优化，仅作补充证据，未修改或替换冻结引用。
- 本轮新鲜公共上游观察：GET `https://judge.buaa.edu.cn/indexcs/simple.jsp` 返回 HTTP 200，含 `cgstuloginbtn`，其 SSO `/login` 链接的 service 为 `https://judge.buaa.edu.cn/`。只输出状态、固定路径与公开 service，不保存原始页面。
- 原 HAR 在 Downloads 中未找到，本轮不声称重新分析原 HAR；历史真实业务结果来自上述记录，当前账号验证单独记录。

冻结旧版 HTTP service 与本轮官网链接冲突：采用当前官网 HTTPS service。历史课程整课排除、WebVPN Cookie worker 独立性与用户引用的真实观察冲突：取消整课排除，WebVPN 同一客户端批量任务按课程串行，选课与业务请求不交错；Direct 保留独立 Cookie worker 与四并发上限。渐进读取原本通过原客户端逐批串行且每批重选课程，保留。

#### 逐操作矩阵

所有行中固定 buaa-api 均无同协议实现，不通过类比补参数。下列「现状」来自 UBAA2；「旧」指冻结实现。

| 操作 | CAS/bootstrap 与 service | 重定向与最终 URL | Cookie/会话 | 方法与精确参数 | 请求头/正文 | 加密签名 | DTO/解析 | 缓存并发 | 错误/退出 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 业务激活 | 旧及现状为 SSO `/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F`；改为官网证实的 HTTPS 编码 service | 旧跟随激活跳转；现有有界跳转固定路线，完成根目录 ticket 回调；`/indexcs/simple.jsp` 即使 200 也应拒绝，WebVPN 先解包判定 | 沿用所属路线 SSO/网关 Cookie；不暴露票据，不建立跨账号共享状态 | GET SSO，GET 服务回调；不增加业务 POST | 旧浏览器 Accept、`zh-CN,zh;q=0.9`、精确 Chrome 58 UA 保持；无正文 | 无新增 Judge 加密或签名；WebVPN 沿现有编码 | 不将登录页当数据；识别固定原生登录路径及登录按钮标记 | 现有批次 activated 复用保持；业务重新激活有界 3 次 | 保留 AuthenticationRequired 内部分支与 UC 仲裁；UC 有效/不确定时上抛 UpstreamUnavailable，UC 明确无效才失效主会话 |
| 课程索引 | 同上，先激活 | `https://judge.buaa.edu.cn/courselist.jsp?courseID=0`；最终地址经过现有允许列表 | 与对应路线一致；发现课程亦会影响网关当前课程，不能与本次批量 worker 重叠 | GET `courselist.jsp`，`courseID=0` | 同上，无正文 | 无 | courseId/courseName 字符串，排除课程 0，保留既有 HTML 链接解析 | 原 5 分钟非空缓存与代次保护保持；索引发现先完成再启动课程任务 | 原生登录页作为认证失败，非200/网络/解析错误保留原分类；空课程仍可合法返回空 |
| 每课程作业列表/全量摘要/诊断 | 同一激活 | 先 `courselist.jsp?courseID=<id>` 再 `assignment/index.jsp`；中间重新认证后必须恢复目标课程 | Direct worker 排除 Judge Cookie 后独立激活；WebVPN 共用网关会话，批量课程执行并发上限改为1，许可覆盖激活/选课/列表/详情全链 | 两个 GET；includeExpired 仅本地过滤，不作为上游参数 | 同上，无正文 | 无 | assignID 数字锚点、排除 problemContent/judgeDetails、非空标题及去重保持；诊断计数来自实际处理索引 | 5分钟非空列表缓存保持；取消历史整课排除；六个月过滤逐项进行，不因一条旧作业停止后续遍历 | 失败不发布成功空列表；沿用诊断/普通读取一致结果、稳定错误与 CLI 失败退出 |
| 单项/批量详情与渐进读取 | 同一激活 | 选课后 GET `assignment/index.jsp?assignID=<id>`；重新认证后先重选目标再重试业务 GET | 与列表同规则；渐进原客户端每批重选保持；WebVPN 批量不能跨课交错，Direct 保留独立会话 | GET；本地键为 courseId+assignmentId，不臆造 URL 中 courseId 参数 | 同上，无正文 | 无 | title/courseName/时间/分数均可选字符串；题目数和已提交数整数；提交状态枚举、题目列表和纯文本详情保持旧 DTO 对照及当前类型 | 2分钟详情缓存、输入顺序、重复键规整、生命周期失效保持；原持久缓存历史策略不扩成永久排除 | 不存在/无权限/格式变化保留原错误；有界重激活失败仍经 UC 仲裁，不抹平为成功 |

#### 实施与证据要求

先建立脱敏回调/原生登录页、重新认证丢失选课、WebVPN 共享课程竞争、混合新旧作业及重复读取反例，再实施。完整核心/Flutter/敏感/冻结门禁，以及 Direct/WebVPN CLI 真实只读列表、刷新和详情分别验收。历史数量不作当前期望值。

### 希冀渐进读取的缓存与调度（2026-11-13）

冻结来源为 ubaa_old`1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。旧版 `JudgeApi.kt`、`Judge.kt`、`LocalJudgeApi.kt` 和 `LocalJudgeApiBackendTest.kt` 定义课程目录、索引、详情、两分钟详情缓存、五分钟列表缓存及隔离 worker。buaa-api的 `api.rs` 无 Judge 模块；已核对最接近的 `api/class/core.rs`、`context.rs`、`request.rs`、`store/{cookies,cred}.rs`、`crypto/mod.rs` 和 `error.rs`，课堂 token 协议不适用于希冀。

| 操作 | CAS/bootstrap 与 service | 重定向和最终 URL | Cookie/Session 范围 | 方法及参数 | 请求头及正文 | 加密签名 | DTO 与解析 | 缓存与并发 | 错误及产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| 课程目录 | 沿当前 HTTPS SSO service，旧版 HTTP service 的裁决沿用上文 | 原有受限跳转与 Judge 登录页识别 | 原账号及实际路线 | GET courselist.jsp，courseID=0 | 原浏览器头，空正文 | 无新增 | 原 Course 字段 | 自动读取复用五分钟有效目录；手动刷新索引及全量刷新重新读取 | 缓存保留原取得时间；身份、路线或退出使计划失效 |
| 每课程作业索引 | 同一业务激活 | 选课后原 assignment/index.jsp | 保留成功选课记忆，重新认证后恢复课程 | GET courselist.jsp?courseID=ID，再 GET assignment/index.jsp | 同上 | 无新增 | 原二元键、标题与去重规则 | 活跃课程索引可在五分钟内复用；历史课程保留原有限期复查；手动刷新绕过索引缓存 | 新作业仍由索引发现，不按旧作业位置提前终止 |
| 详情与摘要 | 同一业务激活 | 原 assignment/index.jsp?assignID=ID | Direct 同课程至多四份详情使用独立 Judge worker；WebVPN 保持共享课程上下文串行 | 原 GET 和 assignID 参数 | 同上 | 无新增 | 完整详情、题目、分数、提交状态不变 | 持久详情沿原十五分钟/六小时/七天策略；无存储时仍允许两分钟内存复用；当前目标和全量刷新强制最新 | 保留认证失败仲裁、部分失败旧数据、取消与迟到结果隔离；复用不更新时间 |

两份冻结来源没有当前 SQLite 渐进扫描协议。缓存批处理和宿主展示频率是本地实现选择，不新增学校端点、版本号或增量参数。WebVPN 共享课程状态与历史课程不可永久跳过的裁决沿用上文。

Direct 并发采用同课程四份详情的小批次，复用原 Cookie 过滤并等待全部在途请求收尾。单课程剩余详情至少八份、首组至少四份需要更新时才建立 worker，避免短课程承担额外激活成本。后续小批次复用 worker。作业索引先单独交付，后续课程优先处理已知未完成作业，显式课程始终优先。缓存命中的连续详情最多合并十六份，共用本批续租和摘要投影。全量刷新、当前详情、错误与取消仍逐项保留语义。

#### 验证范围

同设备通过生产 `UbaaClient.begin_judge_refresh` / `next_judge_refresh` 测量修改前后的渐进链路。登录使用 Core-live 与客户端共用的静默认证流程，固定实际路线，仅执行认证和希冀读取。真实样本均含六门课程、96 份作业，冷读取使用独立空缓存，随后读取同一集合核对键与完整度。耗时从建立渐进计划开始，不包含登录，不表示 GUI 绘制完成。

| Direct 场景 | 原首批 / ms | 当前首批 / ms | 原完整 / ms | 当前完整 / ms | 原批次 | 当前批次 |
|---|---:|---:|---:|---:|---:|---:|
| 空缓存 | 501 | 445 | 11007 | 8657 | 102 | 102 |
| 有效缓存 | 331 | 206 | 1243 | 547 | 102 | 14 |

这些是单次网络样本。WebVPN 基线完整读取 96 份作业，冷读取 14437 ms，缓存读取 1380 ms。当前候选的一次新登录返回 `upstream_changed`；复用并核实已有会话后，读取出现 `timeout` 和不完整结果。本轮不登记 WebVPN 提速或完整通过，待网关请求恢复稳定后，在同一固定路线重新验证冷读取、缓存读取和完整集合。

确定性回归覆盖索引与详情复用、手动发现新作业和改名、无存储内存缓存、四并发上限、短课程选择、WebVPN 串行、首批索引、课程优先级、预取被新详情取代、取消、认证仲裁、路线回退和部分失败保旧。原强制在线测试改用明确的刷新参数，保留原请求数量及数据断言；逐份缓存回调计数由合并批次和完整摘要断言共同覆盖，没有删除业务测试。

### 同课程详情预取与索引正文复用（2026-11-13）

2026-11-13 对照冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LocalJudgeApi.kt`、`JudgeClient.kt`、Judge DTO 与测试，以及固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 API 目录和既有请求、认证与存储对照。旧版通过课程互斥区依次选课、读取；buaa-api 无 Judge 协议，下表各上游协议列均不适用，不借用其他业务字段。

当前已登录 WebVPN 浏览器中，6 门课程提供 96 个去重作业入口。两门课程的索引包含明确选中作业，主要正文和该作业独立详情一致；其中大响应解压后约 5.48 MB，重复详情样本耗时 793 ms。同课程四份详情三轮串行中位数 368 ms、并发中位数 134 ms，正文与选中项一致。跨课程省略选课后，即使官网链接带 courseID，仍出现正文或选中项差异。因此只允许同课程详情并发，保留课程切换及认证恢复串行。这些浏览器样本不代替 Core 完整 DTO 和真实路线验收。

| 操作 | CAS/service | 重定向/最终地址 | Cookie/会话 | 方法/精确参数 | 头/编码 | 加密/签名 | DTO/解析 | 缓存/并发/重试 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 索引及附带详情 | 原 HTTPS Judge 激活 | 原路线内索引地址 | 原 runtime，按课程选择 | GET courselist.jsp?courseID=ID 后 GET assignment/index.jsp | 原浏览器头及 HTML 解压预算 | 无新增 | 同一 DOM 提取索引及唯一明确选中作业的完整详情；无明确身份则单独读详情 | 仅本轮实际网络索引附带结果可满足强制刷新；普通索引缓存不携带新的详情证据；来源时间为取得时间 | 原索引失败和扫描失效语义；身份不明确不推断 |
| Direct/WebVPN 详情小批次 | 父流程统一激活 | 详情重定向/认证交给父流程串行处理 | 父 runtime 独占同一课程；不派生独立认证 worker，不持久化复制会话 | 每项 GET assignment/index.jsp?assignID=ID，最多四项 | 原请求头、Cookie 作用域和正文预算 | 无新增 | 完整 DTO 和输入顺序保持，按课程与作业键交付 | 全部在途请求收尾后才恢复认证、切换课程或返回；复用原缓存期限和重激活上限 | 原认证仲裁、部分失败保旧、取消及路线代次检查；失败不伪装空成功 |

索引先返回，已取得详情通过内部待交付结果逐项发布。两条路线至少两份需要读取时组批，最多四份；持久刷新、无存储在线扫描及明确批量详情共用同课程读取能力，单目标不扩大读取范围。Direct 跨课程批量任务继续使用独立 worker。

Direct 已登录只读证据：相同课程四份详情三轮交替串行中位数 300 ms、四路并发 233 ms，24 次响应 HTTP 200，主要正文与串行基线一致。两条路线的渐进读取统一复用父会话完成选课后的小批次详情 GET，移除 Direct 渐进详情 worker 的重复激活及八项启动门槛；至少两份需要读取时组批，最多四份。上述上游 URL、参数、Cookie 作用域、DTO、缓存期限和认证仲裁保持。`batch.rs` 跨课程任务的独立 worker 与并发上限保留，浏览器同课程样本不用于放开跨课程共享会话。


#### 当前实现的真实读取与验收

使用当前生产 Core 与优化前 `98b5c56c7356514c8cfb0168a483e417836ef877` 的同一渐进入口，在独立空缓存中全量刷新。两条路线均复用并核实浏览器登录会话，96 份作业的完整 DTO 与各自参考读取逐项相等。下表耗时不包含登录，传输量为响应解压后的总大小。

| 路线 | 优化前完整耗时 / ms | 当前完整耗时 / ms | 请求数：原 → 当前 | 独立详情请求：原 → 当前 | 解压字节：原 → 当前 |
|---|---:|---:|---:|---:|---:|
| WebVPN | 13284 | 10264 | 121 → 117 | 96 → 92 | 31392465 → 25739294 |
| Direct | 8067 | 6795、13695 | 177 → 117 | 96 → 92 | 31239595 → 24978326～24978687 |

WebVPN 当前另一次样本为 9994 ms。Direct 样本波动较大，当前证据确认请求数和传输量减少，尚不能确认稳定的耗时收益。有效缓存刷新分别为 WebVPN 431 ms、Direct 906 ms，两者均发送两次请求。无持久缓存在线扫描和明确批量详情在两条路线各读取四项，完整 DTO 均与参考相等。这些是同设备网络样本，不是 GUI 首屏或 P95 数据。

独立新会话补验中，WebVPN 经生产自动验证码登录成功：登录页 HTTP 200、验证码为有效 PNG、提交后 HTTP 302，网关回调及 SSO 验票完成。此前仅记录 `UpstreamChanged` 的失败未复现，旧日志缺少具体失败步骤，无法确认历史原因。

确定性验收覆盖索引正文复用及不明确选中项回退、同课程最多四并发、父会话选课复用、认证恢复前收尾、取消与迟到写入、路线切换和完整 DTO。严格 Clippy、完整 Core 与其余 workspace 测试、Core/Bridge 构建、Rust 文档、全 Flutter 工作区检查、原生集成测试及 FRB 生成零漂移检查通过。公开 Bridge 接口及生成文件保持不变。

### 主动刷新非历史作业（2026-11-14）

本次重新核对上述冻结旧版的 `LocalJudgeApi.kt`（课程、索引、详情、缓存、重激活和隔离 Cookie）、`JudgeApi.kt`、`Judge.kt` 与 `LocalJudgeApiBackendTest.kt`。固定 buaa-api 的 `src/api.rs` 没有 Judge；最接近的 SPOC 及公共 request 实现使用不同的 token/JSON 协议，以下各操作的 buaa-api 对照均不适用。

| 操作 | CAS/service 与引导 | 重定向与最终 URL | Cookie/Session | 方法与精确参数 | 请求头与正文 | 加密/签名 | DTO/解析 | 缓存/并发/重试 | 错误与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| 课程目录 | 沿用已裁决的 HTTPS Judge service；旧版为 HTTP | 原路线有界跳转，最终 courselist.jsp | 原账号及 Direct/WebVPN 会话隔离 | GET，courseID=0 | 原浏览器头、无正文 | 无 | 课程编号和名称 | 自动刷新保留五分钟缓存；主动刷新重新读取 | 认证、解析与网络错误分类保持 |
| 每课程索引 | 同一激活 | 先选课，再 assignment/index.jsp | 同一课程上下文 | GET courselist.jsp?courseID=ID，再 GET assignment/index.jsp | 同上 | 无 | 原作业编号、标题及课程字段，不推断提交状态 | 主动刷新重新发现作业；自动刷新保持原复查期限 | 索引失败保留该课程旧数据，不发布成功空列表 |
| 详情与渐进补全 | 同一激活 | 选课后 assignment/index.jsp?assignID=ID | 原账号、路线、课程与作业范围 | GET，assignID 来自索引，无正文 | 同上，沿用16 MiB详情预算 | 无 | 时间、分数、题目、提交状态来自详情 | 新增 detail_refresh=RefreshActive：主动刷新绕过非历史详情 TTL；历史判据及七天复查保持。full_refresh 仍绕过全部详情缓存；refresh_indices 单独使用仍仅强制索引。同课程四并发、索引内嵌详情复用和有界重激活保持 | 自动计划不能满足主动核验时，完成当前计划后合并执行一次主动计划；取消、账号和路线失效使等待请求失效。完整成功的缓存复用正常完成，读取中 incomplete 只表示进度 |

主动刷新即时核验非历史详情是本机产品语义，不增加学校参数。历史作业仍须同时满足已提交、开始早于六个月前、截止早于十四天前。详情排序依次为显式目标、新增或列表字段变化、未提交或部分提交（按截止时间）、其他非历史、历史；排序只影响处理先后，不省略可见课程或作业。
