# 桌面命令模式与共享应用服务实施计划

日期：2026-11-01。状态：H0 候选 `fa5b8133` 已通过主监督与新上下文只读审查，接续 H1-a 共同无感恢复。正式命令入口及共享接线尚未完成，Windows 原生运行仍待验证。

目标：把命令行能力并入 UBAA App。macOS、Windows、Linux 的图形界面与命令模式共用凭据、会话、缓存、日程和无感恢复；Linux 还支持没有图形会话的 SSH 服务器环境。新入口通过验收后退役独立 Rust CLI 宿主。

架构：GUI 和命令入口调用同一套不依赖界面的应用服务，经 facade/Bridge 使用 Rust Core。平台只适配进程入口、标准输入输出、目录和安全材料。保留一份命令定义、JSON 合同和退出码，具体语言及模块位置由 H0 原型确定。无需 App 窗口提前打开或 UBAA 后台常驻。

技术基础：现有 Rust Core、Flutter/Dart、FRB、SQLite 和平台安全存储。先复用现有能力，不以全面重写账号系统或新增常驻服务作为前提。

执行方式：主聊天设计、拆分和审查，独立执行聊天使用 `gpt-6.1-sol / ultra`。每个可独立验收的单元使用新上下文，执行者可依据证据调整技术接线和细分任务。产品范围依据本文、[日程设计](agenda.md)和[北航云盘设计](bhpan.md)。本文替代旧“CLI 独立安全材料方案 A”及两套独立宿主共享材料的优先路线，不恢复旧 CLI worker 专项。

## 已确认行为

| 场景 | 行为 |
|---|---|
| 默认资料空间 | 同机、同系统用户的 GUI 与命令入口共用一份账号关联、凭据策略、会话和数据。远程服务器有自己的本机资料空间，本阶段不增加跨机器凭据同步。 |
| 无感恢复 | 已保存凭据且允许自动登录时，在线命令先复用会话，明确认证过期后按操作所需路线恢复并继续。与 GUI 使用同一服务，不要求先运行登录命令。 |
| 恢复限制 | 主动退出或关闭自动登录后不自动提交凭据。密码无效或上游要求交互时返回明确结果；临时网络错误不等同于密码失效。恢复有超时与取消，不无限挂住命令。 |
| 账号变化 | 默认共用当前账号，显式登录、切号和退出影响两端。并发恢复合并或协调；旧账号任务不得交付新账号结果。 |
| 命令结束 | 释放本进程句柄，不执行全局退出，不停用另一进程合法使用的库。 |
| 数据 | 保留原随机账号别名与缓存密钥。业务缓存继续 AES-GCM 加密，日程继续独立明文 SQLite。缓存清理不删除日程。 |
| 本机操作 | 日程查询和修改按合法本机账号访问，不因启动命令而请求学校、刷新首页或启动无关后台任务。 |
| 学校写入 | 恢复会话不自动重放可能已到达上游的写请求；保留准备资格、显式提交和结果未知后的只读核对。 |
| 终端 | 保留 human/JSON、stdin/stdout/stderr、退出码、管道、超时与取消。JSON 不混入引擎日志，文件路径和非 ASCII 参数按平台处理。 |
| 安装 | 桌面命令入口随 App 升级。Linux 可以提供只含命令运行组件的安装形态，仍复用同一应用服务与命令实现。 |

macOS、Windows 无需支持未登录桌面的服务器运行。Linux SSH 是正式验收范围，不能依赖 X11/Wayland、Xvfb 或先启动 GUI；可以使用无图形系统服务，所需凭据和缓存密钥提供方式须能支持已配置账号的无感恢复。

用户已反馈现有 App 钥匙串问题解决。复用 App 当前材料路径，不把旧 CLI 材料 worker 修复作为前置任务，不重复扩大该问题。合成验证避免触碰真实材料；发现实际回归时针对修复。

## 当前基础与改动边界

- 日程 Core CRUD、重复规则、学校投影、独立 Bridge/Dart 服务及首页投影已完成；Core 范围快照 `.ics` 修复已独立放行至 `de797fce`。这些能力继续复用。
- 旧实验 HEAD 为 `9835653c`，H0 阶段起点为 `f8e3078f`。旧 CLI-a 独立账号实现及后续 worker 修复未最终放行。工作区继承 10 个跟踪文件修改和 3 个新源码，已有私有补丁快照，不直接整体重置或混入新阶段提交。
- 旧审查确认了任意材料 worker 入口和派生认证失效传播两项问题。随入口删除消失的旧问题登记覆盖去向；仍被公共服务使用的认证失效行为必须修复和回归，不能靠改名宣布消失。
- App 的材料、账号和目录入口在 `packages/ubaa_platform/lib/src/secure_material.dart`、`local_accounts.dart`、`paths.dart`。账号索引队列目前只覆盖单个 Dart 对象。
- 无感恢复在 `packages/ubaa_app/lib/src/controller/recovery/required.dart` 等模块，启动接线在 `packages/ubaa_host/lib/src/ubaa_app_host.dart`。提取必要服务，不启动完整首页 Controller 代替命令运行时。
- Core 的 `crates/ubaa_core/src/session/coordinator.rs` 已提供 revision/CAS，但外部更新会终止旧客户端所有权。共享服务应在安全边界重新取得客户端，不能放宽冲突检查或让旧写意图自动续用新会话。
- `apps/ubaa_cli` 同时包含命令库、独立 `ubaa` 程序及 `core-live`。退役宿主前要迁出命令合同与协议验证工具，保留现有测试覆盖。

## 技术选择与自主范围

H0 用锁定 SDK 和可运行样机确定接线，后续计划依据结果细化，不预先把每个内部接口写死。macOS 的 [Engine](https://api.flutter.dev/macos-embedder/interface_flutter_engine.html)、Windows 的 [Engine](https://api.flutter.dev/windows-embedder/flutter__engine_8h_source.html)、Linux 的 [headless Engine](https://api.flutter.dev/linux-embedder/fl__engine_8h_source.html)都有相关官方入口；在线文档不能代替仓库锁定版本与插件兼容证据。

macOS App Sandbox 是分发选择，不能当作跨平台固定前提。[商店外分发可选择沙箱](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)。优先评估能满足直接文件路径、网盘和命令调用的普通桌面分发；若调整沙箱，须单独验证旧目录、账号与密钥连续性及权限脚本，不能夹带改变签名、发布或移动端权限。Windows 普通桌面入口和 Linux 打包分别设计，不套用 macOS App Group 方案。

Linux 可以用 Docker 构建、运行合成实验和验证纯 SSH 条件。只挂载任务需要的源码及私有合成目录，不挂载真实配置、凭据、会话或整个用户目录，不使用特权容器。依赖下载与镜像构建可联网，运行验收使用离线 Mock 或受控本地服务，不向学校请求。Docker 证据说明实际架构和基础镜像，不替代 Windows 或其他平台的原生证据。

优先复用现有平台材料和恢复规则。Linux 必要的无图形材料适配属于同一服务的后端，不另建独立账号索引；不能因临时没有桌面密钥环就退回明文密码、明文业务缓存或每次手动重新登录。确有技术限制时给出失败证据和可选实现，由监督者在已授权范围内裁定。

## 审查重点

1. GUI 已开时命令被单实例逻辑吞掉，以及命令运行时 GUI 被误判已启动：由 H0/H2 验证双向启动。
2. 两个进程同时恢复、退出、切号，以及旧请求晚到：由 H1-b 验证持久代次和结果交付，不仅验证进程内队列。
3. Linux 无图形会话、凭据服务缺失、进程重开及认证过期：由 H0/H2-linux 分别验证依赖和真实合成材料后端，Mock 身份恢复不能替代原生存储证据。
4. 引擎日志污染 JSON、空输入、管道关闭、取消和文件交付失败：由 H2/H3 验证输出与副作用，不用 Widget 数量代替终端行为。
5. 旧数据、两份历史索引、账号别名或密钥缺失：由 H1-b/H2 验证原件保留和明确错误，不自动创建新别名绕过旧数据。

## H0：三平台运行路线与最小样机

H0 已完成路线审查。输入为本计划、起始提交、继承改动清单及旧审查定位。原型、日志和容器文件放 `.ubaa_local/command_mode_h0/`；长期结论只更新本文、现有合同、决策和状态。

主要核对位置：三个桌面 runner、`apps/ubaa_flutter/lib/main.dart`、`packages/ubaa_host/lib/src/`、`packages/ubaa_platform/lib/src/`、现有 CLI 库和构建/验证入口。

- [x] 逐项记录旧脏改动的去向，保留公共认证修复候选，停止扩展将退役的 worker。未知来源改动保持原样。
- [x] 在锁定 Flutter/FRB/插件版本上确定 GUI 与命令的入口分流、必要插件、参数传递、输出和退出机制。命令入口早于窗口创建和 GUI 单实例检查。
- [x] 建立最小可运行原型：调用已有 Core/Bridge 读取私有合成日程，输出可解析 JSON 和正确退出码；覆盖非法参数、App 未运行/已运行和命令结束后 GUI 仍可使用数据。不能只硬编码固定 JSON 或通过旧 CLI 生产任意索引入口预置身份。
- [x] 尽早用 Docker 或可用 Linux 环境验证无 DISPLAY、无 Wayland、无 Xvfb 的进程启动、必要插件和 Rust FFI；缺少材料服务时给出明确诊断，并确定后续可非交互取得保存材料的接线。
- [x] 为 Windows 核对原生入口、控制台和管道行为；有可用执行环境则实测，否则明确保留原生验证缺口，不虚构 macOS/Linux 结果。
- [x] 冻结下一单元的具体文件、输入输出类型、恢复服务接口和平台能力表。命令解析可复用 Rust 库或迁到命令模块，选择只保留一份实现的最小路径。
- [x] 保存失败与成功证据、冷启动时间和内存观察；完成实际改动所需检查并本地提交文档或经充分验证的最小入口。随后停止，交主聊天审查。

H0 通过表示运行路线已有可复现依据、下一单元可直接实施，不表示四项共享或三平台正式可用。某平台工具不可用时保留具体缺口，可推进不依赖该证据的公共服务工作。原型不改真实账号或生产数据。

### H0 运行路线与样机证据

本轮基线为 `f8e3078f87b85b87f5477f714665abde8a9be8d4`。生产代码没有改动。样机、构建上下文、合成 SQLite、合成 keyring、失败与成功日志保存在私有忽略目录 `.ubaa_local/command_mode_h0/`。样机直接调用已有 `BridgeAgendaStore` 和 Core SQLite，没有建立旧 CLI 账号索引或使用材料 worker。固定合成别名只用于隔离试验，不提供生产身份能力。

核对的是锁定 SDK 和本地依赖源码：Flutter `3.41.9`，提交 `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`，Engine `42d3d75a56efe1a2e9902f52dc8006099c45d937`，Dart `3.11.5`，FRB `2.13.0`。安全存储门面为 `10.0.0`，Darwin/Linux/Windows 实现分别为 `0.2.0`、`3.0.3`、`4.1.0`。目录插件门面为 `2.1.6`，foundation/Linux/Windows 实现分别为 `2.6.0`、`2.2.2`、`2.3.0`。

| 平台 | 运行路线 | 实证与边界 |
|---|---|---|
| macOS | 原生 `main.swift` 在 `NSApplicationMain` 和 XIB 加载前分流。命令使用允许无 view 运行的 Flutter Engine，注册必要插件，执行独立 Dart 入口。GUI 独占 GUI 角色锁。 | 私有 AOT 分流和无窗口 Engine 两条试验均通过真实 Flutter GUI 开/关、命令运行中启动 GUI、命令结束后原 GUI 句柄继续查询。Engine 原生观察为 0 个窗口、无 FlutterViewController，目录插件调用成功。未接入生产 runner。 |
| Windows | 在 `wWinMain` 最前端解析命令角色，再选择无 view Engine 或 GUI。命令分支早于 GUI mutex、控制台重连和窗口创建。 | 已核对锁定 `flutter::FlutterEngine::Run/ProcessMessages/ShutDown`、`DartProject` 参数接口和插件注册。没有可用 Windows 系统、SDK 或 Wine，保留原生构建与终端验收。 |
| Linux | 同一 Dart 应用服务和生成 FRB 绑定编译为 AOT 命令组件，直接加载 Rust `.so`。GUI 分支继续使用 Flutter，命令在创建 `MyApplication` 前分流。 | Debian 12 arm64 Docker 中实际运行，不启动 Flutter Engine、GTK、GUI application ID 或虚拟显示器。运行组件与 App 一起交付，服务器无需安装 Flutter SDK。x86_64 和发行包仍待 H2。 |

FRB `2.13.0` 的运行库及当前生成绑定没有 Flutter 或 `dart:ui` 依赖，loader 明确支持 `dart run` 和 `dart compile exe`。因此 Linux 可以共用 Dart 服务和 Rust Core，同时避开图形运行时。构建期仍经锁定 Flutter workspace 解析依赖，再用仓库 `just dart` 编译；构建期依赖与服务器运行期依赖分别管理。

锁定 Linux SDK 的 public `fl_engine.h` 虽有 `fl_engine_new_headless`，该函数实际只包装 `fl_engine_new`。启动函数 `fl_engine_start` 位于 private header，构造还访问默认 GDK display。H0 选择已有实证的 Dart AOT 路线，不依赖 private Engine API。macOS 的 `FlutterEngine` 无 view 构造、运行和关闭，以及 Windows 的无 view Engine，均有锁定版本公开接口。

单实例只约束 GUI。macOS 当前按 Bundle ID 枚举其他进程，后启动的 GUI 可能把命令进程当作已有 GUI，因此必须替换为 GUI 角色锁或可识别端点。Windows 只在 GUI 分支持有现有 mutex，Linux 命令不注册 GUI application ID。共享账号和会话的并发规则由 H1-b 处理，不能用 GUI 单实例替代。

参数从原生 argv 以字符串数组传给 Dart 入口。Windows 保留 `CommandLineToArgvW` 到 UTF-8 的转换。公共命令服务接受独立的输入、输出、错误输出与完成通道，不直接依赖窗口或全局 `print`。原生保留继承的管道句柄，Engine 日志归入 stderr，JSON 只写命令输出通道。macOS 首次 Engine 试验中，Debug 的 VM 服务日志确实污染了 stdout；私有样机改为原生保存输出句柄、重定向 Engine 日志、通过 MethodChannel 流式交付命令输出后，JSON 解析通过。正式通道还需验证容量、背压、写入失败和取消。Windows 不在命令路径调用会将输出重连到 `CONOUT$` 的 `FlutterDesktopResyncOutputStreams`。完成时先刷新输出、释放本消费者的 FRB/本地句柄，再关闭本进程 Engine 和返回退出码，不调用全局退出账号。

私有样机只实现合成数据创建、查询和保持句柄三种操作，其简化 JSON 与退出码用于检验运行链路。正式命令继续保留 CLI schema v13、human/JSON 和现有退出码。H3 将可复用 Rust 命令定义、解析、输出合同与测试迁到独立命令库，执行时接收公共服务已经核实的账号与客户端，删除独立资料生命周期。`core-live` 在 H4 迁为开发工具，不与 App 启动混合。

### Linux SSH 材料后端

Docker 基础为 `rust:1.95.0-bookworm`，架构 `aarch64`，镜像 digest 为 `sha256:6258907abe69656e41cd992e0b705cdcfabcbbe3db374f92ed2d47121282d4a1`。构建只复制阶段基线所需 workspace 源码、锁定 Dart 依赖和合成样机，不挂载真实配置或用户目录。运行容器使用 `--network none`、`--cap-drop ALL` 和 `no-new-privileges`，仅挂载任务脚本与私有合成证据目录。DISPLAY、WAYLAND_DISPLAY 均未设置，Xvfb 不存在。

实际通过了 Dart AOT→既有 FRB→Rust Core→SQLite 的读取。另将锁定 `flutter_secure_storage_linux 3.0.3` 的 `Secret.hpp` 原生后端接到私有 Dart FFI 适配，在两个独立 D-Bus 会话和 Secret Service 进程之间保存、读回合成值。缺少服务时返回 `material_unavailable` 和退出码 7。该试验证明后端可以脱离图形显示运行，尚未实现生产 `SecureMaterialTransport`，也未验证当前 App keyring item 的原位连续性。H2 必须保留原 schema、label、account 属性及材料键，不能直接采用样机合成 schema。

Linux 正式命令材料适配使用同一用户的 D-Bus Secret Service/libsecret，复用 App 材料数据，账号索引只有一份。SSH 部署需要可非交互取得已保存材料的用户服务：例如登录时由 PAM 解锁的 keyring，或由部署环境安全交付解锁材料的用户服务。样机用 stdin 中的非空合成密码解锁两次，证明重开服务可读取加密 keyring。真实部署的启动、解锁和锁定诊断留到 H2 验证，不把合成密码固化进程序，不降级到明文凭据或明文业务缓存。无服务、材料锁定或解锁需要交互时，命令明确失败，不要求先启动 GUI。

目录服务也必须脱离 GUI。Linux 目录插件在没有 application ID 时回退为可执行文件名，macOS 使用 bundle ID，Windows 使用 EXE 的 CompanyName/ProductName，直接套用另一可执行文件的默认目录会分裂资料。公共目录解析接口固定当前 App 的资料空间，再将同一绝对目录交给消费者，保留 `UBAA_CONFIG_DIR`、原随机 alias、CacheKey 和旧路径冲突检查。

### H0 验证范围与后续验收

macOS AOT 的成功、非法参数和缺失动态库分别返回 0、2、7，stdout/stderr 分开，全部进程结束。真实私有 Flutter GUI 与命令在同一个合成日程库上读写，GUI 保持的原句柄可读到命令新增事项。命令运行中启动 GUI、命令结束后 GUI 再次读取也通过。Linux 同样通过成功和参数错误，并在断网环境验证材料后端。样机不持有 `UbaaClient`，没有学校 HTTP 或网关探测。

新进程启动观察只用于路线选择：macOS AOT 首次普通查询约 22ms，私有 App 原生分流首次调用约 2.06s，后续创建约 120ms；无窗口 Engine 新进程首次约 2.3–2.7s，后续约 0.37–0.80s。单次计时观察为 AOT macOS 约 0.12s、RSS 31.1MB，无窗口 Debug Engine 约 0.43s、RSS 272.9MB，Linux AOT 约 0.00–0.01s、RSS 30–31MiB。macOS 选择 Engine 以复用现有平台插件，接受当前样机观察到的启动和内存开销，生产 Release 仍需另测。Rust 动态库为 Debug，文件系统缓存未清空，未测登录和完整生产启动，不能据此制定性能保证。

Windows 待验项目为：原生构建、无 view Engine 和插件事件循环、GUI 开/关及反向启动、cmd.exe/PowerShell、重定向与管道、Unicode/空参数/引号/反斜杠、stdin EOF、取消/期限、真实子进程退出码。macOS/Linux 的成功不填补这些项目。macOS 生产沙箱、旧目录与 keyring 连续性，Linux 实际 SSH 用户服务、旧材料连续性和 x86_64，同样留到 H2。

H0 只提交设计、决策和状态文档，未修改生产认证、读取、存储或跨语言入口。继承 13 项实验逐项登记在私有 `handoff.md`，原补丁和新文件哈希保持，未混入 H0 提交。派生身份失效回归及四个 Core 修复候选留 H1-b 独立审查，旧 worker 与对应依赖/测试留 H3/H4 迁移或删除时登记覆盖。

## H1：共同应用服务与跨进程状态

按 H1-a、H1-b 两个独立单元使用新会话。H0 交付具体文件与接口后执行，避免一边改平台入口一边猜公共服务。

H1-a 提取现有 App 无感恢复：主要修改 `packages/ubaa_app/lib/src/controller/recovery/`、必要公共服务目录、backend 合同与 GUI 接线。复用 Core 的 `recover_required_session` 和 `login_required_route`，不复制协议实现。

H0 将 H1-a 收敛为以下文件与接口，下一单元从新的固定基线开始：

| 文件 | 责任 |
|---|---|
| `packages/ubaa_app/lib/runtime.dart`（新增） | 公开纯 Dart 的恢复合同、服务和所需 DTO，不导出完整 Controller 或平台总桶。 |
| `packages/ubaa_app/lib/src/contracts/session_recovery.dart`（新增） | `RecoveryScope`、`RecoveryResult`、取消与期限合同。 |
| `packages/ubaa_app/lib/src/services/session_recovery.dart`（新增） | `RequiredSessionRecovery.ensureRequiredSession(feature, scope, deadline, cancellation)`，集中会话复用、凭据许可、目标路线恢复和结果核对。 |
| `packages/ubaa_platform/lib/credentials.dart`（新增窄入口） | 公开已有纯 Dart `CredentialVault` 及抽象，不复制 DTO 或改 namespace。 |
| `packages/ubaa_app/lib/src/bridge/auth/required_session.dart`（新增或同等小模块） | 从当前 part 聚合中提取最小 Bridge 适配，只调用现有两个恢复方法，GUI 与命令复用。 |
| `controller/recovery/required.dart`、`startup.dart`、`resume.dart`、调度及 state 接线 | Controller 调用同一服务。保留界面状态、前后台优先级、首页刷新、提示和写操作等待，不把这些职责搬进命令运行时。 |
| `packages/ubaa_platform/lib/src/defaults.dart` 与 Host 组合根 | 分出只初始化目录、材料、凭据和账号的最小工厂，GUI 原工厂组合该能力。命令不启动 `bootstrapUbaaHost`、完整首页或图片/位置等无关插件。 |

`ubaa_domain`、现有 `contracts/recovery.dart`、`contracts/backend.dart` 和凭据抽象的源码依赖闭包可供纯 Dart 使用。当前 `BridgeBackend`、`BridgeContext` 和部分合同经平台总桶引入 Flutter，不能直接放进 Linux AOT。先收窄所需恢复适配，不要求一次迁移全部 backend，也不为运行时分流新建第二套账号状态。只有后续明确需要脱离 Flutter workspace 的独立构建时，才考虑将这些纯模块机械迁成新包。

`RecoveryScope` 捕获已核实 alias、预期身份、自动恢复许可、账号/路线/后端代次，并提供有效性检查。服务在每次 await 后、提交凭据前和结果交付前重查 scope。H1-a 先接现有进程内代次，H1-b 再接持久共享代次及跨进程协调。`RecoveryResult` 复用 `RecoveredRouteSession`，另外区分 `reused` 与 `reauthenticated`，使 GUI 只在实际重登录后撤销同路线旧计划。

期限与取消不能只用 `Future.timeout` 丢下仍在执行的认证。到期后先撤销本次后续凭据提交和结果交付许可，消费者在明确期限内返回取消或超时。服务保留在途调用的管理句柄，禁止迟到结果触发补读或后续登录，并负责取消与有界收尾。服务关闭也有上限，不能把无限等待转移到销毁阶段。已有 Bridge 无法硬中止时，H1-a 必须证明底层调用的最大收尾期限，或增加最小的中止能力；缺少可验证上限时，该验收项保持未完成。恢复服务不接受自动重放学校写入的闭包。普通消费者关闭只释放本进程资源，全局退出继续走既有显式流程。

H1-a 的失败用例必须覆盖：无 Controller 的消费者恢复后继续原读取；有效会话零凭据提交；明确过期只恢复所需路线；临时网络错误及缺失目标路线零密码提交；关闭自动登录、主动退出、材料不可用和身份不符；无效密码/交互要求的运行期阻断；读取凭据或登录挂起时切号、退出、取消和期限到达，并断言消费者及服务关闭均有界结束、迟到结果不触发后续动作；后端返回异路线或异身份；同 scope 在途合并；写准备/提交/回读收尾前不恢复；关闭命令不撤销其他消费者。本机日程单独证明学校调用次数为零。Core Mock 路线固定并注入 `NeverProbe`。

聚焦命令使用现有 `just flutter-test ubaa_app test/recovery`、`test/session`、`test/write/lifecycle_test.dart`、`test/agenda/lifecycle_test.dart`，以及 Host 的 `test/recovery`、Platform 的 `test/local_accounts_test.dart` 和 `test/credentials`。新增纯服务用例可用 `just dart` 在无 Flutter Engine 的进程中编译运行，证明实际依赖闭包。改动涉及身份与恢复边界，聚焦后执行 `just check-changed base=<H1-a起点> mode=full`，Flutter、原生和生成串行。

- [ ] 先证明过期会话在命令消费者中不能恢复的失败用例，覆盖目标路线、有效会话复用、保存凭据自动登录、临时错误、主动退出和交互要求。
- [ ] 提取不依赖 Widget/页面生命周期的恢复服务，GUI 与命令消费者使用同一实例规则和状态机。命令有期限与取消，恢复成功后继续原读取；本机操作不触发学校请求。
- [ ] 复跑 GUI 原有恢复、路线切换、旧结果交付和学校写入资格回归，聚焦后完成完整相关验收。

H1-b 统一账号和数据访问：主要修改平台账号/目录边界、Core 会话及缓存/日程生命周期、Bridge 与服务接线。

- [ ] 先增加两个独立消费者/进程的失败用例，覆盖同时恢复、切号、退出后重登、旧派生失效晚到、进程结束及崩溃恢复。
- [ ] 统一资料空间、账号映射、恢复许可和持久代次，保留原 alias/key。定义一致的锁顺序；网络和用户交互期间不长期占全局排他锁。
- [ ] 分开普通句柄关闭与全局退出；事务提交和结果交付核对身份与代次。外部会话更新后安全重建客户端，不重放旧写意图。
- [ ] 完成遗留公共认证撤销问题的最小修复及有意义回归，保留已有缓存加密、日程明文、账号隔离和过渡中断保护。
- [ ] 完整相关验收后用新只读上下文审查，再推进平台接入。

## H2：正式命令入口与平台运行

共用命令接线先完成，macOS、Windows、Linux 各自作为独立验收单元和新会话。位置为 H0 确认的命令模块、三个 runner、平台目录/材料适配及入口集成测试。

- [ ] 各平台均验证 GUI 开/关两种状态、GUI 与命令相互启动、同资料空间读写、无感恢复、stdout/stderr、退出码、取消、非 ASCII 参数和路径。
- [ ] Linux 另验证纯 SSH/容器环境、进程重开后保存材料可用、Mock 认证过期后自动恢复，以及缺失依赖时的明确诊断。不得靠虚拟显示器完成该验收。
- [ ] 同一账号使用原材料和目录，旧 App/CLI 有两份资料时保留并识别冲突，不按用户名简单覆盖。调整 macOS 沙箱或打包时单独证明旧数据连续性。
- [ ] 保持移动端行为，必要时更新 Bridge/生成物；实际执行平台构建、最小原生能力及完整相关验收，按平台记录。

## H3：迁入命令能力与日程完整操作

位置为现有 `apps/ubaa_cli/src/command/`、`execute/`、`io/`、`local_agenda/` 的迁移目标和命令测试。保留当前 CLI schema v13 及各操作安全语义；确需破坏兼容时先更新合同和消费方。

- [ ] 列出现有命令、参数、JSON/退出码和测试的去向，将执行统一接入公共服务，禁止复活独立账号生命周期。
- [ ] 迁移认证和既有查询/写操作，保留交互与写资格边界、超时、参数错误和输出覆盖。
- [ ] 完成日程 CRUD、重复修改/删除、完成与重新挂起、覆盖、原子 compare-and-clear 和 `.ics` 安全文件交付；Core 已有功能直接复用。
- [ ] 验证输入文件/stdin、原子输出、不覆盖失败、容量和路径错误；文件访问采用平台合法权限，不把本机明文日程扩展为业务缓存明文。
- [ ] 聚焦后完整验收，并按可审查主题提交。

## H4：退役独立 Rust CLI

在新入口覆盖既有命令及三个目标平台的必要行为后执行。Rust Core 保留；可复用命令库可继续使用 Rust，不为删除目录强行重写语言。

- [ ] 将 `core-live` 移到独立开发工具位置，并更新 `scripts/live/`、justfile、workspace、检查选择器和工具合同测试。
- [ ] 移除独立 `ubaa` main、CLI 专属账号索引和材料 worker，迁出后清理原 `apps/ubaa_cli`。删除测试逐项登记保留覆盖，不能删除门禁解决失败。
- [ ] 核对新二进制入口、包安装、帮助、文档、JSON Schema、CI 和平台脚本；完成新入口端到端与完整确定性验收。
- [ ] 用新只读上下文审查整体差异，确认没有独立产品账号体系残留，才宣布退役完成。

## H5 及后续：日程界面、北航云盘与同步

继续已授权产品范围：五栏导航、日程列表/详情/编辑与导出、北航云盘 B1—B4 完整能力、日程 B5 同步、既定周/月视图和宽屏布局。每个独立单元重新开执行会话，具体协议以已有来源对照为准。课程逐节、同步明文 `UBAA/agenda.json`、上传失败不自动重试和结果未知先读回等决定保留。

## 验证、授权与上下文

遵守 [AGENTS.md](../../AGENTS.md) 和[开发命令](../development/commands.md#检查选择与完成条件)。开发验证只使用合成材料和 Mock 学校 HTTP，路线测试显式固定路线并注入 NeverProbe，防止默认网关探测。真实认证/读取仍需当前功能和路线授权，真实写入逐操作授权；不从自动恢复产品设计推导开发期学校请求授权。只本地提交，不推送、不签名、不发布。

每单元先保留有意义的失败反例，再最小实现、聚焦验证和相应完整验收。文档改动执行文档级检查，身份、并发、存储和跨语言生产改动使用阶段起点基线完成完整相关检查；继承脏改动单独记账。Flutter、原生和生成检查串行，不机械重复同候选有效证据。

监督状态保存在私有 `.ubaa_local/supervision/development_followup/state.json`。每个执行聊天只接收当前阶段说明、基线、必要合同和证据路径。交接写清完成/未完成、提交/脏改动、接口、失败/通过日志与下一步，避免复制长篇工具历史。工作扩大或上下文拥挤时在可恢复位置交接停下，主聊天确认旧会话空闲后另开新会话；同一时刻只有一个源码写入者。

阶段完成后由主聊天核对 Git 与证据；身份、存储、并发、学校写资格和跨语言边界用新的只读审查上下文。发现实质缺陷先修复，不推进依赖阶段。自动接续只在阶段通过接续、实质缺陷、执行失败或需要用户决定时通知，状态未变保持安静。技术细节可在已确认范围内自主裁定，不因普通实现选择反复请求用户确认。
