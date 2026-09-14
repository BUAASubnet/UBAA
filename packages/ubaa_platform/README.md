# ubaa_platform

`ubaa_platform` 是 Flutter 宿主与 UBAA Core 之间的平台能力边界。它不拼接
上游 URL、不读取 Core 的 Cookie/session 文件，也不把密码或响应正文写入日志。

## 凭据保险箱

`CredentialVault` 只定义 `load`、`save`、`clear` 三个异步操作。生产应用应通过
`MethodChannelSecureCredentialStore` 或 `CallbackCredentialVault` 注入系统安全存储；
`MemoryCredentialVault` 仅用于测试，`CredentialVault.sessionOnly()` 只在当前进程内
暂存，`CredentialVault.noop()` 是完全不保存的安全默认值。凭据对象的 `toString`
始终遮盖账号和密码。

生产宿主可使用 `MethodChannelSecureCredentialStore`；它只通过
`cn.edu.buaa.ubaa/platform` 的 typed 方法探测和访问原生安全存储，写入前校验凭据，
不会提供文件或明文回退。原生 handler 缺失时 `probe()` 返回不可用，应用继续使用安全的
session-only/Noop 语义。macOS 已接入 `native/macos/KeychainCredentialStore.swift`，使用系统
登录 Keychain，在固定私有服务与明确 namespace 下保存单个 generic-password 条目，禁用同步，
所有错误均归约为稳定类别。iOS Keychain、Android Keystore、Secret Service、Credential Manager
和 HUKS handler 仍需在后置设备阶段实现与验证。

macOS 显式设置 `kSecUseDataProtectionKeychain=false`，后端限定为登录 Keychain。
`native/macos/LegacyKeychainAPI.swift` 集中管理 legacy 的进程交互策略：全实例共享锁，保存原值、
临时禁止交互、执行操作后恢复；策略失败不会继续存储或虚报成功。恢复失败仅做一次补偿，仍失败
则保存待恢复原值并阻止后续操作，避免把临时 false 当作默认策略。这里使用 deprecated 系统接口
是保留现有 Debug 签名条件的明确兼容决策，不能用 LAContext 标记代替 legacy 交互控制。

macOS 的 `PlatformChannel` 是唯一 MethodChannel 拥有者，`CredentialHandler` 在串行队列调用
Keychain，`PhotoHandler` 继续处理照片。能力探测不读保存值，只表示实现已接入；锁定或访问拒绝
仍可能使后续存储操作失败。`autoLogin` 必须为布尔类型，数值 `0/1` 不能代替它；无记录读取为
`null`，无记录删除幂等。上层 App 的记住/自动联动、登录与注销生命周期不归该适配器控制。

在本包运行 `flutter test test/macos_keychain_store_test.dart` 会编译原生确定性测试并注入全部
Security 调用，不访问系统 Keychain。真实验证在 `apps/ubaa_flutter` 下运行
`flutter test -d macos integration_test/ui_credentials/native_test.dart`：仅访问当次唯一合成
namespace，finally 精确清除，覆盖保存、新适配器读取、更新、删除、输入拒绝与照片探测。
两种证据不能替代真实 App 的记住密码/自动登录验收；来源与边界见
[macOS 凭据对照](../../docs/migration/source-parity-ui-macos-credentials.md)。

## 遥测

`TelemetryClient()` 和 `TelemetryClient.noop()` 默认关闭遥测。只有显式传入
`enabled: true` 与 sink 才会发送事件；事件名和字段均经过固定白名单，自定义策略只能
收窄白名单，不能扩展它。密码、令牌、Cookie、账号、URL、响应正文等字段始终被丢弃。
`MockTelemetryClient`/`InMemoryTelemetryClient` 用于确定性测试，
`CallbackTelemetryClient` 用于接入应用自己的分析 SDK。遥测 sink 异常不会影响登录
或只读业务。

## UI 错误映射

`UiErrorMapper`/`mapCoreErrorJson` 接受 Rust Core 的稳定 `code`、`kind`、`retryable`
字段以及当前 CLI schema-v10 的 `error` envelope，映射到 `ubaa_domain` 的 `UiError` 和
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
`MethodChannelPermissionGateway`，照片使用 `MethodChannelPhotoPicker`，位置使用
`MethodChannelLocationProvider`；它们在插件缺失或返回值不符合合同时安全拒绝。
MethodChannel 定义 Dart/原生的稳定边界；各能力是否完成以对应平台实现及验收证据为准，不能
仅凭共享适配器推定设备权限、安全存储或定位已经可用。
