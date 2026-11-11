# 桌面命令模式 H0 样机证据（归档）

本文保存 [桌面命令模式](../../design/desktop-shared-state.md) 中移出的 H0 样机证据与原交付进度，仅供追溯运行路线的选择依据。现行规则以设计文档和 [App 命令模式设计](../../design/app-command-mode.md) 为准。

## 原文件头部（2026-11-05）

更新：2026-11-05。GUI 与终端使用同一账号和本机数据。统一命令模式、[日程界面](../../design/agenda.md)和北航云盘已进入产品整合分支。macOS 和 Windows 已通过隔离合成材料的命令与 GUI 双进程验收，Linux AOT 命令已通过隔离 SSH/PAM 验收。具体提交与验证范围见[当前状态](../../project/status.md)。

## 原“现有成果与收尾边界”

- 整合分支包含 Core 日程、学校投影、独立 Bridge/Dart 服务和范围快照导出。业务缓存继续加密，日程继续逐记录明文 SQLite。
- 共享服务负责恢复、账号索引、持久代次和关闭与退出。路线重开继承共享账号绑定和关闭控制；发送请求前在材料锁等待结束后重新检查发送条件。
- 公共 Rust 命令库、Windows 工具链和三平台命令入口已接入统一运行时。Windows 已验证原生目录与网络插件、控制台输入输出、双进程共享和正常关闭。
- 主目录旧 CLI 的 13 项未提交实验保留。整合分支保留原有效测试覆盖，独立宿主及专属材料路径已迁出。

客户端重开必须让账号绑定、取消和关闭控制与当前 Core 保持一致。普通关闭只释放本进程资源，全局退出撤销共享账号访问。已发送的学校写请求继续按未知结果规则收尾，不因恢复会话自动重放。

## 原“平台运行选择”表

| 平台 | 目标运行方式 | 仍需交付 |
|---|---|---|
| macOS | 原生入口在窗口与 GUI 单实例检查前分流，无 view Flutter Engine 复用平台插件 | 真实旧材料连续性与签名 Release 行为 |
| Windows | 独立的 `ubaa.exe` 使用无 view Flutter Engine，GUI 的单实例锁只约束 GUI。Windows 11 x64 Debug 验证了 cmd、PowerShell、Unicode、流与退出码，以及 DPAPI 和本机日程共享 | 签名 Release、安装升级与真实旧材料连续性 |
| Linux | 同一 Dart 服务编译为 AOT，直接加载生成 FRB 与 Rust 库，复用 App 材料键和账号索引。Debian 12 arm64 实际 SSH/PAM 已通过 | 其他架构、发行包安装和实际部署验证 |

下列为 2026-11-01 H0 样机的历史依据，用于说明运行路线选择。后续候选状态以状态页为准。

## H0 运行路线与样机证据

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

## Linux SSH 材料后端

Docker 基础为 `rust:1.95.0-bookworm`，架构 `aarch64`，镜像 digest 为 `sha256:6258907abe69656e41cd992e0b705cdcfabcbbe3db374f92ed2d47121282d4a1`。构建只复制阶段基线所需 workspace 源码、锁定 Dart 依赖和合成样机，不挂载真实配置或用户目录。运行容器使用 `--network none`、`--cap-drop ALL` 和 `no-new-privileges`，仅挂载任务脚本与私有合成证据目录。DISPLAY、WAYLAND_DISPLAY 均未设置，Xvfb 不存在。

实际通过了 Dart AOT→既有 FRB→Rust Core→SQLite 的读取。另将锁定 `flutter_secure_storage_linux 3.0.3` 的 `Secret.hpp` 原生后端接到私有 Dart FFI 适配，在两个独立 D-Bus 会话和 Secret Service 进程之间保存、读回合成值。缺少服务时返回 `material_unavailable` 和退出码 7。该试验证明后端可以脱离图形显示运行，尚未实现生产 `SecureMaterialTransport`，也未验证当前 App keyring item 的原位连续性。H2 必须保留原 schema、label、account 属性及材料键，不能直接采用样机合成 schema。

Linux 正式命令材料适配使用同一用户的 D-Bus Secret Service/libsecret，复用 App 材料数据，账号索引只有一份。SSH 部署需要能在无图形环境下提供已保存材料的用户服务。Debian 12 arm64 的实际验收使用同一用户的 D-Bus 和 GNOME Keyring，由 OpenSSH 密码登录经 PAM 解锁 `login` 集合。两个无图形 SSH 会话可读写同一日程，关闭一个会话后，另一个仍可读取并导出 ICS。公钥登录没有提供解锁密码，集合仍锁定时日程命令返回 `material_unavailable`、退出 7；D-Bus 上没有 Secret Service 时返回相同结果。

材料探测在同一材料锁内先读探测键，读失败时保持原事务状态。读成功后才标记并执行可能写入的探测操作。写入结果不明时仍保留未完成标记并阻止后续访问。实际 SSH 验收中，锁定和缺少服务均未改变已提交标记；密码登录解锁后，命令恢复并读取原日程。验证只使用隔离容器中的合成用户和材料，部署安装、旧真实材料连续性和其他架构仍需验收。

目录服务也必须脱离 GUI。Linux 目录插件在没有 application ID 时回退为可执行文件名，macOS 使用 bundle ID，Windows 使用 EXE 的 CompanyName/ProductName，直接套用另一可执行文件的默认目录会分裂资料。公共目录解析接口固定当前 App 的资料空间，再将同一绝对目录交给消费者，保留 `UBAA_CONFIG_DIR`、原随机 alias、CacheKey 和旧路径冲突检查。

## H0 验证范围与后续验收

macOS AOT 的成功、非法参数和缺失动态库分别返回 0、2、7，stdout/stderr 分开，全部进程结束。真实私有 Flutter GUI 与命令在同一个合成日程库上读写，GUI 保持的原句柄可读到命令新增事项。命令运行中启动 GUI、命令结束后 GUI 再次读取也通过。Linux 同样通过成功和参数错误，并在断网环境验证材料后端。样机不持有 `UbaaClient`，没有学校 HTTP 或网关探测。

新进程启动观察只用于路线选择：macOS AOT 首次普通查询约 22ms，私有 App 原生分流首次调用约 2.06s，后续创建约 120ms；无窗口 Engine 新进程首次约 2.3–2.7s，后续约 0.37–0.80s。单次计时观察为 AOT macOS 约 0.12s、RSS 31.1MB，无窗口 Debug Engine 约 0.43s、RSS 272.9MB，Linux AOT 约 0.00–0.01s、RSS 30–31MiB。macOS 选择 Engine 以复用现有平台插件，接受当前样机观察到的启动和内存开销，生产 Release 仍需另测。Rust 动态库为 Debug，文件系统缓存未清空，未测登录和完整生产启动，不能据此制定性能保证。

Windows 待验项目为：原生构建、无 view Engine 和插件事件循环、GUI 开/关及反向启动、cmd.exe/PowerShell、重定向与管道、Unicode/空参数/引号/反斜杠、stdin EOF、取消/期限、真实子进程退出码。macOS/Linux 的成功不填补这些项目。macOS 生产沙箱、旧目录与 keyring 连续性，以及 Linux 旧真实材料连续性和 x86_64 仍待验收。

H0 只提交设计、决策和状态文档，未修改生产认证、读取、存储或跨语言入口。继承 13 项实验逐项登记在私有 `handoff.md`，原补丁和新文件哈希保持，未混入 H0 提交。派生身份失效回归及四个 Core 修复候选留 H1-b 独立审查，旧 worker 与对应依赖/测试留 H3/H4 迁移或删除时登记覆盖。
