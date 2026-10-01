# 统计开关与实际客户端能力对照

2026-09-15，实施前记录。基线为 `a85d111cf5552ae4a1580e677caa1b32f20d6ae4`。本项是设置页状态误报，不涉及学校协议或新增统计服务。

## 当前缺陷与失败证据

`packages/ubaa_host/lib/src/ubaa_app_host.dart` 的生产 `bootstrapUbaaHost` 没有注入统计客户端；`lifecycle.dart` 将空值传给 `AppController`。后者默认使用 `NoopTelemetryClient`，该实现的 `enabled` 恒为false，`track`为空操作。但 `AppController.setTelemetryEnabled(true)` 无条件把自己的布尔值改为true，设置页因此显示“匿名产品改进统计”已开启。

独立探针只注入 `UnavailableBackend` 和 `NoopTelemetryClient`，不初始化认证或请求网络。调用公开开关方法后，预期状态仍为关闭，实际为true，成功编译后的断言失败。精确命令：

```sh
/Users/moorefoss/Dev/flutter-3.41.9/bin/flutter test '/Users/moorefoss/Library/Application Support/UBAA-private-evidence/macos-ui-20260915/telemetry-control/disabled_client_probe_test.dart' --no-pub --reporter expanded
```

运行目录为专项工作区的 `packages/ubaa_app`，退出1，日志为同私有目录下 `disabled-client-probe-red.log`。探针文件不进入Git，正式修复仍须添加正式行为回归。现有Host回调测试只断言开关布尔值变化，没有证明任何统计事件被记录，不能作为功能已经生效的证据。

## 来源与边界

冻结旧版 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 的 `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/SettingsScreen.kt` 只提供连接模式选择及确认取消，没有统计开关或统计服务。冻结示例 `efb7976bf513f38364b88aeb83d704586cff9b2a` 的 `src` 未发现统计/遥测实现；不能从业务课程统计接口类推产品遥测。

现项目 `packages/ubaa_platform/lib/src/telemetry.dart` 明确默认Noop；只有显式配置的客户端才处理白名单事件。`docs/runbooks/local-diagnostics.md` 规定统计是可选能力，失败不影响业务。当前 `SET-05` 的要求是默认和声明一致，不是必须引入新的远端服务。

| 来源或操作 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 冻结旧版设置页 | 无统计操作 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 无统计开关状态 | 不适用 | 不适用 |
| 冻结示例 | 无对应产品遥测实现 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 |
| 本次统计开关 | 不增加上游操作 | 不适用 | 不读取或改变账号/会话 | 沿既有可选客户端，不新增URL或接收端 | 仅沿现有事件/字段白名单 | 不增加 | 区分当前可用能力与用户开关状态；Noop不能报告开启 | 关闭后不再产生新事件；重新开启只对已配置可用客户端生效 | 不可用给明确说明；统计错误不覆盖登录、读取或提交结果 |

## 实施决定

1. 无实际可用统计客户端时，生产设置开关应保持关闭、不可误报开启，并说明此版本未启用统计功能。不能通过注入演示客户端或凭空增加远端收集服务来制造“正常工作”。
2. 已显式注入可用客户端时，保留真正的开启/关闭能力，并用合成事件验证关闭后不记录、重新开启后恢复。能力和用户选择分别处理，不因关闭把原可用能力永久丢失。
3. 不新增外部统计SDK、网络接收端、持久化或权限；不改变LocalDiagnostics与字段白名单，不记录账号、凭据、课程内容、照片或敏感显示数据。CLI、Bridge、Session和配置版本均不变。
4. 本批在其他生产功能修复之后、合成CUA入口冻结之前串行实施，独立审查。当前只是来源及RED已确认，尚未修复，实际设置按钮仍待最终CUA验收。


## 2026-10-02接续实施

当前固定旧版`1f4b8f84`和示例`a63712fa`相较本记录来源均未新增统计设置或改变以上模块。App与Host各新增行为测试并成功编译后按预期失败：Noop开启后布尔值为true、生产设置回调非空。修复只将已配置客户端能力传到共享设置页，Noop保持关闭和不可操作并明确说明；已配置客户端仍在协调器边界关闭/再开启，测试核对真实合成白名单事件数量。无新网络、SDK或发送目标，LocalDiagnostics保持原样。
