# iHome WebVPN 登录循环修复

## 证据范围

依据用户提供的 `d.buaa.edu.cn.ihome.har`（176 条请求）和当前 Kotlin 实现分析。下表编号按 HAR 条目从 1 开始计数。文档只保留协议结构，ticket 和 token 使用占位符，原始 HAR 不加入仓库。本轮没有使用 HAR 凭据重放真实请求，也没有完成修复版 App 的真实 WebVPN 登录验收。

## 浏览器成功链路

HAR 首先记录 WebVPN 自身登录，随后 iHome 业务读取返回 401，页面借助已建立的 SSO 会话完成独立 iHome 登录。

以下地址为从 WebVPN 地址还原的上游地址；实际网络请求始终发往 HTTPS 的 `d.buaa.edu.cn`，`/http/` 和 `/https/` 区分网关访问上游的协议。

| 条目 | 请求 | 状态及下一跳 |
| --- | --- | --- |
| 96 | SSO `/login?service=http://i.buaa.edu.cn/api/authLogin` | 302 → HTTP iHome `/api/authLogin?ticket={ticket}` |
| 97 | HTTP iHome `/api/authLogin?ticket={ticket}` | 302 → HTTPS 同路径同查询 |
| 98 | HTTPS iHome `/api/authLogin?ticket={ticket}` | 302 → HTTP `/api/authLogin`，清除 ticket |
| 99 | HTTP iHome `/api/authLogin` | 302 → HTTPS 同路径 |
| 100 | HTTPS iHome `/api/authLogin` | 302 → HTTP `/web/#/login?type=0&token={token}` |
| 101–102 | HTTP `/web/` → HTTPS `/web/` | 302 后 200 |
| 152、154、155 | 诉求、平台配置和用户资料 | HTTP 200 |

## 根因与修复

客户端 `LocalWebVpnSupport.fromWebVpnUrl` 和服务端 `VpnCipher.fromVpnUrl` 均使用拆分路径、过滤空片段、重新拼接的方式，导致 `/web/` 变成 `/web`。

iHome 认证实现只在精确路径 `/web/` 下读取成功回调的片段 token。路径被改写后，客户端错过已拿到的 token，继续请求 `/web`。若上游将其重定向到 `/web/`，解码又移除斜杠，重复请求直到触发“ihome 登录跳转次数过多”。新增合成回调测试在旧代码上复现了这一相同异常；用户 HAR 记录的是浏览器成功链路，不是 App 内循环的直接抓包。

修复只移除 WebVPN 的协议和加密主机前缀，保留剩余编码路径原文，包括根路径、末尾斜杠和连续斜杠。认证层无需放宽路径匹配，也无需提高跳转次数或切换到直连。

往返测试同时发现客户端转换中 `Url.encodedQuery` 会将登录片段中的问号部分作为查询读取，从而重复拼接到 `#` 前。现在明确只从 `#` 之前提取原查询，防止片段 token 被复制到 HTTP 查询中；真实查询与片段仍分别保留。

## 验证

- 修复前：客户端路径往返、服务端路径往返测试失败；使用真实 WebVPN 主机编码及合成票据的 iHome 登录测试复现“登录跳转次数过多”。
- 修复后：同一登录测试验证两次 CAS 回调后直接提取 token，不请求 `/web`；后续业务读取携带 Bearer，全部请求仍通过 HTTPS WebVPN 网关。
- 路径回归覆盖 `/`、`/web/`、连续斜杠、查询和登录片段；独立断言片段 token 不进入 HTTP 查询。
- 共享层全量测试：213 项，202 通过、11 跳过、0 失败；服务端全量测试：222 项，221 通过、1 跳过、0 失败。
- Android Debug 编译和 APK 签名校验通过；修复版为 `androidApp/build/outputs/apk/debug/UBAA-1.8.1-ihome-webvpn-fix-debug.apk`。未重新发布 Release。
- 上述结果属于本地确定性验证，不等同于修复版真实 WebVPN 账号验收。

## 重新发布准备

按用户要求以修复代码重新发布 v1.8.1，营销版本保持 1.8.1，内部版本代码从 32 递增为 33，保证 Android 正式签名包可以覆盖旧版升级。Release 说明继续使用“新增ihome功能”。旧版发布运行号为 35330789049，源码为 45b415c69cb0c63596ce9d7759de7bf62a46dea6；新产物必须由修复后的提交重新构建，不复用旧运行的资产。
