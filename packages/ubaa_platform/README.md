# ubaa_platform

`ubaa_platform` 是 Flutter 宿主与 UBAA Core 之间的平台能力边界。它不拼接
上游 URL、不读取 Core 的 Cookie/session 文件，也不把密码或响应正文写入日志。

## 凭据与安全材料

生产接线统一为 `PlatformCredentialVault → MaterialCredentialStore → SecureMaterialStore → flutter_secure_storage`，不再探测或调用 `credentials.*` 自定义通道。`MemoryCredentialVault`、session-only和Noop仅供显式测试或无持久能力场景；凭据对象的文本表示始终遮盖账号与密码。

官方五端使用固定插件10.0.0；macOS使用插件的登录Keychain配置，iOS使用首次解锁后仅本机可用配置，Android明确禁用错误自动重置。OHOS宿主注册本仓库社区HUKS插件适配，通过相同的插件2.x平台接口读写，不自建宿主加密通道。插件来源、修订与设备验证限制见[OHOS插件说明](../flutter_secure_storage_ohos/README.md)。

开发阶段按用户要求使用材料前缀 `ubaa.material.v2.`，不迁移或删除旧v1材料及旧macOS通道条目。密码、账号索引、缓存密钥各自使用独立键；业务正文仍由Core加密缓存拥有。能力探测必须写入、读回、删除并确认；不可用时不构造本机账号仓库、不降级明文。存储错误采用安全中文提示与类型化诊断，不输出原始平台错误正文。

聚焦测试为 `just flutter-test ubaa_platform test/credentials`。当前覆盖合成接口与通道合同，真实安全存储、照片权限与系统插件保留原生能力测试，详见[测试策略](../../docs/development/testing.md)。

## 遥测

`TelemetryClient()` 和 `TelemetryClient.noop()` 默认关闭遥测。只有显式传入
`enabled: true` 与 sink 才会发送事件；事件名和字段均经过固定白名单，自定义策略只能
收窄白名单，不能扩展它。密码、令牌、Cookie、账号、URL、响应正文等字段始终被丢弃。
`MockTelemetryClient`/`InMemoryTelemetryClient` 用于确定性测试，
`CallbackTelemetryClient` 用于接入应用自己的分析 SDK。遥测 sink 异常不会影响登录
或只读业务。

## UI 错误映射

`UiErrorMapper`/`mapCoreErrorJson` 接受 Rust Core 的稳定 `code`、`kind`、`retryable`
字段以及当前 CLI schema-v12 的 `error` envelope，映射到 `ubaa_domain` 的 `UiError` 和
安全中文文案，并保留失败实际路线。未知或畸形载荷统一归约为 `internal_error`；上游 message
不展示也不再保留在 `technicalDetail`，旧详情参数仅供兼容。app 的映射入口委托同一策略。

`LocalDiagnostics` 默认仅在本次运行的内存中保存最近 100 个允许字段事件，不收集原文或
个人数据，不写磁盘、不上传。登录失败页和个人页均支持用户主动查看、复制，详见
[本地排障手册](../../docs/runbooks/local-diagnostics.md)。

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
其他平台安全存储插件接入和设备权限验证仍需在后置发布阶段完成。

博雅签到需要调用方坐标时，宿主通过 `PermissionedLocationProvider` 先申请
`foregroundLocation`，再读取一次 `PlatformLocation`；不需要坐标的 action 不会触发权限
申请。`MethodChannelLocationProvider` 只接受 `location.capability` 与 `location.current` 两个
typed 方法，并只读取有限且位于合法范围内的 `lat`、`lng`。插件异常、畸形返回、额外路径
或令牌字段均不会进入业务层；`UnavailableLocationProvider` 和 `MemoryLocationProvider`
分别用于安全拒绝与脱敏测试。

生产宿主的默认组合由 `createDefaultPlatformCapabilities()` 创建：权限请求使用
按平台选择原生权限Gateway或系统单文件选择授权，照片在Windows/Linux使用`DesktopFilePhotoPicker`、其它平台使用`MethodChannelPhotoPicker`，位置使用
`MethodChannelLocationProvider`；它们在插件缺失或返回值不符合合同时安全拒绝。
MethodChannel 定义 Dart/原生的稳定边界；各能力是否完成以对应平台实现及验收证据为准，不能
仅凭共享适配器推定设备权限、安全存储或定位已经可用。

## Windows/Linux系统选图

生产能力组合通过已注册的file_selector 1.1.0打开单文件系统对话框，仅在用户选择后读取。长度检查与流式读取均限制10MiB，取消返回空，异常归约为稳定PlatformCapabilityException；Host只接收字节、canonical文件名和image MIME，不接收路径。照片/文件权限表示可进入这一系统选择流程，其它权限仍委托既有原生Gateway；不声称桌面相机或定位已接入。其它平台保持现有MethodChannel选图实现。

来源和验证边界见[桌面选图对照](../../docs/migration/source-parity-desktop-photo-2026-10-02.md)。本机测试不能替代Windows/Linux原生窗口验收。
