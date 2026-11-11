# 课表旧界面逐操作对照

2026-09-09，E3b实施前。冻结旧版6e75e120a26b0eefb3ab4a6f8251d1230db4a62e，examples efb7976bf513f38364b88aeb83d704586cff9b2a。本批先恢复周课表网格和本地课程详情；学期/周次自然选择及真实周日期仍作为后续接线项，不能以网格完成关闭SCH-01–04。

## 实际阅读的来源

- 旧composeApp下 `ui/screens/schedule/{ScheduleScreen,ScheduleDateLabels,CourseDetailScreen}.kt`、`ui/screens/schedule/ScheduleViewModel.kt`、对应ViewModel/日期测试。
- 旧shared下 `api/feature/ScheduleApi.kt`、`api/local/LocalScheduleApi.kt`、`model/dto/Schedule.kt`、`commonTest/.../LocalScheduleApiBackendTest.kt`。
- examples `src/api/aas/{core,opt,data}.rs`。学期、周次列表和今日接口没有同等实现；仅周课表有同源端点，不借用其额外campusCode、query编码和notArrangeList。
- 当前公开 `BridgeCourseClass` 已有可空color，`BridgeWeeklySchedule`只有arrangedList/code/name；UI投影漏color，可直接补齐而不改Bridge合同。日期须从已读Week.startDate/endDate取得，不能从周号和本机日期反推。

## 逐操作协议与展示边界

下表每行共同使用既有AAS认证/路由对照（source-parity.md“未改变的课表/考试证据”及认证章节）：旧Local先currentUser.do探测，按会话所选Direct/WebVPN的Cookie作用域请求；examples AAS CAS service为 `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp`，校验最终URL前缀；两者差异不由UI改动。本批不改bootstrap、重定向/finalURL、Cookie、TLS、加密或签名常量（这四个业务读取自身无新增加密），宿主继续只用facade/typed Bridge。

| 操作 | 旧HTTP与精确参数 | 头/编码 | DTO与原字段 | 缓存/并发/错误 | 本批变化 |
|---|---|---|---|---|---|
| 学期 | GET student/schoolCalendars.do，无参数 | Accept application/json, text/javascript, */*; q=0.01；X-Requested-With XMLHttpRequest；Referrer homeapp/index.html | Term.itemCode/itemName/selected/itemIndex | 旧VM ensureLoaded、selected优先否则first；旧code!=0失败，当前缓存按账号/读取代次隔离 | 不改读取；当前独立学期缓存保留 |
| 教学周 | GET home/getTermWeeks.do，termCode原值 | 同上，GET参数 | Week.startDate/endDate/term/curWeek/serialNumber/name | 旧VM学期改变读取，curWeek优先否则first；网络/认证错误沿既有合同 | 不改读取；自然周选择接线待做，不把第一项冒充当前 |
| 周课表 | POST student/getMyScheduleDetail.do；form termCode/type=week/week | 同头；FormDataContent；examples不同：POST query另含campusCode空值，明确不借用 | CourseClass全部typed字段含color；WeeklySchedule.arrangedList/code/name，response code不强制等于请求学期 | 旧VM按选定term/serialNumber读取；没有本地20条分页；现有Controller生命周期/迟到保护、错误/退出码不变 | 补UI color原值投影，旧7日×节次网格，本地详情保全字段，无服务端分页时完整集合 |
| 今日课程 | GET home/teachingSchedule/detail.do，rq本机日期/lxdm=student | 同头；GET参数 | bizName/place/time/shortName | 原独立today读取，错误沿合同；不能把week结果冒充today | 保留现有入口和首页独立today，不改变本批请求 |

旧LocalScheduleApiBackendTest直接覆盖学期/考试/成绩，不含全部四种课表请求；其未覆盖部分以实际Local源码及现有Core夹具证明，不夸大旧测试覆盖。examples仅周课表同源，Config currentUser来源与旧学期/周列表不同；其强类型时间、周几和信用转换不用于收窄当前可空公开字段。

## 旧版依据—必要优化—当前实现

| 旧版依据 | 必要优化 | 本批实施目标 |
|---|---|---|
| ScheduleScreen：7列、左36节次列、每节64、至少12节，按原begin/endSection定位；6圆角、4内边距、12课程/11地点；原color明暗适配 | 普通手机完整7列，大字或很窄视口才必要横滚；未知时间不默认周一第一节；重叠课程不能互相遮掉 | 移除按天大卡及宽屏240×7列；保留日期空间待真实Week接线 |
| CourseDetailScreen：课程名称/代码、基本信息、周次教师/教学对象 | 独立本地详情，长文滚动；即使credit空仍保留教师与对象，不复刻旧credit条件误隐藏 | 点击网格课程查看完整typed原字段，不发额外业务读取 |
| 旧整周完整列表 | 防止本地20条截断造成课表漏课；服务端分页仍尊重原合同 | 仅无服务端分页的周课表取消本地分页 |

本批将先观察网格定位、低频字段收敛/本地详情、完整集合与color投影行为RED，再最小实现、聚焦及全门禁、三端原生操作与脱敏图片复验。此处尚无本批PASS结论。


## E3b实现与复验过程

当前已补color纯投影，网格位置、重叠课程完整列表、异常时间详情、非空与空周结构。新增学业测试6项，包含横滚固定节次、未知列表边界、空周；与既有学业测试合计16聚焦PASS。全Flutter667通过。旧CourseDetail的credit条件误隐藏教师/对象未继承。三端r1/r2及手机r3记录均保留为迭代证据，最后r4复验中。学期/周列表协议、缓存和错误均未修改；本地详情不额外读取。


### O3-E3b局部终态（2026-09-09）

课表旧七日节次网格、公开原色、无服务端分页完整集合、重叠课程/未知时间保全、本地详情和空周结构已完成。667项Flutter门禁、16学业聚焦通过；三端r4各14业务，空周提示位置截图发现后RED→GREEN并仅对受影响空周r5各2原生复验。非空UI不受r5调整影响，证据分r4/r5源摘要，不冒称同次全跑。两端各38原图和Mac4独立操作图共80张通过图已复核，另1张Key A输入限制图不标通过。生产Direct32秒/WebVPN31秒，今日1、学期9、周19、周课10，本地详情无额外读取，草稿/实际路线保留，业务写入0。

macOS独立CUA已完成根页→查询面板→选学期→数字4输入→应用/收起→课程详情→底部滚动；此前AXError此次未阻止这条鼠标路径，但完整字母输入仍失败：请求COURSE-SAFE-2仅输入COURSE-SA，Key A keyUp逻辑码0x1400070004与已按下0x61不一致。未取消Flutter断言、未修改认证/资格，也不把tester.enterText视为物理键盘通过。E3c自然周选择与日期、P4其余及P5–P7继续。

## E3c自然选择与真实日期（实施前，起点2610d316）

旧ScheduleViewModel的terms→selectedTerm→weeks→selectedWeek→weekly顺序、独立today/currentWeek缓存及ScheduleViewModelTest四个失败/浏览隔离场景已重新核对。旧DateLabels及5项测试明确：按startDate解析，失败则endDate减6天，接受不补零/日期时间形式，跨年逐日推进，双失败不显示日期；不从本机日期或周号反推。新交互把学期/周次/前后周统一收在右上按需面板，顶栏只显示当前周名称，不新增正文工具条；今日、学期列表、周次列表与手工兼容查询完整保留。

后续实现：App增加按请求学期、backend实例、登录生命周期和readCacheEpoch隔离的独立周选项缓存，合并同代在途请求，force失败不复活旧成功；不改全局schedule快照。调用仍为原scheduleWeeks(term)，无新URL/参数/header/编码/加密/会话规则。UI仅唯一selected学期及唯一current周自动选择，歧义/缺少当前项保持明确待选，不把第一项冒充当前；隐藏页、切换账号/路线或用户已改查询后迟到选项不触发自动课程读取。实际日期只用于请求term/周编号唯一匹配的周结果，不能把其他学期元数据套给现页；路由事实不使用默认策略替代。

缓存与状态衔接先TDD，完成前本段不作为实现或验收结论。E3b既有网格、详情、业务保护及双路线证据保留。

E3c接线补充：自动terms→weeks→week通过现有可见FeatureQuery推进，重用AppController的异查询清旧数据与迟到响应保护，首页today独立投影不改。手动周选择/前后周使用新增按term独立缓存，不占用全局课表。日期只有请求term/周号唯一匹配且周元数据与当前课表实际route一致时才显示；不混入其他路线数据后仍只标课程路线。元数据失败不覆盖成功课表，明确重新获取可重试。stale同查询保留原日期；不同查询由原_beginFeatureRead先清旧集合，不将上一学期课程套到新日期。标题按旧maxLines=1省略，周列表长名称完整换行，本周标记移到日期下方以避免大字窄列；不改任何学校请求字段。
