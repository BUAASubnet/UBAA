# 成绩旧版统计、卡片与更新提醒对照（O3-E2）

2026-09-09，实施基点e22afa5a。冻结旧版6e75e120a26b0eefb3ab4a6f8251d1230db4a62e、示例efb7976bf513f38364b88aeb83d704586cff9b2a；普通开发仅校验refs。本文在生产修改前建立，当前是实施依据，不是实现/验收完成证明。

## 逐页实际源码

已完整阅读旧GradeScreen（385行）、GradeViewModel及其两项测试、GradeScreenLogicTest全部统计与格式规则、GradeScoreWatchViewModel及五项测试、GradeScoreCacheStore与两项隔离/清理测试；复读MainAppScreen的账号key/首页bootstrap/通知消费和HomeScreen的横幅位置/操作。协议来源为GradeApi、LocalGradeApi、model/dto/Grade.kt、LocalScheduleApiBackendTest中成绩请求Mock，示例App模块与既有source-parity.md“未改变的成绩证据”。

| 旧版依据 | 保留行为 | 必要优化/当前公开上限 | 实施定位 |
|---|---|---|---|
| GradeScreen先全部成绩统计卡，再本学期统计，再Outlined课程卡；列表16边距/12间距，课程名及右侧分数徽章，详细字段逐行 | 三端同结构，统计随列表滚动；搜索/学期/已出待出仅顶栏按需面板 | 本学期必须来自该学期完整未筛选集合，全部成绩必须真的读所有学期，不能用当前页冒充；局部失败明确部分覆盖 | UI新增academic成绩内容/flow；Domain统计与typed集合概览 |
| 旧gradeDetailRows课程号/学分/课程属性/课程类别/考试性质/考试类型/成绩类型，无逐门绩点 | 恢复公开可证明的字段和顺序；现有公开绩点仍在按需详情保留 | 旧BuaaScoreCourse.toGrade明确courseType→courseAttribute、scoreType→recognitionType，因此可标课程属性/成绩类型；公开Bridge没有类别、性质、考试类型，不猜、不增协议 | 原GradePresentation的8公开字段，无Bridge变更 |
| GradeViewModel当前学期优先显示，所有学期并发读取，termGrades缓存；选择学期复用已读；刷新保旧数据；全局统计加载中 | 学期实际列表、单学期独立缓存、全部统计加载状态，当前页输入不覆盖聚合 | 当前选中学期只接受唯一selected，不把第一项伪称当前；重复学期不重复加总；某学期失败保成功项并明确覆盖率；账号/路由/生命周期/代数使在途旧结果失效 | App独立成绩读取/聚合缓存，不覆盖全局query snapshot；宿主回调 |
| GradeScoreWatch只检查当前学期；首次非空只建基线，空列表不覆盖；同分无新提醒；变化/新增已出/原分被清空提示，删除课程不提示；通知保留到查看/忽略 | 首页今日课程标题之后、课程列表之前出现旧横幅；仅有变化才显示，查看/忽略消费 | 本地缓存按账号和实际route隔离，不碰Core config/session；旧本地成绩API没有WID，旧key会落到code/name，不能造ID；重复code/name歧义不冒充唯一课程更新 | E2后续本地GradeScoreStore和首页watch接线，明确不是系统推送 |

## 统计规则（逐行与旧测试一致）

课程数为全部条目，学分合计为正学分，包含未出分和通过/不通过课程。只有正学分且score可同时转换绩点/数值得分才参与三平均；原gradePoint不参与公式。优/优秀=4与90、良/良好=3.5与80、中/中等=2.8与70、及格=1.7与60、不及格=0与0；通过/不通过排除。数值分低于60绩点0，否则4−3×(100−score)²/1600，故数值60是1.0，文字及格是1.7，不擅自统一。GPA和加权分按学分，算数平均按纳入门数；Kotlin round为中点取偶，移植不能改成Dart中点远离零。无参与项为null而非0。必要可靠性补充：非有限数不污染整个统计，异常原始分数仍在课程详情可读；不增加排名、官方学业判定或推断学校规则。

## 逐操作协议审查

| 操作 | 启动/服务URL | 跳转/最终URL | Cookie/会话 | 方法/精确参数 | 请求头/编码 | 加密 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 学期列表 | 继承source-parity.md课表学期/AAS证据与LocalScheduleApiBackendTest | Core固定允许主机/落地规则 | 原路线内教务会话 | 既有scheduleTerms，无新增入参 | 原GET/header | 无新增 | 原code/name/selected/index | 复用已实现loadAcademicTerms同代合并/失效机制 | 原稳定错误，不伪空或猜当前 |
| 单学期全部/已出/待出成绩 | 旧LocalGradeApi先GET https://app.buaa.edu.cn/buaascore/wap/default/index，再同URL查成绩 | 原Core登录重定向处理，401/SSO落地与登录页面标记失效判定不改变 | 原主认证+成绩激活会话；宿主不可访问Cookie | POST表单xq=semester、year=year；从真实term编码解析，不增加字段 | 页面Accept text/html等；查询Accept JSON、XHR和同页面Referer；FormDataContent编码 | 无新增 | 旧e/m/d，map values→BuaaScoreCourse→GradeData(termCode为请求原值)；公开BridgeGradeData.termCode和8字段原样投影。新增App集合元数据保留请求/响应学期和未筛选grades | 现有单次读取不改；新聚合仅组合已有read API，缓存按backend identity/lifecycle/epoch与学期；不替换领域当前查询 | 原严格输入/上游/解析错误。非当前学期失败展示部分统计，认证失效仍阻断并失效旧结果 |
| 全学期统计 | 无新URL，逐项调用上一行 | 每个结果记录实际route；Auto不是实际route，多路线聚合须反映在同一个顶栏图标说明中 | 同上，不跨账号或线路混入缓存 | 真实学期列表每个唯一term一次，按旧并发读取，当前已确认的未筛选集合可复用 | 同上 | 无新增 | 只聚合已匹配学期完整公开集合，不从搜索/分页/已出视图计算总览 | 在途合并、force只绕过完成缓存；选择/关闭面板不自动重查全部 | 局部失败不标全部，真实空学期为有效零门；迟到结果不得复活 |
| 首页成绩更新检查 | 无新URL，只查唯一当前学期 | 原业务读取路线 | 本地派生基线独立文件，账号+实际route隔离；既有会话只读 | 上一行既有单学期查询 | 同上 | 无新增 | 原分数字符串trim，code/name fallback来自旧实现；不导出个人课程/分数到证据 | 首页可见触发，同代缓存，不后台定时访问学校；空结果不覆盖基线 | 错误保原提醒/基线，不报告更新成功；缓存损坏不覆盖旧文件 |

示例api/app的激活为微信小程序cas-login、固定APP_UA和GET通用请求，与成绩表单协议不等价；不采用其URL、UA、数据模型或错误正文。示例没有等价成绩页/统计/变化缓存，不通过相似模块猜行为。Core/Bridge v9/CLI v10、认证协议与写入资格不改变。

分批执行：E2a完整集合投影+旧统计/卡片+全学期聚合；E2b首页通知与账号路线隔离本地基线。每批分别RED→实现→GREEN→三端实际渲染/操作/修复→必需门禁→阶段提交。真实学校写入继续禁止；真实成绩读取安全账号授权已具备，个人字段不截图/归档。

## E2a实施补充与原生发现

旧统计与课程卡、完整集合投影及独立聚合均已实现。presentation/grades.dart让原始读取和已缓存学期/视图共用白名单投影；仅改变学期/视图时复用已完成缓存，同查询刷新仍走原backend。已接受的新集合优先于较早在途统计，失败后不允许换视图复活旧成功；认证失效清除本批统计结果。明确刷新完成的当前学期可被本次聚合复用，避免同次刷新再读一次当前学期。

macOS实窗额外发现既有_AcademicTermDialog固定360内容高度导致两个选项仍为528高；这是旧方向要求下的必要细节优化，不改变选择/应用/取消次序。新增高度行为RED后改成内容自适应与0.65视口滚动上限，课表/考试/成绩8项选择器回归通过，手机与macOS原路径已复验；iPad最后查询复验进行中。640项门禁后追加此修复，最终全Flutter641项通过。

生产Direct/WebVPN已各完成9/9学期、82条完整成绩聚合、当前三视图及本地详情；当前学期14条均未出分，已出视图为真实空，不造分数。每项actualRoute匹配预期；全部真实业务写入0。这些证据不覆盖尚未实现的E2b首页变化通知。

E2a最后补验：三端r3正常查询/学期弹窗各2场景均通过，108张候选原图已复核；E2a可分阶段提交，E2b继续。
