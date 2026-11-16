# 本地错误定位与诊断

本手册供处理用户报错的维护者和新增错误场景的开发者使用，说明用户如何提供诊断信息、维护者如何据此定位问题，以及诊断功能的开发规则。

## 何时使用

- 用户报告登录、读取或提交失败，并提供了错误编号或诊断报告。
- 需要判断失败发生在哪一层（UI、应用层、Bridge、Core 或网络传输）。
- 新增或修改错误场景、诊断字段。

## 前提

用户获取诊断信息的方式：

- 在错误卡、行内提示或写入提示打开“错误详情”，选择“分享报告文件”或“保存报告文件”。报告对应当前错误和关联记录。记录过期后仍可复制或导出当前错误的安全摘要，`record_available=false` 表示历史记录已不可用。
- 登录页和启动失败页通过“查看诊断信息”打开报告。进入主页后，在“我的 → 诊断信息”查看当前及历史记录。
- Android、iOS、HarmonyOS 和 macOS 打开系统分享面板。Windows 和 Linux 提供“保存报告文件”。打开分享面板或保存到本机不会发送报告。选择“前往反馈”可打开项目的 [GitHub Issues](https://github.com/BUAASubnet/UBAA/issues)，用户自行创建 Issue 并附上检查过的报告。

诊断的边界：

- 复制、分享和保存均由用户主动操作。完整报告不会自动上传。
- 分享附件使用 UTF-8 JSON，文件名为 `UBAA-report-<时间戳>.json`。系统缓存中的分享附件在后续分享时清理七天前的文件，已交付给接收方的文件由接收方管理。
- 报告保留本次运行及此前七天内最近 100 项错误。宿主将安全字段保存到本机偏好存储，重启后通过 `previous_events` 导出历史记录。启动失败记录能取得的平台和应用版本（含构建号），并以 `initialization_stage` 区分 SDK、Bridge 校验、平台能力、后端打开、应用装配和会话恢复阶段。
- 不读取凭据、会话文件、账号资料或业务输入，也不保存 HTTP 正文、完整 URL、Cookie、照片和位置。
- 报告使用独立的 `schema_version=3`，这是本地诊断格式的版本，与 CLI 和 Bridge 合同版本无关。

## 步骤

1. 用错误编号关联本次运行的报告，查看 `operation`、`code`、`kind`、`route`、`feature`、`cause` 和 `source`。需要定位提交时查看 `write_operation`；云打印批量报告用 `file_index` 表示从 1 开始的文件序号，不含文件名。
2. `source` 只含允许的 UBAA package 源码位置，最多三项，不含本机绝对路径或完整堆栈。没有安全源码位置时不猜测。
3. 按阶段定位代码：

   | 阶段 | 查看 |
   |---|---|
   | 初始化、登录、路线切换 | app/controller |
   | 读取 | 对应的 bridge/read 与 Core feature |
   | 写入准备、提交、丢弃 | WriteCoordinator |
   | 回读 | ReceiptVerifier 和对应的 controller/readback |

4. 需要传输层证据时，按下文的“Rust 传输补充证据”取得 stderr 诊断。

解读报告时：

- `retryable=false` 必须保留。`outcome_unknown` 始终先核对状态，不能用通用重试入口重复提交。
- 报告中的失败路线来自本次错误，不是默认策略或上次成功的快照。
- `business_rejected` 表示学校服务按已知格式拒绝业务操作；`parse_error` 表示响应无法解析；`upstream_changed` 表示响应结构与已验证格式不符。HTTP 403 只说明学校服务拒绝访问，HTTP 429 标记为 `http_rate_limited`。

## Rust 传输补充证据

具体 HTTP 适配器的 `ubaa::transport` tracing 事件只包含固定阶段、保守的原因分类和耗时：

- 发送、响应读取和响应超出预算分别记录。
- 分类只依据稳定的 Reqwest 判断和最多八层标准 I/O 错误链，不格式化原始错误，不记录请求或响应数据。

两种宿主的输出方式：

- 生产 Bridge 初始化时安装一个 stderr 日志订阅器，只接收该安全 target 的 DEBUG 四字段事件；宿主已有全局订阅器时不覆盖。它不读取 `RUST_LOG` 放宽过滤，也不启用第三方详细日志。
- CLI 默认不输出这些事件，保持 JSON 命令的安静错误输出。排障时显式设置 `RUST_LOG=ubaa::transport=debug`。

Flutter 本地报告与 Rust stderr 是两个诊断层：前者记录 UI 操作与安全源码位置，后者提供传输阶段和原因分类。本地报告不包含完整的 Rust 错误链，也不自动收集系统日志。

## 验证

- 定位结论应能对应到报告中的 `code`、`kind` 和 `source`，以及必要时的传输阶段分类。
- 本地诊断不改变业务结果。可选遥测异步执行且有两秒截止预算，异常只记录到本地，不会把登录、读取或提交改成失败。
- 过期读取和已销毁控制器的迟到结果不进入当前页面的诊断。

## 故障处理

- 无法确认 DNS/TLS 的具体原因时保留 `connect`/`unknown`，不要求用户关闭 TLS 进行验证。
- macOS 系统的 network-outbound 拒绝等平台证据可以作为独立排障输入；不在普通报告中粘贴整段系统日志或个人页面。
- 打包权限问题使用实际产物的 Sandbox/network.client 检查（`just flutter-artifact-check`），不能只看源码 entitlement。

## 开发规则

- UI 只使用 platform 的共享错误模板；app 的 `UbaaErrorMapper` 是兼容适配入口，不新增第二份策略。
- Bridge typed 错误使用穷尽枚举映射；兼容 JSON 只解析固定字段，未知路线归空。
- 旧的 `includeTechnicalDetail` 参数只为兼容保留，不再把外部 message 当作“已脱敏”内容保留。新增诊断只能扩充允许字段，不增加原始字符串出口。
- 新错误场景先写从真实适配器或控制器到最终状态的失败测试，并检查原文不会进入 UI、日志或报告。
- 检查按[检查选择与完成条件](../development/commands.md#检查选择与完成条件)执行，日志字段按[日志与诊断脱敏](../development/conventions.md#日志与诊断脱敏)处理。
- 全量门禁、宿主 integration、本地回环和真实学校验证的结果分别记录。真实 App 与 Core-live 按 [AGENTS 授权规则](../../AGENTS.md#真实账号与验收范围)运行。

## 结构化错误上下文

`diagnostic` 保留 Core 源码位置、失败阶段和原因。响应诊断包含 HTTP 状态、响应长度与类别、允许字段的 JSON 类型及解析行列。博雅业务拒绝可携带已确认无个人数据的固定上游提示，未知正文不自动共享。

允许统计时，读取和写入按操作结果计数，同时上报通过校验的诊断字段，界面展示不重复计数。完整报告和本地错误编号不上传。服务端 `error_samples` 与错误计数分开存储，每个安装、日期、版本和错误维度保留最新样本，14 天后清理，安装级删除同时删除样本。先部署识别新事件的服务端，再发布客户端。

在[维护者错误看板](app-service.md#使用情况看板)选择版本、功能、路线和错误码，查看失败次数以及样本中的源码、阶段、原因、HTTP 状态和业务码。也可在受限数据库会话中查询最近的样本：

```sql
SELECT day, app_version, feature, route, error_code,
       diagnostic->>'source' AS core_source,
       diagnostic->>'stage' AS stage,
       diagnostic->>'reason' AS reason,
       diagnostic->>'status' AS http_status,
       diagnostic->>'upstream_code' AS upstream_code
FROM error_samples
ORDER BY day DESC
LIMIT 20;
```

同一错误的计数仍从 `error_days` 或 `error_daily` 查询，样本条数不等于失败次数。
