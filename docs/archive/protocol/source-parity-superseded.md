# 来源对照已取代的计划与旧索引

本页保留从原 source-parity.md 移出的实现前合同、阶段计划、逐按钮审查索引和旧专项清单原文，仅供追溯；现行来源对照见[协议来源目录](../../protocol/README.md)。

## 2026-09-08 UI/UX 重设计前逐操作保持合同

本轮在生产 UI 修改前完成静态来源索引与 typed 接线边界核对，详见
[UI/UX 来源与接线审查](../history/2026-09-08-ui-ux-parity-review.md)。两冻结 HEAD 已读回并与本文件固定值一致；完整 refs 门禁由本轮主证据记录。该审查为每个当前认证/只读 Bridge 操作列出旧版接口、本地实现、DTO、测试与 Rust 示例适用性，并独立应用 C1–C9：URL/service、重定向、Cookie/Session、方法参数、Header/编码、加密、DTO/解析、缓存/并发、错误/退出均保持现有协议。纯视觉不授权改变请求或扩充公开合同。

可接线范围：图书馆馆列表已有 typed 楼层，分区已有父 ID，详情已有 typed 时段；App 可无损保留这些公开字段为选择器，segment 只能取时段 ID。阻塞范围：当前公开分区详情仅给出第一日期/顶层时段，不能据此声称全部日期共享时段；跨日期精确时段需另行合同与失败测试。userInfo 已接入但仅投影 username/name，既有白名单其它字段可做遮罩资料展示，department 没有来源。

审查发现的“SPOC 详情”首表误写 Judge URL 已于本日按两冻结来源和 Core 修正归属；历史说明保留于对应章节，不构成协议变更。Ygdk 主机集合未决边界、Cgyy 仅公开锁码 available、所有 typed 写入资格与单次提交保持原决定。本节只有静态来源证据，不是测试、实时只读或实际 UI PASS。

P3B公共容器补充：刷新状态切换的State保留、隐藏焦点隔离、短视口滚动和Theme依赖仅影响本地呈现。全部认证/只读操作继续应用上述C1–C9，URL/参数/请求次数/DTO/错误码/路线/业务缓存均未变；不从旧展示数据产生新写资格。typed actions每次仍取当前snapshot.details，明确empty清除无效选择，唯一WriteCoordinator不变。6个状态/键盘场景（先5RED/1GREEN）及主题颜色RED合为7GREEN，原生旋转与字体复验独立记录。

## 2026-09-08 P4-B 学业展示模型与只读导航（实现前合同）

本段范围仅 domain 新展示类型、FeatureDetail 可空展示/导航字段、App academic 投影及确定性测试；不改 Core、Bridge v9、UI 或宿主。`just refs` 本轮退出 0，两来源固定提交与本文件一致。字段直接核对生成 `packages/ubaa_bindings/lib/src/rust/api/read.dart`、冻结旧版 `Schedule.kt/Grade.kt/Classroom.kt` 与 `LocalScheduleApi.kt/LocalGradeApi.kt/LocalClassroomApi.kt`；交叉来源为固定 `examples/buaa-api/src/api/aas/{core,opt,data}.rs` 与 `api/app/{core,opt,data}.rs`。后者成绩/空教室不等价，不借用字段或协议。

| 操作 | URL/service、重定向、Cookie/Session | 方法参数、Header/编码、加密 | DTO 与新增展示 | 缓存/并发、错误/退出 |
|---|---|---|---|---|
| 今日课表 | 引用“未改变的课表/考试证据”；两路线与 AAS 激活不变 | scheduleToday 无新增入参；旧 GET 与 Header 不变，不新增加密 | 仅保留既有可空 time/place；不猜周几节次 | 不请求预取、不排序、不新增缓存；错误/路线原样 |
| 学期 | 同上；示例 aas 不替代旧 service | scheduleTerms 原调用不变；点击导航只是待执行 typed query | itemCode/itemName/selected/itemIndex 原类型；非空原 code 生成 scheduleWeeks 导航 | 无新增 HTTP；顺序、空列表、错误不变 |
| 周次 | 同上 | scheduleWeeks(term) 原参数不变 | startDate/endDate/响应term/serialNumber/curWeek/name；导航保留请求 term 与正 week，不从 fields 反解 | 不自动查询下一层；不按日期解析重排；错误不变 |
| 周课表及 summary(term,week) | 同上；不借用示例 campusCode 正文 | 两分支 scheduleWeek(term,week) 请求、表单、编码不变 | 保留 dayOfWeek、begin/endSection int? 与时间/地点/周次教师等 String?；缺值不填 0 | 两分支共用投影，不新增缓存或排序，输入校验与错误不变 |
| 考试三视图 | 同上；当前 term 默认选择不变 | examArrangement(term) 原调用不变 | 保留日期/单侧起止时间/座位等原可空值；arranged 来自原所属集合 | summary 仍 arranged 后 notArranged；顺序、错误、路由不变 |
| 成绩三视图 | 引用“未改变的成绩证据”；示例 App 非同协议 | 旧激活、POST xq/year、Header/编码不变，不新增加密 | score/gradePoint 等 String? 原样；credit double?；不推算排名/GPA | 已出判定沿 score 非空；不排序、不新增缓存，错误不变 |
| 空教室 | 引用“空教室会话同步/查询”；示例 App/Class 非此协议 | classroomSearch 仍 campus/date；本地 floor/section 不加入上游；GET/Header不变 | roomId/floorId/父楼层名、原 availableSections 与精确逗号令牌保留 | 3 不匹配 13；不新增请求/缓存/并发，路线及错误不变 |

所有时间字符串仅展示，不假定可 DateTime.parse 或排序；term/weeks 导航不自动执行网络操作。actions 完全保留，不用展示结构推断任何写资格。本段是实现前约束，后续测试日志单独记录，不代表真实只读或 UI PASS。

本段确定性实施结果：先新增仅 domain 类型/可空接口和六项 App 投影测试，实际运行出现六项 `presentation=null` 预期失败，原十一项 characterization 仍通过（`p4-academic-red.log`）；完成 academic 纯投影后同入口 17 项通过（`p4-academic-green.log`）。domain 全部 28 项测试通过；两个受影响 package 的 `dart analyze` 均无问题。日志位于本轮私有 `<private-evidence>/legacy-tmp/ubaa-ui-ux-20260908/`，由阶段证据归档决定是否纳入长期证据。这些结果仅证明合成数据字段、导航参数和既有请求转发保持，不代表 UI 已使用新结构或实时读取成功。现有 title/subtitle/fields/actions 保留；新增展示不恢复未公开的周表字段，不解析时间排序。

## 2026-09-08 P4-B 读取上下文与父缓存失效（实现前边界）

本段仅修复 App/domain 的结果归属：不同 FeatureQuery 失败不能把父查询内容作为子查询 stale；同查询失败保留原 stale。FeatureReadContext 记录不可变查询键与既有请求代次，默认 loadFeature 的 null query 不等同显式 summary。全局 readCacheEpoch 仅使 UI 父返回帧缓存失效，不改当前可见同参数旧结果的 stale，也不替换受保护的 Ygdk 失败原 snapshot 实例。首页刷新、路线/账号/backend 失效与写后权威回读开始推进 epoch；原 generation、caller-pinned 路线、回读 proof 和写结果语义不变。

来源仍为本文件逐操作九列：URL/service、重定向、Cookie、精确方法参数、Header/编码、加密均不变；DTO 只增加本地查询归属，Core 排序/缓存/并发/错误码不变。回读仍按既有 Evaluation、Ygdk、Cgyy 冻结/typed 合同执行，不增加网络调用。实际新 RED 三项分别暴露跨查询 stale、缺少context与缺少epoch，原62项AppController测试通过；后续结果单独记录。

本段实现后确定性结果：新增读取归属与缓存epoch测试，AppController/写生命周期/回读重入三个入口合计96项全部通过，domain合计30项全部通过，App/domain/Host analyze均无问题。旧首页同查询stale与Ygdk回读失败保持原snapshot实例的断言未改。context用于成功/失败/加载结果归属，caller-pinned Evaluation/Cgyy/Ygdk回读分别带显式summary、orders、overview/records参数；Cgyy失败和Ygdk失败的既有旧快照保留规则不变，由独立epoch通知父缓存失效。此为合成数据验证，不是UI/native/live结论。

## 2026-09-08 P4-B2 独立学期选项与教室参数归属（实现前合同）

本段复用“学期”已核验冻结 LocalScheduleApi/Schedule DTO 与示例 aas 适用性，以及“空教室”LocalClassroomApi/Classroom DTO；`just refs`再次退出0。URL/service、重定向、Cookie、方法/参数、Header/编码、加密、Core排序/缓存/错误码全部不变。App仅在用户明确请求时经 FeatureQueryBackend.loadFeatureQuery(schedule,scheduleTerms)读取，新增独立当前会话选项缓存和同代在途合并，不借写全局schedule snapshot。成功结果可复用，force绕过成功缓存；错误不缓存；生命周期、backend、路线及readCacheEpoch变化后不返回旧成功，迟到返回安全operationConflict。该App选项缓存不是上游缓存改变。

ClassroomPresentation追加可空queryDate/campus，仅由实际classroomSearch调用的同一日期字符串与校区变量投影，不重新读取时钟、不添加上游筛选参数。模型/回调骨架后新增五项App行为及一项metadata断言实际RED，原82项通过；不是编译失败。Core/Bridge v9和UI均未修改，本记录不声称原生或实时通过。

本段实施结果：独立学期缓存/同代合并/force/失败重试/不可变选项/epoch与路线失效/注销/backend重建迟到保护均已确定性验证；同步抛错也经Future.sync正确释放在途句柄。AppController与characterization合计91项通过，domain30项通过；App/domain/Host analyze均无问题。教室queryDate/campus断言与实际client调用参数一致。现有首页snapshot/代次及写回读测试保留；未运行本段UI或原生/真实只读。force在已有同代在途请求时合并该次新读取，否则绕过成功缓存重读。


### P4-C 实施前展示字段核对

[SPOC、希冀、课堂签到逐操作增补](source-parity-ui-coursework.md)核对冻结API/DTO/实现/测试、固定examples最邻近模块、Core/Bridge白名单及App丢失字段。原九列协议矩阵继续为权威，本轮只增加typed投影与已有导航，不改URL、方法、凭证、缓存或写预检。当前仅计划已评审，未将静态盘点计为P4-C验收。


### P4-D 实施前预约领域展示核对

[图书馆与研讨室增补](source-parity-ui-reservations.md)逐项列出11个只读视图、DTO与动作来源、日期关联不可证边界及测试计划。馆区详情过滤空日期后首项与原第一项时段可能不同，顶层回退也没有来源标记，不能仅凭两个非空列表自动绑定首日。此项仍是展示设计边界，不更改Core/Bridge参数或当前手填查询。


### P4-A 实施前账号资料白名单核对

[资料投影来源增补](source-parity-ui-profile.md)按冻结API/DTO/实现/测试边界、examples不等价状态接口、Core/Bridge六字段白名单逐项核对。新增展示仅来自同次userInfo，既有用户资料九列协议矩阵继续适用；保留空username返回null和preferredName，不接证件号码，不持久化联系人展开状态。


### P4-D 博雅与阳光展示接续来源

[博雅与阳光字段、导航及动作边界](source-parity-ui-campus.md)记录5个博雅视图与2个阳光视图、集合统计、分页和固定路线回读，列明可复用的Core/Bridge字段和不可重新推导的写资格。仅实施前静态核对，不将其计为已迁移或原生通过。


### P4-C 课程作业展示实施续记

[课程作业来源增补](source-parity-ui-coursework.md)现追加实际投影与界面行为，不再仅为计划。Judge 保留父作业/嵌套题目与有序双ID；SPOC同次学期、评教全局进度独立传递；原签到/评教资格与请求不改。SIG-02按既有allowed筛选改“可签到”文案，原始记录状态另显。Domain33/App223/UI173与相关追加用例通过；真实只读、原生设备与最终候选门禁分别记账，尚不由这些测试宣称通过。

O3-E1考试/签到旧布局的实施前逐操作复核见[学业旧版对照](source-parity-ui-academic-old.md)，继承本表的协议裁决；UI不更改Core或Bridge合同。

O3-E2成绩旧统计/卡片、全学期聚合及首页变化提醒的实施前依据见[source-parity-ui-grades.md](../../protocol/parity/academic.md#成绩旧版统计卡片与更新提醒对照o3-e2)。本批恢复旧本地统计，不改上游逐门gradePoint或公开协议；详细说明新增本地读取组合/缓存与真实覆盖范围。

## O3-E3a空教室旧布局实施前对照

详见[source-parity-ui-classroom-old.md](source-parity-ui-classroom-old.md)：已逐页核对旧ClassroomQueryScreen/ViewModel/测试及两冻结来源协议边界；计划恢复14节表格、完整滚动和按需详情，右上查询保留。三项行为RED已观察，未因此标记原生/生产验收完成。


E3b课表旧网格与详情实施前逐操作对照见 [课表旧界面](source-parity-ui-schedule-old.md)。已核对公开color字段，协议不改；自然周选择仍待接线。

## 2026-09-15 macOS逐按钮审查补充

- [macOS安全凭据通道](../../protocol/parity/accounts.md#macos-系统凭据存储的双来源核对)：记住密码与自动登录的原生Keychain接线，沿既有认证协议。
- [登录选项与凭据失败恢复](../../protocol/parity/auth-session.md#登录选项与凭据失败恢复的双来源核对)：旧开关联动、保存凭据恢复与本地失败后的UI状态。
- [功能卡片语义动作](../../protocol/parity/host-platform.md#普通与高级功能卡片的原生按钮动作)：普通与高级入口的可执行按钮语义，沿原导航和读取合同。
- [图书馆日期与时段](../../protocol/parity/libbook.md#图书馆日期与时段完整接线实施前来源核对)：同一原始日期与时段的typed关联，保留旧CLI详情形状。
- [博雅筛选与完整详情](../../protocol/parity/bykc.md#博雅类别校区完整详情与筛选偏好实施前对照)：类别/校区/完整字段、已选补查、三个详情入口及账号隔离的筛选偏好。
- [验证码与门锁专用显示](../../protocol/parity/auth-session.md#验证码与门锁信息逐操作来源与专用显示边界)：独立交互认证和短期门锁信息视图的九列、字段及生命周期裁决；普通结果与旧CLI边界不变。
- [统计开关与实际客户端能力](../../protocol/parity/app-service.md#统计开关与实际客户端能力对照)：默认Noop不能报告开启，保留显式可用客户端的真实事件开关，不新增接收端或外部传输。
- [连接策略切换与后台重建](../../protocol/parity/auth-session.md#连接策略切换与后台重建的迟到结果)：旧切换的迟到结果不能覆盖新backend实际策略，保留普通认证和既有请求合同。

## 全部来源对照专项

以下列出本目录全部 source-parity 专项。索引不声明其内容已按当前冻结版本重新验收，具体日期、来源与结论以各记录为准。

- [source-parity-android-widgets-2026-10-03](../../protocol/parity/academic.md#android-桌面课表组件对照与实施)
- [source-parity-auth-2026-10-21](../../protocol/parity/auth-session.md#sso-传输协议与-uc-激活链对照)
- [source-parity-code-organization](../../protocol/parity/core-engineering.md#复杂业务模块目录化来源对照)
- [source-parity-consolidation-2026-10-01](../../protocol/parity/core-engineering.md#分支整合前的冻结来源复核)
- [source-parity-dependency-reuse](../../protocol/parity/core-engineering.md#通用依赖收敛实施前来源裁决)
- [source-parity-desktop-photo-2026-10-02](../../protocol/parity/host-platform.md#windowslinux系统选图接线)
- [source-parity-engineering-dart-2026-10-07](../../protocol/parity/core-engineering.md#独立工程审查修复dart-认证终态与状态所有权来源对照)
- [source-parity-engineering-platform-2026-10-07](../../protocol/parity/core-engineering.md#工程修复本地普通偏好与平台验证来源对照)
- [source-parity-engineering-rust-2026-10-07](../../protocol/parity/core-engineering.md#独立工程审查-rust-修复实施前来源裁决)
- [source-parity-entry-modules](../../protocol/parity/core-engineering.md#core-入口职责整理来源对照)
- [source-parity-gsmis-2026-10-02](../../protocol/parity/gsmis.md#gsmis研究生课表逐操作对照)
- [source-parity-home-calendar-2026-10-25](../../protocol/parity/home.md#首页日程与临近待办来源核对)
- [source-parity-home-concurrency-2026-10-29](../../protocol/parity/home.md#首页分业务并发)
- [source-parity-home-exams-2026-10-25](../../protocol/parity/home.md#首页考试待办)
- [source-parity-home-loading-2026-09-17](../../protocol/parity/home.md#首页加载性能修复来源对照与验证)
- [source-parity-home-performance-2026-10-29](../../protocol/parity/home.md#首页加载性能优化)
- [source-parity-ihome-2026-10-25](../../protocol/parity/ihome.md#ihome-来源对照与实施记录)
- [source-parity-infinite-lists-2026-10-26](../../protocol/parity/host-platform.md#列表连续滚动的来源与边界)
- [source-parity-interactive-integration-2026-10-02](../../protocol/parity/auth-session.md#交互验证码整合前来源与生命周期约束)
- [source-parity-judge-2026-10-23](../../protocol/parity/coursework.md#希冀获取修复实施前来源对照)
- [source-parity-judge-performance-2026-10-24](../../protocol/parity/coursework.md#希冀读取去重实施前双来源核对)
- [source-parity-libbook-auto-seats-2026-10-25](../../protocol/parity/libbook.md#图书馆预约座位自动加载)
- [source-parity-maintainability-transport](../../protocol/parity/core-engineering.md#reqwest-传输诊断来源与行为边界)
- [source-parity-maintainability](../../protocol/parity/core-engineering.md#可维护性治理来源与行为边界)
- [source-parity-offline-recovery-2026-09-17](../../protocol/parity/offline-cache.md#离线恢复逐操作来源对照)
- [source-parity-order-detail-2026-10-03](../../protocol/parity/cgyy.md#研讨室订单详情身份校验)
- [source-parity-quality-2026-10-11](../../protocol/parity/core-engineering.md#f03f04f05f06-实施前来源对照)
- [source-parity-schedule-default-2026-10-23](../../protocol/parity/academic.md#课表默认下载整学期)
- [source-parity-signin-2026-09-17](../../protocol/parity/signin.md#2026-09-17-课堂签到修复对照)
- [source-parity-statistics-defaults](../../protocol/parity/bykc.md#博雅统计与阳光留空默认值核对2026-10-24)
- [source-parity-ui-academic-old](source-parity-ui-academic-old.md)
- [source-parity-ui-bykc-details](../../protocol/parity/bykc.md#博雅类别校区完整详情与筛选偏好实施前对照)
- [source-parity-ui-bykc](source-parity-ui-bykc.md)
- [source-parity-ui-campus](source-parity-ui-campus.md)
- [source-parity-ui-classroom-old](source-parity-ui-classroom-old.md)
- [source-parity-ui-coursework](source-parity-ui-coursework.md)
- [source-parity-ui-grades](../../protocol/parity/academic.md#成绩旧版统计卡片与更新提醒对照o3-e2)
- [source-parity-ui-home](source-parity-ui-home.md)
- [source-parity-ui-libbook-dates](../../protocol/parity/libbook.md#图书馆日期与时段完整接线实施前来源核对)
- [source-parity-ui-login-options](../../protocol/parity/auth-session.md#登录选项与凭据失败恢复的双来源核对)
- [source-parity-ui-macos-credentials](../../protocol/parity/accounts.md#macos-系统凭据存储的双来源核对)
- [source-parity-ui-navigation-actions](../../protocol/parity/host-platform.md#普通与高级功能卡片的原生按钮动作)
- [source-parity-ui-photos](../../protocol/parity/host-platform.md#p5-e-原生照片能力来源核对2026-09-10)
- [source-parity-ui-profile](source-parity-ui-profile.md)
- [source-parity-ui-reservations](source-parity-ui-reservations.md)
- [source-parity-ui-route-lifecycle](../../protocol/parity/auth-session.md#连接策略切换与后台重建的迟到结果)
- [source-parity-ui-schedule-old](source-parity-ui-schedule-old.md)
- [source-parity-ui-sensitive-displays](../../protocol/parity/auth-session.md#验证码与门锁信息逐操作来源与专用显示边界)
- [source-parity-ui-telemetry-control](../../protocol/parity/app-service.md#统计开关与实际客户端能力对照)
- [source-parity-ui-ygdk](../../protocol/parity/ygdk.md#o3-d4阳光打卡旧版依据与实施边界)
