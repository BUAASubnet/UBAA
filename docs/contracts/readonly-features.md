# 只读功能合同

状态：只读实现及隐藏安全诊断均有确定性覆盖；Direct/WebVPN 的真实结果由当前
`core-live` 逐操作记录，`auto` 只保留确定性路由证据。历史实时快照漂移和上游失败
继续保留在迁移状态中，不用聚合成功掩盖单项失败。

CLI 只暴露下列 Core facade 方法。宿主不得导入 `upstream`、拼接上游 URL、探测网关
或自行选择路线；结果由 Core 生成稳定 DTO 和安全路线元数据。原始 HTML、加密参数、
Token、Cookie 和响应正文始终留在 Core 内部，Cgyy 锁码仅投影为 `available`。

| Feature | CLI | Facade | Frozen request evidence |
|---|---|---|---|
| Schedule | `schedule terms`, `weeks`, `current`, `today` | `schedule_terms`, `schedule_weeks`, `schedule_week`, `schedule_today` | `schoolCalendars.do`, `getTermWeeks.do`, `getMyScheduleDetail.do`, `teachingSchedule/detail.do`; `Schedule.kt` |
| Exam | `exam list --term` | `exam_arrangement` | `student/exams.do`; `Exam.kt` |
| Grades | `grades list --term` | `grades` | `buaascore/wap/default/index`, activation GET then `xq`/`year` form POST; `Grade.kt` |
| Classroom | `classroom search --campus --date` | `classroom_search` | SSO sync URL then `buaafreeclass/.../search1?xqid=&floorid=&date=`; `Classroom.kt` |
| SPOC | `spoc assignments`, `spoc assignment show --id` | `spoc_assignments`, `spoc_assignment` | current-term; optional course metadata; global encrypted `queryListByPage` with `kcid=""`; detail and optional submission endpoints; `Spoc.kt` |
| Judge | `judge assignments`, assignment `show`/`details` | `judge_assignments`, `judge_assignment`, `judge_assignment_details` | SSO service, course/assignment HTML links and detail pages; `Judge.kt` |
| Signin | `signin today` | `signin_today` | iClass 8346 跳转、8347 业务登录及今日课堂查询；`Signin.kt` |
| LibBook | `libbook libraries`, `areas`, `area-detail`, `seats`, `bookings` | `libbook_libraries`, `libbook_areas`, `libbook_area_detail`, `libbook_seats`, `libbook_bookings` | 图书馆 CAS 换票、独立 token 及五类座位只读接口；`LibBook.kt` |

Schedule term values and week serials are selected from the upstream response. Grades reject terms that do not match `yyyy-yyyy-semester`. Classroom dates must use `yyyy-mm-dd`; `UBAA_VERIFY_CAMPUS_ID` and `UBAA_VERIFY_DATE` are non-secret live-verifier overrides. Empty lists and empty classroom maps are valid only after the authoritative operation was actually requested and its required wrapper parsed; an unsupported undergraduate portal or missing account capability is a real, nonzero live failure.

实现严格沿用冻结只读路径，包括 AAS CAS 激活、课表表单、SPOC 加密全局分页、业务
认证失效的一次刷新、东八区时间、可选回退、HTML 文本化以及 Judge 详情/题目解析。
SPOC HTML 不进入公共 DTO。Fixture/Mock 只证明请求形状；真实证据以
`docs/migration/status.md` 中 Core-live 的 Direct/WebVPN 逐操作记录为准。
`examples/buaa-api` 的其它协议不能替代本地 API。任何提交、上传、预约、签到、评教
或其它写操作都不在只读入口中。

## Verification-only diagnostics

The hidden `spoc diagnostics` and `judge diagnostics` CLI commands call separate facade methods intended only for deterministic tests and live verification. They do not add a business request, accept a URL, reveal upstream internals, or alter the stable user command surface. They emit the same schema-v2 routed envelope as ordinary reads and must remain on the same resolved route for the complete feature run.

SPOC diagnostics return exactly `globalPageCount` plus the ordinary `result`. The count is a positive `u32` and proves that the authoritative encrypted global page operation completed, so an empty assignment result is distinguishable from a skipped request. A list summary with `UNKNOWN` status must retain a nonempty unknown raw value as `未知状态(<raw>)`; the six known submitted/unsubmitted values can never appear inside that form. Detail may use bare `未知状态` when no submission raw value exists, but parenthesized detail text follows the same exclusion. A sampled detail must preserve both the list item's `assignmentId` and `courseId`; an empty course ID remains valid because it is optional in the frozen list protocol.

Judge diagnostics return `courseCount`, `rawAnchorCount`, `filteredUniqueCount`, and the ordinary `summaries`; they expose neither raw anchors nor any new identity/body field. Public Judge IDs remain nonempty digit strings, preserve leading zeroes and Unicode digits, and are never converted to bounded JSON integers; only the exact course ID `"0"` is excluded by the parser. DTO `totalProblems` and `submittedCount` retain their nonnegative `i32` bounds, while diagnostic `usize` counts are accepted only through JSON's exact-integer ceiling. Problem rows use only `SUBMITTED` or `UNSUBMITTED`; a four-cell upstream row may have an empty problem name. The live verifier compares current and include-expired lists through jq stdin rather than process arguments, validates one detail when available, and outputs only counts plus a salted digest. The digest salt is mandatory for Judge/all verification and is never persisted by the application.
