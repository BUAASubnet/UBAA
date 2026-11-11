# 2026-09-17 课堂签到修复对照

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

## 验证记录

- RED：旧版登录入口断言及整数时间戳测试均失败（4通过、2失败）；双路线写入回归因错误登录路径而失败（1通过、9失败）。未保存真实响应作为fixture。
- GREEN：Core签到单元14项、双路线写入流程10项、Bridge签到6项通过；Mock中的loginName、业务id、sessionId、排课id分别使用不同脱敏值，时间戳使用JSON整数，校验旧版登录端口、参数及后续会话头。
- 修改后Core-live：Direct/WebVPN各自认证、状态和今日查询全部PASS，均读到2条课程。
- 用户追加明确授权“这次进行真实签到提交测试，就签当前在上的课”。北京时间17:11核对唯一处于上课时间且可签到的目标，使用修复后的CLI在Direct路线提交一次；业务success=true、code=200，独立回读目标signStatus由0变1、资格变为denied。该证据仅证明Direct真实提交，不冒充WebVPN写入或原生App验收。
- 真实提交使用新建私有临时会话目录，凭据经stdin传入，原始响应只在内存处理，任务结束删除临时会话；不记录课程名称、排课标识、账号或会话字段。既有账户会话未改写。
- 全量Core-live：`just verify-live mode=direct` 与 `mode=webvpn` 均退出0；WebVPN希冀详情和批量详情因当前列表为空为NOT_APPLICABLE，其余操作PASS。所有实时过程均保持TLS验证。
- 完整门禁首次因工作区已有传输WARN日志导致3项CLI JSON stderr断言失败；将日志改为`ubaa::transport` DEBUG，仅保留方法、超时/连接分类、HTTP状态、字节数和耗时，不输出URL或原始错误。完整`just check`复跑退出0（包含CLI端到端16项、Core/Bridge测试、Clippy、构建及文档检查）；`just refs`、`just layout-check`、`just check-sensitive`均通过。
