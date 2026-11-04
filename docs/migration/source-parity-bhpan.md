# 北航云盘协议来源对照

本文记录北航云盘独立功能的冻结来源、逐操作协议和缺失证据，供后续实现与复核使用。生产功能尚未实现，本文没有真实账号或设备验收结果。产品范围见[北航云盘设计](../design/bhpan.md)，公开边界见[北航云盘合同](../contracts/bhpan.md)。来源冲突、真实操作授权和验收遵守 [AGENTS](../../AGENTS.md#来源对照门禁)。

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

## 来源差异、不可照搬行为与停止条件

“来源事实”描述冻结代码实际做法；“UBAA2 规则”来自现有安全与工程约束；“待证据”表示不能据本文选择一个猜测实现。严格 TLS、日志脱敏和禁止未知写入重试属于已有规则，不是对上游 wire 协议的新推断。

| 边界 | 已知差异或缺口 | 实施限制与解除条件 |
|---|---|---|
| OAuth service 与 challenge | C:50–63 与 K:305–312 的 service wire 编码、query 提取方式不同。SSO 表单也有差异，见上述 login。 | 对这些存在 wire 差异的分支暂停新增生产请求。先逐字段说明是否与现有已审计 SSO 兼容；如不能由适用旧版实现和测试确定，按 AGENTS 将具体差异与脱敏观察写入 decision-log 后裁定。本文不替代裁定。 |
| 重定向与刷新 | C 依赖自动跳转，K 明确处理 303/相对 Location；两源仅检查路径且刷新过期 TODO 未解决。 | 不复制自动跟随未知目标。复用既有手动校验机制前，须为云盘声明允许主机、路径、嵌套 service、有限跳数与终点。未知跳转停止；缺失的实际分支待获授权的同路线认证观察补证。 |
| 成功响应 | 小文件结束登记：C 通用 HTTP 成功，K:555–558 还识别 error 并查目录；大文件 PUT：O:596–615 未验状态，K:493 先验状态。 | 差异本身不能证明某个任意 2xx 正文成功。先用来源支持的失败 Fixture 固定状态和字段要求；不能裁定的业务成功形状暂停成功映射，发送后解析不明保留 OutcomeUnknown。 |
| 分享更新 DTO | D:347–359 跳过读取 item.id/type；O:276–282 又直接序列化 Share 更新。旧版不适用。 | 不推断缺字段、null 或默认 type 的服务器含义。先取得可追溯脱敏请求/响应形状并覆盖创建结果、record 与 history 三种输入，再开放对应更新路径。 |
| TLS 默认配置 | context.rs:249–255 默认 tls=true，request.rs:17–21 直接传给 danger_accept_invalid_certs，实际默认忽略证书错误。 | 不可照搬。按已有规则保持 TLS 校验；证书失败如实报告，不改为绕过。 |
| 原始错误与秘密泄漏 | D:24–28 将原响应交给 error.rs:82–98 记录；C:127–138 也可能记录原文。示例 cloud.rs:174–194、219 打印含 Token 的 Debug 模型及签名 URL。 | 不可照搬。错误、Debug、CLI JSON、Bridge、日志与诊断只接受安全字段，不传播原始异常 source、授权头、分享密码、Token 或签名地址。 |
| 对象存储目标与请求头 | O:508–547、570–661 与 K:397–419、455–549 从本次 API 响应取得对象 URL 与头；K:818–828 明确动态授权数组。两源没有固定对象主机表或对象重定向规则。 | Direct 可消费本次、同操作、经严格 TLS 与账号/路线检查的 API 授权响应。Core 校验结构、预期方法、合法 HTTPS 地址与头，并隔离 Cookie、个人及分享 Bearer，不接受宿主自定 URL 或历史授权。当前拒绝对象重定向和额外认证分支，扩展时再补同路线、同操作证据。真实传输仍按具体操作授权与验收。见[动态传输授权](decision-log.md#2026-11-05北航云盘的动态传输授权)。 |
| 条件写入与固定文件更新 | ondup=1 未证明同名覆盖；上传 rev 是会话参数；Item 无有效 rev 字段。没有 If-Match、If-None-Match、幂等键、原子替换或比较后写证据。 | 暂停依赖原子同名更新的日程固定文件同步。不得默认删旧后传新。解除需要可追溯的条件更新/冲突行为证据及并发反例；若仍无保障，另行审查产品方案。 |
| WebVPN | 云盘两源均为 Direct。sso/auth.rs:18–27 的 VPN 登录说明仅用于 Class，不能证明云盘链路。 | 云盘 OAuth、分享 Cookie、对象存储和下载各阶段分别待证。通用 URL 包装不能解除阻塞；获授权后逐路线验证并记录失败位置与重跑前提，不透明回退 Direct。 |
| 列表完整性 | 回收站固定 start=0/limit=100；其他列表亦无总数/分页结束处理。 | 已返回范围可以展示，完整性保持未知/部分。分页参数、页间去重、顺序、总数与终止条件必须有来源或脱敏上游证据后才能扩展并声明完整；仅凭短页不补出完整标记。 |
| 多阶段重试与核对 | K:411–429 自动重试 PUT；K:562–570 核对只比较文件名；两源无 OutcomeUnknown、回滚或恢复依据。 | 不可照搬写重试、按名称确认成功或整条流程重放。每阶段一次发送，未知后停止后续写入，使用同目标/同路线只读证据核对；缺少强身份核对时继续保持未知。 |

## 实现与验收所需证据

上述记录覆盖 login 与 25 个公开业务操作；模型辅助方法只承担构造、计算与投影，不增加上游能力。全文检索、在线编辑、文件版本历史、团队管理、应用内预览、持久断点续传均无对应公开操作。文档库 Group 分类、Share.preview 权限及上传 rev 不补足这些能力。

生产实现先为各操作建立脱敏请求与解析 Fixture，证明错误回调、缺 Token、权限拒绝、缺字段、混合分享授权、非法外部 URL、短授权数组、非 2xx 带 ETag、缺片/乱序/非法编号、文件改变和最终登记响应丢失等失败行为，再实施有证据的最小请求。来源示例中的真实读写测试及旧版发布/清理任务不得作为普通门禁执行。

确定性验证、CLI 端到端、Direct、WebVPN、平台文件能力与设备证据分别记录在[迁移状态](status.md)，检查清单只使用[开发命令](../development/commands.md#来源对照与真实验证)。真实账号认证和读取依当前会话功能/路线授权；每次真实写入还需要具体操作、目标、路线与时间。路线不可达或未授权时保留阻塞，并在取得相应授权、网络可达且前置证据补齐后重跑该路线。Fixture、另一条路线和历史成功不替代该路线结果。
