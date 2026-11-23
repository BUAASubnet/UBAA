# 门户资料、账户指标、网费流量与财务

本文件收录门户资料、账户指标、网费流量与财务收入查询的来源对照。

## 当前规则

### 门户资料、账户指标与网费流量

身份、学院、五项账户指标和三项流量的接入方案、双来源适用性及逐操作协议见[校园账户查询](#门户资料账户指标与网费流量接入)。云盘指标按用户确认表示剩余空间。

### 当前借阅与续借

旧版冻结参考的 `LocalLibBookApi.kt`、`LibBook.kt` 和 `LocalLibBookApiBackendTest.kt` 对应座位预约，固定 buaa-api 只提供通用 SSO，两者对借阅明细和续借的业务协议均不适用。门户的 `book.bookNum` 继续只作为数量指标。借阅明细沿用门户和财务功能的分层，由 Core 复用当前路线的 SSO 会话并建立图书馆业务会话，通过 facade 和 Bridge 交给 UBAA 的 Flutter 页面。图书馆使用独立的 `library` 路线键，生效策略为 Auto 或 Direct 时只连接 `space.lib.buaa.edu.cn` 原站；显式 WebVPN 在业务请求前返回不支持提示。

公开移动端脚本和 Direct 只读观察共同确定以下证据；原始材料和公开脚本副本只保存在忽略目录 `.ubaa_local/library_loans/`：

- 公开配置 `GET /meta-local/opac/search/search_confs/m` 和同一前端资源的移动端入口 `https://space.lib.buaa.edu.cn:443/meta-local/opac/cas/rosetta`。未认证时入口 302 到学校 SSO，`service` 为该入口且显式包含 `:443`；认证后 SSO 302 回到入口，图书馆再 302，最终在入口路径返回 200。
- Direct 先完成学校 SSO 登录，再用同一 Cookie 容器访问入口；入口、SSO 回调和图书馆落地依次 302，最终 200。业务域观察到 `meta-opac.session` 和 `_zte_sid_`，未记录 Cookie 值。无业务会话时借阅列表返回 HTTP 401。
- 当前借阅页面从第 1 页开始，以 `page` 和 `pageSize=20` 请求 `GET /meta-local/opac/users/loans`，无请求正文。请求拦截器设置 `X-Hw-Lang`（本次取 `chi`）、`X-Hw-explorer: m` 和 `X-CSRF-TOKEN`；该值来自前端本地存储，缺失时为空。Direct 以空值请求列表得到 HTTP 200。
- 列表响应外层为 `code`（整数，成功 0）、`msg` 和 `data`；`data` 含 `currentPage`、`pageSize`、`total`、`totalPage`、`items`。条目观察到的字段包括 `title`、`author`、`bibAttrs`、`loanDate`、`dueDate`、`renewTimes`、`loanId`、`item.barCode`、`location`、`loanStatus`、`loanType`；条码位于嵌套 `item.barCode`，不使用顶层同名字段。字段类型、可空性和 `loanId` 的编码没有跨会话样本，Core 只接受字符串或非负整数标识，缺失视为协议异常。
- 公开脚本 `ReaderLendList` 还请求 `GET /meta-local/opac/users/loan_max_renew_times`，使用与列表相同的 `page/pageSize`，按列表的 `item.barCode` 匹配上限条目的顶层 `barCode`，并以 `maxRenewTimes - renewTimes` 展示可续借次数。该请求没有 Direct 会话样本，属于未真实验证的公开代码证据。
- 公开脚本的续借按钮收集选中记录的 `loanId`，构造 `{loanIds: [...], source: 1}` 并调用 `POST /meta-local/opac/users/batch_renew`；`source=2` 只用于前端检测到第三方 `openId` 的登录方式。页面随后重新读取列表。成功响应的 `data` 为空；拒绝映射以 `loanId` 为键携带失败原因。公开脚本与用户提供的脱敏页面反馈支持下述原因投影。

| 操作 | 引导与 service | 重定向及最终 URL | Cookie/Session 作用域 | 方法、精确参数 | 头与编码 | 加密/签名 | DTO/解析 | 缓存、并发、重试 | 错误与产品含义 |
|---|---|---|---|---|---|---|---|---|---|
| 借阅认证 | 入口为 `/meta-local/opac/cas/rosetta`；SSO 登录页的 `service` 必须恰好解码为该入口 | 入口 302 → SSO → 入口 `?ticket` → 入口 302 → 入口 200；只接受这四类落点 | 复用当前路线 SSO Cookie；图书馆 Cookie 只留在业务域 | 全部 GET，无正文 | 浏览器 HTML 导航；`Accept: text/html,*/*` | 无新增 | 入口路径 200 表示业务会话就绪；SSO 登录页 200 表示需要恢复 | 列表 401 时才引导一次；不跟随未知跳转；串行 | 认证缺失返回 `authentication_required`；其他落点为协议错误 |
| 借阅列表 | 借阅认证 | 精确 `GET /meta-local/opac/users/loans?page=N&pageSize=20` | 图书馆业务 Cookie（`meta-opac.session` 等） | 从 1 开始，每页 20；无正文 | `X-Hw-Lang: chi`、`X-Hw-explorer: m`、空 `X-CSRF-TOKEN`，JSON Accept | 无 | `code=0`；分页 `currentPage/pageSize/total/totalPage/items`；条目读取 `loanId/title/author/loanDate/dueDate/renewTimes/item.barCode/location/loanStatus`；条码缺失时只保留可续借次数未知 | 完整分页成功才返回；`total` 最多 10000；重复标识、页大小或总数矛盾报错；无离线缓存 | 401/403 触发一次认证；5xx 为上游不可用；结构异常为 `upstream_changed` |
| 续借条件 | 借阅认证 | 精确 `GET /meta-local/opac/users/loan_max_renew_times?page=N&pageSize=20` | 同列表 | 每页一次，无正文 | 同列表 | 无 | `code=0`、`data.items[]` 的 `barCode` 和非负整数 `maxRenewTimes`；可续借次数为 `maxRenewTimes - renewTimes`，负值按零 | 只在列表页有记录时读取；响应无有效条件数据或请求可重试超时时，在会话仍有效的情况下保留已读列表，可续借次数为未知 | 401/403 按认证失败；会话、取消、请求安全及来源校验错误终止读取；普通列表保留未知次数；准备和提交时，条件读取失败返回读取错误，次数未知或为零均不可续借 |
| 续借提交 | 借阅认证 | 精确 `POST /meta-local/opac/users/batch_renew` | 同列表；Core 在已锁定的 Direct 路线上复核会话、列表和续借上限 | JSON `{loanIds:[loanId],source:1}`，只提交当前借阅记录中的一个标识 | `Content-Type: application/json`，其余头同列表 | 无 | `code=0` 且 `data=null` 或空对象为成功；`code=0` 且失败映射包含目标 `loanId`，或 `code` 为非零整数时业务拒绝；非 200、正文不可解析、`code` 缺失或类型异常、失败映射没有当前目标均为结果未知 | 单次发送，不自动重试；同记录未确认意图冲突；记录消失、资格未知或用尽、基线变化、读取失败或会话变化均不发送 | 成功、确定拒绝、结果未知分别返回；确定拒绝只显示应用定义的固定提示，见下方白名单 |
| 续借核对 | 借阅认证 | 重新 `GET /meta-local/opac/users/loans?page=1&pageSize=20`，固定 intent 的 `resolvedRoute` | 同列表；不按当前 Auto 重新选路 | 同借阅列表 | 同列表 | 无 | 按同一 `loanId` 匹配，与 prepare 读到的记录比较；按 `YYYY-MM-DD` 或 `YYYY-MM-DD HH:MM:SS` 解析应还日期，只比较年月日。日期确实延后或 `renewTimes` 增加才确认已生效 | 成功和未知结果后自动核对一次；结果仍未知时拦截同一记录，只允许手动核对 | 日期延后或次数增加表示成功；两项均可比较且未变表示未生效。两种结论都解除拦截并关闭本次提示；其余情况保留待核对 |

Core 以 `current_library_loans()` 返回完整范围，以 `library_loans_on_route()` 在 intent 原路线执行写后核对，以 `preflight_library_loan_renew()` 只读复核目标，以 `library_loan_renew_if_route_matches()` 提交单本续借。Bridge 只投影公开记录标识、书名、作者、借还日期、续借次数、可续借次数、状态和馆藏地；续借写意图统一经过 prepare/commit、`outcome_unknown` 和原路线核对。Flutter 页面从「我的 → 待还图书」进入，复用 `library` 恢复目标，账号或路线变化后丢弃旧读取。图书馆明细不写本机业务缓存。

#### 2026-11-23 借阅路线验证

- **Direct：** 认证和 `library_loans` 列表读取通过，账号有 0 条在借。本次没有覆盖列表条目字段和续借条件；历史 Direct 列表样本与公开脚本依据见上表。
- **WebVPN：** 认证通过。经 WebVPN 包装的列表 GET 返回 HTTP 302，`Location` 指向未包装的 `https://space.lib.buaa.edu.cn/meta-local/opac/users/loans`，路径和查询键与原请求一致。响应体约 103 字节，是指向原站的短 `<a href>`。该站点未被代理；客户端不跟随这个跳转。
- **重跑条件：** 有在借记录的账号授权后，在 Direct 核对条目字段和续借上限关联。只读报告区分条目数与续借条件已知数。若 WebVPN 日后开始代理原站，再重新验证该路线。真实续借未执行，需另行授权具体图书、路线和时间。

#### 本次续借结果提示（2026-11-18）

学校公开脚本 `lend-e7733bf7.js` 的 `ReaderLendList.relendClick` 按当前选中记录的 `loanId` 匹配
`data` 中的键，将对应值作为该记录的失败原因。`mspace.js` 的 `$analyzeResponse` 在业务失败时以外层
`msg` 拒绝请求，在成功时只交付 `data`。续借调用未配置成功提示键，学校页面自行显示成功状态。
用户提供的学校页面反馈确认了未到续借窗口的真实业务提示，未提供原始响应、路线或通过文案。
两份冻结来源对该操作各协议列均不适用，原因投影未变更认证、请求、会话或重试行为。

Core 对 `code=0` 的响应只读取目标
`data[loanId]`，对非零整数码读取 `msg`。单本提交收到只有其他记录的失败映射时保留结果未知，按原路线只读核对。
拒绝原因白名单只有「尚未进入续借窗口」：去掉首尾空白后，只有完整匹配 `META-403060: 不允许续借,未达到到期前续借天数` 才显示「尚未进入续借窗口，请稍后再试」。业务含义来自上述页面反馈，字符串由脱敏 Bridge 测试覆盖。其他内容使用通用拒绝提示。学校原文不进入 Bridge 错误、日志、诊断、遥测或缓存。

#### 条码字段形状与固定路线核对（2026-11-18）

复核公开脚本 `ReaderLendList` 和 Direct 列表样本：列表条码只出现在 `item.barCode`，`getMaxLoanTimes` 也用
`e.item.barCode === t.barCode` 关联续借上限；续借上限响应条目则使用顶层 `barCode`。此前 Core 合成样本和
解析器把列表条码当成顶层 `barCode`，嵌套形状只能得到空的条码关联，无法计算可续借次数，已用尽的目标也可能
被当成“未知”而进入预检。

先增加的失败回归使用真实嵌套形状，预期 `canRenewTimes` 为可续借次数，实际得到 `None`；修复后只读取
`item.barCode`，顶层同名字段不构成资格证据，缺失时保持“次数未知”而不是 0。另一个回归用同一形状把
`maxRenewTimes` 设为已续借次数，要求预检返回输入错误且不发送 `batch_renew`。

同期将续借写后核对接回统一写入生命周期：Core 新增 `library_loans_on_route()`，Bridge 新增
`current_library_loans_on_route`；App 在校验原账号、原会话作用域和原记录标识后，只按
`WriteIntent.resolvedRoute` 读取并判断应还日期是否延后或续借次数是否增加。普通浏览和手动刷新仍走 `current_library_loans()`
的 Direct 路线；核对失败、路线不一致或记录不唯一保留未知，不重发写请求。显式 WebVPN 和固定 WebVPN 核对都在发出请求前被拒绝。

续借预检和写后核对均使用同一借阅列表记录的 `dueDate` 和 `renewTimes`。旧版冻结参考的 `LibBookApi.kt`、`LibBook.kt`、
`LocalLibBookApi.kt` 和 `LocalLibBookApiBackendTest.kt` 是座位预约协议。固定 buaa-api 的 `src/api/sso/auth.rs`、
`src/request.rs`、`src/store/{cookies,cred}.rs` 仅覆盖通用 SSO 与请求存储。对预检、续借提交和写后核对，上表各列均无适用的冻结业务协议。
本次以表中的 Direct 列表与公开脚本为依据。预检和核对均取得应还日期时才比较日期。
缺失 `code` 或类型异常的续借响应无法确认写入结果，按既有未知结果流程在原路线只读核对。

### 门户资料、账户指标与网费流量接入

本次提供 Core 与 CLI 在线只读查询。协议依据为用户提供的门户、网费 HAR 及本会话全新 Direct 会话验证。原始材料保留在私有本地目录，仓库只保存合成 Fixture 和脱敏说明。

#### 接入方案

| Core facade | CLI | 数据 |
|---|---|---|
| `portal_profile()` | `ubaa portal profile` | 身份、学院及取得时间 |
| `campus_metrics()` | `ubaa portal metrics` | 网费余额、校园卡余额、未读邮件数、待还图书数、云盘剩余空间，各项分别返回结果和时间 |
| `network_usage()` | `ubaa network usage` | 各网络产品的已用、免费剩余、计费剩余流量及时间 |

分别注册 `portal`、`network` 路线覆盖项，沿用 Direct/WebVPN/Auto 解析和路线会话隔离。Core 拥有业务引导、Cookie、重定向和解析，CLI 只调用 facade。业务读取复用 SSO，不再次提交密码。业务引导失败不认定整个账号已退出。

金额和容量采用十进制字符串，计数采用非负整数。已用流量和计费剩余保留原始单位。免费剩余合计产品免费额度与套餐可用流量，客户端汇总按 1024 进制换算，规则见下文。用户在本会话确认云盘指标表示剩余空间，公开字段为 `cloudStorageRemaining`。

门户资料独立于用户中心 `UserProfile` 和登录成功条件。单项失败不丢弃其他成功项，会话所有权冲突立即停止。公开结果不含内部 ID、跳转 URL、原始上游消息或认证材料。本阶段复用已有会话存储，业务快照缓存、Bridge 与 UI 后续单独接入。

#### 两个冻结来源的适用性

固定值以[冻结参考](../references.md)为准，本次为旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和示例 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

旧版已读取最近的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` 与 `model/dto/UserInfo.kt`：按路线隔离 Cookie，校验主机、路径、Secure 与过期时间，保留 SSO 表单字段并识别登录失败。示例已读取 `src/api/sso/auth.rs`、`src/api/user/auth.rs`、`src/context.rs`、`src/store/cookies.rs`、`src/store/cred.rs`、`src/error.rs`：共享 HTTP/Cookie、六字段 SSO 表单、用户中心独立引导及错误分类。示例的简化 Cookie 与原文日志不作为本次实现方式，继续使用现有 Core 的严格处理。

| 操作 | 旧版同源协议 | buaa-api 同源协议 | 实现依据 |
|---|---|---|---|
| 门户登录 | 不适用 | 不适用 | 门户 HAR 的 GET/302 链及实时成功 |
| 门户身份、学院 | 不适用，用户中心 DTO 无这两个字段 | 不适用 | info 响应和前端标签绑定 |
| 指标配置、网费余额 | 不适用 | 不适用 | items 与 `net.netFee` 详情 |
| 校园卡余额 | 不适用 | 不适用 | 专用响应及前端回退逻辑 |
| 未读邮件 | 不适用 | 不适用 | `mail.unread` 详情 |
| 待还图书 | 不适用，座位协议不属于借阅 | 不适用 | `book.bookNum` 详情 |
| 云盘剩余空间 | 不适用 | 不适用 | `wangPan.wangPan` 详情及用户确认 |
| 网费登录、流量 | 不适用 | 不适用 | 网费 HAR、`/home` HTML 与实时成功 |

两个冻结来源没有本次业务实现，不能借用其业务 URL、字段、加密或错误码。业务请求无额外加密或签名常量，认证继续使用现有 Core SSO。业务 Cookie 的后端有效期和门户后端刷新周期未知。

#### 逐操作协议

表中门户属于 `https://it.buaa.edu.cn`，网费属于 `https://zfw.buaa.edu.cn`。JSON 的 `e=0` 表示已证明的成功，原始 `m` 不公开。

| 操作 | 引导与 service | 重定向及最终 URL | Cookie/Session 作用域 | 方法、精确参数 | 头与编码 | 加密/签名 | DTO/解析 | 缓存、并发、重试 | 错误与产品含义 |
|---|---|---|---|---|---|---|---|---|---|
| 门户登录 | `/manage/common/login/index?redirect=<home>`；home=`https://it.buaa.edu.cn/home/`；SSO service 为 `/manage/common/cas_login/30001?redirect=<home>` 的完整门户 URL | GET → 门户回调入口 `to_bind=0&redirect=<home>` → SSO `/login?service=…` → 原门户回调带 ticket → `/home/` | 门户 `SESS_ID`、`CK_LC`、`CK_VL`；SSO Cookie 按域发送 | 全部 GET，不提交密码 | HTML 导航、正常 TLS | 无新增 | home 与 info 成功共同确认业务登录 | 至多一次引导；串行；无网络自动重放 | SSO 登录 HTML 表示业务认证不可用，HTTP 200 不等于成功 |
| 身份、学院 | 门户登录 | 精确 `/personal/frontend/data/info` | 门户 jar | GET，无参数 | JSON Accept、XHR、Referer home | 无 | `d.info.identity`、`d.info.depart` 非空字符串 | 每次在线读取 | `e=10013` 可触发一次引导；缺字段为协议错误 |
| 指标配置 | 门户登录 | 精确 `/personal/frontend/data/items` | 门户 jar | GET，`type=personal_data` | 同门户 JSON | 无 | `d.data[]`，固定 key 对应 opaque id | 每次重新取配置，ID 不跨账号缓存 | 缺 key、重复 key 使对应指标失败；详情所需 id 无效只影响该详情查询 |
| 网费余额 | 门户登录 | 精确 `/personal/frontend/data/detail` | 门户 jar | GET，`id=<net.netFee配置id>` | 同门户 JSON | 无 | `d.data.value` 数字或数字字符串；保留 unit | 五项串行，分别记录时间 | 有效零值保留；缺失、负值、布尔值、非数字为错误 |
| 校园卡余额 | 门户登录 | `/buaa/frontend/card/balance`；失败回退详情路径 | 门户 jar | GET，专用无参数；回退 `id=<card.balance配置id>` | 同门户 JSON | 无 | 专用 `d.value`，回退 `d.data.value` | 专用失败后按前端行为回退一次，会话冲突除外 | 失败不写成零余额 |
| 未读邮件 | 门户登录 | 精确详情路径 | 门户 jar | GET，`id=<mail.unread配置id>` | 同门户 JSON | 无 | `d.data.value` 整数或整数字符串 | 同网费余额 | 仅数量，不推断邮件内容 |
| 待还图书 | 门户登录 | 精确详情路径 | 门户 jar | GET，`id=<book.bookNum配置id>` | 同门户 JSON | 无 | `d.data.value` 整数或整数字符串 | 同网费余额 | 仅数量，不推断到期日或续借能力 |
| 云盘剩余空间 | 门户登录 | 精确详情路径 | 门户 jar | GET，`id=<wangPan.wangPan配置id>` | 同门户 JSON | 无 | `d.data.value` 数字字符串、unit=G；排除 account 等额外字段 | 同网费余额 | 表示剩余空间，不补造总容量或已用量 |
| 网费登录 | `/sso/cas/index`；SSO service 为其完整网费 URL | GET → SSO → 原入口带 ticket → `/pay/card` | 网费 `PHPSESSID_8800`、`__services_identity`、`_csrf-8800`；jar 按作用域发送 | 全部 GET | HTML 导航 | 无新增 | 精确落点后 GET `/home` | 优先直接读 home；登录重定向可触发一次引导 | 充值页仅为落点，不提交充值、验证码或设置 |
| 网费流量 | 网费登录 | 精确 `/home` | 网费 jar，无 Bearer | GET，无参数 | HTML 导航 | 无 | 唯一表格包含“已用流量”“免费流量剩余(不含套餐)”“计费流量剩余(不含套餐)”；通过表头 data-col-seq 对应单元格，每产品一行 | 不猜 JSON API，不按固定列顺序解析 | 缺失、重复或畸形表头/数值拒绝解析，保留原始单位 |

引导限制 HTTPS 默认端口、精确业务路径、SSO service 和有限跳数。WebVPN 使用现有编解码，仅在 WebVPN 路线接受合法网关包装。嵌套 service 和 redirect 同样校验，拒绝外域、用户信息、错误 ticket 目标及未证明的最终页面。

#### 验证与交付

先运行失败 Fixture/请求测试，再实施最小修复。覆盖混合数字类型、零值、单项失败、校园卡回退、动态 ID、HTML 列重排和多产品、Cookie 隔离、嵌套跳转、登录 HTML、会话代次，以及 CLI JSON/人类输出与二进制入口。

完成 Core/CLI 聚焦回归后，按[开发命令](../../development/commands.md#来源对照与真实验证)执行完整确定性检查与 Direct/WebVPN 真实只读验证，在[当前状态](../../project/status.md)记录实际结果。Python 成功不替代 Rust Core/CLI 成功，个人数据和原始响应不进入共享文档。


验收结果：初始解析测试有 4 项失败，CLI 命令测试因未注册 `portal` 失败；实现后新增 14 项 Core 专项测试、路线配置回读、CLI 数据/中文输出/Schema 反例及二进制缺会话测试通过。Direct 与 WebVPN 各完成三个公开查询，五项指标分别成功，网络业务会话重开后复用成功。完整检查的实际结果见当前状态，真实数值及认证材料均未写入本记录。

## 专项记录

### 财务错误诊断（2026-11-17）

重新核对冻结旧版的本地 API 目录和 `LocalConnectionAuth.kt`，以及固定 buaa-api 的 API 目录、`api/sso/auth.rs`、`request.rs` 和 `error.rs`。两个来源均无财务门户、查询系统登录、收入读取和分页的同源协议，这四项业务的九列对照仍不适用；当前协议采用本页既有财务证据。

| 操作 | CAS 与 service | 重定向与最终 URL | 会话作用域 | 方法与参数 | 请求头与编码 | 加密签名 | DTO 与解析 | 缓存并发重试 | 错误语义 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 门户认证与票据跳转 | 沿原 CAS service | 沿原主机和路径检查 | 原路线 Cookie | 原 GET | 原请求头 | 无新增 | 原票据字段 | 原登录锁 | 记录具体拒绝位置与跳转原因 |
| 查询系统登录 | 沿原引导 | 原登录终点 | 原路线 Token | 原四个表单字段 | 原表单与 Referer | 无新增 | 原 code/data/token | 原认证恢复 | 记录登录状态、包络与 Token 缺失 |
| 收入读取与分页 | 无新增 | 原查询终点 | 原 Bearer Token | 原 userId/currentPage/limit | 原 JSON | 无新增 | 原字段、金额与分页规则 | 原完整成功后替换缓存、最多一次认证恢复 | 记录 HTTP、包络、字段和分页失败，不改变错误码及重试许可 |

诊断只保留固定步骤、原因、响应类型和长度，不保留字段值。此项工程验证不请求学校服务；Direct 与 WebVPN 的真实账号验证分别待授权后执行。


### 流量表内嵌套餐明细（2026-11-14）

旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 均无网费流量的同源实现，本操作在两个冻结来源中仍不适用。用户提供的 Android Direct 诊断报告包含 `/home` 原始 HTML：产品行的第 13 列内嵌套餐表，套餐表复用 `data-col-seq="1"`、`"2"`、`"3"`，其中第 3 列表示有效期。产品的流量字段符合既有格式，原解析器继续遍历套餐行后，将有效期 `0天` 当作已用流量并返回 `upstream_changed`。

表头和产品行以最近的祖先 `table` 确定归属，只解析当前流量表的内容。CAS/service、重定向和最终 URL、Cookie 作用域、HTTP 方法及参数、请求头和编码、加密、DTO、缓存、并发、重试及错误分类继续采用上面的逐操作协议。套餐明细不进入流量产品列表，真实流量单元格仍按现有数值规则解析。合成夹具 `fixtures/readonly/campus/network_packages.html` 保留套餐表结构和列编号，回归用例覆盖套餐有效期与流量字段的隔离。

免费剩余包含套餐可用流量。真实 HTML 中，套餐表通过“套餐名称”和“统计”表头识别，统计单元格的按钮分别显示“总流量：…”和“可用流量：…”。每个产品只合计自己内嵌套餐表中的“可用流量”，不把套餐总量或百分比相加，也不根据含义未确认的有效期 `0天` 排除学校仍列有可用流量的套餐。两个冻结来源对此操作仍不适用；业务请求的九列协议沿用上表，仅扩展 DTO 的免费剩余计算语义。

汇总采用客户端显示约定 `1G=1024M`、`1M=1024K`、`1K=1024byte`，不将其作为上游计费基数的证明。结果选择参与汇总的最大单位，保留最多六位小数；无套餐时保留产品原值和单位。在线结果的 `remainingExcludesPackages=false` 表示免费剩余已包含套餐可用量，计费剩余仍取产品表原值。旧缓存的 `true` 保留原含义，在线刷新后替换。

### 财务收入查询（2026-11-08）

冻结来源为旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。两者没有财务业务接口，财务门户、票据交换、收入字段和分页均不适用。通用 SSO 参考旧版 `LocalConnectionAuth.kt` 的 `LocalCasParser`、路线 Cookie 存储及认证测试，以及 buaa-api `src/api/sso/auth.rs`、`src/store/cred.rs` 的表单与凭据作用域。财务补充来源为 [Auto-BUAA-icw 固定源码](https://github.com/CoolwindHF/Auto-BUAA-icw/blob/dca5fcacc57136b906f4ff1140b3c6df276a40f1/main.py)。真实材料仅保存在忽略目录 `.ubaa_local/finance_integration/`。

| 操作 | 引导、跳转与会话 | 方法、参数、编码与签名 | 数据、并发、错误与产品语义 |
|---|---|---|---|
| 财务门户认证 | CAS service 为 `http://icw.buaa.edu.cn/checkbuaa.aspx`；Direct 实测 HTTP 回调 302 到同路径 HTTPS，再到 `/Newindex.aspx`。WebVPN 实测返回网关相对路径，必须以实际响应 URL 解析相对 Location，再解包验证上游。复用路线内 SSO Cookie。 | SSO 使用既有表单认证；门户跳转为 GET，无新增加密常量。 | 登录页需交给既有认证恢复，业务模块不保存密码。门户非成功终点不能当作成功。 |
| 查询系统登录 | GET `https://icw.buaa.edu.cn/jump.aspx?sysid=wscx`；实测 302 到 `https://chaxun.icw.buaa.edu.cn/gxzhcxzhb/login`，查询参数包含 `Userid/Cypt/Stamp`。 | POST `/api-zhcx/login`，表单 `username=Userid,password=Cypt,yzm=yzm,stamp=Stamp`，Referer 为跳转目标。 | `code=200`、`data.token`；票据只用于本次交换，Token 只存当前路线内存。并发复用现有 CredentialState，退出使迟到结果失效。 |
| 学生收入 | `https://chaxun.icw.buaa.edu.cn/api-zhcx/getStudentSRCX`，Bearer Token，仅查询当前登录账号。 | POST JSON `userId,currentPage,limit`，从第 1 页开始。参考默认 limit=100，Direct 实测 limit=2 可连续翻页至完整终页。 | 当前为 `code=200,data.mx,data.total`；旧 `data.data/count` 仅作为固定补充源码明确支持的另一结构。未知结构报错。金额为数值、最多两位小数，映射整数分；税率和缺失字段保留原语义。只投影流水号、发放项目、摘要、部门名称、项目编号、项目名称、金额、税额、实发、税率、日期、年月，排除证件和银行字段。 |
| 本地缓存 | 同账号跨路线共用业务结果，认证材料按路线隔离。 | 无额外学校请求，复用现有加密仓库与读取票据。 | 所有分页完整成功才替换缓存；失败保留旧结果。记录表示财务录入，不推断银行到账。查询返回范围不额外声明全部历史。 |

参考脚本每轮重新登录、明文配置及状态文件、SMTP 通知不纳入本功能。Direct/WebVPN 的生产入口验收分别记录，探针观察不代替生产验收。

2026-11-12 对照上述两个固定版本及财务补充来源：旧版与 buaa-api 仍无这三个财务操作；buaa-api 的 `src/api/sso/auth.rs` 独立激活 WebVPN，财务补充脚本仅走 Direct。无网关会话的只读探测确认：WebVPN 下门户 `jump.aspx`、查询登录与收入读取都返回 HTTP 302，`Location` 为 `https://d.buaa.edu.cn/login`。该已知落点是网关要求认证；不跟随该跳转，也不改变其它未知跳转的协议错误语义。Direct 及三个财务操作的业务 URL、请求方法和字段、请求头、会话作用域、加密、DTO、分页与缓存继续采用上表合同。GUI 在认证失败时走现有财务路线恢复，按账号与自动登录许可重读一次。

修复后 Core-live 的 WebVPN 新会话登录与收入读取通过；会话失效后的错误分类和 GUI 重试由合成测试验证。真实 Direct 未运行（本次授权只含 WebVPN）；安卓切换网络仍需在安装本修复的设备上复测。

#### 财务收入展示字段（PR #151）

- **DTO 与解析。** `getStudentSRCX` 响应的 `data.mx` 数组中，每条收入记录可包含 `data.mx[].bmmc`（部门名称）、`data.mx[].xmbh`（项目编号）和 `data.mx[].xmmc`（项目名称）。三个字段均预期为字符串，取值时去掉首尾空白。空字符串、纯空白、缺键、`null` 和非字符串值均按缺失处理。`ffxmmc` 继续表示发放项目。`bmbh`、`bmhb`、`xmhb`、`sfzh`、`yhzh`、`yhzh_` 不进入 DTO。
- **错误与产品语义。** 新字段仅用于展示，缺失或类型不符不会导致收入行或整次读取失败。原有字段的校验、错误分类、退出语义和金额含义保持不变。收入记录不表示银行到账。
- **其余对照项。** 实现仅追加收入行解析和公开投影。CAS 引导与 service、重定向与最终 URL、Cookie／Session／Token 作用域、HTTP 方法与参数、请求头与正文编码、加密与签名，以及缓存、并发与重试均沿用上表及 2026-11-12 记录。查询与分页调用链不变，完整读取后才替换缓存。两个冻结来源仍无财务业务接口。
- **真实验证。** 字段依据为贡献者在 PR #151 提供的脱敏真实响应。维护者可用的测试账号没有财务系统权限，本次合入未做路线验证。获得有财务权限的账号授权后，可任选 Direct 或 WebVPN 路线读取财务收入，核对三个字段在响应中的路径与类型。

## GUI 按需恢复（2026-11-12）

重新核对冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LocalConnectionAuth.kt` 中路线 Cookie、会话核验和业务认证失败处理，以及固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/sso/auth.rs`、`request.rs`、`store/{cookies,cred}.rs`。两源没有门户资料、余额或流量的同源业务协议，其业务字段仍不适用。业务协议九列继续采用本页逐操作表，通用认证九列采用[认证对照](auth-session.md)。

GUI 的身份和余额使用 `portal` 恢复目标，流量使用 `network`。只在读取明确要求认证时，核验 Core 返回的实际路线，并由现有恢复服务读取同账号且允许自动登录的材料。恢复后最多再读一次。网络、解析及普通权限错误不提交密码。CAS/service、重定向、Cookie/Token、HTTP 方法和精确参数、请求头和编码、加密常量、DTO 均沿用既有实现。并发消费者共享所需路线的认证，账号和路线变化使旧请求失效。最终读取失败进入本机脱敏诊断。余额逐项失败保留错误码和实际路线，认证失败同样进入一次恢复；恢复失败时保留其他已成功的指标。共享身份重绑开始前撤销旧本地提示读取，完成后重新读取提示。

本次只改变 GUI 恢复和诊断接线，没有新增学校协议。真实 Direct/WebVPN 验证需要当前会话明确的功能及路线授权；本次未执行学校请求。
