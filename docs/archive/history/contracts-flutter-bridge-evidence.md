# Flutter Bridge 合同的 P1 实施证据（截至 2026-09-05）

本页是从 [Flutter Bridge 合同](../../contracts/flutter-bridge.md) 移出的历史验收记录，保留当时的提交、测试与阶段叙述，不代表当前状态。当前状态见[项目现状](../../project/status.md)。

## 原 P1 勾选条件

P1 只有全部方法、DTO、写 intent、测试与生成绑定同时完成后才能勾选；只有合同文件或部分方法不能标记 P1 完成。

## 原第 9 节：历史 P1 与实现证据

- 提交 `2faa753` 实现 `BridgeClient` opaque 生命周期、认证、路线设置、全部表中读取方法、
  typed 写入准备/一次性提交和安全错误投影；Core 新增仅用于准备阶段的路线解析入口。
- `just flutter-codegen-check` 在该提交后再次生成并报告“FRB 生成零漂移”；生成的 Rust/Dart
  文件由 FRB 机械产出，未手工改写生成内容。
- `cargo fmt --all`、bridge 严格 Clippy、bridge 测试（4 项）和 `just check` 均通过；测试覆盖
  相对路径拒绝、幂等 dispose、use-after-dispose、随机 intent/digest 形状以及未知/重复 intent
  在网络前拒绝。
- 生产 Flutter 适配提交 `7bd8fd2` 通过 `BridgeBackend` 连接上述 API，并保留显式
  `UnavailableBackend` 安全失败；生产入口不再默认构造测试支持包中的脱敏后端。
- 读取结果中的 `RouteDecision.resolvedRoute` 现在沿 `FeatureResult`、`FeatureSnapshot` 和
  `BridgeBackend` 传到卡片与详情页；页面显示“实际路线”，不会把 `defaultPolicy` 冒充为本次
  请求路线。app/widget 回归测试固定该投影，刷新失败的 `stale` 数据继续保留上次实际路线。
- 应用层现在通过受限的 `RouteSettingsBackend` 读取 `defaultPolicy` 与 `activeRoutes`；切换
  固定路线后若目标槽位未认证，会清除用户与功能快照并回到登录页，避免继续展示旧路线数据。
  生产 bridge 仍由 Core 完成原子保存、重开和 intent 失效，Dart 不读取 Session 内容。
- 应用启动时先读取同一投影恢复 Core 已保存的 `defaultPolicy`，再检查认证状态；因此设置页不会
  把 `auto` 默认值误显示为持久化的固定路线。
- `AppController.rebuildBackend()` 为 isolate/宿主生命周期重建提供显式安全入口：只有新
  backend 创建成功后才释放旧实例，清空旧用户、路线投影和功能快照，再重新执行初始化；没有
  `BackendFactory` 或正在登录/重建时返回失败，不伪造恢复成功。
- panic 归约、跨进程 Session 锁、路线/会话失效 intent 和研讨室订单敏感字段禁曝快照已有实现与
  回归；Dart schema 快照覆盖全部公开读取 DTO 和十项写入口，应用层已有 dispose、后台恢复和
  代次丢弃的确定性测试，`just flutter-codegen-check` 报告零漂移。上述代码/合同门禁满足当时的
  无签名 P1；原生设备上的 isolate 重建、内存泄漏观测和真实跨平台生命周期仍留待后置设备验证。
- Phase 11I 提交已经闭合 Ygdk typed authority/request、Core expected-route 原子提交入口、
  owner/session/credential generation guard、caller-pinned overview/records 方法，以及 CLI JSON schema v9、
  Flutter Bridge contract v8 和相应生成类型。安全收据已严格收窄为 `{recordId}`，公开字段禁曝；完整
  Rust/CLI/Bridge/Dart/Flutter 门禁、FRB 零漂移、macOS 脱敏宿主 integration 与独立终审均已通过并提交为
  `d8484ad`。该阶段没有联网、上传照片或执行真实写入，也不构成签名、实体设备或正式发布证据。
- Phase 11J 提交 `4b0dcb0` 已升级到 CLI JSON schema v10、Flutter Bridge contract v9，并实现 Evaluation
  typed target、批量四态结果和 caller-pinned 回读；本地确定性门禁、FRB 零漂移与 macOS 脱敏宿主
  integration 已完成。该阶段没有执行真实评教写入，证据范围见[当前状态](../../project/status.md)。
- Phase 11K 提交 `b6ff2c7` 将 Dart 写状态收归 `WriteCoordinator`，状态模型归 `ubaa_domain`，
  backend 绑定与会话失效归 `AppController`，宿主装配及 UI 状态/命令接线归 `ubaa_host`；安全结果消息与
  只读核对由应用层 `WriteReceiptVerifier` 统一编排。该阶段保持 CLI schema v10、bridge v9 和生成绑定，
  不改变上游协议；结构治理的最终候选与发布证据继续单独记录。

