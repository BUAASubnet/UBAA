# 本科课表、考试、成绩与空教室

本文件收录本科教务课表、考试、成绩、空教室及 Android 桌面课表组件的来源对照；研究生系统见 [GSMIS](gsmis.md)。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### 未改变的课表/考试证据

2026-10-25 首页考试待办接线见[本轮来源对照](home.md#首页考试待办)。

`LocalScheduleApi.kt` 探测 `currentUser.do`；`Schedule.kt` 和
`LocalScheduleApiBackendTest.kt` 证明学期/教学周/今日/考试 GET 请求，以及周课表表单字段
`termCode`、`type=week`、`week`。固定的 `api/aas/core.rs` 证明相同的 AAS 专用 CAS 激活和最终
落地 URL。固定的 `api/aas/opt.rs` 使用包含 `campusCode` 的不同查询正文，UBAA 2 没有本地或
实时证据时不借用该字段。不涉及加密；路线锁定、本科不支持分类和脱敏解析器 Fixture 仍是必需项。

2026-08-25 Direct 和 WebVPN 实时结构检查返回成功的 `WeeklySchedule` 信封，包含冻结的
`arrangedList`、`code`、`name` 字段；列表为空，`data.code` 是非空字符串且不同于选定学期。冻结
DTO/解析器只解码 `WeeklyScheduleResponse.datas`，不要求两者相等。因此实时验证器仅检查
`data.code` 为非空字符串；请求学期仍从学期响应选择并原样发送，不得凭空增加两份冻结来源均未
支持的相等规则。

### 未改变的成绩证据

`LocalGradeApi.kt` 证明先在 `https://app.buaa.edu.cn/buaascore/wap/default/index` 激活，再以
表单 POST 发送 `xq` 和 `year`；`Grade.kt` 证明 `e/m/d` 信封及标量映射。固定 App 模块不适用且
不等价，未提供本地成绩 URL、DTO 或错误语义。旧版独立成绩缓存不能作为上游请求缓存证据。UBAA 2
保留严格的 `yyyy-yyyy-semester` 解析，以及稳定的输入无效/上游/解析错误。

### 空教室会话同步

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**`LocalClassroomApi.kt::classroomSyncUrl` 中的精确 SSO 服务地址，包含编码的 `a_buaa/api/cas/index`、redirect、`from=wap`、`login_from=` 和 `noAutoRedirect=1`。**示例：**`api/class/*` 是 iClass 地址，不适用且不等价。**决策：**只使用旧版空教室引导。 | **旧版：**共享跟随跳转的客户端，任意 200..399 均标记同步成功。**示例：**不适用。**决策：**完整地址按路线转换；在实时证据改变前保留旧接受范围。 | **旧版：**所选模式的 Cookie jar，`sessionSynced` 属于单个后端。**示例：**`Sessionid` 是无关的 iClass 令牌。**决策：**每路线/客户端一份同步状态，绝不全局或跨路线共享。 | **旧版：**GET 精确服务地址。**示例：**不适用。 | **旧版：**精确的长 Android/WeCom `User-Agent`，无正文。**示例：**不适用。**决策：**保持旧版 UA。 | **旧版/示例：**不适用。 | **旧版：**只由 HTTP 状态驱动同步标志。**示例：**不适用。**决策：**不向宿主暴露响应 DTO。 | **旧版：**双重检查 `Mutex`，在清缓存/会话重置前每个后端只执行一次。**示例：**不适用。**决策：**复现每路线一次同步，并在失效、注销、重新登录时清理。 | **旧版：**异常由 `runCatching` 吞掉，查询继续并在后续分类认证/上游。**示例：**不适用。**决策：**保留尽力同步边界，不把同步成功单独报告为业务成功。

### 空教室查询

当前实现补充：`crates/ubaa_core/src/features/classroom.rs::parse_response` 与冻结
`LocalClassroomApi` 一致，仅要求完整 `e/m/d.list` 信封和教室字符串字段；`e` 的具体数值
不作为额外成功门控，而是原样保留在 `ClassroomQuery.code`。脱敏回归测试覆盖 `e=1`
的兼容解析，避免引入旧版不存在的非零状态码拒绝。

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**需要先同步教室，GET `https://app.buaa.edu.cn/buaafreeclass/wap/default/search1`。**示例：**iClass 查询不适用且不等价。**决策：**只使用旧版空教室地址。 | **旧版：**查询使用不跟随跳转的客户端，SSO Location/HTML 表示会话过期。**示例：**不适用。**决策：**两条路线都关闭本次请求的跳转。 | **旧版：**当前路线 Cookie jar 和本地认证预检。**示例：**不适用。**决策：**所选路线槽位及其同步状态。 | **旧版：**GET 查询 `xqid=<int>`、`floorid=""`、`date=yyyy-mm-dd`。**示例：**不适用。**决策：**保留精确参数。 | **旧版：**精确长 UA、`Accept: application/json, text/javascript, */*; q=0.01`、路线转换后的 Referer `https://app.buaa.edu.cn/site/classRoomQuery/index`、`X-Requested-With: XMLHttpRequest`，无正文。**示例：**不适用。 | **旧版/示例：**不适用。 | **旧版：**必需 `e:int`、`m:string`、`d` 和 `d.list: Map<String,List<ClassroomInfo>>`；教室要求字符串 `id`、`floorid`、`name`、`kxsds`。**示例：**不适用。**决策：**缺少 `d/list` 是解析错误，不是空成功；真实空 map 仍算成功。 | **旧版：**无结果缓存，同步互斥锁同上。**示例：**不适用。**决策：**保持一致。 | **旧版：**缺少认证、SSO/401 失效、非 200 上游或解析失败；日期校验由宿主 API 负责。**决策：**使用稳定的 `invalid_input`、`authentication_required`、上游和解析错误；除非矩阵明确允许，否则不回退。

2026-08-24 的确定性实现证据：解析测试拒绝缺失 `e/m/d/list` 任一必需层和非字符串教室字段，同时
保留真实空映射。传输测试断言冻结完整移动端 `User-Agent`、XHR/Accept 请求头、路线转换后的
Referer、每客户端一次且路线隔离的同步、尽力失败后的重试，以及一次不跟随重定向的业务请求。
原始 SSO Location、401 和登录 HTML 均返回 `authentication_required`，清理选定的持久化路线及
功能状态；成功替换会话会强制后续再次同步。状态级并发测试证明双重检查异步互斥锁只执行一次
同步。固定示例 Classroom API 不等价，未向本实现提供协议值。

## 专项记录

### 课表默认下载整学期

#### 实施前来源核对

2026-10-23，`just refs` 确认旧版固定为 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api 固定为 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本次改变入口调度和保存后的本地展示，不新增学校协议。

核对旧版 `ScheduleApi.kt`、`LocalScheduleApi.kt`、`model/dto/Schedule.kt`、`ScheduleRepository.kt`、`ScheduleViewModel.kt` 和对应仓库、API 测试；另一来源核对 `src/api/aas/{core,opt,data}.rs`、`src/request.rs`。认证、共享 Cookie、加密与存储的完整来源矩阵继承[离线恢复对照 P4-B、P4-Y 至 P4-AB](offline-cache.md#离线恢复逐操作来源对照)与[现行认证修复](auth-session.md#sso-传输协议与-uc-激活链对照)。

| 操作 | bootstrap、service、跳转与 Cookie | 方法、精确参数、头与编码 | DTO、缓存并发与错误 |
| --- | --- | --- | --- |
| 学期索引 | 原 currentUser 能力检查，必要时原 AAS CAS service：`https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp`；原重定向及业务终点验证；共享当前账号、实际路线会话 | GET `/jwapp/sys/homeapp/api/home/student/schoolCalendars.do`，无参数；沿旧版 AJAX Accept、X-Requested-With、映射后的首页 Referer | 原 code 与学期列表，唯一 selected 才自动选择；完整导入的学期必须存在；失败保留旧内容 |
| 教学周索引 | 同学期索引；每批完成原会话维护后让出队列，不复制 Cookie | GET `/jwapp/sys/homeapp/api/home/getTermWeeks.do`，query `termCode`；原 AJAX 头 | 原 term、number、日期和当前周标记；导入要求正且唯一周次、合法日期和所属学期；未知当前周仍可人工选择 |
| 各周课表 | 同学期索引；固定账号、学期和路线代次，取消或归属变化丢弃迟到结果 | POST `/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do`，表单 `termCode`、`type=week`、`week`，form-urlencoded 和原 AJAX 头；没有 campusCode | 原 arrangedList、notArrangeList、节次及课程 DTO；本科 WeeklySchedule.code 是学号，不是学期；所有周成功才原子保存，失败不覆盖旧完整学期 |
| 下载后的当前周展示 | 只读取本地，校验账号、实际路线、学期和周次；无需 CAS、跳转或 Cookie | 无 HTTP、头、编码、加密或签名变更；复用 OfflineQueryBackend | 只接受完整的精确查询投影，保留原查询修订和数据取得时间；并发切周或新读取后不覆盖当前快照；读取失败保留原内容并记录本地诊断 |

上述各在线操作均沿现有加密、签名、认证恢复与错误映射，无新增常量或错误代码。buaa-api 没有同构持久导入；其周/学期请求通过 query 传递 `campusCode`，学期请求使用 `type=term`，与旧版本科表单路径不同，本轮不采用。旧版研究生有专用适配，本轮不扩展当前 Core 的协议覆盖。完整导入的 code=0 和完整度约束继续 P4-Z，不改变普通读取容错或 CLI 退出语义。

#### 界面行为

用户要求打开课表并确定学期后自动下载整学期，不再点击保存确认。每个界面生命周期内，同一学期只自动尝试一次；正在下载、已完成、失败或已取消均不会因重建或切周再次自动触发。账号、路线或缓存代次改变后重新按现有归属规则判断。学期来源不明确时仍需选择学期，不猜测第一个学期。

右上角刷新使用当前已应用查询的学期，重新运行整学期任务；查询面板内未提交草稿不参与。重复点击由现有任务合并。下载完成后从本地精确投影更新当前周，保留所选周次。失败或取消显示重试，旧数据继续可见。底部只显示进度或结果，不保留首次保存按钮。

#### 验证

实施前反例：三个屏宽的默认下载用例没有启动任务，App 完成导入后当前周仍为空，缓存回读等待未发生，均按预期失败。兼容性复查又用旧 summary 周查询复现未更新当前周，再修复为与 scheduleWeek 一致。RED 日志保存在仓库外私有验收目录。

最终验证：

- 七包格式、分析及测试通过：Domain 53、Platform 84、App 660、UI 367、Bindings 20、Host 101、官方宿主 75，共 1360 项。UI 首次分析发现空状态提前返回后残留的不可达分支，已修正并通过后续完整检查。
- UI 覆盖手机 390、平板 834、桌面 1280 宽度及大字；自动下载、取消、失败重试、右上角整学期刷新均保留当前查询。另覆盖隐藏页、重建、切周、切学期、生命周期代次，以及已有任务不重复启动。
- App 覆盖下载后当前周本地更新、不额外在线单周请求、迟到回读不覆盖切周结果、错账号/路线/查询/完整度拒绝和本地读取失败保留旧快照。复用原任务合并、取消、切路线、退出、清理及并发队列测试。
- 生产 Host 用真实控件进入课表即启动任务，取消后点击右上角刷新重新下载同一学期；使用合成后端，不提交学校写入。该用例替代直接调用宿主回调的旧测试，保留原接线与取消覆盖。
- `just refs`、`just check`、`just check-sensitive`、FRB 生成零漂移通过。`just check-plan` 包含既有未改动的 `.serena/` 而选择全量，本次执行完整门禁；`.serena/` 不纳入提交。

自动化验证使用合成后端和固定夹具，没有运行新的真实账号双路线专项验收。应用重建启动用于用户检查，不计作人工界面验收。所有预览继续本地保留并受 Git 忽略，运行日志保存在仓库外私有目录。

macOS Debug 最终构建成功，并按原隔离检查配置重新启动，供用户检查实际界面。

#### 后续展示调整：静默同步

用户进一步要求隐藏整学期下载和上次保存时间。课表不再显示正常下载进度、完成与取消提示，右上角文案简化为“刷新”，后台仍更新整学期。刷新失败仅显示简短错误和重试，空间不足提示清理；课表正文、首页今日课表及学期/教学周选择去掉保存时间。底层缓存、导入、日期过滤和查询行为保持。

本次为展示调整，不新增测试。移除 UI 进度/成功提示、保存时间和取消控件断言，保留原自动调用、失败重试、固定学期、当前周和未重复发起单周查询的覆盖；宿主测试由取消后刷新改为失败后刷新，取消保护继续由 App 的 `controller_import_test.dart` 覆盖。学期选择测试继续验证缓存选项填入草稿，首页测试继续验证空课表与跨校园日过滤。未删除测试用例。

展示调整验证：聚焦的课表、首页缓存、学期选择和宿主回归通过；按本轮实际修改范围运行 UI 367、Host 101、官方宿主 75 项测试，共 543 项通过，格式分析、冻结来源、敏感扫描、结构与模块检查通过。`just check-plan` 因原有未跟踪 `.serena/` 保守选择全量，本轮将实际修改路径交给同一选择器执行 UI 及依赖宿主门禁，未将历史 Rust 检查作为本轮结果。macOS Debug 已重建并按原配置重新打开；预览保持本地忽略。

### 2026-10-03 Android桌面课表

三种旧版桌面组件、本地读取九列、加密投影/账号边界与验收方案见[Android组件对照](#android-桌面课表组件对照与实施)。当前实施中，不属于已通过能力。

### Android 桌面课表组件对照与实施

状态：功能已实现，原生及Launcher实测已取得；整体项目验收仍受桌面锁屏和外部数据条件限制。两冻结来源及提交沿用 references.md：ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本轮起点的Flutter Android只有主Activity和选图通道，缺少三种桌面课表Provider；本轮已补齐。

#### 依据与行为

已核对旧版 `composeApp/src/androidMain/kotlin/cn/edu/ubaa/widget/` 下 Provider、Renderer、Activity，以及对应 layout/XML；共享 `repository/ScheduleRepository.kt`、`SavedScheduleWeek.kt` 提供持久化与选周规则，`model/dto/Schedule.kt` 提供课程及时间轴。示例的 `api/aas` 有在线课表协议，无Android桌面组件/本地学期库/UI/同周跳转，不借用其字段或网络请求补组件。

| 操作 | CAS/bootstrap/service | 重定向/final URL | Cookie/会话 | 方法/参数 | headers/body | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 发布本地课表 | 无新增网络 | 不适用 | 绑定当前本地随机账号别名，不导出用户名/秘密 | 只用既有OfflineQueryBackend精确本地读取 | 本机typed MethodChannel，无HTTP | 复用Core已加密课表投影，Android宿主副本另用Keystore AES-GCM，无明文降级 | 学期/周/课程/节次仅既有投影字段；未知时间不补猜 | 完整覆盖学期才发布，scope/epoch改变后旧异步结果拒绝 | 缺数据/系统存储不可用如实空态，不伪装在线成功 |
| 周组件上一周/下一周/本周 | 无 | 不适用 | 账号别名+当前周一anchor绑定选择 | 本机PendingIntent步长-1/0/1，不查询学校 | 不适用 | 不新增上游签名 | 按旧版学期日期选择、周编号排序；保留真实空周 | 同账号同anchor保留选择；换账号/跨周重置 | 首末周禁用越界按钮 |
| 今日/未来三天 | 无 | 不适用 | 同一当前账号 | 本地上海日期起1/3天 | 不适用 | 同上 | 按实际周日期和weekday筛课、按开始时间排序；跨周/学期单独选周 | 使用已发布加密本地投影，系统周期刷新 | 日期未覆盖不展示其他周课程 |
| 点击组件 | 无新增网络 | 不适用 | 核对widget owner与当前本地账号 | 打开相同term/week的离线视图；外部intent不授予登录/写资格 | 不适用 | 不适用 | 原始term/week，不从显示文字重建 | 冷/热启动均消费明确目标；账号错配拒绝 | 不等待在线认证、不发学校写请求 |
| 退出/切账号/清缓存 | 无新增网络 | 不适用 | 旧owner失效 | 本机清理与刷新 | 不适用 | 删除宿主副本，系统密钥失败不降级 | 不保留旧文字/图片 | native scope令牌阻止迟到发布；组件显式清图与文字 | 清理失败如实报告，旧账号不再可见 |

#### 实现边界

不新增Bridge/CLI/HTTP协议。共享Dart层只从现有加密缓存抽取只读课表，生产只有Android启用宿主组件；其他平台不增加空壳入口。Android三种Provider沿旧版RemoteViews+Canvas和紧凑布局自适配；周选择与点击保持旧语义。宿主用系统Keystore生成AES-256-GCM密钥，随机IV、完整性校验与私有原子文件；不写日志/明文SharedPreferences中的课程或个人字段。账号以现有随机LocalAccount.id绑定，避免导出真实账号。持久化失效与后台发布的先后顺序由Dart竞态测试和原生Keystore测试验证。

Android实现依据官方[组件指南](https://developer.android.com/develop/ui/views/appwidgets)、[更新机制](https://developer.android.com/develop/ui/views/appwidgets/advanced)与[密码学指南](https://developer.android.com/privacy-and-security/cryptography)。系统API说明只用于宿主接线，不作为学校协议证据。

#### 原生启动问题与裁决

正式Android入口实测另发现平台目录解析只为iOS接原生路径，而Android假定HOME存在；无HOME的真实应用进程抛出“应用私有目录暂不可用”，不能由APK构建通过抵消。这是宿主启动问题，不新增学校协议；冻结旧版使用其Android平台持久化宿主，buaa-api无Android应用目录。沿当前iOS的既有 `paths.config` MethodChannel契约，为Android返回系统 `noBackupFilesDir/UBAA`，只创建自身私有目录、不读取或迁移原用户数据；失败继续明确报错，不改用公共目录。空环境行为测试已复现RED。

目录修复后真实Android的Bridge.open仍失败；直接FRB测试取得稳定错误 `internalError/internal could not lock session`。本机锁定Rust1.95标准库 `sys/fs/unix.rs` 证实File::lock的目标列表不含Android，落入Unsupported分支；不是学校协议或账号失败。冻结两来源没有当前Rust双路线会话修订锁实现。仅Android采用fs2的flock封装，保留操作系统排他锁与原进程Mutex，其他平台沿原File::lock；不删除锁、改内存会话或明文降级。对应[标准库问题](https://github.com/rust-lang/rust/issues/148325)及[fs2接口](https://docs.rs/fs2/0.4.3/fs2/trait.FileExt.html)。

真实Android网络准备进一步失败。当前reqwest锁定依赖rustls-platform-verifier 0.7.0，源码Android验证路径要求先登记JVM、Context和ClassLoader；当前宿主未提供初始化，也未打包其Kotlin证书验证组件。遵循锁定依赖[官方Android说明](https://docs.rs/rustls-platform-verifier/0.7.0/rustls_platform_verifier/android/index.html)补宿主JNI初始化及由`cargo metadata --locked`定位的本地AAR，不更换根证书、不关闭TLS。两冻结参考没有Rustls宿主初始化实现，此处不借用学校URL、字段或签名。旧prepareLogin本身准备双槽，试验只判定WebVPN槽，绝不将Direct尝试记为Direct验证通过。

已建立独立Android 36 arm64模拟器，不放入真实账号。投影和详情字段先RED后GREEN；2项原生加密/代次测试、1项渲染与账号错配测试、2项Flutter→原生通道/Core启动测试，以及Launcher真实添加/翻周/同周跳转/课程详情/学期与周选择/滑动/拉伸/跨周三天均取得证据。完整记录见[Android阶段证据](../../archive/evidence/project-android-widgets-2026-10-03.md)。系统widget不等同macOS按钮验证。

## 历史专项

### 成绩旧版统计、卡片与更新提醒对照（O3-E2）

2026-09-09，实施基点e22afa5a。冻结旧版6e75e120a26b0eefb3ab4a6f8251d1230db4a62e、示例efb7976bf513f38364b88aeb83d704586cff9b2a；普通开发仅校验refs。本文在生产修改前建立，当前是实施依据，不是实现/验收完成证明。

#### 逐页实际源码

已完整阅读旧GradeScreen（385行）、GradeViewModel及其两项测试、GradeScreenLogicTest全部统计与格式规则、GradeScoreWatchViewModel及五项测试、GradeScoreCacheStore与两项隔离/清理测试；复读MainAppScreen的账号key/首页bootstrap/通知消费和HomeScreen的横幅位置/操作。协议来源为GradeApi、LocalGradeApi、model/dto/Grade.kt、LocalScheduleApiBackendTest中成绩请求Mock，示例App模块与既有source-parity.md“未改变的成绩证据”。

| 旧版依据 | 保留行为 | 必要优化/当前公开上限 | 实施定位 |
|---|---|---|---|
| GradeScreen先全部成绩统计卡，再本学期统计，再Outlined课程卡；列表16边距/12间距，课程名及右侧分数徽章，详细字段逐行 | 三端同结构，统计随列表滚动；搜索/学期/已出待出仅顶栏按需面板 | 本学期必须来自该学期完整未筛选集合，全部成绩必须真的读所有学期，不能用当前页冒充；局部失败明确部分覆盖 | UI新增academic成绩内容/flow；Domain统计与typed集合概览 |
| 旧gradeDetailRows课程号/学分/课程属性/课程类别/考试性质/考试类型/成绩类型，无逐门绩点 | 恢复公开可证明的字段和顺序；现有公开绩点仍在按需详情保留 | 旧BuaaScoreCourse.toGrade明确courseType→courseAttribute、scoreType→recognitionType，因此可标课程属性/成绩类型；公开Bridge没有类别、性质、考试类型，不猜、不增协议 | 原GradePresentation的8公开字段，无Bridge变更 |
| GradeViewModel当前学期优先显示，所有学期并发读取，termGrades缓存；选择学期复用已读；刷新保旧数据；全局统计加载中 | 学期实际列表、单学期独立缓存、全部统计加载状态，当前页输入不覆盖聚合 | 当前选中学期只接受唯一selected，不把第一项伪称当前；重复学期不重复加总；某学期失败保成功项并明确覆盖率；账号/路由/生命周期/代数使在途旧结果失效 | App独立成绩读取/聚合缓存，不覆盖全局query snapshot；宿主回调 |
| GradeScoreWatch只检查当前学期；首次非空只建基线，空列表不覆盖；同分无新提醒；变化/新增已出/原分被清空提示，删除课程不提示；通知保留到查看/忽略 | 首页今日课程标题之后、课程列表之前出现旧横幅；仅有变化才显示，查看/忽略消费 | 本地缓存按账号和实际route隔离，不碰Core config/session；旧本地成绩API没有WID，旧key会落到code/name，不能造ID；重复code/name歧义不冒充唯一课程更新 | E2后续本地GradeScoreStore和首页watch接线，明确不是系统推送 |

#### 统计规则（逐行与旧测试一致）

课程数为全部条目，学分合计为正学分，包含未出分和通过/不通过课程。只有正学分且score可同时转换绩点/数值得分才参与三平均；原gradePoint不参与公式。优/优秀=4与90、良/良好=3.5与80、中/中等=2.8与70、及格=1.7与60、不及格=0与0；通过/不通过排除。数值分低于60绩点0，否则4−3×(100−score)²/1600，故数值60是1.0，文字及格是1.7，不擅自统一。GPA和加权分按学分，算数平均按纳入门数；Kotlin round为中点取偶，移植不能改成Dart中点远离零。无参与项为null而非0。必要可靠性补充：非有限数不污染整个统计，异常原始分数仍在课程详情可读；不增加排名、官方学业判定或推断学校规则。

#### 逐操作协议审查

| 操作 | 启动/服务URL | 跳转/最终URL | Cookie/会话 | 方法/精确参数 | 请求头/编码 | 加密 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 学期列表 | 继承source-parity.md课表学期/AAS证据与LocalScheduleApiBackendTest | Core固定允许主机/落地规则 | 原路线内教务会话 | 既有scheduleTerms，无新增入参 | 原GET/header | 无新增 | 原code/name/selected/index | 复用已实现loadAcademicTerms同代合并/失效机制 | 原稳定错误，不伪空或猜当前 |
| 单学期全部/已出/待出成绩 | 旧LocalGradeApi先GET https://app.buaa.edu.cn/buaascore/wap/default/index，再同URL查成绩 | 原Core登录重定向处理，401/SSO落地与登录页面标记失效判定不改变 | 原主认证+成绩激活会话；宿主不可访问Cookie | POST表单xq=semester、year=year；从真实term编码解析，不增加字段 | 页面Accept text/html等；查询Accept JSON、XHR和同页面Referer；FormDataContent编码 | 无新增 | 旧e/m/d，map values→BuaaScoreCourse→GradeData(termCode为请求原值)；公开BridgeGradeData.termCode和8字段原样投影。新增App集合元数据保留请求/响应学期和未筛选grades | 现有单次读取不改；新聚合仅组合已有read API，缓存按backend identity/lifecycle/epoch与学期；不替换领域当前查询 | 原严格输入/上游/解析错误。非当前学期失败展示部分统计，认证失效仍阻断并失效旧结果 |
| 全学期统计 | 无新URL，逐项调用上一行 | 每个结果记录实际route；Auto不是实际route，多路线聚合须反映在同一个顶栏图标说明中 | 同上，不跨账号或线路混入缓存 | 真实学期列表每个唯一term一次，按旧并发读取，当前已确认的未筛选集合可复用 | 同上 | 无新增 | 只聚合已匹配学期完整公开集合，不从搜索/分页/已出视图计算总览 | 在途合并、force只绕过完成缓存；选择/关闭面板不自动重查全部 | 局部失败不标全部，真实空学期为有效零门；迟到结果不得复活 |
| 首页成绩更新检查 | 无新URL，只查唯一当前学期 | 原业务读取路线 | 本地派生基线独立文件，账号+实际route隔离；既有会话只读 | 上一行既有单学期查询 | 同上 | 无新增 | 原分数字符串trim，code/name fallback来自旧实现；不导出个人课程/分数到证据 | 首页可见触发，同代缓存，不后台定时访问学校；空结果不覆盖基线 | 错误保原提醒/基线，不报告更新成功；缓存损坏不覆盖旧文件 |

示例api/app的激活为微信小程序cas-login、固定APP_UA和GET通用请求，与成绩表单协议不等价；不采用其URL、UA、数据模型或错误正文。示例没有等价成绩页/统计/变化缓存，不通过相似模块猜行为。Core/Bridge v9/CLI v10、认证协议与写入资格不改变。

分批执行：E2a完整集合投影+旧统计/卡片+全学期聚合；E2b首页通知与账号路线隔离本地基线。每批分别RED→实现→GREEN→三端实际渲染/操作/修复→必需门禁→阶段提交。真实学校写入继续禁止；真实成绩读取安全账号授权已具备，个人字段不截图/归档。

#### E2a实施补充与原生发现

旧统计与课程卡、完整集合投影及独立聚合均已实现。presentation/grades.dart让原始读取和已缓存学期/视图共用白名单投影；仅改变学期/视图时复用已完成缓存，同查询刷新仍走原backend。已接受的新集合优先于较早在途统计，失败后不允许换视图复活旧成功；认证失效清除本批统计结果。明确刷新完成的当前学期可被本次聚合复用，避免同次刷新再读一次当前学期。

macOS实窗额外发现既有_AcademicTermDialog固定360内容高度导致两个选项仍为528高；这是旧方向要求下的必要细节优化，不改变选择/应用/取消次序。新增高度行为RED后改成内容自适应与0.65视口滚动上限，课表/考试/成绩8项选择器回归通过，手机与macOS原路径已复验；iPad最后查询复验进行中。640项门禁后追加此修复，最终全Flutter641项通过。

生产Direct/WebVPN已各完成9/9学期、82条完整成绩聚合、当前三视图及本地详情；当前学期14条均未出分，已出视图为真实空，不造分数。每项actualRoute匹配预期；全部真实业务写入0。这些证据不覆盖尚未实现的E2b首页变化通知。

E2a最后补验：三端r3正常查询/学期弹窗各2场景均通过，108张候选原图已复核；E2a可分阶段提交，E2b继续。

#### E2b实施与必要优化（2026-09-09）

Domain的GradeScoreBaseline按旧当前学期分数比较；首次非空仅建基线，空集合和失败不覆盖，新增未出分或删除课程不提示，同分不消费原通知。重复code/name的歧义条目保留在基线但不比较，避免误报。唯一selected当前学期由原真实选项决定，缺失或重复不猜。GradeScoreWatch复用已有当前成绩缓存，同代合并、按需刷新，账号/策略/代数变化使在途结果失效；无后台学校轮询。

复读冻结ConnectionRuntime.kt:107–127：旧resetSession同时清认证、会话和GradeScoreCacheStore全部scope。新实现不移植该认证重置，独立ui-grade-scores.json按账号与实际路线保存基线；切路线清在途通知但保各scope，首次路线仅建基线，后续同scope比较。明确“退出并清除本机账号”在原注销之后串行清该账号全部路线，保其他账号；普通退出保留派生基线。此为本地状态隔离的必要优化，Core会话、认证协议及公开配置不变。

本地文件schema1，桌面在写内容前设置600，flush后同目录rename；移动端依赖应用私有沙箱。损坏文件不覆盖，不为了清一个账号盲删其他scope。首次原生清理测试发现损坏文件使退出回调抛未处理异常，已增加失败测试后在退出完成的登录页显示“本机数据未能完全清除，请稍后重试。”，不虚称清理成功。

横幅按旧HomeScoreUpdateBanner放在今日标题与课程之间，普通手机保横排，只有不足300宽或文字放大超过1.2倍才换行。首轮原生观察发现普通手机128高，新高度行为RED后收紧。查看消费通知并携带该通知学期打开成绩；忽略仅消费通知。首次实际WebVPN读取没有通知时曾漏报路线，失败测试后单独记录成绩检查的实际route（含已知失败route），与通知来源一起进入首页唯一顶栏说明；从不以默认策略或学期bootstrap冒充成绩路线。

当前实现进入E2b最后三端与生产只读验收，结果在主证据记录更新，不借用E2a或早期E2b截图。
