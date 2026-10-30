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

## 2026-10-30：项目级审查后的修复

本轮以 `19c97520` 和开始时已有的未提交修改为基线，按协议边界、发布/CI 门禁、宿主生命周期三个主题复核。先保留已正确完成的修复，再用失败反例修复新增回归；未重置已有工作，也未执行学校请求。

- 根 `pubspec.lock`、workspace 八个成员和原生 CI 根配置触发范围已补齐。workspace 解析不会因顶格注释截断成员；新增根 `build/` 忽略规则，构建缓存不进入工作区候选。
- 发布材料包含根锁文件的 138 项依赖。共 326 项材料中 322 项已收集，4 项 OHOS 原生依赖仍需结合产物核对。默认严格模式保留报告并以状态 3 阻断发布；源码 CI 显式使用 `mode=report`，报告保留 `partial` 和阻塞数量，生成错误仍失败。第三方 Git 包不会因目录位置而继承本项目的 LICENSE。
- 集成执行器在启动 Flutter 前验证所有选中入口的环境变量和 Dart defines，并传递配置。过期原生清理记录已归档；当前 catalog 为 11 个入口。
- WebVPN 原生登录/Cookie 路径保持原值；业务根相对包装先还原真实目标再校验，普通相对路径保留业务基址语义，重复包装前缀斜杠不会丢失业务路径。BYKC 只从安全的 `/cas-login` 回调提取 token。Ygdk 逐跳限制已证明的 app/ygdk HTTPS 主机及默认端口，只从 ygdk 回调提取 code，拒绝未知目标；解码保留 `+`、`&` 并只处理一层百分号编码，根路径 query 不受无关 fragment 影响。完整来源、错误分类与路线边界见[认证安全复核](source-parity-auth-review-2026-10-30.md)。
- 宿主在首页首帧后处理积压恢复，后台异步初始化保留前后台状态，退出后重新登录重置首帧标记。新增 smoke 分别覆盖替身的正向登录，以及真实 RustLib/BridgeBackend/Core 的本地首页、缺会话错误和缓存读取。
- Bridge 保留重构前的 `rand 0.10` 依赖系列（锁定解析为 0.10.3），Core/RSA 继续使用 0.8；按实际依赖树登记重复版本原因。上一轮仅证明版本漂移，没有证据证明 rand 0.8 本身导致随机标识安全失效。
- CLI 二进制测试显式依赖 Rust 测试支持包，不再依靠全 workspace 的 feature 合并；单独执行 CLI 全目标测试的 129 项均通过。Bridge 两处旧 BYKC 回调夹具已迁到冻结的 `/cas-login`，保留原有业务断言。

Direct 收到合法 WebVPN 包装后解包并请求直连上游，不等于向网关发送请求，上一轮对路线越界的概括过宽。HTTP(S) 主机大小写由 URL parser 规范化，单凭大小写比较不能证明绕过。Ygdk 未知主机现在明确失败；真实环境若出现额外合法中间主机，需要先取得脱敏证据再扩充。签到和图书馆写请求完成后，解包失败、无法解析或仍然指向网关的异常落点保守返回结果未知，成功 JSON 不能覆盖这一判定，写请求仍只发送一次。

本轮最终验证：冻结引用、布局、敏感扫描、`just check-strict`、八成员 `just flutter-check`（1531 项）、默认 macOS 原生集合（5 个入口、7 项）、FRB 零漂移、依赖审计、文档链接与差异检查均通过。已审阅以 `19c97520` 为基线的按改动计划，并执行完整确定性门禁。依赖材料生成器实际返回预期状态 3，报告记录 4/326 项材料缺口；`allo-isolate` 缺少 manifest license 字段的既有 warning 仍由实际 LICENSE 支撑。成功与失败日志统一保存在被忽略的 `.ubaa_local/supervision/review_fix_2026_10_30/`，包含写后分类反例、未加锁命令文档、CLI 单包依赖和 Bridge 旧夹具导致的首次失败。未运行真实账号双路线、远端 CI、Linux/iOS 专项、其他平台构建或签名发布；这些项目仍需在对应环境验证。

## 2026-10-30：OHOS 材料报告后续修复

报告器现在接受显式 OHOS 材料清单，核对产物、许可证正文与使用方声明摘要，并按实际产物合并重复引用。Bridge 的 OHPM 本地依赖是类型声明包，已单独记录；实际动态库仍由产物验收检查。本机三个插件的 OHPM 锁文件指向同一 HAR，已与固定 SDK 及其许可证正文建立材料映射。补充材料后的报告为 324 条、0 项缺口；之前的固定 4 项判缺已撤销。输入来源是显式声明，未据此宣称已证明二进制构建来源或完成法律审核。说明与清单格式见[OHOS 补充材料](../runbooks/flutter-release.md#ohos-补充材料)，本轮日志与本地材料位于 `.ubaa_local/supervision/ohos_evidence_fix_2026_10_30/`。

本轮材料修复验证：124 项脚本测试、完整严格门禁、1531 项 Flutter 测试、默认 macOS 原生集合 5 入口/7 项、FRB 零漂移、敏感扫描与文档链接检查均通过。缺少补充材料时实际退出 3；摘要变化、重复映射和来源冲突由回归测试验证拒绝。补充材料路径已配置到被忽略的本地工具配置，清单和许可证正文未提交 Git。没有重建或签名 OHOS HAP，也没有执行学校请求。

## 当前未解决与未验证事项

- 远端 CI 尚未运行。阶段 3 已修改 workflow，本地静态检查与监督复核通过；本轮未 push。
- 保留原生集合的 Linux Secret Service 和 iOS/iPad 方向握手专项尚未在本轮运行。最新平台构建结果见下述签名配置记录，正式签名、发布与真实账号验收仍未运行。
- [原生删减登记](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)中的以下项目已无自动化覆盖：原生登录到查询完整路径、十二领域连续导航、十项写操作连续流程、原生软键盘专项、真实账号原生 UI 巡检、真实账号原生恢复、真实账号原生启动性能测量、Flutter 到 Android 的真实课表组件通道、常驻原生合成预览及 bindings 默认 driver。登记表逐项列出仍保留的 App/Host/Widget/Core 等分层覆盖。已删除流程的旧失败随入口移除，不计作修复通过。
- OHOS 原生 `AppScope/app.json5` 仍为 `1.0.0`/`1000000`，两个 Flutter 应用仍为 `0.1.0+1`。版本号仍需在发布前与旧正式包核对，平台标识已按下述签名配置工作统一。OHOS fork 与官方七包 Pub workspace 保持独立，原因和锁文件边界见决策记录。
- Rust 阶段已完成。feature 专属 SSO service URL 未合并，避免改变参数编码、重定向和 Cookie 作用域。监督者决定本轮继续保留历史 `mod.rs` 中的协议实现和 Bridge 离线泛型化，列为后续待办；补充来源或私有观察无法由当前克隆复现的记录仍按[来源对照边界](source-parity.md)保留，不补造证据。
- 最终逐项 UI/设备、异常生命周期、离线性能和发布验收仍有缺口；历史真实只读结果仅属于对应候选，不能继承为当前验收或真实写入授权。

## 本阶段验证

阶段 6 以 `d1872cafdf2e425c9f4a48c2cce5856f53ad458c` 为基线。`just flutter-check`（官方七包全量：domain 60、platform 95、app 683、UI 478、bindings 20、host 102、官方宿主 88）、`just layout-check`、`just check-sensitive`、`just check-strict`、`cargo test --locked --workspace --all-features`、`just flutter-codegen-check`（零漂移）、保留集合 `just integration-test`（4 个 macOS 入口）、golden 六项定向比较、OHOS 工具链/插件合同/HUKS/网络合同和无签名 Debug HAP 均通过。`git diff --check` 已在严格门禁中通过；阶段基线 `just check-plan` 与 `just check-changed` 均通过（基线 `d1872cafdf2e425c9f4a48c2cce5856f53ad458c`）。远端 CI、Linux/iOS 专项按监督者决定留待最终 push 后运行。

## 2026-10-30：统一应用标识与签名配置方法

用户要求延续旧版更新，并统一各平台产品标识。Android、iOS、macOS、Linux 和 OHOS 现在使用 `cn.edu.ubaa`；Apple 测试 target 保留独立后缀，Android Kotlin namespace 不变。Windows 当前没有 MSIX 配置，后续非商店包采用同一标识，商店包使用 Partner Center 指定的身份。

新增[应用签名配置](../runbooks/app-signing.md)，覆盖私有材料目录、六平台配置、二次开发和既有 CI secret 映射。当前阶段没有生成密钥、接入签名流水线或上传发布。旧版桌面身份、macOS 开发容器切换、凭据和数据迁移、正式构建号与覆盖升级仍需独立验证。

验证基线为 `3b676593`，对应源码提交为 `94d34898`。按改动检查通过，包含完整 Rust/脚本检查、八成员 1531 项 Flutter 测试和 FRB 零漂移；严格 ShellCheck、文档链接、布局、合同版本和敏感扫描通过。Android Debug APK、iOS 模拟器 App、OHOS 无签名 Debug HAP 均成功构建，包内应用标识均为 `cn.edu.ubaa`，Android/iOS 产物结构及 OHOS arm64 动态库检查通过。Android 入口类仍正确解析为原 Kotlin namespace 下的 MainActivity。macOS Release 构建设置解析通过，未重建或签名发布包。

Android 首次构建因 TLS 组件 Maven 分发方式变化失败，按[决策记录](decision-log.md#2026-10-30android-tls-组件的-maven-分发迁移)修复仓库地址和 group 后通过，依赖版本不变。OHOS 首次缺少本机 DevEco 根目录，补充被忽略的 `.env.toolchain` 后通过；构建工具生成的无关锁文件和资源变动已还原。本地日志为 `.ubaa_local/signing_*.log`。未运行正式签名、公证、商店上传、旧版覆盖安装、数据迁移、真实账号、远端 CI 或 Windows/Linux 原生构建，签名材料有效性仍需正式候选验证。
