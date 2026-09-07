# P4-A 用户资料白名单最小来源记录

2026-09-08，仅静态核对；未读取真实资料/凭据，未运行测试或 native。仓库路径基于 `/Users/moorefoss/Code/UBAA`。冻结 old=`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`；examples=`efb7976bf513f38364b88aeb83d704586cff9b2a`。

本批只把**现有同次 userInfo 返回**的 schoolId/email/phone/idCardTypeName 继续投影到 App，本地资料详情使用这些字段；不新增网络请求、接口、Bridge字段、证件号码或证件类型代码。联系人默认遮罩，用户主动显示；关闭详情或账号变化清除显示状态及旧资料引用，不持久化显示偏好。

| 来源层 | 准确位置 | 事实/决定 |
|---|---|---|
| 冻结 API | `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/AuthApi.kt:63`、`:273` | getUserInfo返回UserInfo，API委托当前backend，不是另一个校园业务资料接口。 |
| 冻结 DTO | `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/UserInfo.kt:18` | schoolid/name/username/email/phone/idCardTypeName均nullable String；旧DTO另含idCardType/idCardNumber，本批不采用这两个字段。 |
| 冻结本地实现 | `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt:761` | GET uc/api/uc/userinfo，无参数；code=0且data存在返回资料，401/SSO HTML清理本地会话，其他错误保持user_info_failed语义。本批不改任何分支。 |
| 冻结测试边界 | `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/ApiFactoryDispatchTest.kt:321`；`ubaa_old/composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/AuthViewModelInitializeAppTest.kt:240` | 检索到API桩/初始化fake；未发现专门验证这四个userinfo字段真实解码的冻结测试。不能将其它gsmis/getUserInfo.do测试当本接口证据，也不能冒称四字段已有冻结测试PASS。DTO及实际本地反序列化实现是直接来源。 |
| examples最近模块 | `examples/buaa-api/src/api/user/opt.rs:6` | get_state GET `/api/uc/status?selfTimestamp=...`返回原始String；不是资料接口，无等价四字段typed DTO，不借该接口替代userinfo或补字段。用户中心激活复用既有parity说明，不新增协议假设。 |
| 当前 Core 字段 | `crates/ubaa-core/src/domain/auth.rs:167` | Option<String>字段；school_id明确alias `schoolid`（`:175`），phone`:173`、id_card_type_name`:171`、email`:182`。不能把缺字段或空白联系人转成默认真实值。 |
| 当前 Core 请求/解析 | `crates/ubaa-core/src/facade/read/services.rs:21`；`features/user.rs:20`、`:28`、`:41`；`upstream/mod.rs:202` | facade路线解析与本地预检→当前路线GET→parse_user_info。解析要求合法JSON、code0、data存在；同一次读取直接返回Profile，不加联系人请求。 |
| 当前 Core 测试 | `crates/ubaa-core/src/upstream/tests.rs:129`、`:133`、`:134` | 脱敏fixture证明schoolid映射，partial name-only可以解析；本轮仅阅读，未运行，且不能把这两条断言扩成四个新App投影已通过。 |
| 既有 Bridge 白名单 | `crates/ubaa-flutter-bridge/src/api/client.rs:209`、`:533` | BridgeUserProfile已有username/name/school_id/email/phone/id_card_type_name六项，map_profile逐字段映射；没有idCardNumber/idCardType。沿此白名单即可，不改Bridge v9及生成schema。 |
| App当前入口 | `packages/ubaa_app/lib/src/bridge/common.dart:14`、`:16`、`:18`、`:19`、`:20` | _userInfo只调用一次client.userInfo；trim username，null/empty立刻返回null。当前仅投影username与_nonBlank(name)，本批在同对象构造中追加四个可选字段。schoolId不得作为空username的替代登录身份。 |
| 现有显示姓名规则 | `packages/ubaa_domain/lib/src/common/auth.dart:25`、`:36` | preferredName在displayName为null或trim后空时返回username，否则返回原displayName；保持规则，不因schoolId/联系人/证件类型替换姓名。department现无本次userinfo来源，不猜或合成。 |

## 既有九列协议记录直接复用

`docs/migration/source-parity.md:106`“用户资料”表的九列已经覆盖：启动/服务URL、重定向/最终URL、Cookie/会话、方法精确参数、头/正文、加密、DTO字段、缓存并发、错误退出。这里仅补 **DTO→Bridge既有白名单→App的展示投影**；其余八列及DTO上游解析规则全部不变。表已要求展示遮罩敏感字段；主代理裁决进一步明确本地详情默认遮罩联系人、主动显示、关页/换账号清旧状态，不构成协议变更。

资料白名单须区分：schoolId为学校标识/学号；idCardTypeName只是证件类型名称，不是证件号码。不得因旧Core拥有idCardNumber而把它传入新App模型、日志、截图或复制按钮。本文不提供真实个人信息示例。

## 最小后续验收（建议，未执行）

- 单次fake userInfo同时包含四个不同合成值，App字段逐个准确投影，调用次数仍1；可选字段缺失/空白的处理沿现_nonBlank风格，不假定必填。
- username为null、空字符串或全空白时仍返回null，即使schoolId有值；name为空/仅空白时preferredName仍回退username，已有正常姓名规则不变。
- 默认联系人遮罩，主动显示仅本地状态；关闭再开恢复遮罩；账号切换时已展开页/旧异步返回不得泄漏上一账号字段或展开状态。显示状态不进入Core配置、持久化会话或telemetry。
- 图中只synthetic联系人，日志不打印原联系人值；idCardTypeName与idCardNumber禁曝边界分开验证。旧username/displayName场景及不提供新字段的宿主保持兼容。

当前结论仅为来源充分、方案无新增协议；App/UI新行为的RED/GREEN及实际渲染由主代理阶段A另行完成。
