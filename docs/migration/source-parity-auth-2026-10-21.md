# SSO 传输协议与 UC 激活链对照

日期：2026-10-21。实现前记录。基线 `01fd09b4`。

## 来源与冲突决策

- 冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`（表单、跳转、Cookie/会话、UC 状态）、`LocalWebVpnSupport.kt`（网关编解码）、`api/auth/AuthApi.kt`（接口）、`model/dto/UserInfo.kt`（DTO）及 `commonTest/.../api/LocalAuthServiceBackendTest.kt`、`LocalCookieStoreTest.kt`、`LocalWebVpnSupportTest.kt`。
- 冻结 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`：`src/api/sso/auth.rs`、`api/user/{auth,opt}.rs`、`api/aas/core.rs`、`request.rs`、`store/{cookies,cred}.rs`、`error.rs`。其 WebVPN 主要服务 ClassAPI，不是 UBAA 的全请求路线，不能照搬该 service。
- 用户 UC HAR 共 131 请求：#24 密码 POST 返回302；#71 status仍为10600；#72 UC激活跳到 HTTP SSO，#74 HTTPS SSO 返回UC ticket回调，#75去ticket，#76落地；#125/#129 status为0。BYXT HAR共90请求：#0根入口指向HTTP；#1浏览器307升级HTTPS；#26 SSO返回带ticket教务回调；#38/#49 currentUser的code为字符串0，数据在datas。独立解析只输出地址主机/路径、参数名和业务code，不读取到日志的实际凭据或资料。
- 冻结旧版 UC 激活依赖 Ktor 自动跳转，独立 Rust 参考依赖 Reqwest 自动跳转；两者没有覆盖本次 HTTP SSO Location 的显式升级。UBAA2 已手动跳转、禁用 Reqwest 自动跳转、最终核对 UC status，不能直接套用 Kotlin 缺陷结论。UBAA2 当前会原样请求 HTTP SSO，Secure Cookie 因协议不匹配而不发送；WebVPN 包装也会保留 HTTP 上游段。
- 决策：仅对跳转目标中默认 HTTP 端口的精确 `sso.buaa.edu.cn` 主机升级 HTTPS，网关包装先还原、核对目标后按固定路线重包；保留原始查询编码，不改 service 值和其他主机协议。主登录与业务门户既有白名单、跳转上限分别保留。依据是实际浏览器成功链，优先于冻结源未覆盖的旧行为。2026-10-30 起，认证重定向同时拒绝用户信息和未声明端口；SSO 只接受默认端口，iClass 仅在自身主机允许来源已声明的 8346/8347，通用 WebVPN codec 继续支持业务自定义端口；这是针对 Location 注入与网关绕过的安全收紧，若与未覆盖的旧端点行为冲突，必须先补充来源证据再放宽。

## 逐操作对照

| 操作 | bootstrap/service 与最终 URL | 方法/参数/头/body | Cookie、凭据与加密 | DTO/解析、缓存/并发与错误 |
| --- | --- | --- | --- | --- |
| 准备普通/交互式登录 | 两份源都从 HTTPS SSO `/login` 开始；旧版在已有SSO状态时激活UC。UBAA2保留该行为，不能把302本身判为已完成登录。 | GET；无凭据body；UA沿现有传输，不增加fingerprint请求。 | 旧版Cookie按模式隔离并检查Secure/domain/path；buaa-api共享上下文Cookie；UBAA2保持独立RouteClient与session修订检查，不复制另一槽。 | 旧版解析execution和验证码；独立参考不支持等价交互式流程。保留现有Plain/Image/Ready分类，验证码仍按原挑战处理。 |
| 密码提交及后续SSO跳转 | SSO `/login`；六字段与HAR及两源相同。只升级跳转目标的SSO传输，不修改嵌套service。 | POST表单URL编码：username、password、submit、type=username_password、execution、_eventId=submit；旧版允许既有表单附加字段，UBAA2继续保留；Content-Type为application/x-www-form-urlencoded。 | 密码沿TLS原表单提交，不新增密码加密或指纹。WebVPN主机编码沿冻结AES-CFB、key/IV `wrdvpnisthebest!`，不改算法或常量。 | 旧版识别登录错误和密码风险继续；独立参考宽松判HTTP成功。UBAA2保留原错误分类、一次风险继续与10跳上限，最终仍需UC校验。 |
| UC票据交换 | 旧版/UBAA2为 `https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin`；独立参考使用未编码target字符串。HAR证实须再经过SSO(service=UC回调)、ticket回调、去ticket跳转。UBAA2保留既有编码与起点。 | 每跳GET、保存响应Cookie后再发下一跳；不重复密码POST。Location使用URL解析，相对地址按当前响应解析，不对query重新解码/编码。 | Secure Cookie只在HTTPS发送；网关路由下Cookie属于网关并按路径匹配，不外泄到直连；固定路线不随UI策略切换。 | 旧版自动链无显式预算，UBAA2已有10跳预算及缺失Location/服务端错误处理；保留。落地HTML200不能替代最终status。 |
| UC状态与资料 | `/api/uc/status`、`/api/uc/userinfo`沿旧版；独立参考status带selfTimestamp并返回原文，不直接采用其弱校验。 | GET；旧版status有Accept及X-Requested-With，UBAA2当前请求头保持，本次不引入未经反例证明的头变更。 | 以当前路线会话发请求；只有验证成功后保存认证时间与Cookie，失效清理和CAS修订语义不改。 | 旧版code=0且data有身份信息；HAR10600表示尚未激活。UBAA2继续使用白名单UserProfile和稳定错误码，不导出完整个人资料。 |
| 教务及共享业务CAS跳转 | BYXT `/jwapp/sys/homeapp/api/home/currentUser.do` 与现有CAS入口保持；独立参考`api/aas/core.rs`使用homeapp service。HAR中的byrhmhsy是浏览器门户入口，不替换已有homeapp service。其他业务沿现有逐操作来源记录。 | 共享GET跳转只在精确SSO目标上升级；已有业务headers/body/请求参数保持。 | 同一运行时Cookie和固定模式不变；仍由相应业务入口验证业务会话，不把UC成功等同所有业务成功。 | 当前UBAA2仅校验HTTP200，冻结旧版只校验JSON形状，独立参考只校验落地URL；三者均未充分验证currentUser业务状态。HAR #49已核实code为字符串0、datas为非空对象且userId为字符串。新增精确homeapp currentUser最终地址、code=0及非空userId校验，异常响应归为UpstreamChanged，不伪造成功、不推断未知业务码含义；现有本科失败后GSMIS探测保持。共享业务跳转8跳上限、主机白名单与缓存不变。 |

其他业务的请求/DTO/签名常量详见既有 [source-parity.md](source-parity.md) 对应操作，本次不改业务服务参数、数据解析或缓存策略。用户更新指令明确排除中转；不修改旧配置或凭据。

补充边界：发现网关包装目标可以绕过原白名单，先用合成包装未登记主机/非HTTP协议证明失败，再将既有白名单应用于解包后的目标。范围仍是已有白名单，不新增上游主机。
