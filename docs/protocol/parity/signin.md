# 课堂签到

本文件收录 iClass 课堂签到查询、签到提交与业务会话的来源对照。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### 课堂签到今日查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**先访问 `https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter`，再调用 8347 的 `app/user/login.action` 和 `app/course/get_stu_course_sched.action`。**示例：**等价 Class 模块在固定提交中将登录更新为 8346 的 `eschool/app/user/login_buaa.do`，今日查询仍使用 8347 的 `app/course/get_stu_course_sched.action`。**决定：**2026-08-28 Direct 真实运行证明旧登录入口返回 `upstream_changed`，采用示例中更晚且等价的登录入口；查询入口保持旧版。 | **旧版：**最多跟随 8 次跳转，从最终 URL 或 `Location` 中提取大小写不敏感的 `loginName`，并进行百分号解码；Direct/WebVPN 始终保持当前路线。**示例：**登录前同样从 8346 跳转结果提取 `loginName`。**决定：**使用 Core 的手动、允许主机列表跳转，不接受未知主机。 | **旧版：**主认证 Cookie 与 iClass `id/sessionId` 分离；业务会话按学生标识缓存。**示例：**同样维护独立 Class 凭据。**决定：**iClass 会话是每个路线/客户端的进程内状态，不能写入 `session.json`，也不能跨路线复用。 | **旧版：**登录 GET 参数为 `password=""`、`phone=loginName`、`userLevel=1`、`verificationType=2`、`verificationUrl=""`；今日查询 GET 参数为 `id=userId`、`dateStr=yyyyMMdd`。**示例：**登录和查询参数与旧版一致。**决定：**保持完整参数和值，不增加字段。 | **旧版：**今日查询使用 `sessionId` 请求头；请求无正文。**示例：**使用等价会话值作为 `Sessionid`，查询为 POST 并将 `dateStr` 放在 query；**决定：**本轮仅由真实失败证明登录入口变化，查询方法仍保持冻结旧版 GET，除非后续真实证据要求调整。 | **旧版/示例：**无加密。**决定：**不得引入自定义加密或签名。 | **旧版：**`STATUS` 接受字符串或整数；成功值为 `0`、`200`、`success`。今日课程字段为 `id`、`courseName`、`classBeginTime`、`classEndTime`、`signStatus`，状态兼容字符串或整数；提交结果才使用嵌套 `result.stuSignStatus`。**示例：**`STATUS=2` 表示空列表。**决定：**公共 DTO 仅暴露对应稳定字段和 typed 资格，不暴露包装、业务会话或原始响应；空列表语义需以真实响应确认。 | **旧版：**按学生标识缓存业务会话；会话失效后最多刷新一次。**示例：**Class 凭据独立缓存。**决定：**使用路线内登录锁和失效代数，主会话清理时同步清除；并发失效后旧任务不得重新写入。 | **旧版：**未认证返回认证错误；iClass 登录失败时查询退化为空成功，这是旧 UI 的容错行为。**示例：**业务失败上抛。**决定：**Core 不伪造空成功；无法建立业务会话返回稳定上游错误，业务会话失效只清除签到状态，只有 User Center 明确失效才清除主认证。 |

当前实现证据：`crates/ubaa_core/tests/signin.rs` 已覆盖冻结响应的字符串/整数状态解析及独立 iClass 会话；Core facade 和 `signin today` CLI 已接入。固定 `examples/buaa-api` 的 Class 模块提供补充登录入口证据，但其查询方法/请求头与冻结旧版不等价；Rust Core 按冻结旧版使用 GET、`sessionId` 头并将 `id/dateStr` 放在 query。`STATUS=2` 表示今日无课程的合法空结果。2026-08-28 Direct 与 WebVPN 实时验证均通过并返回空列表。

### 历史裁决：时间戳与签到端口、路径及会话解析

当时的实现与逐操作裁决见[2026-09-17 签到修正记录](#2026-09-17-课堂签到修复对照)。该记录保留当时的来源提交，不将后续引用更新冒充重新完成的协议对照。

- 业务登录采用旧版 `8347/app/user/login.action`，必须返回有效业务 `id` 和 `sessionId`，不允许以 `loginName` 回退。
- 时间戳采用 GET，接受 JSON 整数或字符串；Direct 使用 HTTP 8081，WebVPN 使用包装后的 HTTPS 8347。
- 签到 POST 的 Direct 路径带 `/eschool`，WebVPN 8347 路径不带该前缀；`courseSchedId/timestamp` 在查询串，业务 `id` 在表单，业务 `sessionId` 在请求头。
- 两份来源的方法、参数载体及会话语义存在差异，按已记录的旧版权威裁决，不再称为“全面对齐两份来源”。

## 专项记录

### 2026-11-23 签到预检恢复登录

Android 2.0.3（2030）的诊断记录显示，WebVPN 的课堂签到预检在本机路线会话检查处返回 `authentication_required`。应用复用[所需路线会话恢复](offline-cache.md#离线恢复逐操作来源对照)，在释放预检占用后核验课堂签到所需的会话。自动登录沿用账号身份核验、凭据许可和验证码处理。恢复成功后，应用再次调用签到预检，按当天课程状态生成一次性签到意图。

| 操作 | CAS/引导与 service | 重定向与最终 URL | Cookie、Session、Token | HTTP 方法与参数 | 请求头与编码 | 加密与签名 | DTO 与解析 | 缓存、并发、重试 | 错误与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| 会话恢复 | 沿认证对照的所需路线入口 | 沿该路线的认证与激活跳转 | 使用该路线的主会话 | 沿既有认证及身份核验请求 | 沿认证对照原有编码 | 沿原 WebVPN 包装及认证规则 | 复用已核验的用户身份和实际路线 | 复用读取会话恢复队列，恢复前释放预检占用，账号或网络变化时作废本次预检 | 现有自动登录条件、人工验证提示和恢复错误适用 |
| 资格预检与签到提交 | 沿课堂签到今日查询与提交对照 | 沿既有 iClass 路线 | 沿原主会话与 iClass 业务会话 | 沿今日查询和 `stu_auto_sign` 的既有方法及参数 | 沿原请求头和编码 | 沿原协议 | 沿今日课程状态和提交状态解析 | 恢复成功后只重新预检一次，提交继续消费一次性意图 | 恢复失败或复核失败时停止本次操作，提交结果未知时执行原回读规则 |

冻结参考沿本文的今日查询与提交对照。两份来源均无 UBAA 2 的预检协调器和所需路线恢复队列。Direct 和 WebVPN 的真实验证须在获得对应路线的账号读取授权后执行。可用正常的签到预检验证登录恢复与资格复核，实际提交需另有该次签到的授权。

### 2026-11-12 课堂签到展示筛选

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `model/dto/Signin.kt` 和 `SigninScreen.kt` 以 `signStatus` 的 0/1 显示未签到/已签到；buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/class/data.rs` 同样保留原状态，`opt.rs` 没有同等 UI 分组或本地缓存。缓存与在线分组统一按原状态，未知状态只在全部视图显示，“未签到”不等同于允许提交。

本次仅改变展示筛选。CAS/引导、跳转、Cookie/业务会话、HTTP 方法与精确参数、请求头与编码、加密、上游解析均沿用既有九列裁决；缓存格式、并发和重试不变，错误继续显式返回。按钮仍要求有效目标和在线 typed 资格，缺目标的已签到记录保留为只读展示。

### 2026-09-17 课堂签到追加修复

以用户指定的当前冻结旧版为协议权威；此前“全面对齐两份来源”及 sessionId/loginName 可混用的描述由[逐操作修正记录](#2026-09-17-课堂签到修复对照)取代。本轮修复旧版登录入口、严格业务会话和数字时间戳，完整 UI 目标保持暂停。

### 2026-09-17 课堂签到修复对照

用户明确以可用的 `ubaa_old` 为准。本表在生产代码修改前记录；本轮仅修复签到，不恢复暂停的完整 UI 计划。

冻结来源：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；buaa-api `efb7976bf513f38364b88aeb83d704586cff9b2a`，`just refs` 已通过。
旧版路径基于 `shared/src/commonMain/kotlin/cn/edu/ubaa/`：接口 `api/feature/SigninApi.kt`、DTO `model/dto/Signin.kt`、实现 `api/local/LocalSigninApi.kt`、跳转 `api/SigninLoginNameSupport.kt`；测试为 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalSigninApiBackendTest.kt`。另一来源为 `src/api/class/{core,opt,data}.rs`。

| 操作 | 冻结旧版 | buaa-api 差异 | 本轮裁决 |
|---|---|---|---|
| CAS/bootstrap | GET https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter；沿重定向取 loginName，不构造额外 service 参数；上限8次 | 同入口，自动重定向并从最终URL取值 | 保持旧版入口和手动跳转；WebVPN包装与路线Cookie保持现状 |
| 业务登录 | GET https://iclass.buaa.edu.cn:8347/app/user/login.action；password和verificationUrl为空、phone=loginName、userLevel=1、verificationType=2，全在查询串；STATUS成功后必须有result.id和result.sessionId | 8346/eschool/app/user/login_buaa.do，保存loginName与id，实际代码没有读取sessionId | 改为旧版入口，缺失会话拒绝，取消loginName回退；禁止两套协议拼接 |
| 今日列表 | GET https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action；查询id和dateStr(YYYYMMDD)，sessionId头；DTO为id/courseName/classBeginTime/classEndTime/signStatus | POST，同参数在查询串；状态字符串转bool | 保持旧版GET与会话头；原unknown资格保护保持 |
| 时间戳 | GET Direct http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action；WebVPN包装https://iclass.buaa.edu.cn:8347/app/common/get_timestamp.action；无业务参数/会话头；读取timestamp primitive.content | POST并携带id、会话头；从JSON数字文本提取timestamp | 保留旧版GET与端口，兼容整数和字符串 |
| 提交 | POST Direct http://iclass.buaa.edu.cn:8081/eschool/app/course/stu_scan_sign.action；WebVPN包装https://iclass.buaa.edu.cn:8347/app/course/stu_scan_sign.action；查询courseSchedId/timestamp，表单id，sessionId头，application/x-www-form-urlencoded | id在查询串；WebVPN仍带eschool | 保留工作区已有的旧版端口/路径修正，按旧版表单提交 |
| 提交响应 | 顶层STATUS支持0/200/success（数字或文本）；result.stuSignStatus为1才成功 | STATUS字符串0、stuSignStatus字符串1 | 保持旧版业务判定；不透传原始ERRMSG |

各操作无新增加密或签名常量。Cookie仍按现有Direct/WebVPN运行时隔离，业务会话仅在内存缓存，以登录锁防并发和generation防失效后回填。旧版按学号缓存，buaa-api凭据可跨路线复用；本轮不放宽路线隔离。旧版查询异常可能吞为成功空列表，写入登录错误可能自动重放；UBAA2仍明确报错，保留写前资格复核、单次提交和outcome_unknown不可自动重试，不复制旧版的非幂等重发。

实测（修改前）：Direct/WebVPN各自认证与今日查询通过；Direct时间戳GET返回HTTP 200，timestamp类型为整数。仅输出类型和状态，没有保存原始正文。现有parse_timestamp仅接受字符串，故数字响应会在写前被错误拒绝。登录差异按用户指定的旧版权威裁决，查询成功不被用于证明混用协议正确。

#### 验证记录

- RED：旧版登录入口断言及整数时间戳测试均失败（4通过、2失败）；双路线写入回归因错误登录路径而失败（1通过、9失败）。未保存真实响应作为fixture。
- GREEN：Core签到单元14项、双路线写入流程10项、Bridge签到6项通过；Mock中的loginName、业务id、sessionId、排课id分别使用不同脱敏值，时间戳使用JSON整数，校验旧版登录端口、参数及后续会话头。
- 修改后Core-live：Direct/WebVPN各自认证、状态和今日查询全部PASS，均读到2条课程。
- 用户追加明确授权“这次进行真实签到提交测试，就签当前在上的课”。北京时间17:11核对唯一处于上课时间且可签到的目标，使用修复后的CLI在Direct路线提交一次；业务success=true、code=200，独立回读目标signStatus由0变1、资格变为denied。该证据仅证明Direct真实提交，不冒充WebVPN写入或原生App验收。
- 真实提交使用新建私有临时会话目录，凭据经stdin传入，原始响应只在内存处理，任务结束删除临时会话；不记录课程名称、排课标识、账号或会话字段。既有账户会话未改写。
- 全量Core-live：`just verify-live mode=direct` 与 `mode=webvpn` 均退出0；WebVPN希冀详情和批量详情因当前列表为空为NOT_APPLICABLE，其余操作PASS。所有实时过程均保持TLS验证。
- 完整门禁首次因工作区已有传输WARN日志导致3项CLI JSON stderr断言失败；将日志改为`ubaa::transport` DEBUG，仅保留方法、超时/连接分类、HTTP状态、字节数和耗时，不输出URL或原始错误。完整`just check`复跑退出0（包含CLI端到端16项、Core/Bridge测试、Clippy、构建及文档检查）；`just refs`、`just layout-check`、`just check-sensitive`均通过。

### 2026-11-19 签到提交改用 `stu_auto_sign`

本节覆盖课堂签到写入操作。冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 `examples/buaa-api` 固定提交 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 均没有 `stu_auto_sign` 协议；两份来源对该操作的九列均记为“不适用”。本次裁决以用户提供的 2026-11-19 脱敏抓包摘要这一真实上游证据为准，不把 HAR、业务标识、会话标识或原始响应写入仓库。

| 操作 | 业务 CAS/引导 URL 与 service | 重定向与最终 URL | Cookie、Session、Token 的作用域 | HTTP 方法与精确参数 | 请求头与正文编码 | 加密与签名常量 | DTO 与解析字段、类型 | 缓存、并发、重试 | 错误、退出与产品语义 |
|---|---|---|---|---|---|---|---|---|---|---|
| `stu_auto_sign` 签到提交 | 不适用。冻结旧版与 `buaa-api` 均没有 `stu_auto_sign` 操作；业务登录继续沿用既有 `8346` 引导和 `8347/app/user/login.action`，本次不改登录。 | Direct 请求 `https://iclass.buaa.edu.cn:8181/app/course/stu_auto_sign.action`。WebVPN 使用现有 `to_webvpn_url` 包装同一 `8181` HTTPS 地址；WebVPN 提交尚未真实验证。 | 按 [RFC 6265 §8.5](https://www.rfc-editor.org/rfc/rfc6265#section-8.5)，Cookie 不按端口隔离。官方客户端抓包未携带 Cookie，但 2026-11-19 两次只读实测均使用带同主机 Cookie 的 Cookie jar 访问 8181，业务登录、今日课表、签到时间窗和我的课程均返回 `STATUS=0`；因此沿用共享传输的既有 Cookie 行为，不将“抓包无 Cookie”解释为禁止携带 Cookie。业务会话仍使用内存中的 `id` 与 `sessionId`；`sessionId` 通过请求头发送，主认证会话、登录锁和 generation 规则不变。 | `POST`，无查询串。表单恰好六个字段：`id`、`courseSchedId`、`routerInfo=02:00:00:00:00:00`、`longitude=0`、`latitude=0`、`machineInfo=Android`。不发送时间戳。 | 请求头包含正确的 `sessionId` 和 `Content-Type: application/x-www-form-urlencoded`。沿用 Core 既有 User-Agent 约定，不伪造官方学生端 UA。 | 不适用。 | 成功判定沿用 `parse_action_response`：`STATUS` 为 `0`、`200`（兼容数字字符串）或 `success`，且 `result.stuSignStatus` 为 `1`（兼容数字字符串）时返回成功。明确的业务失败状态或 `stuSignStatus=0` 返回失败；无法解析的写后结果归为 `outcome_unknown`。 | 写前重新读取今日课表并复核唯一排课目标和 `signStatus=0`；通过现有单次非幂等提交边界发送；不缓存写请求，不自动重试。 | 旧 `stu_scan_sign` 提交因用户确认不可用而停用；二维码读取仍保留旧时间戳接口。HTTP、传输、认证落点或响应无法确定时返回 `outcome_unknown`，先回读今日状态再决定是否重试。 |

业务登录、会话缓存、登录锁和 generation 沿用既有裁决。真实上游摘要证明了 Direct `8181` 的提交参数和成功响应；WebVPN 只完成地址构造与 Mock 验证，未声称真实通过。

### 2026-11-19 签到二维码展示

冻结旧版（`1f4b8f8412272b6a423d4ad92b396e3db721e6f3`）对照 `LocalSigninApi.kt` 和 `LocalSigninApiBackendTest.kt`；buaa-api（`a63712fa2ae0a6c8066197063ddee98e3a6b5b81`）对照 `src/api/class/{core,opt,data}.rs`。时间戳沿用 2026-09-17 裁决，buaa-api 的 POST、`id` 和 `Sessionid` 差异已在该处记录。两份冻结来源的二维码生成均不适用：只实现提交。二维码内容依据非冻结参考 `zeroduhyy/iclass_buaa` 的 `80a90f8c1dc55513e3f180f2729cc01775d774f2`：`server/src/services/courseService.ts` 的 `generateSignQrForFrontend`、`client/src/pages/CalendarPage.tsx`。

| 操作 | 业务 CAS/引导与 service | 重定向与最终 URL | Cookie、Session、Token | HTTP 方法与参数 | 请求头与正文 | 加密与签名 | 字段与类型 | 缓存、并发、重试 | 错误、退出与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| 读取时间戳 | 要求主认证有效，不执行 iClass 业务登录，无新增 service | Direct 为 `http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action`；WebVPN 包装 `https://iclass.buaa.edu.cn:8347/app/common/get_timestamp.action`，沿用现有请求行为 | Cookie 按路线隔离，不读取 iClass 业务凭据 | GET，无业务参数 | 无业务会话头，无正文 | 无新增常量 | `timestamp` 为毫秒 epoch，接受 JSON 整数和数字字符串 | 每次读取，不缓存，沿用只读路线与重试策略 | 未认证返回认证错误；网络、HTTP 失败和解析错误按现有语义返回，不使用本机时间回退 |
| 生成二维码内容 | 本地生成，无 CAS | 两条路线均生成 Direct 形式 `http://iclass.buaa.edu.cn:8081/eschool/app/course/stu_scan_sign.action` | 不拼接 Cookie、会话或令牌 | 不发送请求；查询串为 `courseSchedId` 和 `timestamp` | 查询参数经 URL 编码，无请求头或正文 | 无 | 返回 `content` 和加偏移后的整数 `timestamp`；偏移范围为 0 至 60,000 毫秒 | 实时面板每 2 秒读取；保存时独立读取一次 | 空课程安排 ID 或超限偏移返回参数错误；二维码交给 iClass App 或微信扫码 |

参考仓库的实时二维码使用服务器原值，每 2 秒刷新。偏移和刷新间隔按用户指定的产品取舍实现，无冻结来源依据：实时偏移为 0，保存偏移为 2,000 毫秒。二维码使用独立的时间戳读取入口。应用内直接提交使用 `stu_auto_sign`，见[签到提交协议](#2026-11-19-签到提交改用-stu_auto_sign)。

二维码面板打开时，若课程尚未签到，前台每 3 秒复用今日签到在线查询，回到前台时立即查询一次。查询按排课 ID 匹配结果，更新签到列表。确认已签到后关闭面板。

本轮不发真实账号请求。二维码内容及 Direct/WebVPN 时间戳路线用合成响应验证；两条路线的新操作均未实测，取得对应路线的只读授权后再验收。
