# 课堂签到

本文件收录 iClass 课堂签到查询、签到提交与业务会话的来源对照。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### 课堂签到今日查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**先访问 `https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter`，再调用 8347 的 `app/user/login.action` 和 `app/course/get_stu_course_sched.action`。**示例：**等价 Class 模块在固定提交中将登录更新为 8346 的 `eschool/app/user/login_buaa.do`，今日查询仍使用 8347 的 `app/course/get_stu_course_sched.action`。**决定：**2026-08-28 Direct 真实运行证明旧登录入口返回 `upstream_changed`，采用示例中更晚且等价的登录入口；查询入口保持旧版。 | **旧版：**最多跟随 8 次跳转，从最终 URL 或 `Location` 中提取大小写不敏感的 `loginName`，并进行百分号解码；Direct/WebVPN 始终保持当前路线。**示例：**登录前同样从 8346 跳转结果提取 `loginName`。**决定：**使用 Core 的手动、允许主机列表跳转，不接受未知主机。 | **旧版：**主认证 Cookie 与 iClass `id/sessionId` 分离；业务会话按学生标识缓存。**示例：**同样维护独立 Class 凭据。**决定：**iClass 会话是每个路线/客户端的进程内状态，不能写入 `session.json`，也不能跨路线复用。 | **旧版：**登录 GET 参数为 `password=""`、`phone=loginName`、`userLevel=1`、`verificationType=2`、`verificationUrl=""`；今日查询 GET 参数为 `id=userId`、`dateStr=yyyyMMdd`。**示例：**登录和查询参数与旧版一致。**决定：**保持完整参数和值，不增加字段。 | **旧版：**今日查询使用 `sessionId` 请求头；请求无正文。**示例：**使用等价会话值作为 `Sessionid`，查询为 POST 并将 `dateStr` 放在 query；**决定：**本轮仅由真实失败证明登录入口变化，查询方法仍保持冻结旧版 GET，除非后续真实证据要求调整。 | **旧版/示例：**无加密。**决定：**不得引入自定义加密或签名。 | **旧版：**`STATUS` 接受字符串或整数；成功值为 `0`、`200`、`success`。今日课程字段为 `id`、`courseName`、`classBeginTime`、`classEndTime`、`signStatus`，状态兼容字符串或整数；提交结果才使用嵌套 `result.stuSignStatus`。**示例：**`STATUS=2` 表示空列表。**决定：**公共 DTO 仅暴露对应稳定字段和 typed 资格，不暴露包装、业务会话或原始响应；空列表语义需以真实响应确认。 | **旧版：**按学生标识缓存业务会话；会话失效后最多刷新一次。**示例：**Class 凭据独立缓存。**决定：**使用路线内登录锁和失效代数，主会话清理时同步清除；并发失效后旧任务不得重新写入。 | **旧版：**未认证返回认证错误；iClass 登录失败时查询退化为空成功，这是旧 UI 的容错行为。**示例：**业务失败上抛。**决定：**Core 不伪造空成功；无法建立业务会话返回稳定上游错误，业务会话失效只清除签到状态，只有 User Center 明确失效才清除主认证。 |

当前实现证据：`crates/ubaa_core/tests/signin.rs` 已覆盖冻结响应的字符串/整数状态解析及独立 iClass 会话；Core facade 和 `signin today` CLI 已接入。固定 `examples/buaa-api` 的 Class 模块提供补充登录入口证据，但其查询方法/请求头与冻结旧版不等价；Rust Core 按冻结旧版使用 GET、`sessionId` 头并将 `id/dateStr` 放在 query。`STATUS=2` 表示今日无课程的合法空结果。2026-08-28 Direct 与 WebVPN 实时验证均通过并返回空列表。

### Signin 时间戳与签到端口、路径及会话解析校正

当前实现与逐操作裁决见[2026-09-17 签到修正记录](#2026-09-17-课堂签到修复对照)。该记录保留当时的来源提交，不将后续引用更新冒充重新完成的协议对照。

- 业务登录采用旧版 `8347/app/user/login.action`，必须返回有效业务 `id` 和 `sessionId`，不允许以 `loginName` 回退。
- 时间戳采用 GET，接受 JSON 整数或字符串；Direct 使用 HTTP 8081，WebVPN 使用包装后的 HTTPS 8347。
- 签到 POST 的 Direct 路径带 `/eschool`，WebVPN 8347 路径不带该前缀；`courseSchedId/timestamp` 在查询串，业务 `id` 在表单，业务 `sessionId` 在请求头。
- 两份来源的方法、参数载体及会话语义存在差异，按已记录的旧版权威裁决，不再称为“全面对齐两份来源”。

## 专项记录

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
