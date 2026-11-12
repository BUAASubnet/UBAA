# App 命令模式设计

本文供实现桌面命令入口的开发者使用，说明统一 App 命令链路、输入输出、恢复与各平台运行条件。产品行为见[桌面命令模式](desktop-shared-state.md)。

文中 H1、H2 等编号是命令模式开发时的任务编号：H1 指共享账号与恢复服务，H2 指公共命令运行时与各平台入口单元，H3、H4 分别指命令库迁移和 `core-live` 迁出，用于对应决策记录与历史证据。

## 公共链路与模块责任

原生入口保留 argv 和标准流，识别 GUI 或命令角色，然后将参数数组传给纯 Dart 命令入口。Rust 只解析一次，返回不透明计划及能力需求。Dart 按计划取得最少的目录、材料和账号能力，通过 H1 公共服务取得有效 scope 与 Core 句柄。Rust 执行一次尝试，Dart 按规则处理认证过期，最后由 Rust 统一渲染。

| 层 | 责任 |
|---|---|
| 原生 | 角色分流、标准流和信号、单调起点、消息循环、本进程强制收尾 |
| 纯 Dart 命令运行时 | 最少能力初始化、H1 scope 与句柄、一次恢复和重跑编排、普通关闭 |
| `crates/ubaa_command` | 唯一 clap 命令树、计划、typed 输入、backend trait、单次执行、结果与 human/JSON 渲染、退出码 |
| Bridge 命令适配器 | 在 Rust 内借用已有 `BridgeClient`、`BridgeAgendaStore` 和可选缓存句柄，落实读取池与认证/写入排他规则 |
| Core facade | 路线、学校协议、会话、业务数据和最终写入规则 |

原生只识别角色标记，Dart 不复制命令语法。命令入口不启动 `bootstrapUbaaHost`、首页 Controller、联网监听或业务预取。句柄通过 opaque 引用传递，不传裸指针、密码、Cookie 或序列化 Session。Bridge 依赖命令库，命令库不依赖 Bridge。

公共 Rust 接口按以下阶段组织：

```text
parse(argv) -> CommandPlan
CommandPlan.requirements() -> CommandRequirements
prepare_input(plan, input, control) -> PreparedCommand
execute_attempt(prepared, backend, control) -> AttemptOutcome
AttemptOutcome = Completed(ResultHandle) | AuthExpired(target, route, result) | SharedStateChanged(target, result)
ResultHandle.render(control, stdout, stderr) -> exitCode
```

固定路线、显式聚合认证和本机日程提供各自的执行适配。`ResultHandle` 不允许宿主自行构造成功正文。`PreparedCommand` 保留一次输入快照，业务重跑不再次消费 stdin。命令分类为 `Local`、`Readonly`、`ExplicitAuth`、`SchoolWrite`，按具体操作判断。Signin perform、LibBook reserve/cancel、Bykc select/deselect/sign、Cgyy submit/cancel、Ygdk submit 和 Evaluation submit-pending 均属于学校写入。

生产命令使用 App 共享材料和当前账号，不使用旧独立 Rust 宿主、专用账号索引或材料 worker。公共协议和命令回归位于 `crates/ubaa_command/tests`，`core-live` 位于独立的 `tools/core_live`，覆盖归属见[测试策略](../development/testing.md#命令宿主替换后的覆盖)。

## 身份、本机数据与恢复

H1-b3 的命令工厂从安全索引捕获不可自行构造的活动账号快照，核对身份、恢复许可、持久代次及目录，然后建立命令 scope。argv 用户名、裸 alias、普通 profile 和旧 JSON 均不能建立合法账号映射。显式登录登记继续使用真实成功 profile/Core 身份能力，普通状态查询不能兑换登记能力。

`Local` 计划只取得合法本机账号和 AgendaStore。仅显式 `--school-cache` 才取得同账号已有缓存，不创建网络客户端、不探测网关、不调用认证状态或恢复服务。缺索引、坏库、缺 CacheKey 或冲突时保留原件并失败，不新造 alias 或密钥。关闭自动登录不阻止合法本机日程访问。业务缓存继续加密，日程保持独立明文 SQLite，缓存清理不删除日程。

恢复目标独立于 UI 菜单，覆盖十五个功能及 user。Bridge/Dart 的 `RecoveryTarget` 与 Core user 受控恢复 facade 逐项映射，user 复用 `Operation::User`。旧 feature API 可作兼容包装。scope 的跨进程有效性依赖 H1-b3 的异步持久校验和本进程撤销通知，内存布尔值不能替代持久代次核对。

网络前后、提交凭据前、学校写入前及交付前均核对 scope。材料锁只覆盖短本机事务，不跨网络、交互和慢管道持有。恢复前释放本次尝试的读取 guard，恢复完成后只使用 H1-b3 确认的合法继任 scope/客户端，不放宽 Core revision/CAS。

只读恢复规则如下：

1. 在线只读计划先按 H1 规则复用或恢复所需会话，再执行读取。
2. 首次尝试明确返回 `authentication_required`，且路线已知、身份一致、scope 有效、允许恢复时，丢弃整条尚未交付的尝试。网络错误、解析错误、无路线错误和异身份均不提交密码。
3. 调用同一个 H1 恢复服务。成功后使用固定输入从命令起点完整重跑一次。第二次过期直接失败，不再恢复。分页命令丢弃第一轮所有页面，stdout 只交付最终尝试。
4. 同账号外部会话更新，只有 H1-b3 确认可以续接时才重建客户端重读，并消耗同一重跑额度。退出后重新登录、切号和许可撤销均停止旧命令。
5. 显式登录、退出和聚合状态走认证服务。学校写入只可在准备资格前恢复；准备或提交后的过期、冲突、取消均终止该写意图，不自动重新准备或提交。

写请求可能已经发送时保留 `outcome_unknown`，只按明确目标和原路线只读核对。未查到结果不能触发重发。命令写 backend 与 GUI 共用 prepare/commit/readback 服务，保留资格目标、摘要、路线、120 秒有效期和单次消费规则。

## 输入、输出、期限与退出码

输入由宿主注入，支持逐行、EOF、错误和取消。密码由宿主的隐藏输入能力准备，不新增明文密码 argv，也不把密码交给普通回显输入。文件路径由 Rust 解释一次，保持相对当前目录语义。Windows 逐项传参数，不重新拼接命令字符串。

执行返回 typed 结果，不向 stdout 渲染。最终尝试确认后才能输出。Rust renderer 保留 [CLI JSON 合同](../contracts/auth-and-user.md)规定的 envelope、human 格式和帮助参数树。本机结果继续使用 `feature=agenda`、operation、accountState，不伪造 resolvedRoute。内部恢复状态、传输序号和材料诊断不新增 JSON 字段。云盘传输进度最多每 500 毫秒向 stderr 交付一行，逐次等待实际写入，不占用 stdout 的最终结果。进度输出失败取消同一命令并返回 7，总期限停止仍保留在线退出码 5。

有界输出采用拉取与确认：每块最多 64 KiB，每条流的队列及在途块合计最多四块；stdout/stderr 两条流合计最多 512 KiB。每条流每次只有一个尚未确认的块。生产线程在队列满时等待，消费端完成实际写入及刷新后才确认。不得使用无界 StreamSink 或先构造完整输出字符串代替背压。短写继续写入剩余字节，断管或刷新失败停止输出并返回 7，两条流都刷新完成后才允许返回 0。

macOS/Windows 在 Engine 初始化前复制继承的标准流句柄，将 Engine/VM/CRT 日志送至 stderr。Dart 通过专用通道传递字节，原生在非消息线程写管道。Linux AOT 直接使用继承 fd。消费端失败、取消或到期必须唤醒等待中的生产线程。交付开始前先核对 scope；开始交付后发生身份变化、取消或 I/O 错误就停止后续字节，不重跑、不追加第二个 JSON。管道可能留下不完整 JSON。

命令默认共用 120 秒总预算，从原生单调时钟起算。现有超时参数若存在则保持语义，并作为预算上限来源。stdin、锁排队、材料、恢复、业务重跑和输出共享剩余时间，阶段不重置预算。Ctrl+C、SIGTERM、完成通道断开和期限都撤销本消费者，不执行 logout。停止后最多两秒收尾，其中恢复服务关闭宽限最多一秒。尚未交付任何字节时，可用一次有限收尾通道交付停止诊断。

Rust `CommandControl` 控制异步尝试和输出队列。Core 的操作作用域读取同一个控制柄，在材料锁释放后的最终发送边界及对象流块同步检查原绝对期限，不依赖异步计时器抢占同步锁。任意同步 `BufRead`、`Write` 或原生材料调用不能由 async select 抢占，宿主必须提供可取消的适配器，并由进程收尾上限处理仍阻塞的本进程线程。H2-common-a 的队列与 Mock 证据不覆盖真实终端、原生材料或平台强制退出。平台单元必须用 barrier 证明各阻塞阶段可观察且有界。

| 退出码 | 行为 |
|---|---|
| 0 | 成功，输出及必要收尾完成；help/version 按原 clap 语义成功 |
| 2 | 参数或 typed 输入错误 |
| 3 | 认证失败、缺登记、旧身份能力 |
| 5 | 网络、在线期限、上游不可达、学校写入结果未知 |
| 6 | 上游变化或解析失败 |
| 7 | 本机材料/存储、内部故障、输出失败、在线取消、本机取消或期限 |

在线取消映射 `internal_error/7`，在线期限映射 `timeout/5`，本机取消或期限映射 `storage/7`。准确原因进入 stderr 和 JSON 错误消息。写入中停止须保守提示可能已发送、只读核对和禁止自动重试。首期不增加 130 或结构化取消码。语言入口装载前的动态库/OS 故障保留原生诊断，不能伪造成功信封。

## macOS

采用 Developer ID 分发并关闭 App Sandbox。保留 Bundle ID、Team 和产品身份，分别保留 Debug JIT 与 Release 实际需要的 Hardened Runtime 权限，不为加载便利扩大 library validation 豁免。平台单元同步更新 entitlement 检查脚本及失败反例，验证实际签名产物。签名、公证和发布另行实施。

同一 `.app` 主程序在 `NSApplicationMain`、XIB 和 GUI 锁之前分流。命令角色使用无窗口 FlutterEngine，窄注册材料等必要能力，运行 RunLoop，结束后关闭本进程 Engine。GUI 角色继续正常界面启动。GUI 专有角色锁放固定 OS 用户私有目录，O_NOFOLLOW、0600、非阻塞 flock，持有到 GUI 退出，不删除或替换锁文件。第二 GUI 只能经本机激活端点唤起持有者，不能按 Bundle ID 把命令误认作 GUI。

PATH 首期文档化安装 `~/.local/bin/ubaa-cli` 符号链接，直接 App 二进制支持 `--command`。默认 App 启动 GUI，名为 `ubaa-cli` 的命令入口无参数进入帮助。安装入口随 App 升级，不新增常驻守护进程。

目录保持既有 path_provider 算法。旧沙箱容器、非沙箱目标、历史 CLI 资料和旧签名先只读盘点。停用旧入口并等待全部旧进程退出后，取得迁移锁和已知旧锁，核对 UID、目录身份、权限和符号链接。目标为空才复制到同文件系统私有 staging；SQLite 用 backup API，或在全部连接关闭后完整处理主库、WAL、SHM。会话、alias、CacheKey、恢复许可、schema 及未完成材料事务都保留。验证后原子落位并持久化标记，异常可续接，旧资料不自动删除。目标冲突、密钥不一致、多个历史索引或事务未完成时停止，不按用户名合库或覆盖原件。

钥匙串优先原位延续 service/account、材料键和 ACL。Bundle ID 相同不能证明 designated requirement 连续。先用合成条目核实旧新签名；必要时由仍满足旧 DR 的迁移版增加新 App 的窄 ACL 信任，或用户对确切条目手动授权。不得批量允许所有应用，不枚举导出明文。出现系统 Keychain 权限提示时立即停止相关自动测试。

Release 性能目标：热启动本机命令 P95≤0.5 秒、正常冷启动 P95≤1.5 秒、峰值 RSS≤150 MiB。固定硬件、架构、版本和签名状态，GUI 开关各至少三十次，记录首字节、退出、P50/P95、RSS 和 physical footprint。冷启动、热启动、首次 Gatekeeper 和首次迁移分别测量。超出目标先定位 Engine、插件和材料探测，并报告 AOT 评估；超出两倍以上阻塞 H2-macos 放行。Debug 样机不作 Release 指标。

## Linux 与 SSH 部署

采用纯 Dart AOT、既有 FRB 和 Rust `.so`，在 GTK/GApplication 之前分流，不启动 Flutter Engine，不依赖 DISPLAY、Wayland 或 Xvfb。GUI 使用原 runner，命令不登记 GUI application ID。命令运行包与 GUI 严格同版本，SSH 可只安装命令运行包。动态库只从受信安装目录加载，不搜索当前目录。构建来自锁定 workspace，运行期依赖按各架构 ELF/ldd 清单核实。

目录显式复现 GUI applicationId 和历史兼容逻辑，不使用 AOT 可执行名回退。保留 `UBAA_CONFIG_DIR` 业务覆盖，材料协调锁固定在 OS 当前用户的私有域，避免 HOME/XDG/配置覆盖分裂锁域。

材料强制 Secret Service。使用窄 libsecret Service API 适配 `SecureMaterialTransport`，保留锁定插件的 default schema/label、同一 Secret item JSON map、材料 v2 键前缀、alias 与 CacheKey。候选 item 不唯一时明确失败，不任意挑选。只连接 `org.freedesktop.secrets`，拒绝 file/portal 降级。使用异步或 GCancellable 操作；collection 锁定或返回 Prompt 时失败，不自动弹窗，不从业务 stdin 读取 keyring 密码。短材料事务和期限沿 H1 协调器，状态不明保留未完成标记。

首批发行版为 Debian 12 amd64/arm64，以及 Ubuntu 24.04 LTS amd64，最低 glibc 以 Debian 12 为准。SSH 部署指南由 Linux 单元提供并实际核实以下步骤：

1. 安装 libsecret、Secret Service、用户 D-Bus 和发行版的 gnome-keyring PAM 模块，使用同一系统用户及已有加密 keyring。
2. 通过发行版 user service/socket 接入同一用户总线，只启用必要 secrets 能力，不为每条命令新建 dbus-run-session。
3. 按目标发行版核对 PAM auth/session/password 接线，不直接替换系统 PAM 文件。用户服务启动与 keyring 解锁分别检查。
4. SSH 公钥登录不能从前序 PAM 获得密码。每次开机后使用已解锁用户会话，或经受保护交互通道手动解锁一次。未解锁时明确失败，口令不得进入 unit、环境、argv 或日志。
5. 提供库、总线、服务、default collection、Locked/Prompt 的脱敏排障和重启后再解锁说明。账号配置和恢复许可均为显式操作。

无图形 Docker 分别构建双架构 Release，记录镜像 digest、ELF 和动态依赖。运行非特权、drop capabilities、no-new-privileges、network none，不挂载真实材料。验证缺库/总线/服务、锁定/Prompt、后端降级、服务挂起、中断和重开。用同生产布局合成 item 验证 GUI→AOT→GUI 连续性、双进程 RMW 与崩溃阻断。实际 SSH/PAM、公钥未解锁及重启后解锁另做原生验证，Docker 不能替代登录会话证据。

## Windows

采用控制台子系统 `ubaa-cli.exe`，图形程序 `UBAA.exe` 使用 WIN32 子系统。两个程序位于同一目录，共用 data、Engine/Rust DLL 和版本清单。终端使用 `ubaa-cli`；图形启动器和快捷方式指向 `UBAA.exe`。CompanyName、ProductName、版本和资料目录规则保持一致，OriginalFilename 分别记录实际文件名。命令不取得 GUI mutex，复用 H1-b2 最终 DPAPI/DACL 材料适配，不新建命令材料库。

控制台入口使用 wmain，严格逐项 UTF-16→UTF-8，保留空参数和非 ASCII 内容。创建 DartProject、无 view FlutterEngine、必要插件与完成/取消通道，不创建 FlutterWindow。通过 `MsgWaitForMultipleObjectsEx`、PeekMessage/DispatchMessage 保持 Engine 消息处理，取消后继续处理收尾，不能只轮询 ProcessMessages。message-only window 与用户可见窗口分别检查。

继承句柄保持管道语义，不重连 CONOUT$。真实控制台使用 WriteConsoleW，重定向/管道输出无 BOM UTF-8。控制信号 handler 只设原子标志和事件，主消息线程通知 Dart，不在 handler 调 Dart/FRB 或持锁等待。CMake 新建无 WIN32 的控制台 target，资源/DLL/AOT 只安装一次，窄注册和链接必要插件，不手改生成文件。

使用已登录桌面的 `ssh windows` 原生 Release 验证 cmd、PowerShell 5.1、PowerShell 7.4+ 等待与退出码、GUI 双向启动、两个命令、Unicode/引号/尾反斜杠、EOF、慢管道/断管、Ctrl+C 和 DPAPI 连续性。分别测进程 UTF-8 字节与 shell 重定向文件，旧 PowerShell 可能转码。H0 的 Windows 源码审查不能替代原生证据。

## 验收

公共命令、共享服务、平台入口和旧宿主迁出按同一产品结果验收。旧命令合同、输入顺序、身份生命周期和只读开发工具覆盖已迁入公共库及 `tools/core_live`，具体映射见[测试策略](../development/testing.md)。原生进程验证检查实际标准流、退出码、共享材料和普通关闭行为。

共享运行时用 barrier 验证第二页过期完整重跑一次、第二轮再过期、503/无路线、两消费者取消一个、持久代次变化、凭据/HTTP/输出阻塞和迟到结果。断言密码提交数、业务调用数、学校写次数、交付次数及总期限。本机学校请求和网关探测必须为零。公共和平台单元还覆盖 GUI 开关、双向启动、两个命令、普通关闭后 GUI 继续使用，以及外部退出/切号/会话更新。

全部认证、查询、学校写入与本机日程命令共用上述链路，`core-live` 独立保留为开发工具。验收范围按[检查选择与完成条件](../development/commands.md#检查选择与完成条件)执行完整验收，Windows 原生结果单独记录。真实账号和学校写入遵循 [AGENTS 授权规则](../../AGENTS.md#真实账号与验收范围)。
