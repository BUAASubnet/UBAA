# 认证安全修复复核

基线 `1e1729a1`，复核 `19c97520` 与未提交修改。冻结引用已通过 `just refs`：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本轮没有学校请求。

旧版已读 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt`、`LocalConnectionAuth.kt`、`LocalBykcApi.kt`、`LocalSigninApi.kt`、`LocalLibBookApi.kt`、`LocalYgdkApi.kt`、对应 feature 接口、DTO 及 commonTest BackendTest；签到另读 `SigninLoginNameSupport.kt` 和测试。另一来源已读 `src/api/{sso/auth,boya/core,class/core,class/data,user/auth}.rs`、`request.rs`、`store/cookies.rs` 和 API 模块清单。buaa-api 没有图书馆或阳光打卡等价协议，相关列不适用。

## 实施前逐操作比较与决定

| 操作 | 引导 URL/service | 重定向与最终地址 | Cookie/Token 作用域 | 方法与参数 | 请求头/编码 | 加密 | DTO/解析 | 缓存/重试 | 错误与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| WebVPN 编解码与认证跳转 | 旧版网关为 HTTPS d.buaa.edu.cn；buaa-api SSO 使用同网关 | 旧 codec 原样保留不能解码的网关原生路径；支持 HTTP(S) 与业务自定义端口。仅在第二段确为加密主机后严格解析端口，禁止畸形端口降为默认端口。保留合法包装 SSO 解包后按 Direct 访问上游 | 旧版按路线；独立参考共享；保留 Core 路线隔离 | 不新增请求 | 保留原 path/query/fragment 编码及嵌套 service | AES-CFB key/IV 与 host 算法不变 | 不新增 DTO；网关原生路径不能误认成包装 | 原跳数和运行时不变 | 非法 wrapper/authority 在请求前拒绝；不把 codec 对自定义端口的支持等同认证端口许可 |
| BYKC CAS/token | 旧版 `/sscv/cas/login`；参考 SSO service 指向同址 | 两源 token 回调 `/cas-login`。先解析包括根相对/协议相对网关包装的实际目标，再检查 sso/bykc authority，最后提 token；普通业务相对路径沿解包后基址 | 原主 Cookie、路线内 token | 原 GET；业务 POST 参数不变 | 原 token 双头和正文编码不变 | 原 AES/RSA/SHA-1 不变 | token 非空、仅安全 bykc 主机；不从恶意包装路径猜来源 | 原登录锁/8 跳不变 | 非法目标零业务请求；回调 token 直接提取，不请求无必要的回调页面 |
| Signin loginName | 旧版 8346 `?type=jumpMyCenter`、8347 `app/user/login.action`；参考业务登录路径不同，沿既有真实证据裁决，登录端点不改 | 旧测试支持绝对、根相对、路径相对；旧 helper 明确支持网关根相对包装。先还原真实目标，iClass 自定义端口只允许 8346/8347，SSO 仅默认端口 | 原路线 Cookie、内存 id/sessionId | 原五个 login query，签到 POST 原值 | 原 sessionId/form 不变 | 无 | 原 loginName 与 DTO；不把 iClass 端口放行到 SSO | 原单飞、读取重试不变 | 写后 SSO 落点仍保守归 OutcomeUnknown；不复用发送前安全 authority 判定缩小未知结果范围 |
| LibBook CAS | 旧版 SSO service 为 `/v4/login/cas`；另一来源不适用 | 旧测试 query cas 与 `/h5/index.html#/cas/?cas=` 均支持。根相对包装先解包再验证 sso/booking 主机；保留 fragment CAS | 原路线内 bearer、Cookie | GET CAS，POST `/v4/login/user` 的 cas；其它参数不变 | 原固定 Header 与 JSON 不变 | 原预约 AES 不变 | cas query/fragment 解析不变 | 原登录锁/8 跳；写不重试 | 写后认证路径与 SSO 保持 OutcomeUnknown；严格 final 检查不能把异常落点变成功 |
| Ygdk OAuth/code | 旧版固定 app `/uc/api/oauth/index`，redirect 为 `https://ygdk.buaa.edu.cn/#/home`；另一来源不适用 | 冻结 BackendTest 证明 app→ygdk 回调，未证明其它中间主机。改为只允许 HTTPS app/ygdk 默认端口；d 只能是 WebVPN 外壳，内层同样验证；未知主机拒绝。code 只从 ygdk 根路径的 query 或 `/home` fragment query 提取 | 当前路线 Cookie；code 仅本轮内存，uid/token 仍受 generation 守卫 | 原 GET campusAppLogin，code 单次 URL 编码 | 不新增 Header 或正文 | 无 | 不增加 DTO；代码中的 app?code Mock 迁为冻结 ygdk 回调；保留 query/fragment 与百分号编码 | 原 10 跳和登录锁；禁止因未知目标改路线 | 这是安全收紧，不声称已证明真实完整链；未知中间学校主机会明确失败，需脱敏证据后才扩充 |

## 审查更正与验证边界

Direct 收到合法 WebVPN 包装后解包并请求上游，不等于向网关发请求，不能据此判为路线越界。Signin/LibBook 非法 final URL 加成功 JSON 的反例证明 Core 分类回归，但生产 Reqwest 禁止自动重定向，普通 Location 无法直接伪造该 final；不将该反例夸大为已证明的远程利用。

Ygdk 旧实现无逐跳白名单不构成继续放行任意主机的理由。本轮只采用已经有证据的 app/ygdk 集合，未知目标失败关闭。真实双路线兼容性尚未验证。

Ygdk `extractOauthCode` 与业务 token 调用 Ktor `decodeURLQueryComponent()`，其 [官方 API](https://api.ktor.io/ktor-http/io.ktor.http/decode-u-r-l-query-component.html) 默认 `plusIsSpace=false`。Core 原来把单个 token 拼成表单查询，导致字面 `+` 变空格、`&` 截断。按冻结语义仅执行一次百分号解码，保留字面 `+` 和 `&`；交换 code 时由 URL serializer 重新编码一次，不进行二次解码。

复核还发现旧的 Core codec 在网关协议/密文前缀含重复斜杠时，过滤空段后仍用规范前缀 `strip_prefix`，失败便把业务 path 丢成空串。`/other?code=...` 因此可能被误识别为 ygdk 根回调。冻结 `LocalWebVpnSupport.kt` 过滤空前缀段但保留后续业务段；本轮沿用该可识别前缀语义，并准确保留主机段之后的原始业务 path。负例先复现 `Some(code)`，修复后必须为 None。网关原生路径继续原样保留。

Ygdk 的冻结 `resolveRedirectUrl` 明确按当前请求（包括 d 网关）解析根相对与路径相对 Location；因此保留当前 `base.join(location)`，不套用 Signin/LibBook 的“先解包业务基址”规则。Direct 拒绝未解包的网关 Location 是本轮显式安全收紧，旧 Ygdk 没有证明该混合路线正常行为；保留拒绝，真实兼容性待验证。该点与共享认证中已有证据的 Direct 解包 SSO 不同。

Ygdk 回调的根路径 query 与 fragment query 分别处理：存在根路径 `?code=` 时，无关 fragment 不改变 code；只有从 fragment 内取 code 才要求片段路由为 `/home`。先将 `/?code=...#section` 写为失败正例，再修正本轮把 fragment 条件施加到所有 code 的过度限制。

此前“主机大小写可绕过”的表述不准确：Rust `url` 会将 HTTP(S) 域名规范化为小写，增加大小写不敏感比较本身不能证明修复了一条可利用路径。保留对应边界用例，但实际缺陷依据是 userinfo、未声明端口、错误解包与提取顺序，不把大小写变体单列为已证安全漏洞。

写后判定还须覆盖 codec 拒绝异常网关的情况：Signin/LibBook 原先 `from_webvpn_url` 失败便回退原始 d URL，再配合成功 JSON 会误报成功。两个完整写链反例使用非法 HTTP 网关 final，证实最终写已发送一次却返回 success；改为解包失败、无法解析 URL 或解包后仍是网关时均返回 OutcomeUnknown。有效业务 false 与成功仍按原响应解析，未知结果不自动重放。该反例也只证明 Core/custom transport 分类边界，未证明生产 Reqwest 可收到攻击者任意 final URL。


## 失败反例与确定性结果

以下反例均在相应生产修复前实际失败，随后复跑通过：

- 网关 `/wengine-vpn/cookie` 与 `/por/login_psw.csp` 被错误按包装协议解析。
- BYKC 根相对恶意 wrapper 被借用当前 bykc 主机；同主机非 `/cas-login` 页面 token 被接受。
- 普通 `../../../cas-login` 在首次 wrapper 修复后被误拒绝；恢复按解包后的业务目录解析。
- SSO 错误借用 iClass 的 8346/8347 端口许可。
- Ygdk 未知主机、未证回调路径和 wrapper 内层非法端口被放行；token 字面 `+` 被转为空格、`&` 截断。
- wrapper 前缀重复斜杠丢弃业务路径；根路径 query code 被无关 fragment 误拒绝。
- Signin/LibBook 写后非法网关 final 加成功 JSON 返回 success；修复后 OutcomeUnknown，写只发送一次。

最终聚焦命令 `cargo test --locked --offline -p ubaa-core --features test-contract --lib --test connection --test bykc --test signin --test libbook --test ygdk`：Core lib 394 通过、1 项按已有标记忽略；connection 9、BYKC 21、Signin 10、LibBook 26、Ygdk 5 全通过。BYKC 双路线测试检查实际请求 host、final/Location token 提取及不额外请求 callback。Ygdk 双路线测试检查未知主机请求前拒绝、WebVPN root-relative wrapper、code 单次解码后重新编码与路线固定。BYKC full_detail 夹具原先人为在 `/sscv/cas/login` 拼 token，已改成冻结证实的 `/cas-login`，未放宽生产回调规则。

最终 `cargo clippy --locked --offline -p ubaa-core --all-targets --features test-contract -- -D warnings` 与 `git diff --check` 通过。补充的写后无法解析/原生网关分支测试已聚焦复跑通过。

本轮只运行本地确定性协议测试。真实账号、学校网络与 Direct/WebVPN 完整实时链均未运行。仓库完整门禁由主任务统一执行，其结果独立记录。

Bridge 的两个共享 BYKC 夹具也曾在 `/sscv/cas/login` 拼接 token，导致严格回调校验后 29 项测试无法进入业务步骤。夹具改为同路线的 `/cas-login` 后，Bridge 157 项通过、2 项按已有标记忽略；业务资格、缓存失效与只发送一次的原断言全部保留。
