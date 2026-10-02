# 研讨室订单详情身份校验

日期：2026-10-03。生产 macOS App 使用 WebVPN，从实际订单列表进入详情后显示编号0、状态未知；私有桌面证据 `desktop-165`、`desktop-166`。这只能证明当前返回投影缺少目标身份，不能据此推断新的上游字段或接口。

## 双来源对照

冻结版本沿用 `references.md`：旧版 `1f4b8f84`，示例 `a63712fa`。旧版接口 `shared/.../api/feature/CgyyApi.kt`、实现 `api/local/LocalCgyyApi.kt:194,359,620`、DTO `model/dto/Cgyy.kt`、测试 `LocalCgyyApiBackendTest.kt:464` 已核对。示例 `src/api.rs` 及各 API 模块没有同协议研讨室实现；其 CAS、加密和错误不能借用。

| 操作 | CAS/bootstrap/service | 重定向/final URL | Cookie/会话 | 方法/精确参数 | headers/body | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 订单详情 | 沿用现有 Cgyy `sso/manageLogin`、业务 `/api/login`；不改 service | 沿用已记录 Cgyy 认证跳转与 WebVPN 转换；不新增 URL | 当前账号、固定 WebVPN、业务令牌作用域不改 | GET `/api/orders/{id}`，原 `nocache`；不改请求 | 原 Accept/Referer/app-key/timestamp/sign/cgAuthorization；无 body | 原签名常量及字段排序不改 | 旧版从 `data` 映射 `CgyyOrderDto`，缺失/null 转空对象、缺 id 默认0；当前低层 parser 相同 | 不用列表资料拼装缺失详情，不扩缓存、不重试提交 | 旧版可产生编号0的伪详情；当前读取出口应拒绝缺失/非正/不同的返回 id，报 `upstream_changed`，CLI 沿用对应退出码 |

## 决策与验证

保留冻结旧版请求、DTO和低层空值兼容规则；在只读详情操作的出口要求响应身份等于所请求订单。依据是本次真实页面缺失身份以及既有 facade 正数输入/唯一目标合同，不猜测字段，也不把列表摘要冒充成功详情。响应缺失时显示现有可恢复错误，返回仍保留父列表。只校验详情，不把合法空订单列表当错误。

新增 Mock 覆盖 `data:null`、缺 `data`、空对象、零/负/错目标 id 和正确身份，断言没有取消请求。先运行RED，修复后GREEN；日志保存在仓库外私有目录。当前实际账号的上游完整详情是否可恢复仍需 WebVPN 重验，不能用该修复宣称上游恢复。

## 实时结构裁决（同日补充）

仓库外只读结构探针通过 facade 注入传输，保留 TLS 验证、Core 重定向/Cookie/签名，只接受 GET 和业务认证 POST；输出字段名、类型及相等性，不输出原始值。两笔列表记录独立得到 HTTP200/code200，`data` 包含 `orderInfo`、`venueInfoBean`、`orderDetailList`、`orderBuddyList`、`checkLogList`。`orderInfo` 无 `id`，也没有任何值等于请求数字编号；其 tradeNo/venueSiteId/reservationDate/theme/orderStatus 分别与对应列表记录相等。证据 `cgyy-shape4.log`。

这份实时证据取代旧版对详情平铺结构的假设：只读详情接受已观察的 `orderInfo` 包装，读取既有同名字段；场馆名称、校区和站点从 `venueInfoBean` 同名字段补足。无回传编号时，结果身份绑定本次请求的正数编号（不是把其他字段猜作编号），交易号、站点和状态必须实际存在；空包装仍报错。若响应明确带有不同 id 则拒绝。此包装不授予任何取消资格，`cancel_target`/`cancelled_target` 均为空，取消动作仍走原始 fresh authority 校验。原平铺结构继续要求 id 匹配。真实上游返回内容不能落入 fixture，新增测试全部使用合成值。

修复完成：身份缺失RED为1失败/1通过；包装支持RED为1失败/3通过；研讨室聚焦39项通过。`just check-sensitive`、`just check`（含CLI端到端）退出0；WebVPN研讨室专项9个步骤全部通过，包含实际订单详情；用途仍为static_fallback、锁码仍为空。生产macOS重建后 `desktop-274` 实际显示所选历史订单的场馆、时段、主题及状态，编号0问题已消除；学校业务写入0。日志前缀 `order-wrapper-*` 均在仓库外私有证据目录。图书馆Space/map阻塞与本修复无关，继续保留。
