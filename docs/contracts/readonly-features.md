# 只读功能合同

状态：只读实现及隐藏安全诊断均有确定性覆盖；Direct/WebVPN 的真实结果由当前
`core-live` 逐操作记录，`auto` 只保留确定性路由证据。历史实时快照漂移和上游失败
继续保留在迁移状态中，不用聚合成功掩盖单项失败。

CLI 只通过 Core facade 访问下列标准和扩展只读方法。宿主不得导入 `upstream`、拼接
上游 URL、探测网关或自行选择路线；结果由 Core 生成稳定 DTO 和安全路线元数据。原始
HTML、加密参数、Token、Cookie 和响应正文始终留在 Core 内部，Cgyy 锁码仅投影为
`available`。

## 标准只读功能

| Feature | CLI | Facade | Frozen request evidence |
|---|---|---|---|
| Schedule | `schedule terms`, `weeks`, `current`, `today` | `schedule_terms`, `schedule_weeks`, `schedule_week`, `schedule_today` | `schoolCalendars.do`, `getTermWeeks.do`, `getMyScheduleDetail.do`, `teachingSchedule/detail.do`; `Schedule.kt` |
| Exam | `exam list --term` | `exam_arrangement` | `student/exams.do`; `Exam.kt` |
| Grades | `grades list --term` | `grades` | `buaascore/wap/default/index`, activation GET then `xq`/`year` form POST; `Grade.kt` |
| Classroom | `classroom search --campus --date` | `classroom_search` | SSO sync URL then `buaafreeclass/.../search1?xqid=&floorid=&date=`; `Classroom.kt` |
| SPOC | `spoc assignments`, `spoc assignment show --id` | `spoc_assignments`, `spoc_assignment` | current-term; optional course metadata; global encrypted `queryListByPage` with `kcid=""`; detail and optional submission endpoints; `Spoc.kt` |
| Judge | `judge assignments`, assignment `show`/`details` | `judge_assignments`, `judge_assignment`, `judge_assignment_details` | SSO service, course/assignment HTML links and detail pages; `Judge.kt` |

## 扩展只读功能

| 功能 | CLI 只读命令 | Facade 方法 |
|---|---|---|
| Signin | `signin today` | `signin_today` |
| LibBook | `libbook libraries`, `areas`, `area-detail`, `seats`, `bookings` | 对应 `libbook_*` 读取方法 |
| Ygdk | `ygdk overview`, `ygdk records` | `ygdk_overview`, `ygdk_records` |
| Bykc | `bykc profile`, `courses`, `course`, `chosen`, `statistics` | 对应 `bykc_*` 读取方法 |
| Cgyy | `cgyy sites`, `purposes`, `day`, `orders`, `detail`, `lock-code` | 对应 `cgyy_*` 读取方法 |
| Evaluation | `evaluation all`, `pending` | `evaluation_all` |

`evaluation pending` 是 CLI 对 `evaluation_all` 返回的 `is_evaluated=false` 课程进行的本地
派生视图，不存在独立的 `evaluation_pending` facade 或 bridge 方法。

LibBook booking 的公开 `status` 为 nullable int，并由 Core 派生
`cancelEligibility/cancelTarget`；`statusName` 只用于展示，宿主不得从文案或原始状态反推取消资格。
取消 action 保存当前 `page/limit`，prepare、commit 与写后读取核对都使用同一页；这些本地 authority
字段不会进入最终取消 wire，最终正文仍只有预约 `id`。

扩展写命令（包括 Cgyy 预约/取消）不属于只读合同；它们虽然有 Core/CLI 协议实现，仍
必须经过显式确认，真实验证入口永久阻止，只有 Mock、Fixture 和向量证据可以证明。

课表学期值和周序号从上游响应中选择。成绩功能拒绝不符合 `yyyy-yyyy-semester` 的学期。
空闲教室日期必须使用 `yyyy-mm-dd`；`UBAA_VERIFY_CAMPUS_ID` 和 `UBAA_VERIFY_DATE` 是
不含秘密的实时验证覆盖项。只有在确实请求了权威操作并成功解析所需包装后，空列表和空教室
映射才是有效结果；本科门户不支持或账号不具备相应能力，都必须作为非零实时失败记录。

实现严格沿用冻结只读路径，包括 AAS CAS 激活、课表表单、SPOC 加密全局分页、业务
认证失效的一次刷新、东八区时间、可选回退、HTML 文本化以及 Judge 详情/题目解析。
SPOC HTML 不进入公共 DTO。Fixture/Mock 只证明请求形状；真实证据以
`docs/migration/status.md` 中 Core-live 的 Direct/WebVPN 逐操作记录为准。
`examples/buaa-api` 的其它协议不能替代本地 API。任何提交、上传、预约、签到、评教
或其它写操作都不在只读入口中。

## 仅供验证的诊断

隐藏的 `spoc diagnostics` 和 `judge diagnostics` CLI 命令调用独立 facade 方法，仅供确定性
测试和实时验证使用。它们不增加业务请求、不接受 URL、不暴露上游内部信息，也不改变稳定用户
命令面。输出与普通读取相同的 schema-v10 路由 envelope，并且一次完整功能运行必须保持同一
条已解析路线。

SPOC 诊断恰好返回 `globalPageCount` 和普通 `result`。该计数为正 `u32`，证明权威加密全局
分页操作确实完成，因此可以区分“作业结果为空”和“跳过请求”。列表摘要为 `UNKNOWN` 时
必须保留非空未知原值并显示为 `未知状态(<raw>)`；六个已知的已提交/未提交值不能出现在该
形式中。没有提交原值时详情可使用不带括号的 `未知状态`，有原值时仍遵守同一排除规则。
抽样详情必须同时保留列表项的 `assignmentId` 和 `courseId`；冻结列表协议中课程 ID 可选，
因此空课程 ID 仍然有效。

Judge 诊断返回 `courseCount`、`rawAnchorCount`、`filteredUniqueCount` 和普通 `summaries`，
不暴露原始锚点或新增身份/正文字段。公开 Judge ID 必须是非空数字字符串，保留前导零和
Unicode 数字，不能转换为有界 JSON 整数；解析器只排除精确课程 ID `"0"`。DTO 的
`totalProblems` 和 `submittedCount` 保持非负 `i32` 边界，诊断 `usize` 计数仅在 JSON 安全
整数范围内接受。题目行只使用 `SUBMITTED` 或 `UNSUBMITTED`；四单元上游行的题目名称可以
为空。Core-live 直接以安全键值摘要输出这些字段，不解析或保存原始 JSON；实时验证器不再依赖
jq、摘要盐或进程参数中的敏感值。`auth/prepare` 必须先于 `auth/login`，并记录
`mapping=embedded_login_state`；登录失败时所有依赖认证的操作都必须逐项输出
`BLOCKED(reason=authentication_failed)`，不能用汇总成功掩盖失败。

Cgyy 目的类型诊断返回 `items` 与 `source`。`source=upstream` 表示本次请求和解析成功，
`source=static_fallback` 表示请求失败或上游返回空集合而使用冻结静态列表；两者都不得把
原始响应投影到宿主。Cgyy 锁码仍只公开 `available`，真实验证永远不调用预约、取消或锁码
写入口。
