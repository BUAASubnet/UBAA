# P4-C 展示来源补充

2026-09-08 静态核对。主仓 HEAD 为 `83ee9e8969b25ca6fdce67ce61a79b86031b573b`，工作区 B2 候选并行进行；冻结 old=`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`、examples=`efb7976bf513f38364b88aeb83d704586cff9b2a`。本文路径相对 `/Users/moorefoss/Code/UBAA`，行号来自本次读取。本文件记录静态核对，不声明实时/渲染 PASS；P4-C生产实现尚未开始。

## 签到：结论及来源

**当前 Core 的 denied 只在目标非空且原始 signStatus=1 时产生；不是一般性的“任何不可签到”。但 signStatus=1 不一定产生 denied：空目标会得到 unknown。** UI 将资格与签到事实分列更准确；保留现 pending=allowed、completed=denied 过滤，不把原始状态重新用于筛选或写入资格。

| 层次 | 确切来源 | 已核对事实及限制 |
|---|---|---|
| 冻结 API | `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/SigninApi.kt:11`、`:13`、`:33`、`:43` | getTodayClasses 返回今日 DTO；performSignin 参数为 courseId。没有通用 eligibility enum。 |
| 冻结 DTO | `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Signin.kt:12`、`:15` | 明确 signStatus 0=未签到、1=已签到；课程安排 ID、课程名称、开始/结束时间、Int 状态。 |
| 冻结本地 | `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalSigninApi.kt:268`、`:280`；写结果`:153` | 今日从 id/courseName/classBeginTime/classEndTime/signStatus 映射；数字/数字字符串兼容。旧 flexibleIntValue 缺失/无法转整数返回0，此处不能照搬为UI默认未签到；当前 Core 已显式 unknown。提交结果才读取 result.stuSignStatus，不能把它当今日列表字段。 |
| 冻结测试 | `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalSigninApiBackendTest.kt:64`、`:358`、`:408`、`:412`、`:470` | 今日数字0、字符串1→整数1；提交嵌套字符串1成功。证明字段兼容，不证明缺失状态可安全写入。 |
| examples 等价模块 | `examples/buaa-api/src/api/class/data.rs:119`、`:136`、`:157`、`:179`；`api/class/{core,opt}.rs` | Schedule.id 明确是签到用安排ID，另有 course_id 用于查课程；status 仅把字符串1/0转 bool，其它拒绝。没有 typed资格模型，不能借此把所有 denied 或 unknown 变成状态事实。examples 不是缺失，但入口/方法的历史差异按已有 parity 决策处理，本轮不改。 |
| 当前 Core | `crates/ubaa-core/src/domain/signin.rs:8`；`features/signin.rs:456` | 原始值保留 Option<i32>；数字或数字字符串可解析且在i32范围内才保留。trim后非空id产生 target；(target,0)=allowed，(target,1)=denied，其它unknown。 |
| 当前 Core 预检 | `crates/ubaa-core/src/features/signin.rs:77`、`:85`、`:94` | 每次以目标重读今日列表，恰一项才继续；目标消失/重复分别返回错误。只有 allowed 可准备写入；denied 明确不可重复签到，unknown 缺少必要字段。列表存在重复并不自动改每项eligibility，预检才挡重复，UI不可推断成功。 |
| 当前 Core 测试 | `crates/ubaa-core/src/features/signin/contract_tests.rs:5`、`:20`、`:32`、`:53`；`crates/ubaa-core/tests/signin/write_authority.rs:56`、`:89` | 分别覆盖0/1、缺失/null/bool/object/小数/坏字符串/越界/2→unknown、空目标、denied/unknown拒绝、目标消失/重复；本轮仅阅读未执行。 |
| Bridge | `crates/ubaa-flutter-bridge/src/api/read/mod.rs:127`；`read/mappers.rs:146` | sign_status、signin_eligibility、signin_target分别原样映射，Bridge不重算事实或资格，无需改Bridge v9。 |
| App现状 | `packages/ubaa_app/lib/src/bridge/read/assignments.dart:194`、`:198`、`:205`、`:223`、`:234` | pending只筛allowed，completed只筛denied；显示状态当前反推自eligibility；action只在target非空时附加并保留资格。P4-C应加typed presentation保留原始signStatus，不能从已翻译FeatureField反推。 |
| 既有设计/矩阵 | `docs/design/ui-ux-redesign.md:62`；`docs/migration/source-parity.md:248`、`:332`、`:615`、`:649` | redesign的denied→已签到对当前Core正常映射成立，不能泛化三态枚举。parity今日表九列已覆盖引导、跳转、会话、方法参数、头/正文、加密、DTO、缓存、错误；11D字段列0/1/unknown需结合非空target条件理解。615/649仅补时间戳与嵌套写响应，不混入展示事实。 |

建议展示裁决（不修改现有筛选、Core写资格或pending/completed含义）：

| 原始 status / 资格 | 状态呈现 | 操作解释 |
|---|---|---|
| 0 + allowed +有效target | 未签到 | 沿现 action/预检提供签到操作，不承诺一定成功。 |
| 1 + denied | 已签到 | 不可重复签到。 |
| 0 + unknown 或1 + unknown（例如目标缺失） | “未签到”或“已签到”作为原始记录事实，同时显式“签到资格无法确认” | 不可把unknown改为allowed；仅在全部列表出现，仍不加入既有pending/completed筛选。 |
| null或非0/1 + unknown | 状态未知；需要诊断时可在更多信息展示原始数值 | 无资格；不是未签到、不是已签到。 |
| 与当前Core映射矛盾的组合，例如0+denied、1+allowed、null+denied | 状态信息不一致；分开展示原始状态与资格，不用资格覆盖原始事实 | 展示层不可重新授予资格，也不可宣称签到成功。该组合非当前parser可产生，若来自fake/版本不匹配应保留合成冲突测试与提示，继续沿现typed action和Core fresh预检；不得静默修正filtered集合。 |

## SPOC：字段与参数来源

| 任务 | 冻结与当前准确位置 | P4-C建议及不可新增内容 |
|---|---|---|
| 作业列表 | old `model/dto/Spoc.kt:23`；`api/local/LocalSpocApi.kt:34`、`:40`、`:56`；Core `domain/spoc.rs:21`、`:47`；Bridge `api/read/mod.rs:144`、`:157`和`read/mappers.rs:167`、`:181` | 保留assignmentId/courseId/courseName/teacherName/title/startTime/dueTime/score/submissionStatus/submissionStatusText；列表整体termCode/termName也已公开，App当前`:13`只遍历assignments而未展示学期，可放列表说明，不能伪造每项学期字段。 |
| 查看详情导航 | old `api/local/LocalSpocApi.kt:37`、`:82`、`:86`、`:202`；Core `facade/read/assignments.rs:56`、`features/spoc/detail.rs:17`、`:29`、`:52`；App `bridge/read/assignments.dart:37` | 精确 assignmentId 即足够；Core先从全局列表匹配，再确认详情返回id一致。列表typed导航应填 view=spocDetail + assignmentId，课程ID只展示归属，不增加详情query参数、不按标题猜作业。 |
| 详情字段 | old `model/dto/Spoc.kt:38`；Core `domain/spoc.rs:69`；Bridge `read/mod.rs:163`、`read/mappers.rs:188`；App`:46` | 除摘要字段增加contentPlainText、submittedAt。old还有contentHtml但当前Core/Bridge故意只有纯文本，不补HTML/WebView、附件下载或提交按钮。分数为可选字符串，不转数字或靠分数判断提交状态。 |
| examples nearest | `examples/buaa-api/src/api/spoc/opt.rs:54`、`:65`、`data.rs:178`、`:224` | 列表按课程GET queryXsZyList，与当前权威全局分页不等价；详情queryKczyInfoByid?id与旧同端点，仅作交叉证据；提交查询在opt.rs:97仅注释，不能当等价实现。examples已有写/上传不属于当前只读facade，P4-C不得接入。 |
| 已有parity与测试 | `docs/migration/source-parity.md:142`、`:154`；old `LocalSpocApiBackendTest.kt:72`、`:285`；Core `features/spoc/tests.rs:194`、`:204`、`:224`、`:292`；`crates/ubaa-test-support/tests/readonly/spoc/detail.rs` | 既有九列/详情逐操作十列表已覆盖全局列表与详情、可选提交补充。测试名明确ID/纯文本/回退/详情不能替换摘要身份。UI只复用公开字段及既有详情query，不重开无关认证协议。 |

当前App `assignments.dart:16`、`:46`仅通用fields，无typed presentation和readNavigation；P4-C应从Bridge对象当场投影身份、enum与文案并附typed导航，原有字段不丢。deadline/score不能自行推出submitted或overdue业务状态。

## Judge：父归属与批量顺序

| 任务 | 冻结与当前准确位置 | P4-C必须保留 |
|---|---|---|
| 列表与详情键 | old `api/feature/JudgeApi.kt:23`、`:28`、`:33`；`model/dto/Judge.kt:23`、`:42`；`api/local/LocalJudgeApi.kt:163`、`:173` | 精确(courseId,assignmentId)二元键；同名课程、同名作业都不能按名称去重或关联。列表includeExpired沿现query保留，不在UI按当前日期重新过滤。 |
| 摘要字段 | Core `domain/judge.rs:47`；Bridge `read/mod.rs:186`、`read/mappers.rs:212` | courseId/courseName/assignmentId/title/startTime/dueTime/maxScore/myScore/totalProblems/submittedCount/submissionStatus/submissionStatusText。App当前`:75`遗漏maxScore和enum；P4-Ctyped投影应补齐。分数仍可选字符串，数量与状态都从DTO读取，不由百分比推断完成。 |
| 详情与题目 | old `model/dto/Judge.kt:58`、`:70`；Core `domain/judge.rs:101`、`:117`；Bridge `read/mod.rs:206`、`:214`、`read/mappers.rs:228`、`:237` | 详情含全部摘要字段、problems、contentPlainText。每题name/score/maxScore/status/statusText；公开题目无problemId/URL/独立题目查询参数。题目必须嵌套在其父作业组，或typed题目presentation明确携带父courseId+assignmentId；不得按相邻列表位置或题名寻找父项。 |
| 单项/批量操作 | Core `facade/read/assignments.rs:110`、`:130`；`features/judge/batch.rs:127`、`:163`、`:249`；App `assignments.dart:99`、`:141` | 单项两个非空ID；批量使用显式judgeKeys，Core过滤空键/去重后恢复调用方规范化顺序，无单独上游批量接口。UI已有空批量拒绝，不替换成新语义；批量返回逐父作业组，不把题目全局混排。 |
| 当前App缺口 | `packages/ubaa_app/lib/src/bridge/read/assignments.dart:107`、`:119`、`:155`、`:173` | 单项/批量都将题目摊平为FeatureDetail，只有题名与三展示字段，父归属和typed状态丢失；即使顺序现在相邻，搜索/分页也会割裂，不能让UI靠位置还原。应由App在映射item.problems时注入父二元键或整个嵌套列表。没有依据增加题目点击跳转到上游页面。 |
| examples | 固定 `examples/buaa-api/src/api`目录及`api/spoc` | 没有Judge等价模块。SPOC虽同属作业功能，ID、HTML解析、选课Cookie与请求不等价，不借参数或DTO。 |
| 已有parity与测试 | `docs/migration/source-parity.md:183`、`:195`、`:201`；old `LocalJudgeApiBackendTest.kt:580`、`:628`、`:693`；Core `features/judge/tests.rs:105`、`:166`、`:198`、`:225`；`crates/ubaa-test-support/tests/readonly/judge/read.rs`、`isolation.rs` | 详情九列已包含题目表、PARTIAL、分数、缓存键；批量九列明确去重、课程分组、调用方顺序、路线/账户隔离。当前Core最高/本人分数、提交数量和enum都已计算，UI无需再次解析文本。历史截止课程ID与诊断计数是Core状态/证据内部能力，不应新增产品操作。 |

## 下一批最小验收建议（未执行）

签到：正常0/allowed、1/denied；0/unknown、1/unknown（空目标）；null/unknown、2/unknown及synthetic矛盾组合，确认事实/资格双字段不互相覆盖，pending/completed仍按原资格过滤，动作target不从courseName或FeatureField获得。

SPOC：展示假ID与typedID相冲突时导航仍采用typed assignmentId；submitted/unsubmitted/unknown与可选字符串score独立；详情纯文本长文/空提交时间；列表学期元数据不伪造到每项。

Judge：两父作业相同题名、相同assignmentId但不同courseId的批量数据；列表导航携带准确二元键；父标题/题目在搜索、分页、返回后保持归属；PARTIAL不被submittedCount或myScore覆盖；maxScore与各题maxScore均可达。所有验证仍只synthetic；native按主代理冻结候选另行执行。


## P4-C 实施续记（2026-09-08，原生复验前）

上述“当前缺口”为 `bb868cd2` 前的审计事实，现 Domain/App 投影已完成；未修改 Core、Bridge、认证、请求参数或学校写入路径。Judge 单项/批量改为父作业详情内嵌题目，保留原题目搜索字段，并保留两层顺序及二元 ID。summary typed 导航额外携带已有 includeExpired 查询上下文，detail backend 仍只消费原双 ID。SPOC 增加同次 term overview；评教增加全局 progress overview，原资格归一化/重复目标保护、签到按资格派生集合保持原样。

来源缺口 RED/GREEN、Controller overview 及瞬时失败规则用例已通过；普通与固定路线评教结果使用同一投影。独立只读代码审查未发现本次 Domain/App 的阻断问题。新 UI 的选择与状态测试不是上游证据，最终真实只读与原生验收仍待完成。
