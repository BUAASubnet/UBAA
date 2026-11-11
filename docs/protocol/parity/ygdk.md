# 阳光打卡

本文件收录阳光打卡 OAuth、概览、记录与提交的来源对照；提交九列见[直接写操作](write-actions.md)。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### 阳光打卡只读查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** OAuth 入口为 `https://app.buaa.edu.cn/uc/api/oauth/index`，交换地址为 `https://ygdk.buaa.edu.cn/api/Front/Clockin/User/campusAppLogin`；**示例：**无等价模块；**决定：**仅采用冻结旧版证据。 | **旧版：**最多跟随 10 次跳转，从 query 或 fragment query 提取并解码 `code`，没有逐跳 host 校验。**当前 Core：**2026-10-30 起只请求冻结代码与测试已证实的 HTTPS app/ygdk 默认端口，WebVPN 内层同样验证，未知主机拒绝。code 只从 ygdk 根路径 query 或 `/home` fragment query 提取。完整真实跳转链的兼容性仍未验证，见[复核记录](auth-session.md#认证安全修复复核)。 | **旧版：**按学生标识缓存独立 `uid/token`，不复用主认证 Cookie；**决定：**挂在路线隔离的业务会话状态中，不持久化敏感令牌。 | **旧版：**先分类、项目、汇总/学期，再记录查询；记录使用 `page`、`limit`、`classify_id`、`user_id`，概览固定 `page=1`、`limit=1000`；**决定：**保持分页与体育分类选择语义。 | **旧版：**POST `application/x-www-form-urlencoded`，所有请求附加 `uid/token` 和 `X-Requested-With: XMLHttpRequest`；**决定：**不记录令牌值。 | **旧版/示例：**无加密；**决定：**不引入签名或自定义加密。 | **旧版：**概览包含学期汇总、分类、默认项目和项目列表；记录包含记录标识、项目、时间、地点、图片、状态及分页字段；时间按上海时区格式化。 | **旧版：**按学生标识缓存业务会话，认证失效时清除并重试一次；**决定：**使用路线内单飞登录与失效代数。 | **旧版：**外层 `code=1` 成功，`-98` 清会话并认证失败，其余使用 `msg` 映射上游错误；非法分页参数为输入错误；**决定：**禁止把失败伪装为空结果。 |

当前实现证据：`crates/ubaa_core/tests/ygdk.rs` 已覆盖概览、记录分页和令牌业务会话，Core facade 与 `ygdk overview`/`ygdk records` CLI 已接入；`ygdk submit` 现已接入照片 multipart 上传和固定字段表单提交，要求 CLI 显式 `--confirm-write`，实时验证永不调用。OAuth code 同时从普通 query 与 `#/home?code=...` fragment query 提取；项目和记录参数按冻结实现同时发送至 query 与表单正文；业务 token 作为单独 URL 值解码，`-98` 会清除业务凭据并完整重登一次。概览统计与学期请求按冻结 `runCatching` 语义作为可选步骤，失败时保留分类/项目结果并回退空统计。上传正文的 `uid`、`token`、`file` 字段、固定边界、文件名和 MIME 已有确定性向量测试。`examples/buaa-api` 没有等价实现，不能从其模块类比 URL、字段或令牌流程。2026-08-28 Direct/WebVPN 实时验证均通过并解析到 11 个项目。实时验证永不调用写操作。

## 专项记录

### 2026-10-31：阳光 OAuth 的 SSO 中间跳转

本次按冻结参考重新核对：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalYgdkApi.kt` 中 `fetchOauthCode`、业务登录与对应 BackendTest；buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/api.rs`、`src/request.rs` 和 SSO 模块没有阳光等价协议，因此本操作不适用其业务字段。

| OAuth 操作边界 | 本次对照与决定 |
|---|---|
| 引导 URL 与 service | 继续采用冻结 OAuth URL 及其 redirect/appid/state/qrcode；SSO service 来自上游 Location，不自行构造。 |
| 重定向与最终 URL | Direct 实测 app OAuth→app 登录→app CAS→SSO `/login`→app CAS→app OAuth→ygdk 回调。旧版逐跳跟随；本次只补充 HTTPS 默认端口 SSO `/login`，WebVPN 解包后同样校验。 |
| Cookie/Session/Token | 当前用户与路线 Cookie；授权码仅在本次登录内存中传递，业务 uid/token 作用域不变。 |
| HTTP 方法与参数 | 沿上游 Location 执行 GET，不修改 query，不发送新业务写操作。 |
| Header 与正文 | 继续无业务正文，不新增 Header。 |
| 加密与签名 | 无新增加密，保留 WebVPN URL 转换。 |
| DTO 与解析 | 仅从 ygdk 根路径 query 或 `/home` fragment 提取 code，SSO query 中同名字段不能作为授权码。 |
| 缓存/并发/重试 | 保留十跳上限、登录单飞和会话代次守卫。 |
| 错误与产品语义 | 未知主机、SSO 非登录路径、HTTP、用户信息或非默认端口仍在发送前失败；此次修复已证实的正常跳转误拦截。 |

本节补充上文历史双主机决定，依据见[决策记录](../decision-log.md#2026-10-31阳光打卡-oauth-补齐-sso-中间跳转)。

### O3-D4阳光打卡旧版依据与实施边界

2026-09-09，实施前对照及实施后回写。基点e812798e；冻结old=6e75e120a26b0eefb3ab4a6f8251d1230db4a62e、examples=efb7976bf513f38364b88aeb83d704586cff9b2a。旧YgdkHomeScreen、ViewModel、ClockinFormScreen、API/DTO/Local与BackendTest已逐段读取；examples模块清单无阳光协议，不借其app或spoc字段类比。

| 旧版依据 | 必要优化 | 当前与实施对应 |
|---|---|---|
| HomeScreen:67–123，学期/本周次数→首页提醒→打卡记录，右下新增；ViewModel.refreshAll先概览再page1记录 | 顶栏唯一刷新与按需查询，不再正文重复刷新；保留摘要和记录同页，项目到新增流程再出现 | 已实现typed概要与记录卡、右下新增；项目仅在新增选择出现，周统计不丢失 |
| HomeScreen:169–224，项目/地点/开始结束、提交时间/图片张数/是否分享 | 保留卡片顺序，低频编号及未知原始state进本地详情；长名称换行可读 | Bridge只含imageCount，没有URL；历史图片仅计数，不伪造图库 |
| ViewModel:143–163，page+1追加记录、失败保留旧列表 | 保留加载更多，按需面板仍能指定原page/size；刷新、筛选、返回不丢草稿 | page/size一基，不能改为研讨室零基；去重只凭公开recordId并标明重复，不重算总数 |
| ClockinForm:165–315，项目→时间→地点→照片→分享→底部提交 | 保留顺序，复用现有typed目标和照片能力；时间日期明确，关闭面板保存草稿 | 旧透明图片/自动补时间不继承：现Core要求明确照片、时间及fresh资格；不为UI改写合同或自动造数据 |
| YgdkReminderStore与ViewModel首页提醒 | 与后续首页六来源共同接入账号隔离的提醒状态 | 不能做不生效开关；本批先记录此依赖，不声称已恢复 |

#### 两操作九列

##### 2026-10-30 OAuth 重定向安全边界

冻结旧版代码和 BackendTest 证明 `app.buaa.edu.cn` OAuth 到 `ygdk.buaa.edu.cn/#/home?code=...`，buaa-api 无等价模块。当前仅允许这两个 HTTPS 默认端口主机，拒绝用户信息；WebVPN 外壳及解包后上游均验证，未知主机失败关闭。code 只从 ygdk 根路径 query 或 `/home` fragment query 提取，单次百分号解码并保留字面加号。真实完整链兼容性尚未验证，遇到未知中间主机必须补充证据再扩充，见[逐操作复核](auth-session.md#认证安全修复复核)。

两读分别复用source-parity.md“阳光打卡只读查询”九列，且已复读LocalYgdkApi:63–105与BackendTest:63–179：OAuth入口app.buaa.edu.cn/uc/api/oauth/index，code换业务campusAppLogin；query/fragment code及既有最多10跳规则不变，完整允许主机集合仍为既有未决项，不臆造白名单。uid/token只存路线隔离业务会话内，认证失效代数/单飞/一次重登沿Core现合同。POST表单与query同时携既有参数、X-Requested-With头，无新加密签名。概览读取体育分类→项目→可选汇总/学期，records读分类→项目→getList(page/limit/classify_id/user_id)；所有上游URL/字段/编码不变。DTO全部来自Bridge白名单：term/week/month/day/good计数、可空目标、分类/默认项目/项目原顺序；记录ID、item、时间、place、imageCount、isOpen、state、createdAt/Label与服务端page/total/hasMore。code=1、-98及非法输入/错误分类不改，不将失败当空记录。

#### 组合读取与业务保护计划

先补投影RED：零计数/未知目标、项目为空仍有概要；记录公开状态/图片数/原始state；普通与固定路线回读相同投影。保留原_ygdkSubmitActions的父分类、正ID、名称、唯一性、allowed与完整target校验，默认项目和进度不授写权限。

旧首页需要概览和记录同页。默认后台loadFeature仍只读取概览，避免首页刷新无端增加记录请求；显式进入阳光首页后再执行当前页读取，记录应固定到本次概览实际路线，使用已有ygdkRecordsOnRoute，不第二次Auto选路。记录失败保留本次概览并显示安全局部错误；不沿用其他路线记录，不伪称记录为空。固定路线写后回读方法仍仅执行原协调器指定读取，UI不得因回读触发额外Auto查询。组合接线必须先有请求顺序/同路线/部分失败/隐藏页不追加请求的RED；未完成前不标首页恢复。

实施后依次检查手机/平板/macOS实际卡片、按需面板、空/错/stale/loading/长文/多页与合成新增准备取消；P5再完成单次commit/固定回读/unknown等。真实.env.local只读单独两路线验证，真实写入禁止。

#### 实施后对应

`feature/overview.dart`与`presentation/ygdk.dart`承载公开投影；`bridge/read/ygdk.dart`普通/pinned读取复用mapper。显式首页概览后固定本次actual route读记录，默认后台概览、写后指定回读不增加Auto。`features/ygdk/home_flow.dart`保留概要、追加相邻同路线记录，显示局部错误；宿主传入同requestRevision的固定回读记录，不额外查询。`record_card.dart`按旧顺序展示，编号/state进入本地详情且仍可搜索。服务端页码/total/hasMore不靠本地长度重算，未知目标不伪造资格。

宿主可见性、连续追加及写后固定回读3项测试通过；首次写后页面没有显示更新记录的行为RED后补接线，未更改WriteCoordinator。新增表单暂复用既有Dialog，仅准备和取消已原生通过；旧独立表单与完整草稿、一次commit/失败/unknown继续P5。提醒开关与首页六来源仍待接入，不把本批只读页面验收当全功能完成。
