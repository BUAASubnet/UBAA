# 应用服务验收对照（2026-11-11）

本页记录应用服务工程验收时，[应用服务合同第 13 节](../../contracts/app-service.md#13-验收)各场景对应的测试与观察，供复核验收范围时查阅。生产部署未在这次验收范围内。

Core 与宿主使用合成账号及学校 transport 替身；Worker 测试使用本地 Workers 运行时。显式联调另用回环 HTTP、实际 Rust 与 Dart FFI、隔离配置目录和 D1/KV。界面运行证据为手机、宽屏和深色布局的 Widget 树渲染，存于 `.ubaa_local/app_service/ui_evidence/`。

| 层 | 测试与观察 |
| --- | --- |
| Core | `app_service::tests` 与 `app_service::queue::tests` 覆盖同意转换、可用性和硬关闭、批次的组合数/数组长度/正文上限、重发、总容量和七天过期、门控设置解除、响应向前兼容、合成账号派生与年级。`transport` 测试断言无 Cookie 和不跟随跳转；本地 HTTP 另核对请求头及拒绝不受信任的 TLS 证书。 |
| Bridge / Dart | Bridge API 测试、控制器生命周期与遥测测试、宿主 `settings/telemetry_test.dart` 和 UI `app/app_service_test.dart` 覆盖白名单、开关和删除、首启、政策升级、基础模式、Noop、设置提示、更新横幅、主动请求提示及公告已读。Widget 运行证据覆盖隐私全文、删除待重试、更新提示和弹窗公告。 |
| Worker | `schema`、`worker_requests`、`worker_storage`、`telemetry`、`bootstrap`、`version` 和 `aggregate` 测试覆盖 Schema 正反例、未知字段拒绝、批次去重、限流、删除、汇总清理和漏跑补算，以及渠道和公告过滤、预发布版本排序。 |
| 仓库检查 | `app-service-check` 核对 Schema `feature` / `error_kind`，`privacy-policy-check` 核对正文摘要、版本、变更要点和嵌入生成物。各门禁均有输入不一致的失败用例。 |
| 端到端 | `just app-service-e2e`：启动配置、门控与公告已读的 D1 写入为零；首次上报落库，丢响应重发不增加计数；关闭后旧批次不再发送；删除写入墓碑并清空四类明细；晚到上报、基础模式命令和重启后的额外上报均无写入。 |

| 合同场景 | 专门测试与观察 |
| --- | --- |
| 关闭统计后接受新版政策 | Core 状态与宿主政策升版测试：保留关闭值，待发队列为空，没有遥测请求。 |
| 收到更新要求后撤回同意 | Core `update_gate_tests.rs`：撤回前学校 transport 和探测均未调用，撤回后合成学校 transport 收到请求。 |
| 重新同意时立即刷新门控 | Dart 生命周期测试断言立即强制刷新；Core `bootstrap` 测试覆盖成功解除、刷新失败和未知状态保留。 |
| 删除先提交，旧上报之后到达 | 本地 HTTP 中继等另一进程的删除提交后才转发旧批次；旧请求收到 410，D1 四类明细均为空，去重行不增加。Worker 测试另覆盖预查和事务之间发生删除。 |
| 删除结果未知后重启 | Core 子进程与真实 Bridge 两次 Flutter 进程核对共享删除标记；先重试删除，成功前不再上报。 |
| 校园午夜后复用会话 | Core `sqlite` 的校园午夜用例：使用同一已确认账号，无需重新登录，两个校园日各有同一用户及年级登记。 |
| 同日升级，旧版本批次晚到 | Core `app_service_daily_account_limit_survives_version_changes_and_confirmation` 核对多个版本只占一个账号名额；Worker 用新、旧版本顺序写入，两个版本的 `active_days` 行均保留。 |
| 关闭时有 503 重试批次，再开启 | Core 状态测试和真实 Bridge 503 联调：关闭清除冻结批次，重新开启并强制上传没有新请求，D1 保持原计数。 |
| 删除尚未定稿的设备 | Worker `aggregate` 删除用例：重算后未定稿的日表、月表移除对应数据，已定稿结果不变。 |
| 同一用户当天使用两个平台 | Worker `aggregate` 去重用例：`all` 为 1，两个平台分组各为 1。 |
| 第七天晚间及月底迟到 | Worker `aggregate` 月末用例：上报计入对应日表和上月月表，八日运行后定稿。 |
| 离线八天，产生九个日期与版本组合 | Core `app_service_splits_nine_date_versions_without_losing_counts` 保留全部计数；Worker 用例中未拆分请求被拒绝且 D1 无写入，按八加一拆分后两个请求均为 204，九组均落库。 |
| 上报预发布版本 `2.1.0-rc.1+15` | 本地 HTTP 实际上报并落库；Rust 与 Worker 共同读取版本排序样例，符合合同的两个比较示例。 |
| 同一批次并发重发 | Worker `worker_storage` 的并发请求均返回 204，三类计数各只累加一次。 |
| 删除成功后收到晚到的 503 | Core `upload` 测试用请求屏障和第二个 SQLite 连接完成删除；收到 503 后旧批次不复活，新安装 ID 下无旧数据。 |
| 基础模式重启 GUI，同时运行命令 | Core 独立子进程与 Bridge 本地 HTTP 联调：GUI 只重试删除，命令模式没有应用服务请求，D1 只增加墓碑并清理旧明细。 |
| 配置响应含未知字段和枚举 | Core `bootstrap` 向前兼容样例：已知字段仍生效，未知更新状态保留门控，仅丢弃无效公告。 |
| 主动刷新与自动刷新遇到门控 | Dart 生命周期测试区分主动与自动提示，覆盖主动下拉加入写后自动核对；Core `update_gate_tests.rs` 断言学校 transport 无调用，本地缓存、日程和导出有实际结果。UI 测试验证横幅及提示弹窗。 |
| 漏跑一天且有第七天迟到数据 | Worker `aggregate` 漏跑用例扩大重算窗口，迟到数据进入日表，旧触发不倒退成功日期。 |
| 无法读版本或非 Release 非回环地址 | Core 构建期配置与上传测试断言完全停用，不发送启动配置、上传或删除请求。 |
