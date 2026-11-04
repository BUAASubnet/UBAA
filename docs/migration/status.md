# 当前实现与验证状态

更新：2026-11-05。开发执行已恢复，当前产品交付为[日程界面](../design/agenda.md)，范围见[当前目标](../../goal.md)。主监督组织执行会话完成实现、验证、审查和整合，随后继续已确定的后续交付。本页区分已进入主线的功能、尚未整合的候选和验证缺口。

## 主线与候选

本次核对的功能基线为 `ubaa2` 在整理前的 `9d7fcbdd`，提交日期为 2026-11-01。该提交相对本地 `origin/ubaa2` 跟踪引用领先 42 个提交，未联网更新远端引用。主目录保留 10 个跟踪文件修改和 3 个未跟踪 CLI 实验，文件清单与原交接一致。

| 范围 | 已有实现与结果 | 当前边界 |
|---|---|---|
| 校园基础功能 | Core、CLI、Bridge 与 Flutter 已接入认证、课表、考试、成绩、作业、签到、图书馆、博雅、研讨室、评教和阳光打卡等能力，详见[功能矩阵](full-feature-matrix.md) | 当前 App 真实账号完整流程、各平台设备及发布验收仍有缺口 |
| 日程基础 | Core 自建事项、重复展开、逐记录明文 SQLite、学校投影、本地覆盖、Bridge/Dart 服务、首页统一投影和 Core `.ics` 范围快照已在主线 | 专用日程页面、编辑交互及导出文件尚未接通 |
| 共享账号与恢复 | `codex/h1b3` / `05666699` 包含共同恢复、共享索引和持久代次、客户端继任、关闭与退出实现；前置单元曾分别放行 | 未合入主线，最终生命周期候选存在下节三个阻塞，整体未放行 |
| 公共命令库 | `codex/h2-common-a` / `e976d1f4` 已提取 Rust 命令定义、计划、输入与输出边界，修复输入顺序后本地验收及复审通过 | 尚未接通正式 App 命令运行时 |
| Windows 工具链 | `codex/windows-build-config` / `5126d69a` 包含公共命令库及工具入口、字符集、锁定版本与主机选择修复，已有本地验收及复审 | 未合入主线；Debug 构建和插件结果不包含新命令宿主 |
| 北航云盘 | 全部 25 项业务操作及登录的来源对照和合同已建立 | 生产认证、读写、传输与界面尚未实现 |
| 日程同步 | 已确定复用网盘接口与明文 `UBAA/agenda.json` | 同步尚未实现，同名更新和并发覆盖仍缺协议证据 |

Windows 候选已经包含公共命令库候选，后续整合不需要重复迁入。功能基线 `9d7fcbdd` 是 H1 和 Windows 两个候选的共同祖先之一。各候选独立通过的结果只属于相应提交。

## 统一 App 命令模式候选

`codex/command-delivery` 从 `6d0e241d` 整合共享服务候选 `05666699` 和 Windows/公共命令候选 `5126d69a`，在独立工作树中交付统一命令链路，尚未整合回主线。

- Core 路线重开保留共享账号绑定与关闭控制，等待材料锁后重新检查关闭、取消和期限。正式回归覆盖三个原有阻塞。
- 公共 Rust 命令库保留 CLI JSON schema v13，Flutter bridge contract v48 提供计划、输入、执行、身份交付与有界输出。Dart 复用共享账号及恢复服务，只读命令最多完整重跑一次，学校写入只在准备资格前恢复。
- 本机日程支持新建、重复范围编辑与删除、完成、本地覆盖、数量比较清除和原子 `.ics` 文件交付。编辑排除日期将随日程界面的 `edit_draft` 接口统一接入。
- macOS 无窗口 Engine 与 Linux AOT 已有隔离合成材料的原生进程证据。Linux Secret Service 适配保留原插件的 schema、account、JSON item 与材料键，双向互通及锁定拒绝通过。
- 旧独立 Rust 宿主和材料 worker 已迁出，`core-live` 保留在 `tools/core_live`。有效覆盖去向见[测试策略](../development/testing.md)。Windows 新命令宿主尚未原生验证，完整退役验收仍有缺口。

当前证据限于合成材料、固定路线和 Mock。Windows 主机暂不可连接；macOS 真实旧材料连续性、签名 Release、Linux 实际 SSH/PAM 与其他架构尚未验证。完整确定性验收结果随候选提交记录。

## 原共享服务候选的问题

两路 2026-11-02 审查的重复问题合并后共三项，原候选为 `05666699`：

1. 路线重开丢失固定共享账号绑定。外部撤销后，新 Core 仍可能使用旧会话，失去实际访问与发送边界的共享版本检查。
2. 路线重开后，普通 `dispose` 仍使用首次 Core 的关闭控制。当前 Core 和在途操作无法及时收到关闭状态。
3. 发送前等待材料锁后没有重新检查消费者关闭状态。既有合成反例观察到关闭后仍交付一次 transport，并返回 `OutcomeUnknown`。

前两项在 Bridge/App 审查中列为 P1，第三项在 Core 审查中列为 P2。统一命令候选已包含针对性修复与正式回归，整合前仍须核对相关验收和复审。日程 GUI 可先复用主线既有服务，不以合入该候选为前提。

现有私有依据位于 `.ubaa_local/supervision/development_followup/` 的 `review_h1b3b_core_20261102.md`、`review_h1b3b_app_bridge_20261102.md` 和 `integration_preparation_20261102.md`。暂停与候选交接见同目录 `takeover_20261102.json`。这些本机材料用于追溯，不是可移植的发布证据。

## 主线能力与合同

- Rust Core 统一拥有学校协议、Direct/WebVPN/Auto 路线、会话、校园读写与加密缓存。宿主通过 facade 或专用 Bridge 使用 Core。
- 功能基线合同版本为 CLI JSON schema v13、Flutter bridge contract v45；Session v2、配置 v1、业务缓存 v7、日程 v2 分别管理。H1 候选 Bridge 已推进至 v47，尚未整合。
- 日程每个事项和覆盖记录单独存储，按账号隔离，退出后保留，同账号重新登录后激活。缓存清理不删除日程，缓存密钥缺失不阻止本机日程操作。
- 首页七类学校待办复用 Core 投影。学校本地标记保留原上游状态，不生成学校写资格。路线切换投影修复已放行至 `8075e64d`，Core 导出修复已放行至 `de797fce`。
- 当前底栏仍为首页、课程、学业、校园、我的。目标导航为首页、学习、日程、校园、我的，具体交互见[日程设计](../design/agenda.md)。
- 门户身份、账户指标和流量已有 Core/CLI/Bridge 与“我的”页实现；历史 Core Direct/WebVPN 验证通过，App 真实账号读取仍待单独验收。
- 各平台标识统一为 `cn.edu.ubaa`。macOS 最低版本为 12.0，iOS 为 15.0；签名配置见[签名手册](../runbooks/app-signing.md)。

## 验证与未解决事项

| 对象 | 已有证据 | 尚未覆盖或需要处理 |
|---|---|---|
| 主线日程 | 2026-11-01 导出修复以 `ac213756` 为基线完成完整相关检查，退出 0；包括 Core/CLI、Flutter、macOS 原生及 FRB 零漂移 | 日程 GUI 与实际文件保存尚未实现，不能据此宣布完整日程可用 |
| 共享服务候选 | 已有 Rust、Flutter、macOS Native 与 FRB 分段通过记录及独立审查 | 原 `full/full2/full3` 均退出 1；后续差异补验未覆盖上述三个缺陷，整体阻断 |
| 公共命令库及 Windows 工具链 | 各自候选有完整本地验收和复审，Windows 有 Debug 构建与插件结果 | 新 App 命令入口、合并候选、完整终端和安装行为尚未验收 |
| Windows Agenda | 2026-11-02 已记录两项 Core 测试在删除目录时报 Win32 32，独立重跑仍失败 | 整合候选是否仍存在句柄占用问题待验证 |
| Linux SSH | H0 Debian 12 arm64 容器中 Dart AOT→FRB→Rust 日程及合成 libsecret 材料试验通过 | 正式材料适配、部署、安装与其他架构未完成 |
| 移动端与 OHOS | 历史 iOS simulator、Android Debug、macOS Debug、OHOS 分析与无签名 Debug HAP 构建，以及 OHOS 模拟器合成 HUKS 流程通过 | 当前候选实体设备、真实账号、异常恢复与发布验收未完成 |
| 签名与版本 | Android 曾构建并校验签名 Release APK | 未安装运行或对照旧正式包；OHOS `1.0.0/1000000` 与 Flutter `0.1.0+1` 仍需发布前统一核对 |
| 远端与发布 | 本地提交与历史本机证据保留 | 本轮无推送、远端 CI、签名或发布验收 |

H1 原生合成退出测试曾进入生产 SSO logout 路径，历史材料无法确认请求是否发送或到达学校，未为补证重放。后续隔离测试的结果与该事件分别保留。

原生登录至查询、连续业务导航与写操作、软键盘、真实账号恢复/性能及部分设备通道的自动化缺口继续见[测试策略](../development/testing.md)与[原生删减登记](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)。现有分层测试不替代这些设备证据。

## 历史验证入口

2026-11-01 的完整状态快照保留在 Git 对象 `9d7fcbdd:docs/migration/status.md`，包含当时的实现细节、逐次计数与验证路径。

日程 Core 导出、首页投影和存储的具体通过记录保留于对应提交及 `.ubaa_local/agenda_1d_export_fix/`、`.ubaa_local/agenda_1c_b_route_fence/`、`.ubaa_local/agenda_plaintext/`。旧 CLI-a 验收仅属于旧方案，不能继承为新命令模式通过。

更早的工程、Core 精简与签名记录见[状态流水](history/2026-10-30-status-log-through-signing.md)、[Core 精简](2026-10-30-core-simplification.md)和[决策记录](decision-log.md)。历史真实学校结果只适用于对应候选和路线。
