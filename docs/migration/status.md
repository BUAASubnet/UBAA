# 当前实现与验证状态

更新：2026-10-30。本文只维护当前快照，不记录单轮验证流水。整改阶段 1–7、Rust Core 精简、审查修复与签名配置的逐轮记录见[状态流水](history/2026-10-30-status-log-through-signing.md)，更早的时间线见[阶段 4 整理前状态](history/2026-10-30-status-before-quality-phase4.md)，历史决定见[决策索引](decision-log.md)。[阶段目标](../../goal.md)定义本轮范围，门禁清单只在[开发命令](../development/commands.md#检查选择与完成条件)维护。

## 当前实现

Rust Core 统一拥有认证、Direct/WebVPN/Auto 路线、会话、十二领域读写和加密缓存。CLI 与 Bridge 通过 facade 使用 Core，Flutter/OHOS 宿主通过 Bridge 与共享 Dart/UI 接线。当前公开合同为 CLI JSON schema v12 与 Flutter bridge contract v42，独立于 Session v2、配置 v1、业务缓存 v7。产品展示版本与合同版本分别治理，取值与发布规则见[版本约定](../development/conventions.md#版本号与依赖)。

主题保存为设备偏好，重启恢复，不随退出或清除账号删除；业务缓存仍由 Core 持有。[界面规格](../design/flutter-ui-spec.md)描述现行展示规则，[来源对照](source-parity.md)保留逐操作协议依据。

Rust Core 已完成精简：缓存刷新、路线安全检查、凭据槽位与协议解析收敛，业务缓存提升为 schema v7 并删除历史开发格式迁移；旧库普通打开会明确拒绝且不改文件，可显式重建。过程见[Core 精简记录](2026-10-30-core-simplification.md)。

各平台产品标识统一为 `cn.edu.ubaa`，签名材料默认放在被忽略的根 `.sign/`，配置方法见[应用签名配置](../runbooks/app-signing.md)。Android 已用本机 keystore 构建并校验 Release APK，尚未安装运行或与旧正式包对照。

## 当前未解决与未验证事项

- 远端 CI 尚未运行。阶段 3 已修改 workflow，本地静态检查与监督复核通过；本轮未 push。
- 保留原生集合的 Linux Secret Service 和 iOS/iPad 方向握手专项尚未在本轮运行。最新平台构建与 Android 签名测试结果见[状态流水](history/2026-10-30-status-log-through-signing.md)，正式发布与真实账号验收仍未运行。
- [原生删减登记](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)中的以下项目已无自动化覆盖：原生登录到查询完整路径、十二领域连续导航、十项写操作连续流程、原生软键盘专项、真实账号原生 UI 巡检、真实账号原生恢复、真实账号原生启动性能测量、Flutter 到 Android 的真实课表组件通道、常驻原生合成预览及 bindings 默认 driver。登记表逐项列出仍保留的 App/Host/Widget/Core 等分层覆盖。已删除流程的旧失败随入口移除，不计作修复通过。
- OHOS 原生 `AppScope/app.json5` 仍为 `1.0.0`/`1000000`，两个 Flutter 应用仍为 `0.1.0+1`。版本号仍需在发布前与旧正式包核对，平台标识已统一。OHOS fork 与官方七包 Pub workspace 保持独立，原因和锁文件边界见决策记录。
- Rust 阶段已完成。feature 专属 SSO service URL 未合并，避免改变参数编码、重定向和 Cookie 作用域。监督者决定本轮继续保留历史 `mod.rs` 中的协议实现和 Bridge 离线泛型化，列为后续待办；补充来源或私有观察无法由当前克隆复现的记录仍按[来源对照边界](source-parity.md)保留，不补造证据。
- 最终逐项 UI/设备、异常生命周期、离线性能和发布验收仍有缺口；历史真实只读结果仅属于对应候选，不能继承为当前验收或真实写入授权。

## 最近一次完整验证

2026-10-30 Rust Core 精简后：完整严格检查、1531 项 Flutter 测试、macOS 默认原生集成、FRB 零漂移和按基线检查通过；Direct 与 WebVPN 各 50 项完整只读检查通过。远端 CI 和正式发布均未运行。
