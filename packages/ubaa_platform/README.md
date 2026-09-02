# ubaa_platform

`ubaa_platform` 是 Flutter 宿主与 UBAA Core 之间的平台能力边界。它不拼接
上游 URL、不读取 Core 的 Cookie/session 文件，也不把密码或响应正文写入日志。

## 凭据保险箱

`CredentialVault` 只定义 `load`、`save`、`clear` 三个异步操作。生产应用应通过
`CallbackCredentialVault` 注入 Android Keystore、iOS/macOS Keychain 等实现；
`MemoryCredentialVault` 仅用于测试，`CredentialVault.sessionOnly()` 只在当前进程内
暂存，`CredentialVault.noop()` 是完全不保存的安全默认值。凭据对象的 `toString`
始终遮盖账号和密码。

## 遥测

`TelemetryClient()` 和 `TelemetryClient.noop()` 默认关闭遥测。只有显式传入
`enabled: true` 与 sink 才会发送事件；事件名和字段均经过固定白名单，自定义策略只能
收窄白名单，不能扩展它。密码、令牌、Cookie、账号、URL、响应正文等字段始终被丢弃。
`MockTelemetryClient`/`InMemoryTelemetryClient` 用于确定性测试，
`CallbackTelemetryClient` 用于接入应用自己的分析 SDK。遥测 sink 异常不会影响登录
或只读业务。

## UI 错误映射

`UiErrorMapper`/`mapCoreErrorJson` 接受 Rust Core 的稳定 `code`、`kind`、`retryable`
字段以及 CLI schema-v2 的 `error` envelope，映射到 `ubaa_domain` 的 `UiError` 和
安全中文文案。未知或畸形载荷统一归约为 `internal_error`；上游 message 默认不会展示，
只有显式请求且通过脱敏检查的短诊断文本才进入 `technicalDetail`。

## 媒体与权限边界

`PlatformPermissionGateway` 统一承载相机、相册、文件和前台位置权限申请，并只返回
`granted`、`denied`、`restricted`、`unavailable` 四种稳定状态。没有原生插件时使用
`UnavailablePermissionGateway`，安全拒绝而不伪造授权。`PlatformPhotoPicker` 只返回
typed 的 `YgdkPhotoInput`，不向业务层暴露文件路径；`UnavailablePhotoPicker` 是无设备
构建的默认后置能力，`MemoryPhotoPicker` 仅用于脱敏 widget/integration 测试。官方 Flutter
与 OHOS 宿主在接收 picker 后会用 `PermissionedPhotoPicker` 包装它；未显式注入权限网关时
默认使用 `UnavailablePermissionGateway`，因此不会在无权限时调用 picker。原生
Keychain/Keystore/Secret Service/HUKS 插件接入和设备权限验证仍需在后置发布阶段完成。
