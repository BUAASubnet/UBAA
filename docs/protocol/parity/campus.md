# 门户资料、账户指标、网费流量与财务

本文件收录门户资料、账户指标、网费流量与财务收入查询的来源对照。

## 当前规则

### 门户资料、账户指标与网费流量

身份、学院、五项账户指标和三项流量的接入方案、双来源适用性及逐操作协议见[校园账户查询](#门户资料账户指标与网费流量接入)。云盘指标按用户确认表示剩余空间。

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

完成 Core/CLI 聚焦回归后，按[开发命令](../../development/commands.md#来源对照与真实验证)执行完整确定性检查与 Direct/WebVPN 真实只读验证，在[当前状态](../../project/status.md)记录实际结果。Python 成功不替代 Rust Core/CLI 成功，个人数据和原始响应不进入共享文档。


验收结果：初始解析测试有 4 项失败，CLI 命令测试因未注册 `portal` 失败；实现后新增 14 项 Core 专项测试、路线配置回读、CLI 数据/中文输出/Schema 反例及二进制缺会话测试通过。Direct 与 WebVPN 各完成三个公开查询，五项指标分别成功，网络业务会话重开后复用成功。完整检查的实际结果见当前状态，真实数值及认证材料均未写入本记录。

## 专项记录

### 校园卡充值（2026-11-18）

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 都没有校园卡掌上服务大厅、openid、充值下单或航财通收银台的同源协议；九列均不借用。

协议依据为用户提供的抓包与本会话实测，原始材料只保存在忽略目录。

| 操作 | 引导与 service | 重定向及最终 URL | Cookie/Session 作用域 | 方法、精确参数 | 头与编码 | 加密/签名 | DTO/解析 | 缓存、并发、重试 | 错误与产品含义 |
|---|---|---|---|---|---|---|---|---|---|
| 卡站点 openid | SSO `/login?service=https://m.icw.buaa.edu.cn/card/home/sisUstbMiniReturnPage/112233/6/auth` | 已登录 SSO 直接 302 出带 `ticket` 的回调；回调 302 到 `/card/goIndex?openid=…&usertype=6` | 卡站点自身 `JSESSIONID`；SSO Cookie 按域发送 | 全部 GET | HTML 导航、正常 TLS | 无新增 | 仅取 `openid`，要求 64–128 位大写十六进制 | 路线内存复用；单飞；随路线状态清理 | 落到 SSO 登录页表示需重新认证；其余偏离视为协议变化 |
| 卡信息 | 同上 | 精确 `POST /card/cardpay/openCardPay` | 卡站点 jar | JSON `{"datajson":信封}`，正文 `openid` | `content-type: application/json`、`x-requested-with`、`session-type: uniapp`、`isWechatApp`、`orgid=2`、Referer `/card/` | AES-128-ECB/PKCS7 + 16 位密钥置换前缀 | `data.cardPay.idserial`、`cardbal` | 每次在线读取 | `success=false` 为业务拒绝；缺失字段为协议错误 |
| 充值下单 | 同上 | 精确 `POST /card/recharge/rechargeByHct?openid=…` | 卡站点 jar | JSON 信封：`idserial`、`txamt`（分）、`payway`（空）、`openid`、`payWay=10`、`tradetype=WAP`、`usertype=1`、`orgid=2` | 同上 | 同上 | `success=true` 时读取顶层 `resultData.orderno` 和 `resultData.mweb_url`，不读取 `data` | 非幂等，至多一次；结果未知不重试 | 金额限 1–100000 分；地址必须为 HTTPS 且主机精确匹配收银台，不含用户信息或非默认端口 |
| 航财通收银台 | 使用下单响应中经 Core 校验的 `mweb_url`；页面需要登录时按原站链路进入 `pass.cc-pay.cn` 和学校 SSO | 从 `https://cashier.cc-pay.cn/cashier?id=<orderno>` 在应用内打开；Android 使用应用管理的轻量浏览器 | 使用浏览器自己的会话，不复制 Core 的 Cookie；Android 普通 SSO 表单见下节 | 宿主不直接请求渠道列表、锁定渠道或提交支付表单 | 正常 HTTPS 导航，保留系统安全警告 | 应用不处理支付签名 | Core 核对商户主机、路径和订单号；不提取最终支付地址 | 打开失败可重开同一订单，不重复下单 | 支付方式及付款确认由用户操作；不支持内嵌浏览器时不开始下单 |

`usertype` 有两处语义：回调路径段固定 `6`（企业微信容器），下单体实测为 `1`（普通浏览器 WebView），两者不可互换。

收银台行为依据为既有航财通前端和手工抓包。历史候选曾由 Core 选择 `alipay_web`、提交已签名的 `payWebForm` 并直接交付支付宝 H5；用户报告直接打开时出现钓鱼风险提示，现改为原始商户页面内的用户操作，不绕过或压制系统警告。两份冻结来源对展开的收银台协议均不适用；现行版本不在原生 Core 复刻这些支付操作。生产 Core 的 Direct/WebVPN 实测仍需分别授权。

用户报告 Android 通用内嵌打开方式不能处理收银台发出的 `alipays://`。应用内轻量浏览器只从可信的 HTTPS 航财通或支付宝页面接收该协议，用户确认后将原地址交给支付宝 Android 包 `com.eg.android.AlipayGphone`。不构造支付 URL，不接受 `intent://` 等其他自定义协议，不关闭 WebView 的 TLS 或安全浏览保护。没有新增业务端点或请求；两份冻结来源也没有同源浏览器交付实现。

#### Android 收银台 SSO 对照（2026-11-19）

核对同一冻结提交的旧版 `LocalConnectionAuth.kt`、`LocalLibBookApi.kt` 和固定 buaa-api `api/sso/auth.rs`、`request.rs`、`store/{cookies,cred}.rs`。普通登录的共同事实是 GET SSO 页面取得当前 `execution`，使用同一客户端 Cookie 和 URL 表单提交凭据。旧版的通用登录默认激活 UC，库预约另有独立的 CAS service；buaa-api 通用登录和 VPN 登录只为各自固定的落地页校验结果。两份来源均无航财通回调及嵌入式浏览器登录交付；不借用其业务端点、密码风险处理、Cookie 保存策略或 TLS 配置。

| 操作 | CAS 与 service | 重定向与最终 URL | 会话作用域 | 方法与参数 | 请求头与编码 | 加密签名 | DTO 与解析 | 缓存并发重试 | 错误语义 |
|---|---|---|---|---|---|---|---|---|---|
| 航财通认证入口 | 原订单返回路径是 `backUrl`；实际 CAS service 是 `https://pass.cc-pay.cn/login`，不是订单页 | 原订单进入航财通登录页，选 `BUAASSO` 后 302 到 SSO，成功票据回到 pass，再回原订单 | 商户保留自己的浏览器会话；不复制 Core Cookie | 抓包见 `GET https://pass.cc-pay.cn/login`，参数 `backUrl` 为原订单地址，`channel=BUAASSO` | 浏览器 HTTPS 导航 | 无新增 | 只识别当前订单对应的回跳目标 | 不重下单、不自动付款 | 登录失败仍可走原页面，不把收银台登录当作付款成功 |
| 普通 SSO 表单 | 仅 HTTPS `sso.buaa.edu.cn/login`，唯一 `service` 为上述 pass 回调 | 证据中登录提交后由 SSO 重定向到 pass 的 `/login?ticket=…`；商户自行消费票据 | 登录挑战及 Cookie 留在同一 WebView；一般恢复仍使用 Core 当前路线 | 真实浏览器证据为 `GET /login?service=…` 后 `POST` 同一 service 下的登录；六个普通字段沿两份冻结来源 | `application/x-www-form-urlencoded`、正常 TLS | 无额外密码加密或支付签名 | 只识别普通登录表单和本次 `execution`；丢弃额外字段，不猜交互挑战 | 一次自动尝试，不重试凭据、不导出或重放票据 | 仅当前账号明确启用的自动登录凭据可用；验证码、额外验证、风险提示或失败保留给原页面处理 |

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
| 学生收入 | `https://chaxun.icw.buaa.edu.cn/api-zhcx/getStudentSRCX`，Bearer Token，仅查询当前登录账号。 | POST JSON `userId,currentPage,limit`，从第 1 页开始。参考默认 limit=100，Direct 实测 limit=2 可连续翻页至完整终页。 | 当前为 `code=200,data.mx,data.total`；旧 `data.data/count` 仅作为固定补充源码明确支持的另一结构。未知结构报错。金额为数值、最多两位小数，映射整数分；税率和缺失字段保留原语义。只投影流水号、项目、摘要、金额、税额、实发、税率、日期、年月，排除证件和银行字段。 |
| 本地缓存 | 同账号跨路线共用业务结果，认证材料按路线隔离。 | 无额外学校请求，复用现有加密仓库与读取票据。 | 所有分页完整成功才替换缓存；失败保留旧结果。记录表示财务录入，不推断银行到账。查询返回范围不额外声明全部历史。 |

参考脚本每轮重新登录、明文配置及状态文件、SMTP 通知不纳入本功能。Direct/WebVPN 的生产入口验收分别记录，探针观察不代替生产验收。

2026-11-12 对照上述两个固定版本及财务补充来源：旧版与 buaa-api 仍无这三个财务操作；buaa-api 的 `src/api/sso/auth.rs` 独立激活 WebVPN，财务补充脚本仅走 Direct。无网关会话的只读探测确认：WebVPN 下门户 `jump.aspx`、查询登录与收入读取都返回 HTTP 302，`Location` 为 `https://d.buaa.edu.cn/login`。该已知落点是网关要求认证；不跟随该跳转，也不改变其它未知跳转的协议错误语义。Direct 及三个财务操作的业务 URL、请求方法和字段、请求头、会话作用域、加密、DTO、分页与缓存继续采用上表合同。GUI 在认证失败时走现有财务路线恢复，按账号与自动登录许可重读一次。

修复后 Core-live 的 WebVPN 新会话登录与收入读取通过；会话失效后的错误分类和 GUI 重试由合成测试验证。真实 Direct 未运行（本次授权只含 WebVPN）；安卓切换网络仍需在安装本修复的设备上复测。

## GUI 按需恢复（2026-11-12）

重新核对冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LocalConnectionAuth.kt` 中路线 Cookie、会话核验和业务认证失败处理，以及固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/sso/auth.rs`、`request.rs`、`store/{cookies,cred}.rs`。两源没有门户资料、余额或流量的同源业务协议，其业务字段仍不适用。业务协议九列继续采用本页逐操作表，通用认证九列采用[认证对照](auth-session.md)。

GUI 的身份和余额使用 `portal` 恢复目标，流量使用 `network`。只在读取明确要求认证时，核验 Core 返回的实际路线，并由现有恢复服务读取同账号且允许自动登录的材料。恢复后最多再读一次。网络、解析及普通权限错误不提交密码。CAS/service、重定向、Cookie/Token、HTTP 方法和精确参数、请求头和编码、加密常量、DTO 均沿用既有实现。并发消费者共享所需路线的认证，账号和路线变化使旧请求失效。最终读取失败进入本机脱敏诊断。余额逐项失败保留错误码和实际路线，认证失败同样进入一次恢复；恢复失败时保留其他已成功的指标。共享身份重绑开始前撤销旧本地提示读取，完成后重新读取提示。

本次只改变 GUI 恢复和诊断接线，没有新增学校协议。真实 Direct/WebVPN 验证需要当前会话明确的功能及路线授权；本次未执行学校请求。
