# 课表与考试

课表模块提供学期、周次、周课表和今日课程；考试模块按学期读取考试安排。两个模块都依赖教务系统数据，并在服务器中转和本地连接模式之间保持同一 DTO 契约。

## 课表能力

- 查询学期列表和周次列表。
- 按学期与周次查看周课表。
- 使用 HorizontalPager 在课表区域跟手拖动换周；已加载的相邻周同时绘制，在线模式在切换到未加载周时查询，松手吸附。箭头和周次选择使用分页动画，到达学期边界不越界。
- 左侧显示完整节次及上下课时间，空课时也显示。研究生导入时保存 `skjcList` 作息表；没有作息表的旧缓存，仅当研究生学期格式及全部已知课程边界与已核验的 01 标准方案一致时，补全标准 14 节。其他方案缺失的时间显示 `--:--`，可手动本地化课表获取上游作息表，避免误用另一套时间。
- 查看今日课程摘要。
- 课程详情页面复用周课表中的课程数据。

### 离线学期课表

- 首次登录后，首页自动在线加载今日课程，课表页在线加载学期、周次及选中周，无需先导入。点击“刷新”重新查询在线课表；浏览不会自动写入本地课表。点击“课表本地化”才下载并保存整个学期。
- 课表页左侧学期名称可切换学期；“本地化系统当前学期”用于保存系统当前学期。已保存的历史学期继续保留，未保存的学期也可直接在线浏览。
- 本地直连/WebVPN 的研究生课表从一次 GSMIS `bykb/loadXskbData.do` 响应生成全部周次；本科及服务器中转依次读取该学期全部周课表。
- 所有周次成功后才保存，失败或取消不会覆盖旧课表。页面展示最后成功本地化时间，本地化失败时仍显示原来的课表。校验请求学期、周次归属、完整性、重复周次及日期，本科周课表的 `code` 实际为学号，不能当作学期代码。本科周次的日期时间先转为 `yyyy-MM-dd` 再保存，保证本地日期比较正确。
- 整学期缓存按小块写入，全部写入成功后才发布新版本，兼容桌面 `Preferences` 的单值长度限制。旧版单值缓存仍可读取，并在下次成功更新后迁移；读取不触发迁移或联网。
- 首页优先调用今日课表接口，网络失败时回退到已本地化课表。学期、周次及周课表查询同样支持失败后读取已保存数据；没有可用本地数据时显示原始查询错误。切换学期浏览不影响首页当天课程。
- 课表按成功登录的学号隔离，切换连接模式不删除缓存。注销后关闭离线访问入口，重新登录同一账号后可再次读取该账号缓存。
- 断网重启后可从登录页点击“查看已保存的离线课表”，查看当天课程和周课表；此入口不授予在线登录状态。尚未成功导入时没有离线课表。
- 博雅、签到、希冀和考试不属于此本地课表，不会由课表缓存自动恢复。

### Android 桌面周课表小组件

- 桌面提供“UBAA 周课表”“UBAA 今日课程”（默认宽4×高2格）和“UBAA 近日课程”（默认宽2×高4格），均允许缩放。HyperOS 等桌面的最终格数由桌面测量决定。
- 周课表在矮尺寸显示七天摘要，拉高后显示含时间轴的完整网格；今日/近日以时间、课程、地点列表展示，近日涵盖从今天起三天并支持跨周。点击进入离线周课表。
- 上一周、下一周、回到本周按钮只读本地缓存；手动切换保留到下一自然周，然后自动回到当前周。无覆盖今天的学期时显示最近保存学期的边界周，并标注实际周开始日期。
- 使用原生 AppWidgetProvider、RemoteViews 和 Canvas，无额外小组件框架。系统周期刷新间隔为 30 分钟，实际执行可能被系统省电策略延后；周期刷新不请求学校系统。应用内成功更新课表、切换账号或注销时通知小组件刷新。
- 小组件只读取当前账号的缓存，注销后清空展示；点击入口不授予登录状态。尚未导入课表时引导打开应用。

### 研究生课表

- 数据源为 GSMIS“我的课表”，入口是 `https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp/*default/index.do`。本地连接与服务器中转复用各自的 SSO 会话和 WebVPN 地址转换。
- 学期列表通过 POST `modules/xskcb/kfdxnxqcx.do` 获取；读取 `datas.kfdxnxqcx.rows`，校验 `totalSize` 和学期代码后选择所需学期。
- 课表通过 POST `bykb/loadXskbData.do` 获取，表单为 `ZC=&XNXQDM=<所选学期>&XH=&XQDM=`。课程来自 `rwList`，排课来自 `jgList`，完整作息表来自 `jcfaList[].skjcList`。
- 已确认本科门户可用的账号继续查询本科课表。门户探测不可用或要求认证时，课表模块保留主会话并验证 GSMIS 课表子应用；由课表接口自身的认证和响应决定是否成功。服务器在课表请求成功后可确认研究生门户类型。
- 本地连接报错区分登录、课表请求和解析阶段，只显示阶段、HTTP 状态或异常类型。主页面不展示响应正文，解析失败时可由用户主动导出本次响应。
- 按周次位图筛选排课，同一教学班、地点、教师及周次的连续节次合并显示。节次和时刻均来自上游，支持第 14 节晚课。
- 使用 `rwList.SCSKRQ` 的首次上课日期和排课周次、星期交叉校验第 1 周的星期一；缺少对应日期或数据冲突时拒绝覆盖缓存。位图长度仅作为可查询周次范围，不代表官方学期长度。
- 已选但未排课的课程不会伪造上课时间；当前周没有排课可以正常显示空课表。
- 直连/WebVPN 需要更新客户端；服务器中转需要部署包含此适配的后端，安装新 APK 不会更新公共服务器。
- 研究生考试安排仍未接入，本次课表适配不改变考试接口的支持范围。

GSMIS 真实样本验证使用仓库外的目录，内含 `课表响应.txt` 和 `学期候选响应.txt`。运行 `./gradlew :shared:jvmTest --tests '*GsmisScheduleSampleTest' -PgsmisScheduleSampleDir=样本目录绝对路径`；也可设置 `UBAA_GSMIS_SCHEDULE_SAMPLE_DIR`。Gradle 会将目录纳入测试输入。当前可选样本测试针对 `20261` 学期和 2026-09-07 开学的样本，其他学期应先调整预期校历。未提供样本时测试跳过。

历史 YJSXK 解析器及网关注入清理只保留作旧样本兼容验证。`-PgraduateScheduleSample=样本绝对路径` 或 `UBAA_GRADUATE_SCHEDULE_SAMPLE` 配合 `--tests '*GraduateScheduleSampleTest'` 验证旧格式。请勿把包含个人信息或登录 Cookie 的响应提交到仓库。
本地直连/WebVPN 的 JSON 解析失败时，课表页可手动复制本次响应以复现问题。响应只留在内存，不自动复制或发送，不包含请求头；仍可能包含姓名、学号和课程信息，请勿公开发布。

## 考试能力

- 按学期查询考试安排。
- 展示考试名称、时间、地点、座位号等考试信息。
- 通过 ViewModel 的 `ensureLoaded()` 避免页面重复加载。

## 技术路径

- `ScheduleApiBackend` 和 `RelayScheduleApiBackend` 负责 relay 模式接口。
- `LocalScheduleApiBackend` 在本地连接模式下访问本科教务上游。
- 服务器的 `ScheduleService` 适配上游课表接口，`ScheduleRoutes` 暴露统一 HTTP API。
- 考试模块通过 `ExamService` 和 `ExamRoutes` 提供 `/api/v1/exam/list`。

## 接口

- `GET /api/v1/schedule/terms`
- `GET /api/v1/schedule/weeks?termCode=...`
- `GET /api/v1/schedule/week?termCode=...&week=...`
- `GET /api/v1/schedule/today`
- `GET /api/v1/exam/list?termCode=...`

## 来源文件

- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/schedule/ScheduleScreen.kt`
- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/schedule/ScheduleViewModel.kt`
- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/exam/ExamScreen.kt`
- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/exam/ExamViewModel.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/ScheduleApi.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalScheduleApi.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/GraduateScheduleUpstream.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/GsmisSchedule.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/repository/ScheduleRepository.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/repository/ScheduleSnapshotStorage.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Schedule.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Exam.kt`
- `server/src/main/kotlin/cn/edu/ubaa/schedule/ScheduleRoutes.kt`
- `server/src/main/kotlin/cn/edu/ubaa/schedule/ScheduleService.kt`
- `server/src/main/kotlin/cn/edu/ubaa/exam/ExamRoutes.kt`
- `server/src/main/kotlin/cn/edu/ubaa/exam/ExamService.kt`
- `server/src/test/kotlin/cn/edu/ubaa/schedule/ScheduleRoutesTest.kt`
- `server/src/test/kotlin/cn/edu/ubaa/exam/ExamRoutesTest.kt`
