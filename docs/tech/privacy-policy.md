# 隐私政策

UBAA 尊重用户隐私。本页基于当前仓库实现，说明当前版本对学号、密码、登录会话和教务数据的处理方式；如果实现发生变化，本页也应同步更新。

## 核心结论

- 在 `DIRECT`（直连）和 `WEBVPN` 模式下，本应用不收集、不上传任何用户的学号、密码及教务数据，所有请求均由用户设备直接发往学校上游系统或 WebVPN。
- UBAA 同时提供 `SERVER_RELAY`（服务器中转）模式。使用该模式时，客户端请求会先发送到 UBAA server，再由 server 访问学校上游系统。因此，“所有请求均在设备本地完成”这一表述不适用于服务器中转模式，也不适用于当前仅支持服务器中转的 Web/Wasm 端。

## 客户端本地处理

- 连接模式、Token、ClientId、直连/WebVPN 会话与 Cookie 保存在用户设备本地。
- 如果用户启用记住密码，学号和密码会保存在设备本地的 `CredentialStore` 中，用于后续自动填充或自动登录。
- 公告已读、课程筛选、预约表单等偏好设置也保存在本地。

## 服务器中转模式下的处理

- 为了完成登录和业务请求，服务端会处理用户提交的学号、密码，以及学校上游系统返回的教务数据。
- 服务端会在 Redis 中维护运行所需的 Session、Cookie、Refresh Token、预登录上下文和短期业务缓存。
- Refresh Token 在服务端以哈希形式保存，不以明文写入持久化存储。
- 登录统计会记录成功事件数量；用于去重统计的用户标识会先做哈希处理，再写入指标存储。

## 会话清理

- 切换连接模式时，应用会清理当前模式作用域下的 Token、ClientId、本地会话、Cookie 和相关缓存。
- 用户退出登录后，当前会话对应的认证状态会被清理。
- 服务端会定期清理过期 Session、预登录状态和短期业务缓存。

## 适用边界

- 如果你希望学号、密码和教务数据始终只在设备本地与学校系统之间传输，请使用 `DIRECT` 或 `WEBVPN` 模式。
- 如果你使用 `SERVER_RELAY` 模式，或在 Web/Wasm 端使用本应用，请默认理解为请求会经过 UBAA server 的运行时中转。

## 来源文件

- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/ConnectionRuntime.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/CredentialStore.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`
- `server/src/main/kotlin/cn/edu/ubaa/auth/session/SessionManager.kt`
- `server/src/main/kotlin/cn/edu/ubaa/auth/session/RedisSessionStore.kt`
- `server/src/main/kotlin/cn/edu/ubaa/auth/session/RefreshTokenStore.kt`
- `server/src/main/kotlin/cn/edu/ubaa/metrics/LoginMetrics.kt`
