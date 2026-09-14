# 博雅类别、校区、完整详情与筛选偏好：实施前对照

日期：2026-09-15。两个冻结来源已现场校验；当前字段/流程索引以41ece772为基线。以下为来源与实施裁决，不是功能或真实App通过记录。

## 主线实施裁决

1. Task3D新增 `BykcCourseCatalogItem/Page`、`BykcCourseFullDetail` 以及 `bykc_course_catalog`、`bykc_course_full_detail`，保留旧列表/详情方法、旧序列化结构和CLI10请求次数。候选Bridge10复用前批版本，不另行升级CLI/Session/配置；Host只消费typed数据。
2. 新完整详情校验返回课程id等于请求id，不匹配为明确上游结构错误；这是新接口的一致性约束，不声称旧版已有此检查。只读已选补查保留旧“内层course_id首项匹配”，无匹配与考勤缺字段分别保持None/null；该显示结果不产生写资格。当前已选父帧的(recordId,courseId)唯一匹配和Unknown保护保持。
3. 所有新完整详情按旧顺序处理selected=true的主请求→配置→已选补查，主配置有效也补考勤；补查失败整次失败，合法无匹配才为空。展示采用主详情配置优先；现有写前校验采用已选配置优先，不能混用。新增Bridge显示配置仅四个可空日期与完整点数，不传原始配置字符串或新增位置调用。
4. 课程列表、我的课程、首页博雅待办三个入口都接完整读取。普通详情中的签到/签退沿现有独立已选读取取得可验证身份后进入现有准备流程；不得从FullDetail.attendance、hasSignPoints或显示文案生成许可。已选详情保留父帧的具体记录、原动作与迟到保护，只追加同课程补充信息；补查记录身份不能覆盖另一个已选记录。
5. 类别和校区按旧三维交集/维度内并集，类别取子类别优先的显示名；保留五个固定类别、校区规范化和已选校区，重置默认同时恢复三维默认值。只筛当前服务器页并明确范围，不偷偷抓取全部页或更改服务器总数。
6. 已确认旧 `BykcCourseFilterStore` 和 `MainAppScreen.kt:260–268,366–375` 按schoolid恢复、保存及默认时清除筛选。因此Task3D2必须补齐账号隔离的跨重启偏好；只存状态枚举/类别/校区三组非秘密偏好。采用独立UI偏好文件/注入存储，复用当前宿主隔离配置目录与本地存储模式，不改Core配置v1或Session2，不存课程列表/详情/联系人/凭据。读取迟到不得覆盖新的编辑或账号，保存失败仍保留本次选择并反馈，明确退出清除时继续清理该账号偏好。
7. 联系人、电话、开课单位、纯文本简介和适用范围按旧字段直接投影，不新增拨号、消息、WebView或附件动作；不自动进入日志/诊断。缺少考勤保持Unknown，不能复制旧null被视为可签到的宽松布尔。

上述接口与身份约束可在未发布候选内调整，但必须保留对应RED、旧API兼容和动作权威。Task3D2未实现时不得把跨重启筛选记为已恢复；当前全项仍待实施与macOS逐按钮实测。

## 1. 约束与来源索引


goal.md第9条已明确允许本专项有来源的typed只读补齐；尚未发布候选统一为 Bridge v10，CLI v10、Session v2、配置 v1 与写入确认权威保持。审计时生产 Bridge 常量仍为 9（crates/ubaa-flutter-bridge/src/api/client.rs:17）；“候选 v10”是本次变更目标，不能写成当前已实现。CLI 常量在 apps/ubaa-cli/src/io/schema.rs:19，Session 在 crates/ubaa-core/src/session/types.rs:97，配置在 crates/ubaa-core/src/config.rs:74–95。

下文定位均相对此工作树；O 前缀统一为 ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e；E 前缀统一为 examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a。

| 简称 | 精确源码路径 |
|---|---|
| O-API | ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/BykcApi.kt |
| O-DTO | ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Bykc.kt |
| O-Local | ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalBykcApi.kt |
| O-Crypto | ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalBykcCrypto.kt |
| O-Connection | ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt |
| O-WebVPN | ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt |
| O-BackendTest | ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalBykcApiBackendTest.kt |
| O-Filter | ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/bykc/BykcCourseFilters.kt |
| O-FilterTest | ubaa_old/composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/screens/bykc/BykcCourseFiltersTest.kt |
| O-FilterStore | ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/BykcCourseFilterStore.kt |
| O-ListUI | ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/bykc/BykcCoursesScreen.kt |
| O-DetailUI | ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/bykc/BykcCourseDetailScreen.kt |
| O-ViewModel | ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/bykc/BykcViewModel.kt |
| O-Navigation | ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/navigation/MainAppScreen.kt |
| E-Core | examples/buaa-api/src/api/boya/core.rs |
| E-Opt | examples/buaa-api/src/api/boya/opt.rs |
| E-Data | examples/buaa-api/src/api/boya/data.rs |
| E-Request | examples/buaa-api/src/request.rs |
| E-Context | examples/buaa-api/src/context.rs |
| E-Cookies | examples/buaa-api/src/store/cookies.rs |
| E-Cred | examples/buaa-api/src/store/cred.rs |
| C-Domain | crates/ubaa-core/src/domain/bykc.rs |
| C-Parser | crates/ubaa-core/src/features/bykc/parser.rs |
| C-Read | crates/ubaa-core/src/features/bykc/read.rs |
| C-Auth | crates/ubaa-core/src/features/bykc/auth.rs |
| C-Write | crates/ubaa-core/src/features/bykc/write.rs |
| C-Facade | crates/ubaa-core/src/facade/read/services.rs |
| B-DTO / B-Map / B-Methods | crates/ubaa-flutter-bridge/src/api/read/mod.rs / mappers.rs / methods.rs |
| A-Read | packages/ubaa_app/lib/src/bridge/read/bykc.dart |
| D-Presentation | packages/ubaa_domain/lib/src/feature/presentation/bykc.dart |
| U-Detail / U-Navigation | packages/ubaa_ui/lib/src/features/bykc/details.dart / packages/ubaa_ui/lib/src/common/read_navigator.dart |

冻结旧 API 的界限：O-API:15–24/65–98 分别定义列表、独立详情、已选与统计；O-API:140–179 是 Relay 宿主 API，不能误当直连上游请求。上游事实采用 O-Local，不从 Relay 的 GET 路径推导学校 POST 协议。

## 2. 请求共用事实

以下 H、K、L、F 是后续各操作九列表的完整展开定义，各行仍分别列明采用范围。

- H（旧版业务请求）：O-Local:447–490。POST 到当前路线包装后的 https://bykc.buaa.edu.cn/sscv/{apiName}；Content-Type 为 application/json; charset=UTF-8，Accept 为 application/json；Referer 为当前路线包装后的 https://bykc.buaa.edu.cn/system/course-select，Origin 为当前路线包装后的 https://bykc.buaa.edu.cn；同时发送 auth_token、authtoken、ak、sk、ts。正文直接是加密后的 Base64 文本。响应先尝试 JSON 字符串解包，再 Base64/AES 解密，失败保留原文本供既有解析。
- K（旧版加密）：O-Crypto:11–46。AES 密钥长 16，字符集为 ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678；AES-128-ECB，平台 PKCS5Padding，RSA PKCS#1 v1.5 分别加密 AES key 与 JSON UTF-8 字节的 SHA-1 小写十六进制摘要，ts 为毫秒时间戳。固定 RSA 公钥位于 O-Crypto:11–12；E-Core:11–16 的 PEM 内容与之相同。当前 crates/ubaa-core/src/features/bykc/crypto.rs:14–64 保留旧公钥、字符集与同一加密方式，不新增常量。
- L（会话与登录）：O-Local:287–365 按用户名缓存 LocalBykcClient，clientMutex 与 loginMutex 防止重复创建/并发登录，bykcToken 仅内存。O-Connection:98–140 按连接模式保存 Cookie；:153–188 规范化 domain/path 并按 domain/path/secure/有效期发送；:231–262 的共享客户端自动跳转。O-WebVPN:98–102 把全部博雅 URL 包装为当前 WebVPN 路线。新入口继续交给现有 Core runtime、路线独立业务状态和 Cookie，不复制示例存储方式。
- F（旧版只读失败）：O-Local:290–325/437–445/471–498/758–772。401、SSO 最终页/登录 HTML 判为未认证；包含“会话已失效”/“未登录”的解码结果清业务 token；除明确未认证异常外，callApiRaw 遇异常最多强制重新 login 并重试一次。decodeData 只接受 status=="0" 且 data 非 null；失败映射为业务认证错误或 bykc_error/安全操作文案，不把失败返回空列表。Kotlin 库无 CLI 退出码。本候选复用当前 Core 既有 request_api/error/finish_routed 链，不扩大重试或修改 CLI 退出分类。

示例差异必须保留：E-Core:121–141 仅发 Authtoken 与 Ak/Sk/Ts，通过 .json(&body) 给 Base64 正文加 JSON 字符串包装，未显式设置旧版 Referer/Origin/Accept；响应直接去首尾字节后解密。E-Request:17–22 交 reqwest 默认跳转和 Cookie provider，另有可接受无效证书的 builder 参数，这一参数绝不能带入现项目。E-Cred:73 使用 600 秒可刷新令牌有效期，E-Context:184–188 可显式把凭据/Cookie 保存文件；这些不适用于本次新增 typed 读取。

补充源码核对：examples/buaa-api/src/crypto/aes.rs:293–325 明确使用 ECB/PKCS7Padding；本次对 O-Crypto、E-Core 与当前 Core 的公开 RSA key 做了仅内存字符串规范化比较，三者相等。该比较未执行学校请求或读取账号数据，不是加密行为测试通过证据。

## 3. 逐操作双冻结源九列

### 3.1 博雅业务引导（所有网络操作前置）

| 来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧版 | O-Local:506–508 的业务入口 https://bykc.buaa.edu.cn/sscv/cas/login；备用 /cas-login?token=。业务服务参数由该入口跳转产生，Local 不手写 SSO service | :354–364 从自动跳转最终 URL、否则 Location 提取非空 token；未找到则尝试备用页。O-BackendTest:250–303 覆盖经 SSO 跳转取令牌 | L：当前模式 Cookie；业务 token 留 LocalBykcClient 内存 | GET 业务登录页，必要时 GET 备用页；无列表/详情参数 | 共享客户端 Cookie；GET 无加密正文 | TLS；这里不执行 K 的业务正文加密 | :501–504 用 token 查询参数正则；没有公开宿主 token 字段 | clientMutex、loginMutex，已获 token 直接复用 | O-Local:347 先要求现有会话；认证异常按 F 映射；没有 CLI 退出合同 |
| 示例 | E-Core:27 显式 https://sso.buaa.edu.cn/login?noAutoRedirect=true&service=https%3A%2F%2Fbykc.buaa.edu.cn%2Fsscv%2Fcas%2Flogin | :29–38 依赖 reqwest 自动跳转；最终 URL 等于请求 URL 报 Redirect failed；从 token= 后取文本。WebVPN 仅 TODO，不能当已实现 | E-Core:21–23 先看 SSO 过期；Boya token 写 CredentialStore；E-Cookies/E-Context 公共上下文 | GET 上述 SSO URL，固定 service | E-Request 默认 UA/Cookie，无正文 | TLS 设置可由 builder 改；无本次可借用的新密码算法 | 字符串 token，不验证成旧版 DTO | E-Cred:73/135–152 的 600 秒过期/刷新；无 O-Local 等价的登录 mutex 逻辑 | 无 token、未跳转返回 Error::server；没有本项目退出码 |
| 候选决定 | 复用 C-Auth:13–65，不重新构造 SSO service | 当前最多 8 跳，继续既有 sso/bykc 跳转主机检查、相对跳转还原及固定路线；不借本次改认证 | 继续现有 runtime Cookie 与路线内存 credential；不写 Session 新字段 | 新入口不增加第二种 bootstrap | 同现有 Core | 同现有 Core | 不外传 token/execution/raw | C-Auth:20–27 已有 login_guard；新操作共享 | 不修改既有认证/重试/错误策略；当前行为与旧版/示例差异另见第 8 节 |

### 3.2 课程分页及筛选所需字段读取

| 来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧版 | 3.1 业务引导；操作 /sscv/queryStudentSemesterCourseByPage，O-Local:372–382 | H/F 的业务最终 URL/登录页检查，无该操作专属跳转 | L；同一当前用户和连接模式 | POST；仅 pageNumber:Int、pageSize:Int（:932–935）；all 不是上游参数。默认 page=1、size=20、all=false 见 O-API:65–70 | H；两个分页整数编码成 JSON 再加密 | K；没有筛选签名常量 | content→toCourseDto(:523–544)；category、subCategory、audienceCampuses、hasSignPoints 有明确转换；page totalElements/totalPages 不随本地过滤减少 | O-Local 不缓存列表；O-ViewModel:95–100/148–216 缓存加载状态，加载更多追加；all=false 只过滤当前页 expired/ended | F；无效结构为失败，不返回伪空页；无 CLI 退出码 |
| 示例 | E-Opt:19–31 为同一业务路径；3.1 示例引导 | 自动跳转；无独立业务登录页防护 | 同 E-Context 的 Cookie/Boya token | POST；page:u8、size:u8 → pageNumber/pageSize，无 all | E-Core:121–141 的 JSON 字符串包装及单 token 头 | 同 AES/RSA/SHA1 公钥，但随机 key 字符集采用 examples/buaa-api/src/utils/str.rs:4–12 的字母数字全集 | E-Data:104–115 只提 content，丢弃分页总数；Course:124–155 解析二级分类/校区/配置，没有一级分类/hasSignPoints DTO | 返回 Vec，无旧 UI 累加/筛选缓存 | E-Data:15–25 要求 status=="0"；字段要求更严格，错误可带 errmsg；无本项目 CLI 分类 |
| 候选决定 | 新 bykc_course_catalog 复用现有 Core 引导与同一列表路径 | 不变 | 同一已解析路线 runtime | 保留 page/size/all 和当前 App 的 all=true；不新增 category/campus 查询参数、不自动遍历全部页 | H 的现有 Core 实现 C-Auth:128–153 | 继续现有 crypto | 新独立 CatalogItem/Page，见第 7 节；基底 BykcCourse 与服务器分页元数据保留；类别/校区只做已加载页筛选 | 不新增请求/列表缓存；新字段随读取快照原子替换；保留筛选选择 | 当前错误分类与旧 CLI 形状不变；无证据字段不能从名称/地点推导 |

### 3.3 单门课程完整详情的主请求

| 来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧版 | 3.1；O-Local:384–388 /sscv/queryCourseById | H/F；详情没有专属外部跳转 | L；课程 ID 不改变 Cookie scope | POST {"id": Long}（:943–945），不是 courseId；O-API:79–80 独立详情返回 BykcCourseDetailDto | H | K | O-Local:94–113/547–586：解析课程、selected 严格为 true 时补查 3.4/3.5；联系人、电话、开课单位、简介、适用范围、解析后签到配置，详见第 4/5 节 | 每次详情调用重新请求；selected=true 即使主配置有效仍补查考勤；详情无只靠列表缓存的实现 | 任一主请求/补查失败经 execute 返回整个详情失败；无部分成功兜底；无 CLI 退出码 |
| 示例 | E-Opt:37–44 同一 /sscv/queryCourseById | 同 E-Core 通用请求 | 同示例共享上下文 | POST {"id": u32} | E-Core 通用包装 | 示例通用算法 | 仍返回 Course；E-Data:147–149 明确不解析 courseDesc；联系人/电话/开课单位/学院年级人群范围未建模；无 selected 后补查逻辑 | 单请求，未实现旧版完整详情组合 | Res::parse 成功码/字段解析错误；不能用示例无字段证明旧版字段无来源 |
| 候选决定 | 新 bykc_course_full_detail(id)；旧 bykc_course_detail(id) 保持当前路径与行为 | 复用 current route，不在补查之间重新选路线 | 主请求和补查共享同一个 runtime | id>0 校验；主请求仍仅 {"id":id}；selected==Some(true) 才顺序补查 | 不变 | 不变 | 新 FullDetail DTO；独立可空显示字段；description_plain_text 由 courseDesc 清理；不接收 raw；selected 的原 `Option<bool>` 保留 | 一次 facade resolve、顺序最多三次业务读取；未选只一次主请求；失败不替换为“空详情成功” | 补查错误整次返回；未知/缺失考勤保持 null；不能从这些字段合成写资格 |

### 3.4 已选详情补查第一步：当前学期配置

| 来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧版 | 3.1；O-Local:390–391 /sscv/getAllConfig | H/F，无额外跳转 | 继续主详情的 LocalBykcClient 与当前模式 Cookie | POST {}；不把调用方估算日期发给配置 API | H | K | semester:`List<LocalBykcSemester>` 默认空；id:Long、semesterName:String 必填；起止 String?；:626–639 取第一个包含 now 的项，否则按可解析结束时间选最大，无法解析使用 1970 回退比较 | :275–284 每次 selected 详情补查，不借 UI 已选缓存；与下一请求有顺序依赖 | 空学期或所选起止为 null 抛 LocalBykcException；整个详情失败，不改查其他字段/当前月份 |
| 示例 | E-Opt:10–15 同一路径 | 同通用请求 | 同共享 Cookie/token | POST {} | 示例通用包装 | 示例通用算法 | E-Data:44–60 只取 semester 第一项；:65–83 另提供本地估算学期；没有旧版当前窗口优先/最新结束回退 | 独立 get_semester，调用方再传 semester | 缺学期或日期解析失败为错误；不能把估算日期作为本次回退 |
| 候选决定 | 复用 C-Read:119–130 的 get_chosen_courses 内部流程 | 固定主详情已解析路线 | 同一 runtime | 精确 {}，不新增参数 | 不变 | 不变 | 复用 C-Parser:504–543 的现行 resolve_current_semester；不复制示例 first()/estimated_current() | 与查询已选串行；不额外调用第二次 getAllConfig | 配置失败直接上抛；现行 Core 还拒绝空字符串起止，保留该既有行为 |

### 3.5 已选详情补查第二步：本学期已选记录

| 来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧版 | 3.1；O-Local:393–401 /sscv/queryChosenCourse | H/F，无额外跳转 | 与详情/配置同一当前用户/路线 | POST {"startDate":String,"endDate":String}，字符串直接取配置选定项；没有 courseId 参数 | H | K | data.courseList；每项外层 id 是选课记录 ID，courseInfo?.id 是课程 ID；:282–284 找第一条内层 ID==请求课程 ID；拿该外层 checkin/pass，主配置缺失或解析失败时才用其 courseInfo.courseSignConfig | 依赖配置结果；完整列表只获取一次；不按 record.id 匹配课程，不取其他课程字段 | 请求失败使整个详情失败；合法空 courseList/未匹配是成功，checkin/pass 留 null，已存在主配置保留 |
| 示例 | E-Opt:50–59 同一路径 | 同通用请求 | 同共享上下文 | POST startDate/endDate，日期来自传入 Semester.format() | 示例通用包装 | 示例通用算法 | E-Data:331–350 直接把每项 courseInfo 解为 Selected，外层记录/考勤信息丢弃；无旧详情补查/合并 | 不提供旧版自动补查；调用方负责调用 | Res::parse/严格字段错误；不支持据外层考勤构造本次详情 |
| 候选决定 | 直接复用 C-Read::get_chosen_courses(runtime) 的整个配置+查询链 | 不调用会重新解析路线的另一 facade 方法拼接 | 同 runtime，同一业务令牌 | 与上述完全同形 | 不变 | 不变 | C-Parser:316–367 已保留 course_id、记录 id、可空 checkin/pass、sign_config；按 course_id 找首条作只读合并，保留 source record ID 仅用于定位，不当写目标 | 配置+已选共两次业务调用；selected 非 true 不执行；主详情配置优先，已选配置仅回退 | 复用读取函数的错误；空/无匹配仍可有详情；不调用 write_preflight 接口，更不能以补查结果替代写前权限核对 |

### 3.6 已加载页的类别/适用校区筛选

| 来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧版 | 无独立上游操作；输入来自 3.2 | 不适用，纯本地选择/过滤 | 不修改会话；O-FilterStore:25–38 按 userKey 存储筛选偏好 | 类别/校区不发请求；仅 requiresAllCourses 影响后续 getCourses 的 all 本地开关 | 不适用 | 不适用 | O-Filter:54–77/123–149：状态/类别/校区维度 AND、维度内 OR；类别 subCategory 优先；校区用 audienceCampuses 精确文本匹配 | 五种固定二级类别；校区候选=加载数据+已选校区，去空去重排序；不会因刷新丢已选校区。旧 ViewModel 可累计分页 | 正常“当前筛选条件下暂无课程”不等于请求失败；无 CLI 退出码 |
| 示例 | 无对应 UI/筛选 API；同协议课程字段只在 E-Data | 不适用 | 无同等筛选偏好实现 | 不适用，不能推导 category/campus 上游参数 | 不适用 | 不适用 | E-Data 的 Category/Campus 转换是协议 DTO，不是旧筛选交集行为 | 无旧筛选缓存/持久化 | 无旧 UI 空态语义 |
| 候选决定 | 纯 UI/领域展示状态，不新增 facade 筛选查询参数 | 不变 | 不写配置 v1 或 Session v2 | 维持 App 原 all=true；当前只对已加载服务器页筛选，保留范围提示 | 不适用 | 不适用 | 严格用新 typed category/subCategory/audienceCampuses；禁用从课程名/地点推测；未知类别不冒充“其他方面” | 草稿/页面状态和已选校区稳定保留，服务器总数不重算 | 空匹配与失败分开；仅当前页筛选不能宣称全量搜索；旧跨重启偏好另见第 8 节 |

## 4. 精确字段来源、类型、可空性与转换

| 公开显示含义 | 上游精确字段及旧原始类型 | 旧转换/DTO 与具体行号 | 示例对应/冲突 | 推荐新类型 |
|---|---|---|---|---|
| 一级类别 | courseNewKind1: LocalBykcCourseKind?=null；其中 id:Long、kindName:String 必填 | O-Local:825–847/537/567：kindName trim、空→null；O-DTO:12–20：博雅课程→BOYA，其他非空→UNKNOWN；最终 category 可空 | E-Data 只读取 courseNewKind2，不实现一级类别 | `Option<BykcCourseCategory>`；复用现有 C-Domain:104–111 与 C-Parser:394–408 |
| 二级类别 | courseNewKind2 同上 | O-Local:538–539/568–569；O-DTO:26–38：德育/美育/劳动教育/安全健康/其他方面五值，未知非空→UNKNOWN，缺失/空→null | E-Data:193–206 对未识别名字一律 Other，不能照搬 | `Option<BykcCourseSubCategory>`；复用 C-Domain:115–134/C-Parser:410–418 |
| 适用校区 | courseCampusList:`List<String>`?=null；courseCampus:String?=null | O-Local:848–849/524/554/739–750：trim→去空→“全部校区”改“未指定校区”→去重；若结果非空直接采用；若空且 rawCampus trim 后恰等于 ALL，补单项“未指定校区”；否则空列表 | E-Data:247–263 把“全部校区”映为 Campus::All，陌生校区一律 Unknown，未实现 ALL fallback | `Vec<String>`，保持真实文本与上述规范化；不用地理位置枚举强行收窄 |
| 是否有地点签到配置 | 没有 hasSignPoints 上游字段；来源 courseSignConfig:String?=null | 列表 O-Local:541 为 parseSignConfig(...).signPoints 非空；详情 :570 为合并后 signConfig.signPoints 非空。不是 courseSignType 判断、也不是半径>0 判断 | 示例只有 `Option<SignConfig>`，且只留最后一个点，无法复用它计算完整点数 | bool；只读派生，不代表可签到、位置有效或当前时间可写 |
| 联系人 | courseContact:String?=null | O-Local:836/573，trim、空→null；O-DTO:117 | 示例 Course 未声明 | `Option<String>`，课程公开联系信息；不混用个人资料 contact 字段 |
| 联系电话 | courseContactMobile:String?=null | O-Local:837/574，trim、空→null；O-DTO:119 | 示例未声明 | `Option<String>`；不能转整数，避免丢前导字符/分机 |
| 开课单位 | courseBelongCollege:LocalBykcCollege?=null，其中 id:Long、collegeName:String 必填 | O-Local:819–822/834/575，取嵌套 collegeName 后 trim、空→null；O-DTO:121 | 示例未声明 | `Option<String>` organizer_college_name |
| 课程简介 | courseDesc:String?=null | O-Local:853/576 trim、空→null；O-DTO:123 保留 HTML 片段；O-DetailUI:266–278/468–482 在展示前转纯文本 | E-Data:147–149 明确注释掉 description，不解析；同协议无该字段实现，不能据示例删能力或猜其他字段 | `Option<String>` description_plain_text；只从 courseDesc 派生，桥接不提供任意 HTML/raw |
| 适用学院 | courseCollegeList:`List<String>`?=null | O-Local:850/578/741–742：null→空，元素 trim、去空；不做 distinct | 示例未声明 | `Vec<String>` audience_colleges |
| 适用年级 | courseTermList:`List<String>`?=null | O-Local:851/579/741–742，同上；O-DTO:129 明确为年级范围，不把 term 解释成当前学期配置 | 示例未声明 | `Vec<String>` audience_terms |
| 适用人群 | courseGroupList:`List<String>`?=null | O-Local:852/580/741–742，同上；O-DTO:131 | 示例未声明 | `Vec<String>` audience_groups |
| 解析后签到配置 | courseSignConfig:String?=null，内部 JSON 四个日期:String?=null、signPointList:`List<LocalBykcSignPoint>`=emptyList()；点 lat/lng:Double 必填，radius:Double=0.0 | O-Local:610–624/894–907；null/空白/解析失败→null；四日期经 :753–755 转可空 LocalDateTime；点列表保留全部，不过滤负/零半径后重算“有点” | E-Data:266–299 要求字符串，非空解析失败报整个 Course 错误；日期不可空，signPointList 经 :315–323 只取最后一点、空点报错 | Core `Option<BykcSignConfig>` 或独立显示配置；Bridge 新显示配置只需四个 `Option<String>` 与 sign_point_count，见第 7 节；不改变现有写用配置解析 |
| 是否已选 | selected:Boolean?=null | O-Local:856/103 仅 true 触发补查；:543/572 的旧公开 selected 为 selected==true（null→false） | E-Data:155 为必填 bool | 新嵌套基底仍保留当前 `Option<bool>`；补查判定用 ==Some(true)，禁用字符串/数字猜布尔 |
| 考勤与考核 | queryChosenCourse 外层 checkin:Int?=null、pass:Int?=null；不是 queryCourseById 的同名字段 | O-Local:100–109/869–877；详情直接保留 null；旧“已选列表 DTO”另在 :146 把 checkin 缺省成 0，但这不是详情规则 | E-Data:331–350 丢弃外层，不支持此补查 | `Option<i32>` checkin/pass；C-Parser:328–358 已保留 null，可复用；不从 null 推未签到/未考核 |

旧详情简介的可复用显示规则：O-DetailUI:468–482 把 br 改换行、段落结束改双换行，移除标签，依次解码 nbsp/lt/gt/amp/quot/&#39;，trim 行尾、压缩 3 个以上换行为 2 个后 trim。这是显示转换的明确来源；迁入 Core 或桥接前的纯文本投影不需要猜网络端点。新增文本不进入诊断、日志或自动持久化，也不因电话号码字段存在自动发起通信。

旧 DTO 的课程原始分类/单位对象还要求内部 id，当前 C-Parser 的既有分类 helper 只读取 kindName；本次新增展示不得凭对象 id 创造新业务标识，若实现计划要改变字段畸形时的全局失败策略，须单列 RED 与决策，不能趁本批修改旧读取形状。

## 5. 完整详情补查的精确算法和失败边界

O-Local:94–114/275–284/547–586 是完整依据，不能只以 fixture 的“有某字段”代替这段实现。

1. 请求 queryCourseById(id)，计算既有课程显示状态，先解析主详情 courseSignConfig；checkin/pass 初始化 null。
2. 仅原始 selected==true 时执行 getAllConfig，按当前时间选学期，再 queryChosenCourse(startDate,endDate)。即使主详情 signConfig 已存在，也必须查已选记录以获取考勤。
3. 使用首个 courseInfo?.id==请求 courseId 的已选记录。外层 id 是选课记录标识，绝不能拿它跟课程 ID 比；不能按 courseName 匹配。
4. 仅主详情 signConfig 为 null（包括解析失败）时才采用匹配已选记录 courseInfo.courseSignConfig 的解析结果；主详情有效配置始终优先。
5. checkin/pass 来自匹配的已选记录。合法空列表或无匹配不会抛错，checkin/pass 继续为 null；主详情配置不丢失。
6. getAllConfig 请求失败、空 semester、所选项缺少起止、queryChosenCourse 请求/解析失败，都未在此链路捕获。它们由 execute→mapFailure 转成整个详情 Result.failure；不能把补查失败当“未选”“未签到”“签到配置空”或返回整页成功。
7. 旧 DTO canSign/canSignOut 是旧显示/动作规则的产物：O-Local:647–661/716–719 把 checkin=null 也视为未签到，pass=null 也满足 pass!=1。现 Core C-Parser:448–459 明确要求 checkin/pass 均存在，否则 ActionEligibility::Unknown。当前规则保留；新详情不移植旧布尔资格。
8. 当前 C-Write:125–149 的写前核对是另一条权威链：优先已选记录 sign_config，缺失才从课程详情回退，然后用当前完整字段与时间核验。它与旧详情的“详情配置优先”顺序相反。读详情合并不能改写这个顺序、不能将已加载详情当 prepare/commit 权威。

当前 Core 的可复用点已经足够：

- C-Read:107–145 的 get_chosen_courses(runtime) 已完成配置→当前学期→已选列表读取，不必复制三套协议代码。
- C-Parser:316–367 保留 record.id、course_id、可空 checkin/pass、解析后的 sign_config。对有效课程 ID 的首条匹配可以复现旧详情展示；该读取返回的附加内部作业字段无需进入新 Bridge。
- 新 facade 方法仿 C-Facade:71–81：先一次 resolve_operation，之后所有主请求/补查都用同一个 runtime_for(resolution.mode)，最后 finish_routed。不得从 App 连续调用三个 facade 方法让路线被重新选择。
- 独立新方法读取一次原始主 payload 后同时构造旧基底与新增投影；不能先调用旧 get_course_detail 再重复请求 queryCourseById 以找已被丢弃的字段。

## 6. 当前丢失位置与 UI 行为

| 层 | 已确认缺口/已有能力 | 精确定位 |
|---|---|---|
| Core 领域模型 | BykcCourse 只有基本信息、时间、人数、状态、selected 与选退资格；列表和详情共用，类别/校区/联系人等没有承载字段。现成类别枚举及 BykcSignConfig 已供已选记录使用 | C-Domain:19–37/61–67/72–100/104–153 |
| Core parser | course() 只返回上述窄结构；parse_courses_at 调用 course；parse_course_detail 也是 course(envelope)。原始响应中的目标字段在这里丢弃；不能通过桥接映射补回 | C-Parser:52–101/229–265 |
| Core 读取流程 | get_course_detail 只有 queryCourseById；没有 selected 后配置/已选补查。另有可复用 get_chosen_courses 及专用写前读取 | C-Read:50–83/85–145 |
| facade | bykc_courses/bykc_course_detail 的返回形状直接服务现有 CLI；改变旧结构会扩大 CLI JSON，与“保持 CLI v10”目标冲突 | C-Facade:47–81；apps/ubaa-cli/src/backend/fixed.rs:102–111；apps/ubaa-cli/src/backend/routed.rs:126–135 |
| Bridge | BridgeBykcCourse 与 Core 同样窄；map_bykc_course 无这些字段；课程列表/详情方法各返回旧结构。现成 category/subCategory/signConfig 存在于 BridgeBykcChosenCourse | B-DTO:255–329；B-Map:282–299/310–349；B-Methods:243–273 |
| App | summary 固定 all=true，保留服务器分页；详情只调用 bykcCourseDetail，然后 _bykcCoursePresentation(isDetail:true)。已选记录另外有 typed 签到动作，目标是 courseId | A-Read:13–19/65–79/84–129/154–190/329–354 |
| 领域展示 | BykcCoursePresentation 不含类别/校区/详情补充；BykcChosenPresentation 有两级分类/四个签到日期/点数，但不含完整课程详情 | D-Presentation:6–31/33–63 |
| UI | query 中只具状态 chips；列表过滤只检查状态。课程详情只显示基本信息和时间安排；已选详情有考勤/考核/分数/签到窗口/点数；缺完整课程详情来源读取 | packages/ubaa_ui/lib/src/features/bykc.dart:47–62；packages/ubaa_ui/lib/src/features/bykc/display.dart:186–207；packages/ubaa_ui/lib/src/common/detail_list.dart:108–117；U-Detail:30–133/135–255 |
| 已选详情导航 | 当前从已选列表创建本地子帧，没有网络课程详情；刷新按 (recordId,courseId) 唯一匹配原读取快照，缺失/重复即空，不保留旧动作。补齐完整详情时须保留此动作与身份保护 | U-Navigation:189–205/283–307 |

旧筛选规则应完整迁入而非只添加两个控件：

- 固定二级类别顺序是德育、美育、劳动教育、安全健康、其他方面，排除 Unknown（O-Filter:18–21/58；O-FilterTest:79–100）。
- 状态/类别/校区三维交集；每维未选择即不限，每维多选是并集；类别值取 subCategory.displayName，缺失才用 category.displayName（O-Filter:123–140）。
- 校区候选取已加载课程的 audienceCampuses 并加入当前已选校区；trim、去空、去重，按学院路→沙河→杭州→未指定→其他文本排序（O-Filter:54–64/156–169）。选择“未指定校区”只匹配该文本，不等于所有校区；空适用校区在有校区过滤时不匹配。
- 默认四状态 selected/preview/full/available；空状态集合或选 ended/expired 才 requiresAllCourses。Full 还有容量显示修正，不能改变现有 Full/Available 行为（O-Filter:31–46/131–149）。
- O-FilterStore 按用户保存偏好；当前 App/UI 的范围是读取帧状态。恢复筛选应至少保证面板关闭、详情往返和数据刷新保留选择；跨重启持久化已纳入Task3D2，采用独立本地偏好存储，不改Core配置v1；在D2通过前仍记为未完成。
- 当前服务器页大小和总数由 Core 返回。搜索/筛选结果为 0 时不能擅改 totalElements/totalPages，也不能显示“所有课程均无匹配”。

## 7. 最小兼容 DTO/API 方案

下面是已选定的新增接口方案，尚未实施；若实施中需要调整名称或结构，先在本页更新有依据的决定，边界与数据来源保持。

### 7.1 Core/facade 新增独立结构

    BykcCourseCatalogItem {
        course: BykcCourse,
        category: Option<BykcCourseCategory>,
        sub_category: Option<BykcCourseSubCategory>,
        audience_campuses: Vec<String>,
        has_sign_points: bool,
    }

    BykcCourseCatalogPage {
        content: Vec<BykcCourseCatalogItem>,
        total_elements: i32,
        total_pages: i32,
        size: i32,
        number: i32,
    }

    BykcCourseFullDetail {
        course: BykcCourseCatalogItem,
        course_contact: Option<String>,
        course_contact_mobile: Option<String>,
        organizer_college_name: Option<String>,
        description_plain_text: Option<String>,
        audience_colleges: Vec<String>,
        audience_terms: Vec<String>,
        audience_groups: Vec<String>,
        sign_config: Option<BykcSignConfig>,
        attendance: Option<BykcCourseAttendanceDisplay>,
    }

    BykcCourseAttendanceDisplay {
        record_id: i64,
        course_id: i64,
        checkin: Option<i32>,
        pass: Option<i32>,
    }

    UbaaClient::bykc_course_catalog(page: i32, size: i32, all: bool)
        -> RoutedResult<BykcCourseCatalogPage>
    UbaaClient::bykc_course_full_detail(id: i64)
        -> RoutedResult<BykcCourseFullDetail>

说明：

- course 组合旧 BykcCourse，避免给旧 Serialize 结构直接加字段；旧 bykc_courses/bykc_course_detail 保持原返回结构/请求次数，不新增 CLI 命令或改 JSON schema。
- attendance 为只读补查定位与显示：无匹配为 None，已匹配但 checkin/pass 缺失为 Some(null/null)，可区分“无匹配”与“缺字段”。不包含 can_sign/can_sign_out 或新资格；不把 record_id 用作写目标。
- FullDetail 的 course.has_sign_points 要由最终解析/回退后的 sign_config 生成；列表项只由该列表行自带配置生成。
- 时间格式沿旧 LocalDateTime 的有效性规则，缺失/空白/无法解析的签到日期在显示投影中保持 None。不要为了本次显示修正而改现有写用 parse_sign_config 或资格算法。
- 如为新只读方法增加 id 一致性检查，它须有独立 RED：当前普通 detail 不校验返回 id==请求 id，只有 C-Read:94–100 的写用配置读取有校验。该项可提升新方法可靠性，但不能悄改旧 CLI 或声称旧 Local 已做检查。

### 7.2 Bridge v10 的最小公开投影

新增 BridgeBykcCourseCatalogItem/Page、BridgeBykcCourseFullDetail、对应 Routed wrapper 与两个只读方法，旧 Bridge 方法保持可用。复用已有 BridgeBykcCourseCategory/SubCategory，保持未知值枚举。列表只暴露旧列表已展示的四项补充。

新详情 sign_config 推荐使用独立 BridgeBykcSignDisplayConfig：

    BridgeBykcSignDisplayConfig {
        sign_start_date: Option<String>,
        sign_end_date: Option<String>,
        sign_out_start_date: Option<String>,
        sign_out_end_date: Option<String>,
        sign_point_count: i32,
    }

旧详情界面只展示四个日期窗口与签到地点数（O-DetailUI:281–309），因此新详情不需要新增坐标操作接口。现有 BridgeBykcSignConfig 与已选写路径保持原样；新显示 DTO 不包含原始 courseSignConfig 字符串、上游 URL、鉴权内容、附件路径或任意键值字典。点数从完整解析列表得出，不能拿示例的“最后一个点”代替。

App 只通过 typed Bridge 消费新列表/详情，继续把动作和展示字段分开。适用校区/类别进入强类型 Presentation；完整详情新增独立 Presentation 或明确的 detail supplement，避免靠 FeatureField 字符串逆向推断字段关系。联系人/电话是来源明确的课程联系信息，可在详情显示，不应自动进入通用日志、诊断或默认导出。

### 7.3 已选详情接线必须单列

当前已选详情是本地快照子帧，不能仅替换普通 bykcDetail 就宣称已选详情也完整：

- 对有效 courseId 可以通过新详情方法加载非敏感补充，保留当前 (recordId,courseId) 读取帧和既有 typed 动作快照；父已选读取成功更新后仍需唯一匹配，失配/重复清除动作。
- 完整详情请求/补查失败须显示详情失败或明确的补充读取错误，不把联系人/简介/签到信息空白当完整成功；不得用旧缓存动作掩盖当前会话失效。
- 新补查的 attendance 只读，不能生成签到/签退/退选许可。选退及签到仍通过既有 WriteCoordinator 和 Core 的 prepare→确认→单次 commit→核对链。
- 普通课程详情若要提供通往当前已选记录的入口，必须从现有独立已选查询拿到可验证身份；不能把新 attendance 显示对象自动升级为写操作依据。

### 7.4 与完整详情直接相关的旧入口/按钮差异

| 入口或按钮 | 旧版具体实现 | 当前差异与本批接线要求 |
|---|---|---|
| 选择课程列表→详情 | O-Navigation:876–880 按列表课程 id 发起 loadCourseDetail，并保留列表快照；同一详情页可以显示未选与已选状态 | 当前 A-Read:26–33 已有普通详情导航，新方法应替换此路径的显示读取，不能只补已选子帧 |
| 我的课程→详情 | O-Navigation:925–929 按 courseId（不是记录 id）重新读完整详情；旧 BykcChosenCoursesScreen.kt:82–84 整卡点击 | 当前 U-Navigation:189–205 仅生成已选本地快照，故必须补独立完整详情读取，保留现有父快照/唯一身份保护 |
| 首页博雅待办→详情 | O-Navigation:480–486 的 OpenBykcCourse 直接以 courseId 读取并进入同一详情，未携带列表快照 | 本报告不修改首页；主线需让已存在的博雅待办详情路由使用同一新读取能力，不能只验从课程列表进入。若主线保留先进入已选页的产品路径，应明确与旧直接详情入口的差异 |
| 选择课程 | O-DetailUI:383–400 未选分支按钮，按 resolveBykcSelectButtonState 启用并展示禁用原因 | 当前 U-Detail:95–130 已有“准备选课/准备退选”，仍只消费 typed action；本批完整字段补齐不复制旧时间/人数重算写许可 |
| 签到、签退 | O-DetailUI:318–368：selected 时且 pass!=1、signConfig 非空才展示两按钮；按钮可用性由旧 attendanceActionState 决定；考核完成时显示说明 | 当前普通课程详情 U-Detail:30–133 没有签到/签退入口，仅已选详情 :223–237 存在。这是完整详情直接相关的入口差异：只把新配置/考勤显示出来仍不能宣称旧详情按钮路径全部等价。可通过当前已选读取的可验证记录导航到既有签到准备路径；不得拿 FullDetail.attendance 生成写权限 |
| 退选 | O-DetailUI:370–382 的已选分支；O-Navigation:905–906 传当前课程 ID | 当前普通/已选详情均有 typed 退选准备；保持课程 ID 与记录 ID 分离、当前 Unknown 拒绝规则 |
| 联系人/电话与简介 | O-DetailUI:251–278/432–466 用 DetailItem/Text 显示，无拨号回调；简介经 :468–482 转纯文本 | 补齐显示即覆盖此旧能力，不需要顺带新增拨号、打开网站、HTML WebView 或附件操作；纯文本转换详见第 4 节 |

O-Navigation:902–915 把四种旧按钮直接接到 ViewModel，旧签到传 null/null 坐标。本报告只核对入口存在性；本次保持当前确认/权威合同，不移植旧直接提交链。旧详情组件自身没有刷新/重试回调（O-DetailUI:28–40/58–75）；其错误页是加载失败文本，当前共享刷新/返回能力应继续保留，不必虚构旧“详情重试按钮”作为新增来源。

## 8. 实质差异与实施前必须明确的裁决

| 差异 | 两源或当前的具体事实 | 本批建议 |
|---|---|---|
| 示例是否同协议 | E-Opt 提供同名四项端点，E-Core 同公钥/加密协议；但 Course 缺若干详情字段 | 明确“同协议、部分字段/组合行为未实现”，绝不能写整个 examples 不适用 |
| 校区与类别 | 旧 ALL/全部校区→未指定，示例 All；旧未知二级→Unknown，示例 Other | 采用旧 Local+DTO 直接转换，保留未知，不从地点/名称推断 |
| 详情完整性 | 旧 selected=true 无条件补查配置/已选；示例和现普通 Core 都只有主请求 | 新独立完整详情实现补查；旧方法/CLI 保持请求次数和形状 |
| 详情补查失败 | 旧任何补查错误整次详情失败；合法无匹配才 null | 本批保持；失败不能伪装成“未选/未签到/无配置” |
| 签到配置优先顺序 | 旧详情主配置优先；当前写前已选配置优先 | 新显示沿旧详情；现有 write_preflight/权威链保持，不反向复用显示结果 |
| 缺失考勤权限 | 旧 null checkin 可视为未签到，现 Core null checkin/pass 为 Unknown | 遵守当前合同，不新增旧 canSign 布尔，更不放宽写资格 |
| 学期选择 | 旧/现 Core 为包含 now 优先，失败取最新结束；示例取第一项或估算 | 复用现 Core；禁止借示例估算日期 |
| 配置/点列表 | 旧全部点、缺半径默认 0，解析失败配置为 null；示例末点、空点报错，日期必填 | 复用旧支持的完整点/可空规则；新显示日期规范化独立于写逻辑 |
| 匹配重复 | 旧详情及当前 Core 签到预检均用首个 course_id 匹配；当前 UI 子帧还要求 (recordId,courseId) 唯一 | 只读合并可保持首项语义，不能将首项展示对象变写目标；若改为重复时报错，须在正式决策与 RED 明确标为新约束 |
| 响应身份 | 旧详情不检查返回 id 是否等于请求 id；当前普通读取也无检查，写用配置读取有 | 新详情可独立增加一致性约束并记录，不修改旧 CLI；没有返回错 id 的 live 证据 |
| 信封/错误 | 旧/示例仅 status=="0"；当前普通 C-Parser:15–34 仍兼容 success=true/result，错误优先 msg；当前写前/写入已严格 | 此前兼容差异真实存在；本批不顺手改旧通用信封和写链。新增入口复用现读链并在正式来源写明，不宣称字节级完全等价 |
| 网络包装/重试 | 旧双 token、原始 Base64；示例单 token、JSON 字符串；旧一次重登录重试与现 request_api 不完全同形 | 继续当前经裁决的网络实现，新增纯投影/读组合不借示例替换 |
| 旧列表范围与偏好 | 旧 ViewModel 可累加页，旧 FilterStore 按用户持久化；当前 App 每次展示服务器页，状态存读取帧 | 本批保持当前分页与范围提示，跨重启偏好由紧接的Task3D2按独立本地存储补齐；不能因此修改Core配置v1或合并账号偏好 |

没有发现阻止已证字段/补查链实施的上游字段空白。新增API命名、只读首项匹配/响应身份、Bridge点数投影、三个详情入口与独立筛选偏好已在开头裁决，按Task3D/3D2实施；不得把本页的设计完成当作功能或实测完成。

## 9. 必要 RED 与验收建议

本审计没有添加或运行 RED；以下是实施者在生产修改前应真正观察的失败，不得把本清单当通过记录。

| RED 组 | 失败行为与关键断言 | 推荐位置 |
|---|---|---|
| R1 列表字段来源 | 新列表解析得到两级类别与可空 Unknown；校区 trim/去空/全部校区转换/去重/ALL 回退；缺/空校区不是所有校区；hasSignPoints 只跟完整有效配置的点列表，零/负半径不当“没有点”；服务器分页元数据不变 | crates/ubaa-core/src/features/bykc/tests.rs 邻近分页测试；使用完全自造脱敏 JSON，不复制旧测试联系人/电话 |
| R2 完整详情字段 | 联系人/电话/开课单位可空与 trim；学院/年级/人群列表去空且顺序保持；courseDesc 的换行、实体、标签纯文本投影；四时间窗和多点点数；新字段不能出现在旧 BykcCourse 的序列化快照 | 同上，独立 FullDetail parser 测试及 CLI 旧形状回归 |
| R3 已选补查顺序 | 新方法 selected=true 的顺序为 queryCourseById→getAllConfig→queryChosenCourse；false/null 不补查；主配置已有效仍补查考勤；配置起止按现行当前学期/最新回退；同一已解析路线；旧方法依旧只有 queryCourseById | crates/ubaa-core/tests/bykc.rs 或新增独立只读 Mock 文件；Mock 断言方法/路径/安全结构，不输出密文/凭据 |
| R4 身份与回退 | record.id≠courseInfo.id；仅按内层 ID 匹配；无匹配保留主配置且 attendance=None；主配置有效时优先于已选，主配置缺/坏时用匹配已选；其他课程不能污染；缺 checkin/pass 保留 null | Core 只读组合/解析测试 |
| R5 错误与原子性 | getAllConfig 请求失败、空学期、所选日期缺失、queryChosenCourse 失败/坏结构，均整次详情 Err；不回假成功；会话/路线变化后旧响应不能复活当前页；合法空 courseList 与上述错误不同 | Core Mock 与 App controller/导航测试 |
| R6 筛选 | 三维 AND/维度 OR、二级优先一级回退、五固定类别、未知不冒充其他、刷新保留已选校区、关闭面板/往返详情保选择；只筛当前页且总数不变；Full/Available 旧行为不回退 | packages/ubaa_ui/test/navigation/bykc_content_test.dart，必要时独立筛选测试 |
| R7 Bridge/App 投影 | 新类型的 null/empty/0 传递准确，DTO/绑定暴露白名单；description 是纯文本；详情请求使用新 method；CLI10/Session2/配置1 与旧 Bridge methods 留存；候选统一 Bridge10 | Bridge mapper/schema/生成兼容测试，packages/ubaa_app/test/bridge_backend_characterization/bykc_presentation.dart |
| R8 已选详情与写入权威 | 打开已选详情取得完整补充仍保留 record/course 身份；父刷新记录失配/重复清动作；补查 attendance 或 hasSignPoints 存在不产生允许写动作；prepare/commit 仍重读原专用权威，详情配置优先级不改变写前优先级 | UI navigation、App write lifecycle 与已有 Core 写前回归 |
| R9 三种详情入口 | 选择课程列表、我的课程、已存在的首页博雅待办入口均能取得完整详情；从课程列表打开已选课程时能沿可验证已选读取进入既有签到/签退准备路径；新详情补查错误不能静默降级为“完整成功” | packages/ubaa_ui/test/navigation/ 与 App 接线测试；不修改写逻辑 |

现有可引用但未在本审计重跑的行为证据：

- O-BackendTest:71–192 的列表/状态例有类别/校区输入；:196–246 的 pathless Cookie；:250–303 的 SSO 链；:307–431 的详情/当前学期已选/开课单位/未指定校区/考勤；:526–581 的 WebVPN 包装。旧列表例未逐字段断言所有补充，因此转换函数自身仍是关键证据。
- O-FilterTest:15–110 覆盖默认、三维交集、固定类别、校区去重和刷新保留；:154–229 覆盖 Full/Available。
- 当前 crates/ubaa-core/src/features/bykc/tests.rs:322–403/592–630 覆盖学期、已选字段/包装与坏签到点；Core 专用写前测试在 crates/ubaa-core/tests/bykc.rs:113–297/461 起。当前测试通过与否须由主线在新实现后实际执行。
- 本报告完成标志仅为来源/方案审计完成。实施后仍需聚焦 RED→GREEN、just check-sensitive、just check、绑定生成和相应 App/UI 回归；是否进行实时/原生验收按主线授权流程执行，静态审计不计 live 或 App 验收。

## 10. Task3D2本地筛选偏好九列

| 操作/来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧按账号恢复/保存/默认清除 | 无上游操作 | 不适用 | MainAppScreen的userData.schoolid仅作本地userKey；不改Cookie | BykcCourseFilterStore.get/save/clear，无HTTP | Settings键bykc_course_filters:userKey，JSON仅statuses/categories/campuses | 无上游加密或签名 | StoredBykcCourseFilters三组字符串列表，get解析失败返回null；默认筛选时删除该键 | 登录账号维度remember恢复，选择立即更新并保存；从默认/非默认切换是否需要全部课程沿原规则 | 坏存储读取回默认，不把它当学校查询失败；无CLI退出码 |
| 示例 | 没有对应UI偏好实现，九列不借协议DTO类推 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 |
| 当前专项 | 不新增上游请求 | 不适用 | 复用本机当前认证账号范围；旧Core配置1/Session2不变 | 独立注入存储read/write/clearAccount，仅保存用户本地选择 | 独立UI偏好文件，白名单三组选择；生产位于已隔离配置目录，合成默认内存 | 使用现有本地私有文件权限/原子替换模式，不借博雅业务AES | 强类型状态与合法类别，校区保留规范化文本；无课程/联系人/凭据/原始数据 | 存储排队和账号/编辑代次防迟到；面板/详情/后台/重启恢复均不跨账号 | 读取失败回默认并提示；保存失败保留本次选择并提示；清除失败继续其余账号清理，不能报告全部成功 |

D2必须先观察行为RED：新宿主/存储实例重启恢复三维选择、默认重置后下次恢复默认、账号A/B隔离、慢读取不覆盖编辑/新账号、写失败仍可筛选、明确账号清除移除偏好且其它清理失败不跳过。该本地能力不改变CLI schema或Bridge网络API，也不恢复任何已缓存的业务权限。
