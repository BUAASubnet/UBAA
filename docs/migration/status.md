# 当前实现与验证状态

更新：2026-10-30。本文只维护当前快照，旧时间线见[阶段 4 整理前状态](history/2026-10-30-status-before-quality-phase4.md)，历史决定见[决策索引](decision-log.md)。[阶段目标](../../goal.md)定义本轮范围，门禁清单只在[开发命令](../development/commands.md#检查选择与完成条件)维护。

## 当前实现

Rust Core 统一拥有认证、Direct/WebVPN/Auto 路线、会话、十二领域读写和加密缓存。CLI 与 Bridge 通过 facade 使用 Core，Flutter/OHOS 宿主通过 Bridge 与共享 Dart/UI 接线。当前公开合同为 CLI JSON schema v12 与 Flutter bridge contract v42，独立于 Session v2、配置 v1、业务缓存 v6。产品展示版本与合同版本分别治理，取值与发布规则见[版本约定](../development/conventions.md#版本号与依赖)。

主题保存为设备偏好，重启恢复，不随退出或清除账号删除；业务缓存仍由 Core 持有。[界面规格](../design/flutter-ui-spec.md)描述现行展示规则，[来源对照](source-parity.md)保留逐操作协议依据。

## 整改阶段 1–6 的实际结果

| 阶段 | 已提交结果 | 验证证据与边界 |
|---|---|---|
| 1：去除个人机器依赖 | `29cccb26`、`ff9a52e7`：本地工具链入口、敏感扫描、证据脱敏、环境说明及许可证 | 完整严格 Rust/Shell、七包 Flutter、FRB 和文档站构建通过；证据 JSON 保留。 |
| 2：统一权威来源 | `fd96b0bf`、`c92806b4`：工具配置解析与转发、长期规则、门禁清单、冻结来源及开发约定 | 严格门禁、七包 1523 项、FRB 零漂移及文档站构建通过。原生两项流程失败和旧启动锁 EPERM 经监督复核保留为当时失败。 |
| 3：门禁与 CI | `03beae27`、`7e2d486c`、`5b03cbdd`：保留原生能力、迁移夹具、修启动锁、统一脚本与版本、修 codegen 和 CI 配置 | 严格门禁、refs、布局、敏感扫描、文档链接/版本、FRB 零漂移通过。以 `c92806b4` 为基线的 check-changed 完整通过，七包 1526 项。监督者复核通过。 |
| 4：文档瘦身与同步 | `308fa383`、`050be54b`：归档历史文档、修复现行链接、同步状态、决策索引和文档边界 | 现行文档断链为 0，旧决策逐字归档并保留索引，4000 个证据 JSON 原位保留。监督者复核通过。 |
| 5：Rust 重构 | `19102297`、`00f40e01`、`b616bc53`、`fb73bac4`、`8d761ac9`、`fb8a60d4`、`81c6a0d6`、`bdc4232b`、`edeb41a4`、`db422ebd`、`29104992`、`69141903`、`aa687563`、`cdb65c22`、`a1d654ca`、`3cd9e3e5`、`f89ce2e2`、`80e1d77a`：依赖、错误与 HTTP 辅助、时区、SSO/缓存流程、CLI 契约和模块布局重构及最终状态同步 | `cargo test --locked --workspace --all-features`、严格 Clippy、`just check-strict`、七包 Flutter、FRB 零漂移、保留集合 macOS 集成测试和阶段基线 check-plan/check-changed 均通过；协议边界保持不变。 |
| 6：Dart/Flutter/OHOS 重构 | `1b53eb1a`、`8480c23e`、`758e5de1`、`dbc3c847`、`c8777caa`：官方七包与 `ubaa_test_support` 纳入根 Pub workspace，统一 `flutter_lints`/implementation_imports，抽取跨包测试夹具，按 library 聚合布局门禁，Android release 签名改为显式配置，刷新 FRB 生成绑定；OHOS 保持独立 fork/锁文件 | 七包 `just flutter-check` 全部通过，OHOS 工具链、插件合同、HUKS/网络合同和无签名 Debug HAP 通过；golden 无变更，FRB 零漂移。 |
| 6b：阶段 6 顺延低风险项 | `DemoBackend` 迁入测试支持包，删除无人使用的兼容别名/re-export；统一三个 OHOS 插件和 Cargokit 出处清单；清理平台模板 TODO/占位资源并补本地生成目录忽略；机械合并重复测试点击夹具 | `just flutter-check`、golden 六项、`just check-strict` 和 `git diff --check` 通过。未改 bundle id、application id、版本号或生产协议。 |
| 7：依赖审计 | 加入 Dependabot（Cargo、Pub workspace、独立 OHOS Pub、docs npm、GitHub Actions）；锁定 cargo-deny 0.20.2，配置 advisories/licenses/bans/sources，升级可修复公告并登记 RSA 无修复公告豁免；新增显式联网 `just dependency-audit` 和 CI 步骤 | 本机 `just dependency-audit` 通过；RustSec 数据库访问只在该入口/CI 显式发生，纯校验门禁不隐式联网。 |

阶段 3 原生 catalog 保留 10 个入口：`platform/*` 与 `synthetic/cache/*`。本机适用的 macOS 八个入口共 23 项通过，包含默认网络/插件/FFI/启动锁四入口的完整运行。启动锁由应用派生独立 Perl 进程持锁，从 PATH 查找解释器，不依赖终端访问应用容器的权限。照片首轮出现 SemanticsHandle 活跃断言，停止同时读取 UI 后代码不变重跑通过，首次失败保留。阶段 3 当时只完成 OHOS 工具链预检与 HUKS/网络插件合成合同；阶段 6 已在同一锁定工具链上完成无签名 Debug HAP 检查，仍未运行实体设备验收。

## 当前未解决与未验证事项

- 远端 CI 尚未运行。阶段 3 已修改 workflow，本地静态检查与监督复核通过；本轮未 push。
- 保留原生集合的 Linux Secret Service 和 iOS/iPad 方向握手专项尚未在本轮运行；其他平台原生构建、签名、发布与真实账号验收也未运行。
- [原生删减登记](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)中的以下项目已无自动化覆盖：原生登录到查询完整路径、十二领域连续导航、十项写操作连续流程、原生软键盘专项、真实账号原生 UI 巡检、真实账号原生恢复、真实账号原生启动性能测量、Flutter 到 Android 的真实课表组件通道、常驻原生合成预览及 bindings 默认 driver。登记表逐项列出仍保留的 App/Host/Widget/Core 等分层覆盖。已删除流程的旧失败随入口移除，不计作修复通过。
- OHOS 原生 `AppScope/app.json5` 仍为 `1.0.0`/`1000000`，两个 Flutter 应用仍为 `0.1.0+1`；平台标识和版本号可能影响已安装应用升级，本阶段没有修改，留待后续决定。OHOS fork 与官方七包 Pub workspace 保持独立，原因和锁文件边界见决策记录。
- Rust 阶段已完成。feature 专属 SSO service URL 未合并，避免改变参数编码、重定向和 Cookie 作用域。监督者决定本轮继续保留历史 `mod.rs` 中的协议实现和 Bridge 离线泛型化，列为后续待办；补充来源或私有观察无法由当前克隆复现的记录仍按[来源对照边界](source-parity.md)保留，不补造证据。
- 最终逐项 UI/设备、异常生命周期、离线性能和发布验收仍有缺口；历史真实只读结果仅属于对应候选，不能继承为当前验收或真实写入授权。

## 本阶段验证

阶段 6 以 `d1872cafdf2e425c9f4a48c2cce5856f53ad458c` 为基线。`just flutter-check`（官方七包全量：domain 60、platform 95、app 683、UI 478、bindings 20、host 102、官方宿主 88）、`just layout-check`、`just check-sensitive`、`just check-strict`、`cargo test --locked --workspace --all-features`、`just flutter-codegen-check`（零漂移）、保留集合 `just integration-test`（4 个 macOS 入口）、golden 六项定向比较、OHOS 工具链/插件合同/HUKS/网络合同和无签名 Debug HAP 均通过。`git diff --check` 已在严格门禁中通过；阶段基线 `just check-plan` 与 `just check-changed` 均通过（基线 `d1872cafdf2e425c9f4a48c2cce5856f53ad458c`）。远端 CI、Linux/iOS 专项按监督者决定留待最终 push 后运行。
