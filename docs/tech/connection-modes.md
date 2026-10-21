# 连接模式

UBAA App 支持直连和 WebVPN 两种连接模式。服务器中转已弃用，不再作为可选连接方式。模式选择影响认证、Cookie、上游访问方式和可用平台。

## 模式

- `DIRECT`：客户端直接访问校内上游。
- `WEBVPN`：客户端通过北航 WebVPN 访问上游。
- `SERVER_RELAY` 仅保留旧配置与后端代码的兼容标识，不在 App 中提供。

## 平台能力

`ConnectionRuntime.availableModes()` 根据 `supportsLocalConnectionModes()` 决定可选模式。当前平台实现如下：

- Android、iOS、JVM/Desktop：`supportsLocalConnectionModes()` 返回 `true`，提供直连和 WebVPN。
- JS Browser、Wasm JS Browser：不支持本地连接模式，显示使用原生客户端的提示，不再自动进入中转模式。
- 启动时发现旧 `SERVER_RELAY` 配置，会清除旧会话、关闭自动登录并返回模式选择页；保留用户记住的账号密码。

## 切换语义

切换模式会调用 `resetSession()`，清理以下状态：

- 所有模式作用域下的 Auth Token 和 ClientId。
- 本地认证会话和 Cookie。
- 自动登录开关。
- shared API 客户端、本地上游客户端、希冀缓存和学期缓存。

## WebVPN URL

本地 WebVPN 访问通过 `LocalWebVpnSupport` 和上游 URL 包装完成。UC 激活时手动跟随 SSO 票据跳转，先还原网关地址、将 SSO 的 HTTP 地址升级为 HTTPS，再包装回同一 WebVPN 路由，最多跟随 10 次跳转。

## CGYY 例外

普通本地上游请求通过 `localUpstreamUrl()` 决定是否包装 WebVPN URL。CGYY 另有 `localCgyyUpstreamUrl()`，当前始终返回原 URL；代码注释说明 `cgyy.buaa.edu.cn` 可公开访问，因此本地 CGYY 不会因为当前模式是 `WEBVPN` 而走 WebVPN 包装。

## 来源文件

- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/ConnectionRuntime.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/core/ApiFactory.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt`
- `server/src/main/kotlin/cn/edu/ubaa/utils/VpnCipher.kt`
- `shared/src/commonTest/kotlin/cn/edu/ubaa/api/ConnectionRuntimeTest.kt`
- `shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalWebVpnSupportTest.kt`
