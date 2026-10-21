# 登录与连接模式

登录模块负责把用户凭据、验证码、预登录上下文和连接模式绑定在一起。客户端恢复已保存的直连或 WebVPN 模式；旧服务器中转配置会被清除，返回模式选择页。

## 用户能力

- Android、iOS、Desktop 支持直连模式和 WebVPN 模式。
- Web/Wasm 端显示使用原生客户端的提示，不再提供已弃用的服务器中转。
- 支持验证码获取、预登录、登录、登录状态检查和退出登录。
- 切换连接模式时会清理 Token、ClientId、本地会话、Cookie、本地上游客户端和学期缓存，避免跨模式复用旧状态。

## 技术路径

- `ConnectionRuntime` 决定可用模式、当前模式和切换时的会话清理。
- `DefaultApiFactory` 根据模式选择直连或 WebVPN 的本地实现；relay 实现仅保留兼容代码。
- 本地直连/WebVPN 由 `LocalAuthServiceBackend` 登录统一认证，并把上游 Cookie 持久化到本地存储。
- SSO 提交成功后还需要访问 UC `/api/login` 完成票据交换，并以 `/api/uc/status` 的业务结果判断登录状态；不能把 SSO 的 302 当作整个 App 登录成功。
- UC 激活手动处理跳转，将 SSO 默认端口的 HTTP 地址升级为 HTTPS，保留 `service` 编码；WebVPN 模式保持网关路由，超过 10 次跳转会终止。

## 接口

以下为仍保留在代码中的服务端接口，不再作为 App 的认证路径：

- `POST /api/v1/auth/preload`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/login-stats`
- `POST /api/v1/auth/refresh`
- `GET /api/v1/auth/status`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/captcha/{captchaId}`

## 来源文件

- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/AuthViewModel.kt`
- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/LoginScreen.kt`
- `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/ConnectionModeSelectionScreen.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/ConnectionRuntime.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/core/ApiFactory.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/AuthApi.kt`
- `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`
- `server/src/main/kotlin/cn/edu/ubaa/auth/api/AuthRoutes.kt`
- `server/src/test/kotlin/cn/edu/ubaa/auth/api/AuthRoutesTest.kt`
- `shared/src/commonTest/kotlin/cn/edu/ubaa/api/ConnectionRuntimeTest.kt`
