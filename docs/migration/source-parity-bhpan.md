# 北航云盘协议来源对照

本文记录北航云盘独立功能的冻结来源、逐操作协议和缺失证据，供后续实现与复核使用。当前候选已接入 Direct 元数据、文件与分享管理及个人秒传，完整验收结果见状态页。真实账号与设备验收的操作范围和结果见状态页。产品范围见[北航云盘设计](../design/bhpan.md)，公开边界见[北航云盘合同](../contracts/bhpan.md)。来源冲突、真实操作授权和验收遵守 [AGENTS](../../AGENTS.md#来源对照门禁)。

## 冻结来源与阅读位置

下列行号对应表内固定提交。以后换钉时须重新核对，不能把当前行号套用到其他版本。源码只读，引用不包含真实分享标识、签名地址、凭据或业务响应。

| 来源 | 固定提交 | 文件与阅读范围 |
|---|---|---|
| 旧版 | `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` | [UploadLatestReleaseToBhpanTask.kt](../../examples/ubaa_old/buildSrc/src/main/kotlin/cn/edu/ubaa/gradle/UploadLatestReleaseToBhpanTask.kt)，下文简称 K。参数与上传分流在 44–107 行，目录及 multipart 解析在 134–177 行，任务编排在 192–248 行，认证在 271–334 行，删除在 336–357 行，上传在 376–570 行，请求及跳转在 573–726 行，辅助解析在 736–829 行。 |
| 旧版测试 | 同上 | [BhpanUploadSupportTest.kt](../../examples/ubaa_old/buildSrc/src/test/kotlin/cn/edu/ubaa/gradle/BhpanUploadSupportTest.kt)，下文简称 T。凭据键解析在 9–60 行，发布文件过滤与统计在 102–141 行，分流阈值在 143–147 行，multipart 解析在 149–175 行，相对跳转与 303 在 177–215 行。 |
| buaa-api 操作 | `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` | [cloud/opt.rs](../../examples/buaa-api/src/api/cloud/opt.rs)，下文简称 O，已读取 1–666 行全部操作。 |
| buaa-api 认证与请求 | 同上 | [cloud/core.rs](../../examples/buaa-api/src/api/cloud/core.rs)，下文简称 C，31–175 行；[request.rs](../../examples/buaa-api/src/request.rs)，10–23 行；[sso/auth.rs](../../examples/buaa-api/src/api/sso/auth.rs)，7–94 行。 |
| buaa-api 数据与状态 | 同上 | [cloud/data.rs](../../examples/buaa-api/src/api/cloud/data.rs)，下文简称 D，1–668 行；[context.rs](../../examples/buaa-api/src/context.rs)，12–18、126–192、247–305 行；[store/cred.rs](../../examples/buaa-api/src/store/cred.rs)，13–40、66–89、126–158 行；[store/cookies.rs](../../examples/buaa-api/src/store/cookies.rs)，1–33、60–132、216–269、297–322 行；[error.rs](../../examples/buaa-api/src/error.rs)，81–99、113–132、185–195 行。 |
| buaa-api 示例测试 | 同上 | [examples/cloud.rs](../../examples/buaa-api/examples/cloud.rs)，19–295 行。示例从本地认证目录加载状态并执行真实读写，不属于脱敏 Mock 测试。 |

旧版仅有发布工具中的同源实现，没有面向用户的云盘 API/DTO 或页面。K 中的目标目录来自本地配置，使用个人 OAuth Token；“共享目录”文案不能证明该工具使用分享链接临时 Token。其他操作的旧版列明确标为“不适用”。

## 公共协议列

逐操作表与本节共同组成 [AGENTS 要求的协议列](../../AGENTS.md#来源对照门禁)。表中标记是来源行为的引用，不是已实施的 UBAA2 行为。每行未覆盖的公共项仍受对应公共规则约束；特殊授权、外部请求及多阶段写入在该行另列。

静态地址记号：B 为云盘 HTTPS 默认端口源站，主机 `bhpan.buaa.edu.cn`；S 为学校 SSO HTTPS 默认端口源站，主机 `sso.buaa.edu.cn`；E 为 B 下 `/api/efast/v1`；L 为 B 下 `/api/shared-link/v1`。这些记号仅展开固定 API 入口，不表示允许访问任意路径、重定向或动态主机。

| 标记 | 引导 URL 与 service | 重定向及最终 URL | Cookie/Session/Token 范围 | 请求头与正文编码 | 加密或签名 | 缓存、并发、重试 | 错误、退出及产品语义 |
|---|---|---|---|---|---|---|---|
| 个人请求 P | C:112–117 在本地 Token 估计过期时调用下文 login；业务行不另造 CAS/service。旧版 K:217–221 先 SSO、再云盘认证。 | C:163–170 使用共享 reqwest client，未逐操作检查最终地址；K:586–599 使用默认跟随跳转的 client。固定业务路径见逐操作行。两源未给出业务重定向主机白名单。 | C:80–108 从 B 域 Cookie 取个人 OAuth Token 并写入共享凭据；C:158–163 用 Bearer。K:587–595 按 Cookie 名取个人 Token，没有域名限定。两者没有 UBAA2 的账号、路线和代次模型。 | C:163–168：GET 参数用 query、JSON 用 json、空请求不加正文；K:591–595 显式 JSON Content-Type。默认 UA 分别见 request.rs:7–20、K:736–739。 | 云盘业务无额外客户端加密或自算签名。C:10–29 中手动登录 RSA 内容为未使用注释，不作为 SSO 密钥依据。 | 两源没有云盘业务缓存或云盘操作事务。buaa-api 共享 Cookie/凭据，个人 Token 使用 600 秒本地滑动估计，见 cred.rs:76–77、141–153；C:172 成功即刷新该估计。云盘请求无业务自动重试。旧版 API 调用不自动重试。 | C:121–143 仅以 HTTP 2xx 判定通用请求成功，再由各行解析；非 2xx 归为泛化服务器错误。K:597–599、765–768 对非 2xx 报错。两源均未建模写入结果未知，也未提供云盘专用注销。 |
| 分享请求 A | 先执行下文 share_parse，已有个人会话不能代替具体分享授权。 | 同共享 client 行为；来源未验证分享入口的最终主机或路由。 | 使用分享临时 Token 作 Bearer；来源不持久化 Item.token，但共享 Cookie jar 仍参与请求。复制另存使用双授权，详见对应行。 | 除 Bearer 来源外同 P。 | 同 P。 | O:51–59 把 Token 传给目录子项；D:475–484 传给上传参数。失效后由调用者重新解析分享，没有刷新协议或 expiry 字段。C:172 即使使用分享 Token 也刷新个人 Token 本地估计，此关联不可照搬。 | 来源缺少权限、过期、次数耗尽等稳定错误分类，不能把分享失败当成个人账号整体退出。 |
| 对象传输 X | 必须来自同一次上传授权或下载授权响应，来源没有独立 CAS/service。 | 两源直接使用返回地址，仍使用共享 HTTP client；没有动态主机白名单、跨域重定向或授权传播校验证据。 | 上传只显式附上游给定请求头，未另加个人 Bearer；共享 client 仍可能按 Cookie 规则发送 Cookie。动态授权值均为秘密材料。 | 上游 authrequest 数组首项是方法、次项是 URL、后续为头字符串；来源代码固定使用 PUT 或 POST，没有校验首项。正文是文件字节或合并 XML。 | 地址和授权头由上游生成，源码没有生成算法或可移植密钥。 | 无传输状态持久化或断点恢复；缓冲、顺序和重试见上传行。 | 外部非 2xx、请求已送达后的断线、响应丢失和最终登记失败须分别核对；来源只返回普通错误，不能据此证明失败前没有写入。 |

Cookie 与持久化补充：buaa-api Cookie 按主机、Path、Secure 过滤，但忽略 Max-Age/Expires，且 Path 仅用前缀匹配；credential 与 Cookie 可写为普通 JSON，见 cookies.rs:1–33、129–132、216–269，context.rs:175–192。旧版 CookieManager 只驻内存，见 K:668–726。以上都是来源实现方式，UBAA2 继续遵守现有[连接与会话合同](../contracts/connection-and-session.md)，不复制简化 Cookie 或明文业务凭据持久化。

## 认证

| 操作与来源 | 引导与 service | 重定向及最终 URL | Cookie/Session/Token | 方法、精确参数 | 头与编码 | 加密/签名 | DTO/解析 | 缓存、并发、重试 | 错误与产品含义 |
|---|---|---|---|---|---|---|---|---|---|
| login；C:33–110；旧版 K:276–334、637–665；测试 T:177–215 | 两源 GET B`/anyshare/oauth2/login?redirect=%2Fanyshare%2Fzh-cn%2Fportal`。signin 分支访问 S`/login`，service 指向 B`/oauth2/signin`；C:62 使用未百分号编码的 service，K:312 使用百分号编码。 | 识别 B`/oauth2/signin` 或 B`/anyshare/oauth2/login/callback`。signin 分支经 SSO 后要求 callback；直接 callback 分支再 GET B`/anyshare/oauth2/login/refreshToken`。C 依赖自动跳转且只判断 path；K 手动处理最多 20 次 GET/Location，解析相对地址并覆盖 303。两者未严格验证最终主机。 | C:50–59 把整个 query 作为 challenge Cookie 解析，K:305–308 只提取 challenge 参数后设 Secure Cookie。C:65–67 正常路径删除 challenge，80–108 取个人 Token、清理部分 OAuth Cookie；K 未清理 challenge。刷新 Cookie 真实有效期未知，异常清理未覆盖。 | 云盘 OAuth 请求均 GET。依赖的 SSO 普通提交为表单 POST；buaa-api sso/auth.rs:49–56 的 submit 字段与 K:609–615 不同，风险页继续表单也不同。云盘须复用 UBAA2 已审计 SSO，不从发布工具新建登录器。 | GET 导航；SSO 为 application/x-www-form-urlencoded。service wire 编码及 challenge 提取差异见后文停止条件。 | 云盘没有实际调用手动登录 RSA。SSO 本身无此云盘 RSA 加密。 | callback 路径与个人 Token Cookie；不公开 challenge、OAuth 状态或 Token。C:38–42、69 留有刷新失效与回调失败 TODO。 | P；SSO/云盘状态共享但没有登录 single-flight 或分享 Cookie 竞争保护。无业务重试。 | 缺 challenge、错误落点或缺 Token 报错。HTTP 成功或 callback 路径本身不足以证明当前账号身份与权限。云盘专用退出和过期服务端识别无证据。 |

## 读取操作

以下个人业务操作继承 P 的引导、重定向、头、编码、加密、缓存/并发/重试及错误列。支持分享 Token 的行同时继承 A。请求字段写出冻结代码的固定值；响应没有的字段不补造。

| 操作、buaa-api 位置与旧版对应 | 方法与精确参数 | 授权与 DTO/解析 | 错误、产品含义与特殊缺口 |
|---|---|---|---|
| get_root_dir；O:15–24、D:32–81；旧版不适用 | GET E`/entry-doc-lib`；query 固定 `sort=doc_lib_name,direction=asc`；All 不加 type，User/Shared/Department/Group 的 type 依次为 `user_doc_lib/shared_user_doc_lib/department_doc_lib/custom_doc_lib`。 | P；响应数组 `RootDir{id:String,name:String}`。转 Item 时使用默认时间、size=-1、无分享 Token。 | 分类表示可读取的文档库入口，不能推出团队创建/管理能力。没有分页或总量字段。 |
| get_user_dir；O:27–34；旧版不适用 | GET E`/owned-doc-lib`；空正文、无参数。 | P；严格解析为 `[RootDir;1]` 并转 Item。 | 0 项或多项均解析失败，不能默选第一个。 |
| list_dir；O:39–62；旧版 K:573–584、134–162，T:102–141 | POST E`/dir/list`；JSON `by=name,docid=<目录>,sort=asc`。两源同字段。 | P 或 A；D:84–125 的 Dir 为 `dirs:Vec<Item>,files:Vec<Item>`。分享来源 Token 复制到每个子项。旧版仅解析发布前缀文件与数组数量。 | 通用 DTO 必须保留所有条目，不能继承发布前缀过滤或把缺失数组默认为空。源码未证明列表完整性、分页或权限字段。 |
| get_item_size；O:65–77、D:220–232；旧版不适用 | POST E`/dir/size`；JSON `docid=<目标>,onlyrecycle=false`。 | P 或 A；`dirnum/filenum/totalsize` 分别映射 i64 目录数、文件数和字节数。 | 来源未校验负计数、溢出或文件/目录差别，输入与 DTO 失败需有明确语义。 |
| get_suggest_name；O:79–100；旧版不适用 | POST E`/file/getsuggestname`；JSON `docid=<父目录>,name=<名称>`。 | 固定 P，未使用 parent.token；从响应抽取 name 字符串。 | 文件和目录共用名称空间；带点目录可能按扩展名方式生成建议。建议名称只表示一次读取，不能锁定名称或代替写权限。 |
| list_recycle；O:190–204；旧版不适用 | 先 get_user_dir，再 POST E`/recycle/list`；JSON `by=time,docid=<个人根>,limit=100,sort=desc,start=0`。 | P；解析为 Dir。Item 的 create_time 可缺失并用默认时间；没有总数、游标或完整性字段。 | 仅首批最多 100 项，没有翻页循环和结束证明。不能宣布完整回收站，少于 100 项也缺少独立的完备证明。 |

Item 字段与类型：D:95–137 的 docid/name 为 String，size 为 i64，size=-1 表示目录；modified 与可选 create_time 由 i64 时间值除以 1,000,000 后交给 DateTime。注释的时间单位表述不能替代该计算行为。rev 被注释掉，不是读取结果字段。其他字段形状、缺失值或单位不得凭 AnyShare 名称扩展。

## 文件与回收站写入

本表全部继承 P。每次请求的服务端效果均为写入；两源无条件写入、事务或幂等键证据。成功响应的缺字段或传输异常不能统一当作“未写入”。

| 操作、buaa-api 位置与旧版对应 | 方法与精确参数 | 授权与 DTO/解析 | 错误、产品含义与特殊缺口 |
|---|---|---|---|
| create_dir；O:103–115；旧版不适用 | POST E`/dir/create`；JSON `docid=<父目录>,name=<名称>,ondup=1`。 | P；响应抽取 docid 字符串。没有采用 parent.token。 | 同名处理由 ondup 决定；没有覆盖或分享建目录依据。 |
| rename_item；O:119–129；旧版不适用 | POST E`/dir/rename`；JSON `docid=<目标>,name=<新名称>,ondup=1`。 | P；只检查通用请求成功，未解析业务收据。 | 来源注释不存在目标可返回 400。不能用无正文成功推断目标仍为原版本。 |
| move_item；O:132–144；旧版不适用 | POST E`/dir/move`；JSON `destparent=<目的目录>,docid=<来源>,ondup=1`。 | P；响应抽取 docid 字符串；两个 Item 的分享 Token 均未采用。 | 不能扩展为跨分享移动或多项原子移动；返回 docid 可能变化，后续身份依实际响应。 |
| copy_item；O:147–174；旧版不适用 | POST E`/dir/copy`；JSON 同 move_item。 | 个人来源用 P；分享来源仍用个人 Bearer，并附 `x-as-authorization: Bearer <该分享Token>`。响应抽取 docid 字符串。 | 分享另存的目标是个人授权目的目录，不能混用另一个分享作为目标。来源 Some 分支绕过 unireq，不刷新个人本地估计。 |
| delete_item；O:176–187；旧版 K:336–357 | POST E`/file/delete`；JSON 仅 `docid=<目标>`，两源相同。 | P；buaa-api 只检查 HTTP 成功；旧版过滤发布文件后逐项调用。 | 产品含义为移入回收站。O 注释称重复删除不报错，但无幂等或失联重放保证；K 捕获错误后继续并输出完成，不能照搬到用户文件管理。 |
| delete_recycle_item；O:209–217；旧版不适用 | POST E`/recycle/delete`；JSON 仅 `docid=<回收站目标>`。 | P；只检查通用请求成功。 | 永久删除单项；多项需分别请求，来源没有清空回收站或批量事务接口。 |
| restore_recycle_item；O:220–233；旧版不适用 | POST E`/recycle/restore`；JSON `docid=<回收站目标>,ondup=1`。 | P；响应抽取 docid 字符串。 | 没有指定新父目录、自动改名或覆盖既有对象的证据。 |

## 分享操作

本表除 share_parse 外继承 P；share_parse 的导航与临时授权按该行完整列出。分享管理与接收他人分享分别建模。

| 操作、buaa-api 位置与旧版对应 | 方法与精确参数 | 授权与 DTO/解析 | 错误、产品含义与特殊缺口 |
|---|---|---|---|
| share_history；O:236–242、D:294–343；旧版不适用 | GET B`/api/doc-share/v1/docs-shared-with-anyone`；无参数、空正文。 | P；`entries[].doc{id,type}` 与 `link_configs[]` 展平为 Share。链接字段 id/title/expires_at/password 为 String，limited_times 为 i64，allow 为字符串数组。 | 没有分页和总数处理。名称含 history 指分享记录，不是文件版本历史。密码与分享访问材料不得进入日志。 |
| share_record；O:246–255、D:237–256、347–359；旧版不适用 | GET L`/document/folder/{docid}?type=anonymous`；docid 只把 `:`、`/` 替换为对应百分号编码。 | P；解析为 Vec<Share>。路径固定 folder，来源示例也用于文件，未提供其他类型路径。 | 不自行发明 file 路径。ShareItem 的 id/type 在反序列化时跳过，直接回传 update 可能丢失关联信息，须先补 Mock 与必要上游证据。 |
| share_item；O:263–271、D:147–160、237–292、347–450；旧版不适用 | POST L`/document/anonymous`；JSON 含 `item{id,type,allow},title,expires_at,password,limited_times`；外层 id 不序列化。type 为 file/folder，allow 只采用 D 中五种权限字符串。 | P；输入由条目构造，返回抽取 id 后填回 Share。默认仅 display，默认不过期、空密码、次数不限的具体表示见 D:147–160。 | 预览/下载/创建/修改为分享权限；enable_upload 组合 create+modify。配置权限不能证明应用已有预览器或分享目录建目录协议。 |
| share_update；O:276–284；旧版不适用 | PUT L`/document/anonymous/{分享id}`；JSON 同 share_item，外层 id 仍不序列化。 | P；仅检查通用请求成功。来源输入来自创建结果或读取结果。 | 读取 DTO 的 item 信息丢失与更新序列化兼容性尚待核实，不能猜 null/default 的服务端含义。修改/取消权限的精确产品输入由实现任务按证据设计。 |
| share_delete；O:289–297；旧版不适用 | DELETE L`/document/anonymous/{分享id}`；空正文。 | P；仅检查通用请求成功。 | 删除分享访问入口，不删除文件。不存在、重复删除及撤销传播时效无来源保证。 |
| share_parse；O:308–367、D:164–217；旧版不适用 | GET L`/links/{分享id}` 读 password_required。需要密码时 POST B`/link`，JSON `id,type=anonymous,password_required=true,password=<输入>`；否则 GET B`/link/{分享id}`。再 GET E`/entry-item`。 | 链接导航复用 Cookie jar；从对应 `link_token:<分享id>` Cookie 取临时 Token，以该 Token 作 entry-item Bearer。解析为单元素数组，created_at/modified_at 为时间字符串，id/name 为 String，size 为可选 i64，缺失视作目录；结果附内存 Token。 | 不要求个人登录。缺密码为参数错误；各段未统一校验 HTTP 状态，后续解析失败不可当空内容。成功路径删除临时 link Cookie 与入口 Cookie，异常路径未保证清理；无临时 Token expiry 或刷新协议。只支持一个分享根目标。 |

share_parse 时间字符串按 D:181–192 的解析和 UTC+8 转换处理，与普通 Item 的整数时间解析不同。不存在精确类型或边界的响应须先形成脱敏 Fixture，不以字符串相似代替时间证据。

## 上传与下载

普通授权请求继承 P 或 A，对象请求继承 X。本表的多阶段流程属于同一个用户操作，但每个已经发出的写阶段都可能留下远端结果。

| 操作、buaa-api 位置与旧版对应 | 方法与精确参数 | 授权与 DTO/解析 | 缓存、并发、重试、错误与产品含义 |
|---|---|---|---|
| get_download_url；O:374–438；旧版不适用 | 单文件 POST E`/file/osdownload`，JSON `docid,authtype=QUERY_STRING`；目录按下一行 batchdownload，name 使用目录名。 | P 或 A；单文件取 authrequest 第二项地址，目录取得 ZIP 地址。未实际 GET 文件。 | 签名地址及有效期是临时授权材料，来源只返回 String，未验证 URL、最终跳转、长度或内容。目录打包是否产生服务端临时资源未明，不扩展为业务文件写入。 |
| get_batch_url；O:394–455；旧版不适用 | 空选择报错；单个文件分流 osdownload。其他情况 POST E`/file/batchdownload`，JSON `name=<输入>.zip,reqhost=<B主机>,dirs=[目录id],files=[文件id]`。 | 只取第一项 Token；响应抽取 url 并删除反斜杠，未按 JSON 字符串正常解码。 | 混合个人/分享或不同分享来源未校验，不能照搬。ZIP 命名与路径分隔符、地址解析和重定向需要明确验证。没有 Range、落盘、续传、解压或摘要校验实现。 |
| upload_fast_check；O:463–474、D:491–530；旧版不适用 | POST E`/file/predupload`；JSON `slice_md5,length`。 | 固定 P，无目的目录与分享 Token；响应抽取 match，与 true 文本比较。 | 探测与创建分开。O 注释分享目录始终不匹配，不能作为分享上传预检。前 200 KiB 哈希必须按精确长度处理，普通 Read 的短读边界需要测试；探测结果不能保证下一次秒传成功。 |
| upload_fast；O:481–501、D:536–574；旧版不适用 | POST E`/file/dupload`；JSON `client_mtime=<当前毫秒>,crc32,docid=<目的目录>,length,md5,name,ondup=1`。 | 固定 P；输入完整 MD5 与 CRC32，响应 success 必须为 true。 | 这是创建业务文件的写入。分享目录明确不支持；不因预检成功自动绕过确认。没有更新既有同名文件的依据。 |
| upload_small；O:508–549、D:650–657；旧版 K:387–433、540–570 | POST E`/file/osbeginupload`，JSON `client_mtime,docid=<目录>,length,name,ondup=1`；对象 PUT 文件字节；最后 POST E`/file/osendupload`，JSON `docid=<授权返回>,rev=<授权返回>`。两源阶段与字段相同。 | P 或 A；开始响应为 `authrequest,docid,rev`。X 的 URL/头由上游返回；buaa-api authrequest 是 Vec<String>，旧版动态数组。 | buaa-api 将整个文件 Vec 作为正文；旧版流式读取文件。旧版非 2xx PUT 最多 3 次尝试，见 K:411–429，此写重试不可照搬。buaa-api 校验 PUT HTTP 状态；结束登记只检查 HTTP，旧版还检查 error 字段并轮询目录文件名。各阶段响应丢失均不能证明无写入。 |
| upload_big；O:556–665、D:577–668；旧版 K:436–570，T:143–175 | POST E`/file/osinitmultiupload`，JSON `docid=<目录>,length,name,ondup=1`；POST E`/file/osuploadpart`，JSON `docid,rev,uploadid,parts=1-N`；逐块对象 PUT；POST E`/file/oscompleteupload`，JSON `docid,rev,uploadid,partinfo`；按返回 XML 与授权执行对象 POST 合并；最后 osendupload，JSON `docid,rev`。 | P 或 A；初始化返回 String 类型 docid/rev/uploadid；授权为编号到方法/地址/头数组的映射；partinfo 每项为 ETag 与块长。完成协议为 XML+JSON multipart，随后由 X 请求。 | 两源按数字编号顺序、20 MiB 块长上传并保留 ETag；仅末块可不足块长。buaa-api PUT 不检查状态即取 ETag，旧版先检查 HTTP。完成与结束登记必须分别确认。无断点恢复、上传取消接口、缺片/重复片/非法编号验证或持久传输日志。 |

上传辅助参数的计算与顺序见 D:454–575：compute_mini 记录文件长度、前 200 KiB MD5 并回到开头；compute_full 记录完整 MD5/CRC32 并回到开头。秒传先 mini 探测后 full 提交；普通与分块上传没有发送这两个哈希的证据。上传前后文件改变、零字节分块、长度与正文不一致均需确定性反例。K:103–107、T:143–147 固定大于 100 MiB 才分块；O 的 5 GiB/100 GiB 文字为来源注释，没有对应边界校验或实时容量证据。

## 当前传输实现

普通上传沿两源使用开始授权、对象 PUT 和最终登记。大于 100 MiB 的文件按旧版阈值切为 20 MiB 分片，精确匹配 1—N 授权与块长，逐块核对成功状态和非空 ETag，再消费合并 XML/POST 授权及最终登记。最终响应须为 JSON 对象且没有 `error`。每个写阶段至多发送一次。

对象地址和头只来自本次 API 授权，独立客户端严格验证 TLS、拒绝重定向和额外认证，不附加个人/分享 Bearer 或导航 Cookie。URL 比较允许解析器对默认 HTTPS 端口的规范化，请求仍使用授权原地址。上传与下载均以最多 64 KiB 的块处理，上传核对实际读取长度，下载不进入通用响应正文。单文件及 ZIP 下载以 GET 消费当次地址，属于客户端最小消费，冻结来源没有正文下载实现。

开始请求的确定 400/401/403/404/409 拒绝保留原错误。初始化已经接受或后续阶段不确定时返回 `OutcomeUnknown`，不因后续 4xx 抹去已有远端阶段。开始响应先核实 docid/rev 并保存已知 U，再消费对象授权；授权不支持时零对象发送并保留 U。上传取消停止后续发送，下载失败清理私有半成品，已有用户文件保持原件。普通命令的原控制柄贯穿材料锁后与后续发送检查。流块在共享材料与会话检查之后再次读取原控制函数、文件取消和客户端关闭状态，等待锁期间停止的当前块不再推进。Bearer 在取得材料锁后重新核对文件状态和传输取消。

## 来源差异、不可照搬行为与停止条件

“来源事实”描述冻结代码实际做法；“UBAA2 规则”来自现有安全与工程约束；“待证据”表示不能据本文选择一个猜测实现。严格 TLS、日志脱敏和禁止未知写入重试属于已有规则，不是对上游 wire 协议的新推断。

| 边界 | 已知差异或缺口 | 实施限制与解除条件 |
|---|---|---|
| OAuth service 与 challenge | C:50–63 与 K:305–312 的 service wire 编码、query 提取方式不同。SSO 表单也有差异，见上述 login。 | 采用旧版 K:305–327 的 service 编码、challenge 提取与 GET 会话复用，具体依据见[实施取舍](decision-log.md#2026-11-05北航云盘的认证与分享关联)。没有复制 buaa-api 的第二份 SSO 表单认证。缺少实际分支的同路线认证观察，真实协议验收仍待授权。 |
| 重定向与刷新 | C 依赖自动跳转，K 明确处理 303/相对 Location；两源仅检查路径且刷新过期 TODO 未解决。 | 不复制自动跟随未知目标。复用既有手动校验机制前，须为云盘声明允许主机、路径、嵌套 service、有限跳数与终点。未知跳转停止；缺失的实际分支待获授权的同路线认证观察补证。 |
| 成功响应 | 小文件结束登记：C 通用 HTTP 成功，K:555–558 还识别 error 并查目录；大文件 PUT：O:596–615 未验状态，K:493 先验状态。 | 差异本身不能证明某个任意 2xx 正文成功。先用来源支持的失败 Fixture 固定状态和字段要求；不能裁定的业务成功形状暂停成功映射，发送后解析不明保留 OutcomeUnknown。 |
| 分享更新 DTO | D:347–359 跳过读取 item.id/type；O:276–282 又直接序列化 Share 更新。旧版不适用。 | 创建结果保留原输入的 item，history 的 D:294–343 显式包含 doc.id/type，均可据完整字段更新。record 缺少关联时拒绝更新。三种输入分别由 Mock 固定请求字段，依据见[实施取舍](decision-log.md#2026-11-05北航云盘的认证与分享关联)。 |
| TLS 默认配置 | context.rs:249–255 默认 tls=true，request.rs:17–21 直接传给 danger_accept_invalid_certs，实际默认忽略证书错误。 | 不可照搬。按已有规则保持 TLS 校验；证书失败如实报告，不改为绕过。 |
| 原始错误与秘密泄漏 | D:24–28 将原响应交给 error.rs:82–98 记录；C:127–138 也可能记录原文。示例 cloud.rs:174–194、219 打印含 Token 的 Debug 模型及签名 URL。 | 不可照搬。错误、Debug、CLI JSON、Bridge、日志与诊断只接受安全字段，不传播原始异常 source、授权头、分享密码、Token 或签名地址。 |
| 对象存储目标与请求头 | O:508–547、570–661 与 K:397–419、455–549 从本次 API 响应取得对象 URL 与头；K:818–828 明确动态授权数组。两源没有固定对象主机表或对象重定向规则。 | Direct 可消费本次、同操作、经严格 TLS 与账号/路线检查的 API 授权响应。Core 校验结构、预期方法、合法 HTTPS 地址与头，并隔离 Cookie、个人及分享 Bearer，不接受宿主自定 URL 或历史授权。当前拒绝对象重定向和额外认证分支，扩展时再补同路线、同操作证据。真实传输仍按具体操作授权与验收。见[动态传输授权](decision-log.md#2026-11-05北航云盘的动态传输授权)。 |
| 条件写入与固定文件更新 | 两份冻结实现没有版本条件。2026-11-05 的官方检索正文补充 `metadata/osdownload.rev` 与开始、初始化、最终登记的 `editedrev`，详见下节。 | 可据此设计本机同步及 Mock 路径。北航部署的同版本下载、最终比较原子性、创建竞争与结构化冲突仍未验证，真实自动同步保持未验证。禁止删旧后传新。 |
| WebVPN | 云盘两源均为 Direct。sso/auth.rs:18–27 的 VPN 登录说明仅用于 Class，不能证明云盘链路。 | 云盘 OAuth、分享 Cookie、对象存储和下载各阶段分别待证。通用 URL 包装不能解除阻塞；获授权后逐路线验证并记录失败位置与重跑前提，不透明回退 Direct。 |
| 列表完整性 | 回收站固定 start=0/limit=100；其他列表亦无总数/分页结束处理。 | 已返回范围可以展示，完整性保持未知/部分。分页参数、页间去重、顺序、总数与终止条件必须有来源或脱敏上游证据后才能扩展并声明完整；仅凭短页不补出完整标记。 |
| 多阶段重试与核对 | K:411–429 自动重试 PUT；K:562–570 核对只比较文件名；两源无 OutcomeUnknown、回滚或恢复依据。 | 不可照搬写重试、按名称确认成功或整条流程重放。每阶段一次发送，未知后停止后续写入，使用同目标/同路线只读证据核对；缺少强身份核对时继续保持未知。 |

## 实现与验收所需证据

### 2026-11-05 实现采用的协议行为

个人认证复用当前已认证的 SSO 会话，不接受第二份用户名或密码。OAuth 的 service 采用旧版 K:312 的百分号编码，challenge 只提取 K:305–308 指定的单个 query 参数，并在成功或失败后删除临时 Cookie。手动 GET 跳转支持旧版测试证明的相对 Location 与 303，限制在两源的云盘 OAuth 路径和 SSO `/login`，SSO service 固定为云盘 `/oauth2/signin`。SSO 重新出现登录表单时返回认证不可用，交由既有学校认证流程恢复。刷新入口只采用 C:70–72、K:322–327 已有分支，不估计服务端 Token 寿命。WebVPN 继续不可用，不能隐式转用 Direct。

文档库、个人根、目录、大小、建议名称、回收站、分享历史和单项目分享记录按上表实现，列表完整性保留未知，回收站明确首批 100 项。普通条目的微秒时间按来源除以 1,000,000 转成 Unix 秒，未返回的根目录时间为空。必需数组、字符串和计数严格解析，缺字段不能成为空结果。公开条目使用 Core 签发的句柄，分享临时 Token 与个人 Token 留在 Core。

文件写入沿用每行精确 JSON 和 `ondup=1`。个人目标与分享目标分别检查，只有 copy 另存使用个人 Bearer 加来源分享的 `x-as-authorization`。每份确认只消费一次，网络发送后的响应丢失或成功收据解析失败返回 `OutcomeUnknown`。rename/delete 等来源没有收据的操作沿用 HTTP 成功语义，不补造版本证明。分享创建结果包含原输入的 item，history 的 D:294–343 明确保留 doc.id/type 与 allow，两种来源均可使用完整关联更新。record 的读取模型跳过 item.id/type，继续拒绝从缺失关联构造更新。

个人秒传采用 O:463–511 的 predupload 与 dupload，前 200 KiB MD5 只用于探测，匹配后才计算完整 MD5/CRC32。文件读取缓冲为 64 KiB，计算摘要期间检查取消，确认后在发送边界重新核对文件长度、修改时间、账号与路线。每个进度控制只用于一个任务，未匹配时停止，最终提交响应丢失保持 OutcomeUnknown。CRC32 使用锁文件已有的 crc32fast 1.5.3，Core 将既有传递依赖声明为直接依赖，用于来源要求的 crc32 字段。

业务 API 只发送显式 Bearer，导航 Cookie 与分享临时 Cookie 在各自边界内处理。下载准备消费 osdownload 或 batchdownload 授权结构后只公开方法、主机、端口与头名称，不公开或访问签名地址。Direct 对象传输按当次动态授权规则实现，未知重定向和额外认证分支拒绝；北航部署的同名条件覆盖和 WebVPN 继续等待验证。公开爱数开发者文档的检索入口为 <https://developers.aishutech.com/napi/documents/307>，文档检索摘要包含另一套“文件请求上传”接口的 version 比对说明，但未取得北航部署与冻结上传流程的对应证据。不能据该摘要把上传 rev 解释为 CAS，也不能据官方示例固定对象主机。

上述记录覆盖 login 与 25 个公开业务操作；模型辅助方法只承担构造、计算与投影，不增加上游能力。全文检索、在线编辑、文件版本历史、团队管理、应用内预览、持久断点续传均无对应公开操作。文档库 Group 分类、Share.preview 权限及上传 rev 不补足这些能力。

生产实现先为各操作建立脱敏请求与解析 Fixture，证明错误回调、缺 Token、权限拒绝、缺字段、混合分享授权、非法外部 URL、短授权数组、非 2xx 带 ETag、缺片/乱序/非法编号、文件改变和最终登记响应丢失等失败行为，再实施有证据的最小请求。来源示例中的真实读写测试及旧版发布/清理任务不得作为普通门禁执行。

确定性验证、CLI 端到端、Direct、WebVPN、平台文件能力与设备证据分别记录在[迁移状态](status.md)，检查清单只使用[开发命令](../development/commands.md#来源对照与真实验证)。真实账号认证和读取依当前会话功能/路线授权；每次真实写入还需要具体操作、目标、路线与时间。路线不可达或未授权时保留阻塞，并在取得相应授权、网络可达且前置证据补齐后重跑该路线。Fixture、另一条路线和历史成功不替代该路线结果。

## 日程固定文件的版本条件

本节保留旧共享文件的协议依据，当前生产同步使用后文的独立快照路径。

2026-11-05 核对[官方 AnyShare 7.0.0 接口文档](https://developers.aishutech.com/napi/documents/307)的搜索引擎正文，索引标记约六个月前抓取。直接读取页面超时。记录只采用公开字段和语义，不作为北航部署验收。认证、路线、Cookie/Bearer、JSON 编码和动态对象传输仍遵守本文 P/X 公共列及[动态传输决定](decision-log.md#2026-11-05北航云盘的动态传输授权)，不增加认证或 HTTP 实现。

| 操作 | 冻结旧版 `1f4b8f84` | 冻结 buaa-api `a63712fa` | 官方依据与本次采用 |
|---|---|---|---|
| 个人目录与 `UBAA` 定位 | K:134–164 解析指定目录，未提供个人根目录 API | O:15–59 读取个人库与目录，O:103–115 创建目录，JSON `docid/name/ondup=1` | 复用 bhpan facade 的明确个人库与完整目录结果。范围未知或不完整的列表不能证明目标不存在 |
| 文件基版元数据 | K 仅保存 `docid/name`，无版本读取 | D:95–114 的 `Item.rev` 被注释，无 metadata 操作 | 官方 POST `/efast/v1/file/metadata` 支持 `docid/rev`，空 rev 表示最新。取得非空基版 R，下载与后续比较均绑定同一对象/R |
| 固定版本下载 | 无正文下载实现，不适用 | O:374–387 的 POST osdownload 只传 `docid/authtype=QUERY_STRING`，未传 rev，只提取授权 URL | 官方 osdownload 可传 rev，响应含 rev。请求固定 R，不以“下载时最新”代替 R；授权与对象 GET 由 bhpan facade 消费 |
| 首次文件创建 | K:388–419、435–455 普通/分片开始均使用 `ondup=1` | O:508–520、560–572 同为 `ondup=1` | 个人 `UBAA/agenda.json` 首次创建保持不覆盖。范围未知不能推断缺失；首次启用已明确确认创建时，可直接以 `ondup=1` 尝试，冲突后只读重定位，不删除或覆盖原文件 |
| 普通与分片条件更新 | K 普通/分片均没有 editedrev | O 普通/分片均没有 editedrev | 官方 osbeginupload/osinitmultiupload 支持 `editedrev=R`。新上传返回版本 U，U 不能替代基版 R |
| 最终条件登记 | K:540–560 仅传 `docid/rev` | O:538–547、653–662 仅传 `docid/rev` | 官方 osendupload 的 `rev=U, editedrev=R` 分工明确。实际最终比较原子性仍待北航部署验证 |
| 成功或 unknown 核对 | K:562–573 只轮询同名可见；不能证明内容与版本 | 无上传后正文核对或结果未知模型 | 成功后对同对象固定 U 读回并逐记录核对；unknown 保留待同步，先只读核对，不自动重发。官方字段说明的 `403203` 与错误表 `403002203` 尚有歧义，不猜测稳定错误码 |
| 同步文档、合并与本机确认 | 无等价本机日程协议，不适用 | 无等价本机日程协议，不适用 | `schema/items/overlays` 属于 UBAA 本地产品格式。Core 负责记录排序、删除标记、事务及快照确认，不从学校 DTO 推断同步字段 |

上述版本字段已接入最小 Core facade，并由 Mock 验证同对象/R 下载、开始与最终登记的 R/U 分工、未知结果保留 U 及首次不覆盖参数。真实能力恢复前，需要当前会话的具体授权及同版本下载、两客户端同 R 最终登记至多一个成功、首次同名创建不覆盖和结构化冲突的脱敏部署证据。WebVPN 单独验证。


## 日程不可变快照的操作组合

本次以 `11832957` 为基线，重新读取固定旧版 K 的目录解析、普通上传与最终登记，以及固定 buaa-api O:39–77、103–115、508–547 的列表、统计、建目录和普通上传。认证、引导 URL、重定向、Cookie/Bearer 作用域、JSON 编码、加密常量和错误列沿用本文各操作及公共列。分页接口的端点、参数和 DTO 单独记录如下。

| 操作 | 冻结旧版 | 固定 buaa-api | 同步采用与未决证据 |
|---|---|---|---|
| 定位目录与读取列表 | K:134–164 仅解析返回的 files，不证明完整 | O:39–62 发送已有 dir/list 参数并解析 dirs/files，没有分页结束字段 | 只使用已签发个人目录句柄，各层通过完整分页后再定位；旧 `dir/list` 不增加分页参数，未知或失败结果不能证明缺失 |
| 分页列举目录 | 没有等价路径，不适用 | O:39–62 只有 POST dir/list，没有 folders/sub_objects，不适用 | 官方 GET /efast/v1/folders/{id}/sub_objects 使用 limit、marker，返回 dirs/files、next_marker。北航 Direct 实测全 GNS 百分号编码作为一个路径段，limit=2 的四页为 2/2/2/1，末页 next_marker 明确为空字符串；缺省、null 或短页均不能作为结束。排序只首轮传，不推断其他分页字段 |
| 首次建目录 | 旧版使用预先配置目录，无等价创建 | O:103–115 使用 docid/name/ondup=1 | 确认后复用现有建目录；同名拒绝和并发结果不从 CAS 失败推断 |
| 新建不可变文件 | K:388–419、540–570 使用 name/ondup=1，最终 docid/rev，随后按列表检查同名 | O:508–547 同为普通上传，无条件版本比较 | 每发布身份一个新文件，不用 editedrev 更新。最终登记前后可见性的 Direct 结果见下文，明确回执与当前版本正文共同确认发布 |
| 正文读取与确认 | 无等价正文下载 | O:374–387 只提供 osdownload 动态授权请求 | 当前 metadata 与指定当前版下载继续使用已实现 facade，不能仅凭对象可下载确认发布 |
| 本机发布序号、删除摘要、启用许可 | 无等价本机协议，不适用 | 无等价本机协议，不适用 | 由 Core SQLite 事务与共享应用服务管理，不从上游字段推断 |

同步复用每个云盘 facade 自身的发送前路线解析。当前 WebVPN 云盘能力未验证，云盘用进程内原因标识不支持路线，同步统一归约为 `Unverified`（命令 `sync_unverified`、退出码 6），覆盖作业内 Auto 路线变化。Direct 认证错误与共享身份失效继续保留原分类。冻结旧版 K:276–334 与 buaa-api C:33–110 只提供 Direct 认证，没有 WebVPN 云盘或同步退出码约定，本项不适用。引导、URL、认证材料、请求字段与编码沿用各操作原有规则。

不可变快照不改变普通云盘业务的现有成功与错误约定。生产同步使用独立快照的分页发现与发布确认，不读取旧共享文件。Direct 的分页与初次文件可见性已有下述部署证据，旧共享文件的条件覆盖能力继续保持 `Unverified`。


官方分页来源为 [AnyShare 7.0.0 文档](https://developers.aishutech.com/napi/documents/307)的“分页列举目录”。2026-11-05 检索正文确认 limit 的开区间为 0 到 10000、推荐 1000，marker 由前次成功响应取得，首轮不传。新列表条目标识为 id，包含 name、rev、size 和 RFC 3339 的 created_at/modified_at；目录示例 size=-1。旧 dir/list 的 docid 与数值时间结构不适用于该接口。

同日主监督在既有七文件合成目录完成 Direct 只读验证：四次 GET 的 limit 均为 2，后续 marker 与前页响应逐字相同，前三页非空、末页明确空串。合并得到七个唯一 name/id，与同轮旧列表一致，无重复，业务写入为零。安全摘要保存在本地忽略的 command_delivery/sync_deployment_probe/paged_directory_probe/multi_page/live_result.json；共享文档不记录真实 GNS、marker 或认证材料。两源认证、路线与 Bearer 规则继续适用，本次不改认证接口。该记录没有覆盖 WebVPN。

2026-11-05 重新读取官方分页文档正文，核实 `limit/marker`、可省略的首轮排序和 `id/rev/name/size/created_at/modified_at`。新增 `bhpan_list_complete` 只接受已签发的个人目录句柄，使用每页 1000 项且不指定排序，后续只原样编码前页 marker。只有明确空字符串结束后才签发条目；相同 ID 的一致重复条目合并，字段或类型冲突、标记循环、必需字段缺失、某页失败及取消均不交付部分结果。原 `dir/list` 与普通浏览的范围语义保持原有约定。完整路径定位逐层读取全部分页后再确定缺失，同名歧义和中间文件均失败。

同日授权的既有合成测试目录通过当前 Core facade 完成 Direct 初次文件观察：开始授权并完成对象 PUT 后，最终登记尚未发送，第二客户端完整分页未列出目标；最终登记明确成功后，第二客户端取得同名条目、当前 metadata 与该当前版本的完整正文，发布身份和正文均一致。每个写阶段只发送一次。该观察支持正常发布后读回确认；丢失最终回执的尝试仍保持 unknown，仅作只读核对。明确成功的最终回执与对象、版本、名称、大小一同持久保存在原在途记录中，进程重启后可继续核对，任何字段变化均不能确认。该验证没有执行旧共享文件覆盖，也没有验证 WebVPN 云盘链路。原始材料仅保存在本地忽略的 `agenda_sync_snapshot/live/` 任务目录。

2026-11-05 的后续 Direct 验收在原合成目录内新建四份日程快照。一次新文件发布在 begin/PUT 完成、最终登记发送前未出现在第二客户端完整目录中；最终登记成功后，当前 metadata 与完整正文一致。两个独立 SQLite 库各创建一条合成事项，经过实际上传、当前版本下载与 Core 合并后均保留两条事项；随后发布删除摘要，另一库再次合并旧快照仍保留删除。私有探针仅对该目录将分页大小设为 2，完整遍历分别为 4/5/5/6 页，末次得到 11 个唯一对象，后页 marker 均与前页响应一致，末页明确空串。没有新建目录或重试写入。原始材料及脱敏汇总保存在本地忽略的 `agenda_sync_snapshot` 目录。WebVPN 登录遇到验证码，未进入云盘读取或写入。
