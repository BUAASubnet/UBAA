# 开发命令与门禁

本文是开发、维护、PR/CI 和发布验收命令清单的唯一维护位置。长期安全和来源规则由 [AGENTS.md](../../AGENTS.md)定义，当前任务见[goal.md](../../goal.md)，实际结果见[迁移状态](../migration/status.md)。以下说明按当前 [justfile](../../justfile)和工作流核对，不将计划中的整改写成现有覆盖。

## 工具与准备

Dart/Flutter 调用遵守 [AGENTS 项目工具链规则](../../AGENTS.md#项目工具链入口)。环境安装、固定版本和变量见[开发环境](setup.md)。以下转发保留参数、空参数与调用目录，Shell 参数仍须正常加引号：

```bash
just dart --version
just flutter doctor -v
just flutter-ohos --version
```

| 命令 | 实际作用 |
|---|---|
| `just setup` | 显式联网准备本机环境：依次安装缺失的锁定工具并执行下列准备命令，已一致项跳过；不改写已有 SDK 或 `.env.toolchain` |
| `just doctor` | 只读对照本机工具与 `versions.env`，不联网；必需项不符时退出 1 |
| `just refs-bootstrap` | 仅首次缺少冻结引用时显式联网建立；已有路径只校验，不覆盖、不拉取 |
| `just quality-tools-bootstrap` | 显式安装带版本与哈希锁的 Python 质量依赖 |
| `cargo fetch --locked` | 显式预取锁定 Cargo 依赖 |
| `just flutter-dependencies` | 准备根 Pub workspace 的八个成员（七个正式包、`ubaa_test_support`）锁定依赖，不运行测试 |

## 检查选择与完成条件

先运行有意义的聚焦检查，再审阅并执行按改动计划。阶段基线为开始工作时的提交，避免干净工作树漏掉已提交改动：

```bash
just check-plan base=<阶段开始提交>
just check-changed base=<阶段开始提交>
```

默认 `mode=commit` 包含暂存、未暂存、未跟踪、移动与删除；显式基线还包含分支提交。混合改动合并所需检查，共用检查只执行一次。提交前按下表选择，普通改动无需再叠加完整清单：

| 改动 | 提交前执行范围 |
|---|---|
| 根目录或已知工程目录中的 Markdown、文档图片 | refs、敏感扫描、差异空白、合同版本、文档断链、静态 Cargo 命令锁定扫描；文档站及其 npm 配置另运行站点构建 |
| 普通脚本、justfile、workflow | refs、敏感扫描、差异空白和 `just script-check`，不启动 Rust、Flutter 或 FRB 编译 |
| 普通 Rust / CLI 展示代码 | refs、敏感扫描、差异空白和 `just check`；共用脚本、布局、版本与文档检查已包含其中 |
| 普通 Dart 展示代码、资源或测试 | 共用静态检查及布局检查；生产代码沿本地普通依赖和开发依赖选择消费者，普通测试只检查所属包 |
| 原生平台目录或原生测试 | 提交前检查所属 Flutter 包，推送前或 CI 执行原生集成及对应平台专项；涉及 FFI 或安全边界时立即完整验收 |
| 安全、协议、并发、存储、公共合同、跨语言边界、依赖配置或未知影响 | 提交前完整确定性验收，继续保守处理 |

自动完整范围包括 Core/Bridge、Fixture、Dart Domain、Platform/Host 生产代码、App 中展示目录以外的生产代码、CLI 执行/凭据读取、UI 写操作与缓存管理等边界，以及凭据读取与签名权限脚本。路径选择不能判断所有语义：其他目录中出现安全、协议、并发、存储或跨语言影响时，审阅者必须显式选择 `mode=full`。未知路径或无法解析的本地依赖也执行完整验收。OHOS 改动另外提示 `just ohos-check` 和对应设备验证。

FRB 生成检查只随 Bridge API 源码、生成文件、生成配置及依赖配置/锁文件变化执行，Bridge 测试和平台接线不单独触发重生成。Core 的认证、缓存等内部变化仍执行完整相关测试，未改变生成输入时不额外重生成。未知影响和显式 `mode=full` 保留生成检查，使用 `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1`。

推送前审阅同一阶段范围：

```bash
just check-plan base=<阶段开始提交> mode=push
just check-changed base=<阶段开始提交> mode=push
```

`mode=push` 对代码改动扩展到全部 Flutter 包，Rust 使用严格 ShellCheck；只有原生、FFI、平台改动或完整验收范围才执行原生集成。纯文档和普通脚本仍使用各自级别。全量 Flutter、原生集成和生成检查可由同一候选提交的 CI 承担，应明确记录本地未运行及远端结果，不能提前宣称通过。安全等完整验收范围仍须在提交前完成。

修改门禁或测试框架时，提交前执行脚本级自测与新增失败反例，再验证实际受影响的入口。完整确定性清单保留为显式模式及 PR/CI 的最终验收要求：

```bash
just check-changed base=<阶段开始提交> mode=full
```

该入口依次运行 refs、敏感扫描、差异空白、一次 `check-strict`、全部 Flutter 包、原生集成和一次 FRB 生成检查。`check-strict` 已包含布局、脚本合同、版本及文档检查，不再另跑普通 `check`、`script-check` 或默认 `check-changed`。空工作树也可显式执行 `mode=full`。PR/CI 保留完整相关检查，发布验收继续执行完整清单与平台专项。

原生与发布候选还必须执行对应平台专项，见下文；测试、构建、设备、学校实测和发布分别记账。普通工程检查不请求学校服务。

| 入口 | 实际范围和失败条件 |
|---|---|
| `just refs` | 只读校验两个固定参考的 remote、HEAD 和干净工作树；缺失或不匹配失败 |
| `just layout-check` | 手写源码 1000 行/目录 16 文件棘轮、现有精确 baseline 及目录命名 |
| `just check-sensitive` | 分别扫描 index blob 与未忽略工作区候选；读取或工具失败非零 |
| `just docs-link-check` | 只读检查 Markdown 相对目标、站内路由及标题锚点；历史范围见下文 |
| `just tool-version-check` | 校验版本镜像及全部第三方 Action 的 SHA 锁定 |
| `just dependency-audit` | 显式联网运行锁定版本的 cargo-deny，检查 Rust advisories、licenses、bans 和 sources；缺少固定工具或版本不符失败 |
| `just contract-version-check` | CLI/Bridge 常量、JSON Schema、Dart 接受版本与当前文档声明静态一致性 |
| `just shell-check` / `just shell-check-strict` | 全部候选 Shell 运行 bash -n；严格模式必须存在 ShellCheck 0.11.0，宽松模式缺失时明确 SKIP |
| `just cargo-lock-check` | 静态扫描文档、Shell、workflow 与 justfile 中的 Cargo 命令锁定要求，与 CLI 二进制合同使用相同范围和规则，无需编译 Rust |
| `just script-check` | 严格 ShellCheck、脚本自测、Shell 合同、布局、原生清单、文档、版本和 Cargo 命令锁定检查 |
| `just check` / `just check-strict` | 相同的 Rust、CLI 和脚本检查；仅 ShellCheck 必需性不同。普通 Rust 提交使用前者，推送与完整验收使用后者 |
| `just flutter-check` | 依次对根 Pub workspace 的八个成员执行锁定 pub get、format 检查、analyze、test；golden 使用 macOS 基准 |
| `just flutter-codegen-check` | 锁定 FRB codegen 2.13.0 重生成，只写 FRB 生成路径并格式化生成 Rust 文件，检查 index、工作区及未跟踪生成文件；禁用 Web 输出 |
| `git diff --check` | 检查当前差异中的空白错误；提交前另查 `git diff --cached --check`，验收提交范围时传入基线 |

`script-check` 与 Rust 检查共用 `_script-contracts`；`check` 和 `check-strict` 在此基础上通过 `_rust-shell-contracts` 追加 Rust 检查：Python 脚本自测、原生清单、文档断链、工具版本镜像、完整自有依赖闭包、layout/contract-versions/references/flutter-toolchains/maintenance-gates/live-launchers 六个 Shell 合同脚本、实际布局与版本 checker、静态 Cargo 命令锁定扫描、Cargo metadata/fmt/Clippy、Core 关闭/开启 test-contract 的合同、其余 workspace 测试、构建、文档和差异检查。这里的 references 合同使用临时仓库，并不替代实际冻结引用校验；live launcher 合同使用假程序和虚构凭据，不请求学校。

`just dependency-audit`（由 `scripts/release/dependency-audit.sh` 实现）是独立的网络入口，不由 `check`、`check-strict` 或其他纯校验命令隐式调用。该入口检查 `CARGO_DENY_VERSION` 锁定的 cargo-deny，并允许 cargo-deny 按配置从 RustSec advisory 数据库获取或更新安全公告；CI 在安装同一版本后显式调用它。没有网络时应如实记录该入口未运行，不能把离线 Cargo metadata 或 release-preflight 的许可证材料当作 advisory 审计通过。

这三个入口均不隐含完整 Flutter、FRB 生成、原生设备或学校实测。`fmt` recipe 也只执行格式检查，不写文件。

## 聚焦回归与原生验证

| 命令 | 用途 |
|---|---|
| `just source-files` | 定位手写源码，排除生成文件与历史验收元数据 |
| `just flutter-test ubaa_app test/features/grades` | 固定 SDK 的包内普通测试，不解析依赖或选择设备 |
| `cargo test --locked -p ubaa-cli --all-targets` | CLI 合同与二进制端到端 |
| `just core-test-contract` | 默认 Core 编译/Rustdoc、启用 test-contract 的全目标测试，以及注入关闭时的预期编译失败合同 |
| `just test` / `just fmt` | 前者执行 Core test-contract 合同及其余 workspace 测试；后者仅执行 Cargo 格式检查，不写文件 |
| `just module-check` | 自有源码完整依赖闭包、环、library 聚合尺寸与 part 归属 |
| `just integration-check` / `just integration-list` | 校验并查看保留的十一个原生能力和宿主 smoke 入口 |
| `just integration-test` | 默认 macOS：宿主 smoke、网络恢复、插件、FFI 缓存、跨进程启动锁 |
| `just integration-test suite=synthetic/cache/bridge_test.dart platform=macos` | 按精确路径与平台执行；device 未填时回退为平台 |
| `just script-test` | Python 门禁及离线分析的合成合同 |

集成清单中的 `environment` 表示当前进程或工具链配置必须提供的非空环境变量，缺失时入口在启动 Flutter 前失败；`defines` 会逐项转换为 `--dart-define=...` 传给 Flutter。`runner` 为 `test` 或 `run`，分别执行对应的 Flutter 子命令，清单中的 `ci` 入口只能使用 `test`。

原生集成保留真实原生能力、FFI/启动锁和最小宿主 smoke。保留覆盖与自动化缺口见[测试策略](testing.md)。各平台构建、设备验收和发布证据分别记录。

OHOS 宿主与三个 *_ohos 插件不属于官方 Pub workspace 的八个成员。`ohos-check` 当前执行 OHOS 宿主 analyze/test、工具链预检、HUKS 与 connectivity 的合成合同及 HAP 构建；package_info_plus_ohos 仅被间接编译，没有独立自动合同。普通 Flutter 成功不能代替 OHOS 结果，这些覆盖缺口留待后续阶段。

## 当前 CI 的实际范围

| 工作流 / 作业 | 当前触发与实际执行 |
|---|---|
| [ci.yml](../../.github/workflows/ci.yml) / contract-gates | ubaa2/main/dev push 与 PR；Ubuntu 显式 bootstrap 参考/质量工具、安装固定 cargo-deny 并运行联网依赖审计、校验 refs/敏感扫描、执行 check-strict、准备 Dart 依赖、检查 FRB。发布前置报告不在日常 CI 运行，发布前本地执行 `just release-preflight` |
| ci.yml / flutter-contracts | macOS 15 执行完整 flutter-check，失败时上传脱敏 golden 差异；不在此作业运行原生集成 |
| ci.yml / rust-platforms | macOS/Windows 执行 Cargo fmt、全特性 Clippy、Core 默认关闭态检查/Rustdoc、开启 test-contract 的全目标测试、关闭态负向编译合同，其余 workspace 全目标测试/构建及文档 |
| [flutter-platforms.yml](../../.github/workflows/flutter-platforms.yml) / native-debug | 手动、受路径过滤的 PR，以及 ubaa2/main/dev push；构建 Linux/Windows/macOS/iOS simulator/Android APK，检查产物并生成源码/产物关联。macOS 执行默认原生集合，Linux 执行隔离安全存储；Markdown 路径被排除，OHOS 不在此工作流 |
| [docs.yml](../../.github/workflows/docs.yml) | 手动、文档站相关 PR 和 ubaa2/main/dev push；npm ci 与 docs:build 检查站内链接；仅配置的发布分支且非 PR 时上传/部署 Pages |

三个工作流统一 push 分支为 ubaa2/main/dev，PR 保留各自路径过滤，均使用 concurrency 取消同一 ref 的旧运行。第三方 Action 使用完整 SHA，工具版本来自 `scripts/tools/versions.env`，Flutter 安装由同一脚本完成。当前本地通过不等于候选远端 CI 通过。网站本地检查为 `npm run docs:build`，不验证站外全部工程文档。

## 构建与发布命令

| 命令 | 作用 |
|---|---|
| `just flutter-build platform=<平台> mode=debug` | 官方目标 host/macos/linux/windows/android-apk/ios-simulator 的原生构建，具体目标由脚本白名单限定 |
| `just cache`、`just cache-clean <范围…>` | 只读显示仓库内构建缓存占用；按范围删除可重建产物（如 `rust-incremental`、`flutter-macos`、`ohos`），任一目录受跟踪或未被忽略时整体拒绝；`.ubaa_local` 只显示不清理 |
| `UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug` | 固定 OHOS fork 与 DevEco/API26 的无签名 Debug HAP；无签名模式不能用于发布或实体设备验收 |
| `just flutter-artifact-check macos <私有绝对路径>/ubaa_flutter.app` | 只读检查产物；macOS 从真实签名读取并要求 Sandbox 和客户端联网权限，不修改或重签 |
| `just release-preflight <私有绝对路径>/release-report` | 默认 `mode=strict`：干净工作树、空报告目录下生成离线 Dart/OHOS 许可证材料；材料缺口保留报告并以状态 3 阻止发布 |
| `just release-preflight <私有绝对路径>/release-report mode=report` | 仅收集材料，报告列明完整性和发布阻塞项；材料缺口不改变退出码，真实生成错误仍失败；不判定发布通过 |

两种报告模式均不签名、不上传、不使用真实账号。OHOS embedding HAR 的许可证从锁定的 OHOS Flutter SDK 推导，规则见[OHOS 原生依赖材料](../runbooks/flutter-release.md#ohos-原生依赖材料)，仓库内类型声明单独记录；实际 HAP、动态库与签名仍需产物验收。

构建、签名、安装、实体设备和发布准入详见[发布流程](../runbooks/flutter-release.md)。无签名构建、模拟器、Mock 和 CI artifact 均不能代替实体设备、安全存储、签名或发布证据。

## 来源对照与真实验证

所有认证、读取或写入功能变更遵守 [AGENTS 来源对照门禁](../../AGENTS.md#来源对照门禁)。补齐来源差异并通过失败反例/聚焦回归后，提交前必须完成本页完整确定性验收，其中敏感扫描和严格 Rust/CLI 检查不能省略。纯展示、文档或测试整理没有协议变更时，不因此执行学校请求。

认证、读取或写入协议变更，以及发布验收，还必须有 CLI 二进制端到端和 Direct/WebVPN 两条路线的真实只读证据。CLI 端到端已包含于严格入口的 CLI 测试；真实验证按 [AGENTS 授权规则](../../AGENTS.md#真实账号与验收范围)执行：

```bash
just verify-live mode=direct
just verify-live mode=webvpn
```

两条路线逐条串行执行，只接受 direct/webvpn，禁止以 auto 代替。可用 `feature=auth route=direct` 等参数缩小已获授权的范围；缩小运行不等于完整验收。授权或网络条件不足时如实登记未运行/失败及重跑条件，双路线要求保持，不静默豁免。真实写入须逐次具体授权，以上入口只读，不能验证写入成功。

verify-live 从被忽略的 `.env.local` 安全读取非空主名称凭据，经 stdin 交给 Core-live；工具配置不会加载该凭据文件。每条路线使用一个固定 RouteClient 串行执行，只输出安全摘要。Core-live 是脚本化只读验证的网络执行程序；真实 App 另行按授权验收，不能据此声称项目只有一个会联网的程序。具体操作和失败记录见[只读手册](../runbooks/live-readonly-verification.md)。

## 网络与写入边界

- 实际 refs 校验不联网、不改冻结目录；只有 refs-bootstrap 可以联网建立缺失冻结引用。已有目录错误时停止，不清理或重置敏感参考。
- 普通检查不访问学校服务。Cargo/Rustup/Flutter 可能补齐工具或依赖缓存，flutter-check 会执行锁定 pub get；依赖源访问与学校请求分别管理。质量 Python 工具缺失时明确失败，安装只经显式 bootstrap。
- 按改动检查本身只读 Git/pubspec，所选子命令仍可能写缓存。门禁 recipe 统一设置 `CARGO_INCREMENTAL=0`，不积累只用一次的增量缓存；日常 Rust 与 Flutter 运行保留增量。开发构建只带行号调试信息，需要查看变量时临时设 `CARGO_PROFILE_DEV_DEBUG=true`。FRB 生成检查的现有写入副作用已在上表说明，不能称所有 check 都只读。
- 日志、stdout/stderr 和报告遵守[统一日志脱敏规则](conventions.md#日志与诊断脱敏)，禁止全局 trace。仅在已获授权的窄范围诊断使用 RUST_LOG，原始 stderr 不进入共享文档。
- 锁文件、parser、lint 或生成检查失败时定位原因，不通过放宽规则、删除测试或手改生成物获得通过。upstream_changed 只表示响应不满足已证明合同，不能据此猜字段或绕过挑战。

## 文档链接范围

`docs-link-check` 检查当前 Markdown 的本地文件、站内路由和标题锚点，不请求外站。`docs/migration/history/` 和 `docs/design/evidence/` 按归档约定保持历史内容，检查器不把这些快照内部链接当作当前可执行承诺。锁定的 Cargokit 上游文档同样不改写。当前文档指向这些目录的目标和锚点仍检查。该范围决定见[决策记录](../migration/history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29门禁基础逻辑与-ci-统一)。

带参数的项目 recipe 同时接受位置参数和 `key=value`，关键字可换序，重复或未知参数失败；例如 `just flutter-build mode=debug platform=linux`。Dart/Flutter 的自由参数仍原样透传。
