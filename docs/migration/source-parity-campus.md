# 门户资料、账户指标与网费流量接入

本次提供 Core 与 CLI 在线只读查询。协议依据为用户提供的门户、网费 HAR 及本会话全新 Direct 会话验证。原始材料保留在私有本地目录，仓库只保存合成 Fixture 和脱敏说明。

## 接入方案

| Core facade | CLI | 数据 |
|---|---|---|
| `portal_profile()` | `ubaa portal profile` | 身份、学院及取得时间 |
| `campus_metrics()` | `ubaa portal metrics` | 网费余额、校园卡余额、未读邮件数、待还图书数、云盘剩余空间，各项分别返回结果和时间 |
| `network_usage()` | `ubaa network usage` | 各网络产品的已用、免费剩余、计费剩余流量及时间 |

分别注册 `portal`、`network` 路线覆盖项，沿用 Direct/WebVPN/Auto 解析和路线会话隔离。Core 拥有业务引导、Cookie、重定向和解析，CLI 只调用 facade。业务读取复用 SSO，不再次提交密码。业务引导失败不认定整个账号已退出。

金额和容量采用十进制字符串，计数采用非负整数。流量保留原始单位，不推断 G 的字节基数。两项剩余流量明确不含套餐，不合成总剩余量。用户在本会话确认云盘指标表示剩余空间，公开字段为 `cloudStorageRemaining`。

门户资料独立于用户中心 `UserProfile` 和登录成功条件。单项失败不丢弃其他成功项，会话所有权冲突立即停止。公开结果不含内部 ID、跳转 URL、原始上游消息或认证材料。本阶段复用已有会话存储，业务快照缓存、Bridge 与 UI 后续单独接入。

## 两个冻结来源的适用性

固定值以[冻结参考](references.md)为准，本次为旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和示例 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

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

## 逐操作协议

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

## 验证与交付

先运行失败 Fixture/请求测试，再实施最小修复。覆盖混合数字类型、零值、单项失败、校园卡回退、动态 ID、HTML 列重排和多产品、Cookie 隔离、嵌套跳转、登录 HTML、会话代次，以及 CLI JSON/人类输出与二进制入口。

完成 Core/CLI 聚焦回归后，按[开发命令](../development/commands.md#来源对照与真实验证)执行完整确定性检查与 Direct/WebVPN 真实只读验证，在[当前状态](status.md)记录实际结果。Python 成功不替代 Rust Core/CLI 成功，个人数据和原始响应不进入共享文档。


验收结果：初始解析测试有 4 项失败，CLI 命令测试因未注册 `portal` 失败；实现后新增 14 项 Core 专项测试、路线配置回读、CLI 数据/中文输出/Schema 反例及二进制缺会话测试通过。Direct 与 WebVPN 各完成三个公开查询，五项指标分别成功，网络业务会话重开后复用成功。完整检查的实际结果见当前状态，真实数值及认证材料均未写入本记录。
