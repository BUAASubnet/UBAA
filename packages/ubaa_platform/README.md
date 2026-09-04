# ubaa_platform

`ubaa_platform` 是 Flutter 宿主与 UBAA Core 之间的平台能力边界。它不拼接
上游 URL、不读取 Core 的 Cookie/session 文件，也不把密码或响应正文写入日志。

## 凭据保险箱

`CredentialVault` 只定义 `load`、`save`、`clear` 三个异步操作。生产应用应通过
`CallbackCredentialVault` 注入 Android Keystore、iOS/macOS Keychain 等实现；
`MemoryCredentialVault` 仅用于测试，`CredentialVault.sessionOnly()` 只在当前进程内
暂存，`CredentialVault.noop()` 是完全不保存的安全默认值。凭据对象的 `toString`
始终遮盖账号和密码。

生产宿主可使用 `MethodChannelSecureCredentialStore`；它只通过
`cn.edu.buaa.ubaa/platform` 的 typed 方法探测和访问原生安全存储，写入前校验凭据，
不会提供文件或明文回退。原生 handler 缺失时 `probe()` 返回不可用，应用继续使用安全的
session-only/Noop 语义；各平台 Keychain、Keystore、Secret Service、Credential Manager
和 HUKS handler 仍需在后置设备阶段实现与验证。

## 遥测

`TelemetryClient()` 和 `TelemetryClient.noop()` 默认关闭遥测。只有显式传入
`enabled: true` 与 sink 才会发送事件；事件名和字段均经过固定白名单，自定义策略只能
收窄白名单，不能扩展它。密码、令牌、Cookie、账号、URL、响应正文等字段始终被丢弃。
`MockTelemetryClient`/`InMemoryTelemetryClient` 用于确定性测试，
`CallbackTelemetryClient` 用于接入应用自己的分析 SDK。遥测 sink 异常不会影响登录
或只读业务。

## UI 错误映射

`UiErrorMapper`/`mapCoreErrorJson` 接受 Rust Core 的稳定 `code`、`kind`、`retryable`
字段以及当前 CLI schema-v9 的 `error` envelope，映射到 `ubaa_domain` 的 `UiError` 和
安全中文文案。未知或畸形载荷统一归约为 `internal_error`；上游 message 默认不会展示，
只有显式请求且通过脱敏检查的短诊断文本才进入 `technicalDetail`。

## 媒体与权限边界

`PlatformPermissionGateway` 统一承载相机、相册、文件和前台位置权限申请，并只返回
`granted`、`denied`、`restricted`、`unavailable` 四种稳定状态。没有原生插件时使用
`UnavailablePermissionGateway`，安全拒绝而不伪造授权。原生宿主可使用
`CallbackPermissionGateway` 把 SDK 结果转换为该稳定状态；回调异常会安全归约为
`unavailable`。`PlatformPhotoPicker` 只返回
typed 的 `YgdkPhotoInput`，不向业务层暴露文件路径；`UnavailablePhotoPicker` 是无设备
构建的默认后置能力，`MemoryPhotoPicker` 仅用于脱敏 widget/integration 测试。原生宿主可
使用 `CallbackPhotoPicker` 接入系统选择器；异常会转换为稳定的相册能力错误。官方 Flutter
与 OHOS 宿主在接收 picker 后会用 `PermissionedPhotoPicker` 包装它；未显式注入权限网关时
默认使用 `UnavailablePermissionGateway`，因此不会在无权限时调用 picker。桌面文件选择器
可将包装器的 `permission` 显式设为 `PlatformPermission.files`。原生
Keychain/Keystore/Secret Service/HUKS 插件接入和设备权限验证仍需在后置发布阶段完成。

博雅签到需要调用方坐标时，宿主通过 `PermissionedLocationProvider` 先申请
`foregroundLocation`，再读取一次 `PlatformLocation`；不需要坐标的 action 不会触发权限
申请。`MethodChannelLocationProvider` 只接受 `location.capability` 与 `location.current` 两个
typed 方法，并只读取有限且位于合法范围内的 `lat`、`lng`。插件异常、畸形返回、额外路径
或令牌字段均不会进入业务层；`UnavailableLocationProvider` 和 `MemoryLocationProvider`
分别用于安全拒绝与脱敏测试。

生产宿主的默认组合由 `createDefaultPlatformCapabilities()` 创建：权限请求使用
`MethodChannelPermissionGateway`，照片使用 `MethodChannelPhotoPicker`，位置使用
`MethodChannelLocationProvider`；它们在插件缺失或返回值不符合合同时安全拒绝。
MethodChannel 只定义 Dart/原生的稳定边界，不等价于已完成任一平台的原生权限、安全存储或
定位实现。
