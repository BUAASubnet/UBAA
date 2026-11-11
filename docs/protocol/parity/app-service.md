# 应用服务（遥测、更新与公告）

本文件收录应用服务遥测、更新、公告及统计开关的来源边界；这些都不是学校协议。

## 当前规则

### 应用服务（遥测、更新与公告）

2026-11-10 设计前核对了冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的以下文件：
- 服务端：`server/.../version/AppVersionService.kt`、`AppVersionRoutes.kt`、`announcement/AnnouncementService.kt` 和 `metrics/LoginMetrics.kt`；
- 客户端：`shared/.../api/auth/UpdateService.kt`、`AnnouncementService.kt` 和 `api/storage/AnnouncementReadStore.kt`。

实施接口检查时复核了旧版的 `AnnouncementRoutes.kt`、`AuthService.kt` 中的统计调用和更新、公告、统计测试。旧版只有中转服务器的版本与公告接口；活跃统计是中转服务器登录成功后的内部写入，不存在客户端批次或按安装 ID 删除接口。

固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/api.rs` 列出学校 API；其中 `api/app/{core,opt,data}.rs` 使用北航 App 的 CAS 和考试接口。`api/sso/auth.rs`、`api/user/auth.rs`、`request.rs`、`store/{cookies,cred}.rs` 和 `error.rs` 提供学校认证与请求支持。该提交没有 UBAA 客户端自身的更新、公告、遥测或删除操作。

应用服务是 UBAA 自己的 Cloudflare Worker。下表四项操作的学校 CAS 与 service、跳转与最终地址、Cookie/会话/Token、方法与参数、请求头与正文、加密与签名、DTO 与解析、缓存与重试、错误与产品语义均不适用；表中接口和行为均指 UBAA 应用服务。旧版只作为产品行为参考。决定见 [ADR 0008](../../adr/0008-app-service-worker.md)，行为见[应用服务合同](../../contracts/app-service.md)。

| 操作 | 旧版行为 | buaa-api | CAS/service、重定向、Cookie/会话、加密 | 方法、参数与 DTO | 缓存、并发、重试与错误 |
| --- | --- | --- | --- | --- | --- |
| 更新检查 | 中转服务器 `GET /api/v1/app/version?clientVersion=`，返回状态、单一下载地址和缓存的 Release 说明；客户端失败时返回 null | 不适用 | 不适用，不携带学校 Cookie | 新接口 `GET /v1/bootstrap`，按渠道返回版本与链接，增加最低可用版本 | Worker 缓存 300 秒；失败时静默；只有成功的响应才能改变门控 |
| 公告 | 服务器 `announcement.json` 单条公告；客户端按 ID 记录已读 | 不适用 | 不适用 | 并入 `GET /v1/bootstrap`，支持多条、定向和两级展示 | 已读状态只在本机；来源改为仓库 Markdown 同步到 KV |
| 活跃统计 | 登录成功后在服务端对学号做无密钥哈希，写入 Redis HyperLogLog，按窗口和路线计数 | 不适用 | 不适用；改为客户端加盐哈希，再由 Worker 做 HMAC | 新接口 `POST /v1/telemetry`，按天聚合，字段按白名单 | `batch_id` 去重；D1 精确去重；明细按保留期清理 |
| 删除统计 | 无按安装 ID 删除操作 | 不适用 | 不适用 | 新接口 `POST /v1/telemetry/erase`，只接收合同版本与安装 ID | 幂等；用墓碑阻止晚到批次重新写入 |


更新门控在学校传输前检查安装级许可和最低版本。两个冻结来源都没有这个跨功能门控。门控不修改认证、自动恢复、读取、写入和流式传输各自已登记的 CAS/service、重定向、凭据、请求编码、解析、缓存与重试约定。拒绝发生在校园网探测或学校请求交付前，返回不可重试的 `update_required`；写协调器不登记发送，本机退出、缓存、日程与导出继续可用。具体操作的上游对照继续使用本索引中各功能已有的记录。

评教批次与读取沿用[评教逐操作对照](write-actions.md#ubaa2-直接写操作与评教2026-08-28)，研讨室活动类型、阳光打卡概览、SPOC 课程补充与认证回查、Judge 认证回查分别沿用[场馆对照](cgyy.md#场馆预约只读查询)、[阳光打卡只读查询](ygdk.md#阳光打卡只读查询)、[SPOC 列表](coursework.md#spoc-列表)、[SPOC 认证](coursework.md#spoc-认证)和 [Judge 批量与缓存](coursework.md#judge-批量与缓存)。这些操作的可选数据回退不吞掉本机更新拒绝。评教批次已经交付写入后，保留已确认结果，遇到门控后停止并将剩余课程标记为未尝试。

应用服务客户端收到 `410` 时，只将合同机器码 `install_erased` 视为已删除；其他 `410` 保留原批次重试。手动删除记入 GUI 与命令模式共享的最近交付时间；用户可以立即手动重试，自动前台与命令模式继续使用六小时间隔。定时任务按校园日汇总 D1 并清理明细，不请求学校。主动刷新若复用写后核对的在途读取，仍收到同一次门控拒绝提示；自动核对保持静默，学校读取协议不变。本地 HTTP 与 D1 结果见[应用服务验收对照](../../archive/evidence/app-service-acceptance-2026-11-11.md#应用服务验收对照2026-11-11)。

复审后的本机协调仍使用上表的操作边界：读取门控失败时放行本次学校请求并保留门控记录，GUI 定期复查共享状态，Core 继续按最近尝试时间节流上传、删除和启动配置。旧版 `AnnouncementRoutes.kt` 与服务端 `AnnouncementService.kt` 只读取单条公告且没有版本筛选，固定 buaa-api 没有对应操作。公告上限缺省构建号时包含同版全部构建，沿用原启动配置的请求、响应字段和缓存规则。

## 专项记录

### 统计开关与实际客户端能力对照

2026-09-15，实施前记录。基线为 `a85d111cf5552ae4a1580e677caa1b32f20d6ae4`。本项是设置页状态误报，不涉及学校协议或新增统计服务。

#### 当前缺陷与失败证据

`packages/ubaa_host/lib/src/ubaa_app_host.dart` 的生产 `bootstrapUbaaHost` 没有注入统计客户端；`lifecycle.dart` 将空值传给 `AppController`。后者默认使用 `NoopTelemetryClient`，该实现的 `enabled` 恒为false，`track`为空操作。但 `AppController.setTelemetryEnabled(true)` 无条件把自己的布尔值改为true，设置页因此显示“匿名产品改进统计”已开启。

独立探针只注入 `UnavailableBackend` 和 `NoopTelemetryClient`，不初始化认证或请求网络。调用公开开关方法后，预期状态仍为关闭，实际为true，成功编译后的断言失败。精确命令：

```sh
just flutter test '<private-evidence>/macos-ui-20260915/telemetry-control/disabled_client_probe_test.dart' --no-pub --reporter expanded
```

运行目录为专项工作区的 `packages/ubaa_app`，退出1，日志为同私有目录下 `disabled-client-probe-red.log`。探针文件不进入Git，正式修复仍须添加正式行为回归。现有Host回调测试只断言开关布尔值变化，没有证明任何统计事件被记录，不能作为功能已经生效的证据。

#### 来源与边界

冻结旧版 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 的 `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/SettingsScreen.kt` 只提供连接模式选择及确认取消，没有统计开关或统计服务。冻结示例 `efb7976bf513f38364b88aeb83d704586cff9b2a` 的 `src` 未发现统计/遥测实现；不能从业务课程统计接口类推产品遥测。

现项目 `packages/ubaa_platform/lib/src/telemetry.dart` 明确默认Noop；只有显式配置的客户端才处理白名单事件。`docs/runbooks/local-diagnostics.md` 规定统计是可选能力，失败不影响业务。当前 `SET-05` 的要求是默认和声明一致，不是必须引入新的远端服务。

| 来源或操作 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 冻结旧版设置页 | 无统计操作 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 无统计开关状态 | 不适用 | 不适用 |
| 冻结示例 | 无对应产品遥测实现 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 |
| 本次统计开关 | 不增加上游操作 | 不适用 | 不读取或改变账号/会话 | 沿既有可选客户端，不新增URL或接收端 | 仅沿现有事件/字段白名单 | 不增加 | 区分当前可用能力与用户开关状态；Noop不能报告开启 | 关闭后不再产生新事件；重新开启只对已配置可用客户端生效 | 不可用给明确说明；统计错误不覆盖登录、读取或提交结果 |

#### 实施决定

1. 无实际可用统计客户端时，生产设置开关应保持关闭、不可误报开启，并说明此版本未启用统计功能。不能通过注入演示客户端或凭空增加远端收集服务来制造“正常工作”。
2. 已显式注入可用客户端时，保留真正的开启/关闭能力，并用合成事件验证关闭后不记录、重新开启后恢复。能力和用户选择分别处理，不因关闭把原可用能力永久丢失。
3. 不新增外部统计SDK、网络接收端、持久化或权限；不改变LocalDiagnostics与字段白名单，不记录账号、凭据、课程内容、照片或敏感显示数据。CLI、Bridge、Session和配置版本均不变。
4. 本批在其他生产功能修复之后、合成CUA入口冻结之前串行实施，独立审查。当前只是来源及RED已确认，尚未修复，实际设置按钮仍待最终CUA验收。


#### 2026-10-02接续实施

当前固定旧版`1f4b8f84`和示例`a63712fa`相较本记录来源均未新增统计设置或改变以上模块。App与Host各新增行为测试并成功编译后按预期失败：Noop开启后布尔值为true、生产设置回调非空。修复只将已配置客户端能力传到共享设置页，Noop保持关闭和不可操作并明确说明；已配置客户端仍在协调器边界关闭/再开启，测试核对真实合成白名单事件数量。无新网络、SDK或发送目标，LocalDiagnostics保持原样。
