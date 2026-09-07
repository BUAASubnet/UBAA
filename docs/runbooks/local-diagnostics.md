# 本地错误定位与诊断

## 用户如何提供错误信息

登录失败时，在错误卡复制错误编号，或选择“查看诊断信息”查看本次运行的报告。已进入主页时，在“我的 → 本次运行诊断”查看或复制。复制是用户主动操作，不会自动上传。

本地诊断默认只在内存保存最近 100 项错误；退出进程后消失。不读取凭据、会话文件、账号资料或业务输入，也不保存 HTTP 正文、完整 URL、Cookie、照片和位置。

报告使用独立 `schema_version=1`，这是本地诊断格式，不是 CLI v10 或 Bridge v9 的版本。

## 维护者如何定位

1. 以错误编号关联当前运行的报告，查看 `operation`、`code`、`kind`、`route`、`feature`、`cause` 和 `source`。
2. `source` 仅含允许的 UBAA package 源码位置，最多三项；不包含本机绝对路径或完整堆栈。没有安全源码位置时不猜测。
3. 根据阶段定位：初始化、登录和路线切换查看 app/controller；读取查看对应 bridge/read 与 Core feature；写入准备/提交/丢弃查看 WriteCoordinator；回读查看 ReceiptVerifier 和对应 controller/readback。
4. `retryable=false` 必须继续保留。`outcome_unknown` 始终先核对状态，不能用通用重试入口重复提交。报告中的失败路线来自本次错误，不是默认策略或上次成功快照。
5. 一次错误的用户文案可以共享，但机器码不得合并，例如 parse_error 仍是 parse_error。

本地诊断不会改变成功业务结果。可选遥测异步执行且有两秒截止预算，异常只记录到本地；错误不会反过来把登录、读取或提交改成失败。过期读取和已经销毁控制器的晚到结果不进入当前页面诊断。

## Rust 传输补充证据

具体 HTTP 适配器的 `ubaa::transport` tracing 事件只包含固定阶段、保守原因分类和耗时。发送、响应读取和响应超预算分别记账。分类只依据稳定 Reqwest 判断和最多八层标准 I/O 错误链，不格式化原始错误、不记录请求/响应数据。

生产 Bridge 初始化安装仅接收该安全 target 的 DEBUG 四字段事件的 stderr 日志订阅器；宿主已有全局订阅器时不覆盖。它不读取 RUST_LOG 放宽过滤，也不启用第三方详细日志。CLI 默认不输出这些诊断事件，保持 JSON 命令的安静错误输出；需要排障时显式设置 `RUST_LOG=ubaa::transport=debug`，沿用现有运行手册的日志控制。

Flutter 本地内存报告与 Rust stderr 是两个诊断层：前者记录 UI 操作与安全源码位置，后者提供传输阶段和原因分类。不得声称本地报告包含完整 Rust 错误链或自动收集系统日志。无法确认 DNS/TLS 具体原因时保留 connect/unknown，不要求用户关闭 TLS 进行验证。

macOS 的系统 network-outbound 拒绝等平台证据可以作为独立排障输入；禁止在普通报告中粘贴整段系统日志或个人页面。打包权限检查使用实际产物的 Sandbox/network.client 门禁，不能只看源码 entitlement。

## 开发规则

- UI 只使用 platform 的共享错误模板；app 的 UbaaErrorMapper 是兼容适配入口，不新增第二份策略。
- Bridge typed 错误使用穷尽枚举映射；兼容 JSON 只解析固定字段，未知路线归空。
- 旧 includeTechnicalDetail 参数为兼容保留，但不再把外部 message 当作“已脱敏”内容保留。新增诊断只能扩充允许字段，不增加原始字符串出口。
- 新错误场景先写从真实适配器或控制器到最终状态的失败测试，并检查原文不会进入 UI/日志/报告。
- 工程验收使用 `just check-strict`；普通 `just check` 显示 ShellCheck SKIP 时，不计为完整静态检查。
- 全量门禁、宿主 integration、本地回环和真实学校验证分别记账。当前真实 App/Core-live 仍暂停。
