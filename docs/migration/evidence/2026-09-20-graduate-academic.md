# Graduate academic extraction — 2026-09-20

Extracted from personal branch 22f751a5 onto upstream 0f73bd2c. Scope: GSMIS schedule/grades/exam reads and confirmed student identity isolation. No offline cache, calendar, native, reservation or UI redesign changes.

Frozen references verified with just refs before edits. Existing undergraduate protocol comparison remains in source-parity.md; neither frozen reference implements GSMIS. The following operation evidence is carried from the previously validated migration, not inferred from undergraduate APIs.

新增来源为仓库外 `reference-snapshots/graduate-2026-09-10`，由 UBAA-PR
`fdd85993b807e7a3977cbae5fe279d15f52f1c75` 加未提交源码快照组成，文件 SHA256 在该目录 manifest.json。
不读取/提交个人响应。用户已确认旧 APK 课表和空成绩/空考试可用；非空成绩只有合成测试，非空考试无协议证据。

两冻结来源逐项检查：旧版 `api/feature/{ScheduleApi,GradeApi}.kt`、`api/local/{LocalScheduleApi,LocalGradeApi,LocalConnectionAuth}.kt`、`model/dto/{Schedule,Grade,Exam}.kt` 及对应 Backend/Cookie/Auth 测试；示例 `api/aas/{core,opt,data}.rs`、`api/app/{core,opt,data}.rs`、`request.rs`、`store/{cookies,cred}.rs`、`error.rs`。它们没有以下 GSMIS 课表/成绩/考试协议（旧 server 的 getUserInfo 只是门户探测，非同协议）。故每行 URL、参数、DTO、密码/签名、错误均不得由这些本科接口类比推导。既有本科行为维持当前 Core 契约。

共同会话/传输决策：快照 `GraduateScheduleUpstream.kt` 和 `GsmisAcademicUpstream.kt` 都 GET 对应应用入口，使用主认证会话跟随学校重定向，不硬编码 CAS service、v、_yhz 或浏览器 Cookie；本次沿用 Core 有界重定向、TLS 校验、按模式/域/路径 Cookie 隔离，仅加入 gsmis 主机。最终 SSO URL、CAS title/execution 或401为认证失败；非200保留状态/阶段，不回传正文。无新增加密、签名常量。GSMIS 查询 XHR 头为 `Accept: application/json, text/javascript, */*; q=0.01`、`X-Requested-With: XMLHttpRequest`、`Referer: <转换后应用入口>`；POST 为表单，课表学期例外为空 body 无 Content-Type（与快照一致）。直连和WebVPN都转换 URL/Referer。读取串行完成后才返回；不新增跨账号持久缓存，不改凭据仓。

| 操作 | 快照请求/业务入口 | 字段、完整性和错误 | 缓存/并发/来源差异 |
|---|---|---|---|
| 课表学期 | GET `https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp/*default/index.do`，POST `/modules/xskcb/kfdxnxqcx.do` 无负载 | code=0,datas.kfdxnxqcx.rows/totalSize；XNXQDM、XNXQDM_DISPLAY；完整、代码合法、倒序 | 两冻结来源无同协议；不借本科学期代码；仅成功业务证明能力 |
| 整学期课表/周/今日 | 同入口，POST `/bykb/loadXskbData.do`，`ZC=&XNXQDM=<term>&XH=&XQDM=` | code=1；rwList(XNXQDM,BJDM,SCSKRQ)、jgList(BJDM,KCDM,KCMC,XQ,ZCBH,KSJCDM,JSJCDM,JCFADM,JASMC,JGJSXM,ZCMC)、jcfaList.skjcList(JCFADM,DM,KSSJ,JSSJ)。校验学期、课程关联、唯一节次、位图、日期对应周一起点；不能猜开学日期。仅同班/教师/地点/位图/方案的相邻节次合并；全部有效节次构建时间轴 | 快照 GsmisSchedule.kt/GraduateSchedule.kt 及测试；两冻结无同协议。不迁移YJSXK JSON脚本修复；位图仅表示可查周范围；今日使用上海日期 |
| 成绩全量/学期 | GET `https://gsmis.buaa.edu.cn/gsapp/sys/wdcjapp/*default/index.do`，POST `/modules/wdcj/xscjcx.do`，`pageSize=12&pageNumber=<1..>` | code=0,datas.xscjcx.{rows,totalSize,pageNumber}；总数0..10000且不变、页码一致、每页<=12、WID唯一，不返回部分结果；学期来自成绩XNXQDM/XNXQDM_DISPLAY | 快照GsmisAcademicUpstream.kt/GsmisAcademicTest.kt；两冻结无同协议。空成绩不调用课表或字典，历史成绩不受课表开放学期约束 |
| 成绩字典/GPA | 同成绩入口，非空时POST `/modules/wdcj/cjfzdjcx.do` 空表单 | code=0,datas.cjfzdjcx rows/totalSize；CJFZDM+DM/MC匹配，DYJDZ与DYBFZCJ取有效范围。百分制<60为0，否则4-3*(100-score)^2/1600；五级制用字典。SFYX=0、T/EX、非0/1成绩制不入GPA，未知值不冒充0。正学分加权，GPA与均分分母独立，空分母null | 原本科计算不变；特殊培养环节不根据课程名猜；非空仍需真实样本验证。字典匹配不唯一则不猜其值 |
| 考试学期 | GET `https://gsmis.buaa.edu.cn/gsapp/sys/wdksapp/*default/index.do`，POST `/modules/ksxxck/getXnxqList.do` 空表单 | datas数组，DM/MC/SFDQXQ，学期合法且唯一，倒序 | 两冻结无同协议；与课表学期独立 |
| 考试列表 | 同考试入口，POST `/modules/ksxxck/getWdksxx.do`，`xnxqdm=<term>` | success=true，countKs/countKcks/countJk非负且必需；全0为空；任一正数明确unsupported并提示官网，绝不伪装空 | 两冻结无同协议；非空明细证据不足；不推测课程/时间/考场字段 |


Current routing supersedes the earlier probing fallback: confirmed user-center school_id (username only if absent), 8 ASCII digits undergraduate, ASCII letter prefix plus digits graduate regardless of case; all other formats rejected before academic requests. Network/parse errors and term shape never select another student system. Runtime identity clears with session memory. Restore loads identity once on the resolved route.

Validation: in progress. Nonempty graduate exam details remain unsupported (explicit error); no invented fields. Nonempty grades and fresh extraction live validation require additional user evidence.

RED: restored_session_recovers_identity_once_and_rejects_unknown_numbers failed on upstream: profile request count 0, expected 1. Existing schedule_terms entry used twice before exam_terms existed.

## Candidate validation

- Core all-features tests and workspace all-targets tests passed. CLI graduate command/schema tests passed. Workspace Clippy all-features/all-targets with warnings denied passed.
- Flutter app 273 tests passed; graduate UI check passed. App/UI analysis passed. FRB 2.13 generation zero drift passed. Layout, frozen references, sensitive scan and contract version checks passed.
- New Flutter RED tests reproduced scheduleTerms being incorrectly requested for graduate empty grades and exam defaults; both passed after consuming gradeOverview/examTerms. A nonempty synthetic grade test preserves Core statistics across term/view filtering.
- Local Windows just check stopped in the existing references shell test: MSYS /tmp versus Windows C:/... remote URL spelling. No weakening of the gate; complete Linux gate and macOS goldens require CI.
- This extracted candidate has not been tested with live undergraduate/graduate accounts in Direct/WebVPN or on mobile. Earlier personal-branch user checks are historical evidence only. Nonempty graduate exams remain explicitly unsupported; nonempty graduate grades are covered only by sanitized tests.
- Flutter keeps upstream layout. It uses each application own terms and renders Core graduate statistics without running the undergraduate aggregate loader. Offline, calendar, widgets and general UI migration are excluded.

Flutter domain: 54 tests and analysis passed. Flutter UI on Windows: 235 passed, 14 macOS golden baselines differed; no golden files updated. The separate graduate UI regression passed. Mac CI remains authoritative for visual baselines.

CI follow-up: upstream CI at 56543e66 passed all four primary jobs, including Linux strict gates and macOS Flutter goldens. Native macOS build passed, but its existing app_flow smoke still targeted the previous navigation groups, inline filters and duplicate confirmation title. Updated only test navigation/typed metadata fixtures to match the current upstream UI, preserving all twelve feature queries and all write submission/readback assertions. Registered the same seven smoke flows in the existing host widget-test entry so ordinary Flutter CI catches future drift; the combined 16-test entry and host analysis pass locally. New grade widget coverage lives in the existing academic test directory to respect the 16-source-file directory limit. Native rerun remains required.
