# 只读功能合同

本合同供修改学校只读功能的开发者使用，列出每个功能的 CLI 命令、facade 方法、冻结请求证据、公开 DTO 与隐藏诊断规则。

CLI 只通过 Core facade 访问下列标准和扩展只读方法：

- 宿主不导入 `upstream`、不拼接上游 URL、不探测网关，也不自行选择路线；结果由 Core 生成稳定 DTO 和安全路线元数据。
- 原始 HTML、加密参数、Token、Cookie 和响应正文始终留在 Core 内部，Cgyy 锁码仅投影为 `available`。
- Direct/WebVPN 的真实结果由 `core-live` 逐操作记录，`auto` 只有确定性路由证据；聚合成功不能掩盖单项失败。实际结果见[状态页](../project/status.md)。

## 门户账户与网络流量

`portal profile`、`portal metrics`、`network usage` 为在线只读命令，分别调用 `portal_profile()`、`campus_metrics()`、`network_usage()`。CLI 及单路线诊断客户端均通过 facade 接入，普通 CLI 的路线由 Core 决定。配置 `[route.features]` 可以分别设置 `portal`、`network`，取值为 `direct`、`webvpn` 或 `auto`。

| 返回类型 | 公开字段与含义 |
|---|---|
| `PortalProfile` | `identity`、`department`、`fetchedAt`，分别表示门户身份、学院及 Unix 秒取得时间。资料不作为认证资格。 |
| `CampusMetrics` | `networkBalance`、`cardBalance`、`unreadMail`、`borrowedBooks`、`cloudStorageRemaining`。云盘字段表示剩余空间。 |
| `CampusMetric<T>` | `status=success` 时包含 `value` 和 `fetchedAt`，`status=failure` 时包含安全 `error` 和 `fetchedAt`。有效零值为成功，单项失败保留其他项。 |
| `CampusAmount` | `value` 为十进制字符串，`unit` 为上游单位，可为空；金额和容量不经过浮点换算。邮件、图书数量直接采用非负整数。 |
| `NetworkUsage` | `products`、`remainingExcludesPackages=true`、`fetchedAt`。每产品提供 `productName`、`used`、`freeRemaining`、`billableRemaining`，三项流量使用 `CampusAmount`。 |

错误分级：

- 业务认证或公共配置失败返回整体错误；指标服务、字段或格式失败记录在对应指标。
- 会话所有权冲突立即终止，不作为部分成功。
- 部分指标失败时命令仍返回成功信封，调用方须检查各项 `status`；Core-live 将任何失败项单独记为 FAIL。

原始 Cookie、CAS ticket、配置 ID、跳转 URL、上游消息与 HTML 不进入 DTO。网络两项剩余量均不含套餐，不合计成总剩余量。图书只有数量，不推断书目和到期日。

三个命令为兼容性新增，沿用 CLI JSON schema v14 的信封；Schema 为 `portal`、`network` 增加独立且封闭的数据定义，既有命令的 DTO 不变。本阶段不增加业务快照磁盘格式或 Bridge API。来源、精确参数及失败边界见[门户与网费来源对照](../protocol/parity/campus.md)。

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

LibBook booking 的公开 `status` 为 nullable int，并由 Core 派生 `cancelEligibility/cancelTarget`；`statusName` 只用于展示，宿主只从 typed 资格判断能否取消，不从文案或原始状态反推。取消 action 保存当前 `page/limit`，prepare、commit 与写后读取核对都使用同一页；这些本地 authority 字段不进入最终取消 wire，最终正文仍只有预约 `id`。

扩展写命令（包括 Cgyy 预约/取消）不属于只读合同。它们虽然有 Core/CLI 协议实现，仍必须经过显式确认；真实验证入口永久阻止这些命令，只有 Mock、Fixture 和向量证据可以证明。

输入与空结果：

- 课表学期值和周序号从上游响应中选择。成绩功能拒绝不符合 `yyyy-yyyy-semester` 的学期。
- 空闲教室日期必须使用 `yyyy-mm-dd`；`UBAA_VERIFY_CAMPUS_ID` 和 `UBAA_VERIFY_DATE` 是不含秘密的实时验证覆盖项。
- 只有在确实请求了权威操作并成功解析所需包装后，空列表和空教室映射才是有效结果；本科门户不支持或账号不具备相应能力，都必须作为非零实时失败记录。

实现与证据：

- 实现严格沿用冻结只读路径，包括 AAS CAS 激活、课表表单、SPOC 加密全局分页、业务认证失效的一次刷新、东八区时间、可选回退、HTML 文本化以及 Judge 详情/题目解析。
- SPOC HTML 不进入公共 DTO。
- Fixture/Mock 只证明请求形状；真实证据以[状态页](../project/status.md)中 Core-live 的 Direct/WebVPN 逐操作记录为准。
- `examples/buaa-api` 的其它协议不能替代本地 API。
- 任何提交、上传、预约、签到、评教或其它写操作都不在只读入口中。

## 仅供验证的诊断

隐藏的 `spoc diagnostics` 和 `judge diagnostics` CLI 命令调用独立 facade 方法，仅供确定性测试和实时验证使用。它们不增加业务请求、不接受 URL、不暴露上游内部信息，也不改变稳定用户命令面。输出与普通读取相同的 schema-v16 路由 envelope，并且一次完整功能运行必须保持同一条已解析路线。

SPOC 诊断：

- 恰好返回 `globalPageCount` 和普通 `result`。该计数为正 `u32`，证明权威加密全局分页操作确实完成，因此可以区分“作业结果为空”和“跳过请求”。
- 列表摘要为 `UNKNOWN` 时必须保留非空未知原值并显示为 `未知状态(<raw>)`；六个已知的已提交/未提交值不能出现在该形式中。
- 没有提交原值时详情可使用不带括号的 `未知状态`，有原值时仍遵守同一排除规则。
- 抽样详情必须同时保留列表项的 `assignmentId` 和 `courseId`；冻结列表协议中课程 ID 可选，因此空课程 ID 仍然有效。

Judge 诊断：

- 返回 `courseCount`、`rawAnchorCount`、`filteredUniqueCount` 和普通 `summaries`，不暴露原始锚点或新增身份/正文字段。
- 公开 Judge ID 必须是非空数字字符串，保留前导零和 Unicode 数字，不转换为有界 JSON 整数；解析器只排除精确课程 ID `"0"`。
- DTO 的 `totalProblems` 和 `submittedCount` 保持非负 `i32` 边界，诊断 `usize` 计数仅在 JSON 安全整数范围内接受。
- 题目行只使用 `SUBMITTED` 或 `UNSUBMITTED`；四单元上游行的题目名称可以为空。
- Core-live 直接以安全键值摘要输出这些字段，不解析或保存原始 JSON；实时验证器不依赖 jq、摘要盐或进程参数中的敏感值。
- `auth/prepare` 必须先于 `auth/login`，并记录 `mapping=embedded_login_state`；登录失败时所有依赖认证的操作都必须逐项输出 `BLOCKED(reason=authentication_failed)`，不能用汇总成功掩盖失败。

Cgyy 目的类型诊断返回 `items` 与 `source`：

- `source=upstream` 表示本次请求和解析成功；`source=static_fallback` 表示请求失败或上游返回空集合而使用冻结静态列表。两者都不把原始响应投影到宿主。
- Cgyy 锁码仍只公开 `available`，真实验证永远不调用预约、取消或锁码写入口。

## GSMIS研究生课表

课表、成绩和考试统一使用 `it.buaa.edu.cn/personal/frontend/data/info` 的 `d.info.identity` 分流：

- 本科生使用现有本科接口，研究生、硕士研究生和博士研究生使用 GSMIS。
- 未知身份明确返回 `unsupported`，门户失败不查询教务；不按学号、学期编码或业务错误切换学籍系统。
- 身份按路线和认证代次复用，清理会话后重新获取。
- 门户可达性是在线学业查询的前提，Auto 仍沿现有规则选择 Direct/WebVPN。

研究生课表保留学期完整性、排课班号、唯一校历周一和节次核对，以及唯一作息方案补全。

成绩总览 `grades overview` / `grades_overview`：

- 返回完整历史成绩、成绩自身的学期与全局/分学期统计；本科返回 `graduate=false`，继续原逐学期查询。
- GPA 与均分分别使用有效正学分作为分母，缺少有效分母时为 null。界面只展示 Core 统计，不按本科等级规则重算研究生成绩。
- 历史成绩中最近学期不自动标为当前学期，也不据此启动当前学期成绩通知。

考试学期 `exam terms` / `exam_terms`：

- 返回考试系统学期；研究生考试三项计数均为零才返回空，非空明细返回 `unsupported`。
- 考试学期缓存使用独立键，不借课表学期。
- 单学期成绩的可空 `statistics` 随原缓存保存，旧记录缺字段按 null 读取。

以上在 CLI schema v14、Bridge v56 引入；缓存键和可空字段为追加，业务库版本保持 v8。来源与真实验证边界见[GSMIS逐操作对照](../protocol/parity/gsmis.md)。


## iHome

`ubaa ihome list` 默认读取公共诉求；`--scope mine|followed|appraised` 切换个人列表，`--page` 和 `--limit` 控制分页，公共列表支持 `--keyword`、`--category-id` 与 `--filter`。`detail <id> --mine` 使用本人详情路径；`config`、`notices` 和 `notice <id>` 读取配置与公告。普通详情省略 `--mine`。CLI不开放关注或支持写入。

数据只包含诉求、部门回复、评价、当前轮次进度和明确的状态/数量；原始用户对象、联系方式字段和业务令牌不进入合同。DTO及来源矩阵见 [iHome对照](../protocol/parity/ihome.md)。

## 财务收入

`finance incomes` 读取财务查询系统当前返回范围，只有全部分页完整成功才返回。公开字段包含流水号、项目、摘要、录入日期、年月、金额、税额、实发金额和税率展示值。金额使用整数分，零与缺失分别保留。该接口不提供银行到账确认。

Core 的 `finance_incomes` 提供在线数据，`refresh_cached_finance` 和 `read_finance` 复用账号加密缓存。App 的 `FinanceService.refresh/cached` 由 `AppController.financeService` 提供，账号或路线代次变化后拒绝旧绑定。

共享界面在“校园”页提供“财务查询”入口，先显示离线记录再读取在线结果，按所属年月分组并合计实发金额；页面注明录入记录不代表银行到账。

API Token 仅存路线内存，退出或会话失效即清除。查询只使用已认证财务跳转取得的账号，不接受任意用户编号。证件、银行账号和原始响应不进入 DTO、命令输出或缓存。来源见[财务对照](../protocol/parity/campus.md#财务收入查询2026-11-08)。
