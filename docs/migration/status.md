# 当前实现与验证状态

2026-11-01 [App 命令模式 H0](../design/desktop-shared-state.md#h0-运行路线与样机证据)候选 `fa5b8133` 已通过主监督与新只读上下文审查，接续 H1-a 共同无感恢复：macOS 原生入口分流、真实 Flutter GUI 与命令双向启动及合成日程共享读取通过；Linux Debian 12 arm64 Docker 在无 DISPLAY/Wayland/Xvfb、运行期断网条件下通过 Dart AOT→FRB→Rust 日程读取，并通过锁定插件 libsecret 后端的合成材料保存与服务重开读回。macOS/Windows 选择无 view Engine，Linux 选择同一 Dart 服务的 AOT 运行组件。Windows 只完成锁定源码核对，原生环境待验。H1-a 文件与恢复接口已收敛，H0 只提交文档。正式入口、公共账号/恢复服务、命令迁移及独立 Rust CLI 退役仍分阶段实施。继承 13 项实验保持，未混入 H0 提交。

旧 CLI-a 方案已有独立账号登记和 list/show/unsynced 代码。`9835653c` 的后续独立审查又发现材料 worker 可直接调用、派生认证失效未传播两项问题，因此旧方案未最终放行。后续未提交修复尚未完整回归，按清单保留取舍；旧 worker 不再作为独立开发目标。用户反馈 App 钥匙串问题已解决，后续复用现有能力，发现实际回归再修复。Core 导出最后独立放行点为 `de797fce`。CLI schema v13、Bridge v46、日程 schema2、业务缓存 schema7 和 Session v2 当前保持。

H1-a 的恢复操作控制前置单元已完成本地分段验收：Core/Bridge 增加独立的单次控制柄、单调期限、请求前后检查和中断收尾。Bridge 锁等待与永挂 transport 可取消，清目标 pending 与旧计划，保留已保存会话。所有权检查成功时保留另一条合法路线的内存状态，检查失败时沿用既有的失败关闭规则。原始工作区未修改，候选在独立检出验证。共同纯 Dart 恢复服务与 GUI 接线现已实现：先合并同功能校验，再合并同 scope、同实际路线的登录。消费者独立取消或到期，最后消费者退出才撤销共享操作，关闭保管仍在收尾的数量。相同材料被拒后，其他路线的迟到读取与未发送排队登录失去提交资格，其他材料和有效会话复用继续执行。legacy authStatus 挂起期间切号的基线既有缺口已补公开行为回归。纯 Dart 行为 21 项通过，完整相关检查已按下述分段补齐，H1-a 共同服务单元尚待最终监督复核。具体范围与返回预算见[Bridge v46](../contracts/flutter-bridge.md#v46所需路线恢复的按操作控制)。

本单元以 `9d7fcbdd` 为基线。最后一轮 `just check-changed mode=full` 的严格 Rust/CLI/脚本、版本、文档、布局、feature-on/off 和生产编译通过，Core 507 项、Bridge 169 项、八包 Flutter 1,635 项通过，保留 Core 1 项和 Bridge 2 项既有忽略。静态分析为 692 项既有 info，无 warning/error。该完整入口在 macOS Cargokit 构建失败，退出码 1 保留。后续定位到当前 Apple linker 在 macOS 12.0 与 `strip=debuginfo` 组合下生成的 proc-macro dylib 字符串池未对齐，dyld 拒绝加载。仅本轮低符号验证环境增加 `CARGO_PROFILE_DEV_STRIP=none`，保留 Debug 断言和 macOS 12.0 部署目标，原 staticlib 命令与 `just integration-test` 均退出 0。五项真实 macOS 集成包含新增恢复控制 FFI probe，最终 `just flutter-codegen-check` 也退出 0 且零漂移。原生运行器保留既有应用置前失败提示，五项断言均完成。

上述结果复用同一生产与测试代码的既有通过段，再补齐原生和生成检查。完整失败日志与新增分段命令、环境、tree 和退出码保存在被忽略的 `.ubaa_local/command_mode_h1a/`。本轮只使用合成材料、固定路线和 Mock 学校 HTTP，没有真实账号、学校请求、其他平台设备、远端 CI 或发布验收。

以下 CLI-a 验收数字属于既有候选的历史证据，不能用于证明新命令模式或共享服务已完成。

CLI-a 审查修复以 `3dab915046f6111bffe0a3ea0b6596b7ee1cdb55` 为基线完成 `just check-changed base=3dab9150 mode=full`，退出码 0。Core 单元测试 497 项通过、1 项既有手动基准忽略，CLI 库 31 项、身份生命周期 6 项、日程二进制 2 项和原有合同回归通过。八包 Flutter 1,635 项、macOS 原生五项及 FRB 生成零漂移通过，静态分析为既有 692 项 info，无 error/warning。依赖审计 advisories/licenses/bans/sources 全部通过，保留既有 allo-isolate manifest 许可证字段警告。

macOS 材料改用已锁定 security-framework 3.7.0 的原生字节接口，同一真实 CLI 的短命工作进程创建、更新并跨进程重开合成条目，使用系统默认 ACL，不扩大其他应用访问权限。已核对含双引号、单引号、反斜杠、中文及可选 CacheKey 的 69 账号索引、超过 4 KiB 的正文和非 UTF-8/零字节往返。超过既有 1 MiB 读取边界时在修改前拒绝，保留原材料。索引登记容量预检还验证旧映射、alias、CacheKey 不变且不产生 pending。材料拒绝、写入后回执失败、目录替换、结果交付检查、跨进程锁及退出重登继续回归。原生测试移除直接从测试程序调用生产 AgendaAccess 的接线，生产登记行为由 CLI 库 Mock 聚合登录测试保留，真实材料创建/更新/读回和结果交付由真实 CLI 子进程覆盖。

本轮失败反例、聚焦结果、依赖审计及完整日志与退出码位于被忽略的 `.ubaa_local/agenda_cli_a_fix/`。`red_identity.log` 为固定 Direct、NeverProbe 与 Mock HTTP 的三项实际失败，`red_platform.log` 为未登记平台阻断失败，`red_keychain_parser.log` 仅用本机 security help 复现旧分词与行长故障。聚焦和完整记录分别为 `focused_final.log/.exit`、`full.log/.exit`。成功登记 JSON 断言补回后的 CLI 库回归另见 `registration_json.log/.exit`，最终完整重跑也包含这些断言。首轮完整入口因 Core 过期票据测试构造器遗漏代次字段失败，修正后完整重跑通过，原失败保留为 `full_first.log/.exit`。macOS 运行器仍报告应用置前提示，五项断言均完成。其他平台仅用不支持 provider 的确定性模拟，Linux/Windows 未原生运行。本轮没有读取真实凭据或会话，没有学校认证、读取或写入，没有远端 CI、实体设备或发布验收。旧 Keychain 条目若被系统 ACL 拒绝，保持材料并报告固定 unavailable，本轮不自动迁移权限。

更新：2026-11-01。本文只维护当前快照，不记录单轮验证流水。整改阶段 1–7、Rust Core 精简、审查修复与签名配置的逐轮记录见[状态流水](history/2026-10-30-status-log-through-signing.md)，更早的时间线见[阶段 4 整理前状态](history/2026-10-30-status-before-quality-phase4.md)，历史决定见[决策索引](decision-log.md)。[阶段目标](../../goal.md)定义本轮范围，门禁清单只在[开发命令](../development/commands.md#检查选择与完成条件)维护。

## 当前实现

日程一期 1a、1b 已增加 Rust Core 自建事项、标准重复展开、教学周规则转换、账号独立持久化、八类学校来源投影、课程逐节展开和本地合并查询，入口见[日程 Core 合同](../contracts/agenda.md)。日程 schema v2 使用逐记录明文 SQLite，无需密钥，不随只读缓存淘汰或重建，退出后保留，同账号登录后显式激活。学校投影沿现有首页规则并保留原始状态，合并查询叠加本地完成、隐藏与备注，返回各缓存范围时间和缺失信息。未同步删除标记一律保留。1c-a 已接入独立 typed Bridge、Dart 服务及账号生命周期。1c-b 已将首页七类学校待办切到 Core 统一纯投影，在线结果不依赖缓存或日程打开成功，离线沿用原快照证据，覆盖失败单独提示。Core 范围快照 `.ics` 已实现，本机导出与同账号指定路线缓存导出均不联网。CLI-a 已接入独立安全登记和三个本机只读命令，CLI v13；本机修改、导出文件和同步继续保留为后续阶段。日程已改为事项/覆盖各一行，仅更新变化记录并去除整账号密文上限。旧版、未知版和损坏库拒绝且保留，不自动迁移或重建。只读缓存继续加密，缓存 schema v7 及加密保持不变。已知账号身份与缓存密钥读取解耦，清除登录材料及缓存保留随机别名和原密钥。日程错误与可重建业务缓存错误分列，缓存不可用仍可操作本机日程。日程持久写操作与打开、关闭共用串行尾链。关闭请求立即撤销访问，已交付写入在关闭完成前收尾，旧代次排队写入在进入后端前拒绝，同账号重新打开不能越过旧写入。读取不阻塞关闭，安全索引禁止恢复独立启动。

Rust Core 统一拥有认证、Direct/WebVPN/Auto 路线、会话、校园领域读写和加密缓存。CLI 与 Bridge 通过 facade 使用 Core，Flutter/OHOS 宿主通过 Bridge 与共享 Dart/UI 接线。当前公开合同为 CLI JSON schema v13 与 Flutter bridge contract v46，独立于 Session v2、配置 v1、业务缓存 v7。产品展示版本与合同版本分别治理，取值与发布规则见[版本约定](../development/conventions.md#版本号与依赖)。

Core 与 CLI 已增加门户身份/学院、五项账户指标和网络流量在线查询，云盘指标明确为剩余空间。此前三个 facade 方法和 `portal profile`、`portal metrics`、`network usage` 命令已在 Direct/WebVPN 两条路线实测成功，并验证网络业务会话在 CLI 进程重开后复用。单项指标失败保留其他结果，金额采用十进制字符串，免费与计费剩余流量分别保留“不含套餐”的含义。精确范围见[门户与网费接入](source-parity-campus.md)。Bridge v43 已提供这三项类型化读取，移动端底栏新增“我的”页展示身份、账户指标与流量，先显示本机快照再后台在线刷新，并支持下拉刷新；三组数据按账号与路线保存快照，指标逐项保留最近成功值，App 内真实账号读取尚未单独验收。iOS 最低版本已按 Xcode 27.2 统一为 15.0。

macOS 应用最低版本已按用户要求统一为 12.0，以匹配 Xcode 27.2 的构建范围。Runner、Podfile 和自有 bindings Podspec 保持一致，依赖 Pod 的较低目标由安装后处理提升，较高要求继续保留。依据见[部署目标决定](decision-log.md#2026-10-31macos-最低版本统一为-120)。

官方 Flutter 与 OHOS 共用的 bootstrap 在 SDK 和平台能力初始化前先提交 Flutter 启动页，后端打开期间继续显示相同外观。SDK、Bridge 自检或平台能力失败时显示安全诊断与重启指引，并保留原始错误向上传播；后端工厂失败仍可“重新打开”。iOS 原生启动背景按系统明暗使用主题 surface 颜色。用户保存的主题在宿主读取偏好后生效，若与系统主题不同，启动期间仍可能出现颜色切换。

课表切周时优先用同学期的周次元数据显示目标日期。加载快照尚无路线时沿用同一读取代次的元数据，明确路线不符或账号代次变化会清除旧元数据。网格固定七天，节次列显示开始、结束时间。第 1–14 节按用户确认的 2026—2027 校历作息展示，课程详情保留原始时间，校历之外节次继续使用接口与课程边界。研究生特殊作息的展示取舍见[校历作息优先](decision-log.md#2026-10-31课表节次轴固定采用校历作息)。

主题保存为设备偏好，重启恢复，不随退出或清除账号删除；业务缓存仍由 Core 持有。[界面规格](../design/flutter-ui-spec.md)描述现行展示规则，[来源对照](source-parity.md)保留逐操作协议依据。

Rust Core 已完成精简：缓存刷新、路线安全检查、凭据槽位与协议解析收敛，业务缓存提升为 schema v7 并删除历史开发格式迁移；旧库普通打开会明确拒绝且不改文件，可显式重建。过程见[Core 精简记录](2026-10-30-core-simplification.md)。

各平台产品标识统一为 `cn.edu.ubaa`，签名材料默认放在被忽略的根 `.sign/`，配置方法见[应用签名配置](../runbooks/app-signing.md)。Android 已用本机 keystore 构建并校验 Release APK，尚未安装运行或与旧正式包对照。

OHOS 已修复 Rust 动态库被改名导致的启动白屏，并更正 HUKS 密钥存在性查询，使首次写入能够创建密钥。API 26 的 DevEco 模拟器已验证正常入口显示登录页，以及合成安全材料的写入、读回、进程重启后读取和删除。模拟器配置关闭 Impeller，构建后保留该配置；OHOS 分析、测试、插件合同和无签名 Debug HAP 构建通过。实体设备、签名发布和当前 OHOS 真实账号验收仍未验证。密钥接口依据与来源边界见[首次创建安全存储密钥](source-parity.md#2026-10-30ohos-首次创建安全存储密钥)。

阳光打卡 OAuth 已补齐 HTTPS 默认端口 SSO `/login` 中间跳转，保留目标地址、路线和授权码来源校验。2026-10-31 的此前独立验证中，`just verify-live feature=ygdk route=direct` 与 `route=webvpn` 均通过认证准备、登录、状态、概览和记录读取，两条路线分别返回 11 个项目与 20 条记录，退出码均为 0。此次真实验证不包含打卡写入或原生 UI。

首页分批读取在首批可用结果后进入后台补全，Dart 与 Bridge 最多八组并发，仍保留同组串行和写方优先。主动刷新先推进主读取代次，再读取博雅已选与研讨室订单，避免重复请求。下拉等待可显示结果，标题栏统一显示刷新状态。“我的”按五分钟过期刷新，并在账号、路线或业务缓存代次变化时清除旧结果；金额与流量只在展示层做十进制舍入。

底栏顺序为首页、课程、学业、校园、我的。手机支持五页横向切换，保留已访问页状态并停用后台页动画；首页待办直接打开目标详情，单层返回首页，分类入口仍按列表与详情逐层返回。首页进入前最多等待本机缓存 800ms，查询切换最多等待缓存种子 300ms，默认读取与本机缓存恢复并行，账号、路线与读取代次继续隔离。博雅选课页每页 8 条，可见列表串行预取至 40 门，失败后等待显式重试。取舍与来源见[缓存与分页决定](decision-log.md#2026-10-31缓存预读与博雅首屏分页)。

本地会话恢复中及暂时失败时均保留原位登录入口，登录面板保留当前页面位置。合成测试覆盖入口、验证码流程及恢复期间导航，真实账号长时间后台恢复仍需设备验证。

启动页、初始化失败页和宿主首帧统一使用保存的主题，启动偏好读取最多等待 300ms，失败或超时跟随系统。Android 12+ 同步应用外观并设置系统启动背景，macOS 在 Flutter 首帧前按同一偏好键设置窗口底色。OHOS 共用启动逻辑，继续使用 OHOS 偏好插件分支。主题回归覆盖首帧、失败页、超时、原生通知与迟到读取竞争，平台差异见[启动主题决定](decision-log.md#2026-10-31启动主题与-android-应用外观同步)。

iOS simulator 的 `debug_unpack_ios` 架构误报已修复。构建入口仅在发现 Xcode 27.2 的 `lipo` 多架构参数解析错误时，默认选择本机架构，其他工具链保持原行为。2026-10-31 在 Flutter 3.41.9 / Xcode 27.2 上实际构建通过，产物为 arm64 模拟器应用；脚本自测覆盖正常探测、明确缺陷、无关错误和显式架构覆盖，详见[命令说明](../development/commands.md#构建与发布命令)。

2026-11-01 日程 1d 的 Core 导出部分以 `8075e64d` 为基线完成 `just check-changed base=8075e64d mode=full`，退出码 0。严格 Rust/CLI/脚本检查、八包 Flutter 1,635 项测试、macOS 五项原生集成及 FRB 生成零漂移全部通过。Core 单元测试 489 项通过，1 项既有手动基准忽略；日程聚焦 78 项在 `TZ=UTC` 通过，其中新增 10 项导出回归。初始 5 项导出反例失败，随后 2 项学校覆盖/缓存反例失败，均已保留日志并修复。新依赖的 advisories、licenses、bans、sources 审计通过，两个锁文件只新增日历依赖链，没有升级既有包版本。依赖审计保留既有 allo-isolate 缺少 manifest 许可证字段的警告，macOS 运行器仍有应用置前提示，五项断言均完成。

该 Core 导出阶段只交付范围快照和 CLI 接线设计，当时 CLI schema v12、Bridge v45、日程 v2、缓存 v7 均保持。后续 CLI-a 已实施身份登记、跨进程锁及只读命令，原子文件输出继续留给下一阶段。修复前未优化构建的完整 Core 测试耗时 930.64 秒，其中 600 次重复、每次 63,000 字节备注的超限用例长期占用序列化锁。独立审查确认属性折行的二次增长，修复说明见[最近一次完整验证](#最近一次完整验证)及[导出合同](../contracts/agenda.md#rfc-5545-范围快照导出)。证据在被忽略的 `.ubaa_local/agenda_1d/`，完整记录为 `full.log` 与 `full.exit`，依赖审计为 `audit.log`，失败反例为 `red.log`、`red_school.log`。本轮没有读取真实凭据/会话，没有学校请求、远端 CI、其他平台设备或发布验收。

## 当前未解决与未验证事项

- 远端 CI 尚未运行。阶段 3 已修改 workflow，本地静态检查与监督复核通过；本轮未 push。
- Android 应用外观同步和冷启动背景尚无本轮设备验证；macOS、iOS 和 OHOS 也未新增启动外观目视验收。iOS 原生启动图仍按系统外观绘制，Android 12 以下原生背景跟随系统资源，Flutter 首帧使用应用偏好。
- 保留原生集合的 Linux Secret Service 和 iOS/iPad 方向握手专项尚未在本轮运行。本轮平台构建结果见下节，历史 Android 签名测试结果见[状态流水](history/2026-10-30-status-log-through-signing.md)，正式发布与真实账号验收仍未运行。
- [原生删减登记](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)中的以下项目已无自动化覆盖：原生登录到查询完整路径、十二领域连续导航、十项写操作连续流程、原生软键盘专项、真实账号原生 UI 巡检、真实账号原生恢复、真实账号原生启动性能测量、Flutter 到 Android 的真实课表组件通道、常驻原生合成预览及 bindings 默认 driver。登记表逐项列出仍保留的 App/Host/Widget/Core 等分层覆盖。已删除流程的旧失败随入口移除，不计作修复通过。
- OHOS 原生 `AppScope/app.json5` 仍为 `1.0.0`/`1000000`，两个 Flutter 应用仍为 `0.1.0+1`。版本号仍需在发布前与旧正式包核对，平台标识已统一。OHOS fork 与官方 Pub workspace 保持独立，原因和锁文件边界见决策记录。
- Rust 阶段已完成。feature 专属 SSO service URL 未合并，避免改变参数编码、重定向和 Cookie 作用域。监督者决定本轮继续保留历史 `mod.rs` 中的协议实现和 Bridge 离线泛型化，列为后续待办；补充来源或私有观察无法由当前克隆复现的记录仍按[来源对照边界](source-parity.md)保留，不补造证据。
- 最终逐项 UI/设备、异常生命周期、离线性能和发布验收仍有缺口；历史真实只读结果仅属于对应候选，不能继承为当前验收或真实写入授权。

首页日程 1c-b 的独立复核发现路线切换窗口内启动的纯投影可以交付旧路线来源。本轮已在 App 阻止 transition 期间的新投影，并在交付时核对实际 policy。宿主同步撤销旧投影，切换成功、失败回滚及最后一个旧请求收尾后重新触发投影。旧签到读取只保留只读内容，切换后的新读取继续沿原在线资格规则关联动作。修复没有改变学校协议、日程关闭写入尾链或磁盘版本。

## 最近一次完整验证

2026-11-01 H1-a 共同 Dart 恢复服务以 `7d42a9181dc0a5bfcc6ad912dcfe0519c2a4d783` 为固定基线执行完整验收。`check-plan mode=full` 通过，原 `check-changed mode=full` 在 macOS 原生构建复制 kernel_blob 时因磁盘空间不足退出 1，此前严格 Rust/CLI/脚本检查及八包 Flutter 的格式、分析和 1,667 项测试全部通过。Core 单元测试 507 项通过，保留 1 项既有手动基准 ignored。原生补跑暴露 smoke 测试仍观察旧恢复入口的 10 秒超时，其余四项通过；将观察点迁到实际受控操作并转发取消、释放后，五项原生集成全部通过。原等待期限、身份/界面断言与真实 FRB/Core 调用保持。该测试迁移和后续状态文档以外的源码与已通过候选一致，因此复用已有 Rust/Flutter 段，随后 FRB 生成检查退出 0、生成零漂移。原 full 的构建失败和后续原生超时均保留原退出码与日志，没有记作 full 退出 0。

共同服务的纯 Dart 21 项、App 恢复/session/write 生命周期/agenda 222 项、Host recovery 18 项和 Platform 账号/凭据 20 项聚焦检查通过。两项独立审查发现均已先用失败反例确认，再完成最小修复：同份已拒材料在另一条路线读取返回或排队时失去密码提交资格，legacy authStatus 挂起期间切号不再提交原账号保存密码，后者是基线已有缺口。真实 Dart AOT→FRB→私有 Rust Mock transport 复跑确认在途网络等待取消、两个控制柄各释放一次、服务收尾及同客户端后续调用；该证据未覆盖文件锁等待取消。最小平台工厂复用现有安全材料、账号 alias 和 CacheKey，并通过 GUI 工厂正对照证明图片/位置初始化隔离。本机日程实际 BridgeAgendaBackend 查询与完成的合成测试保持学校入口零调用。生产 Rust、生成绑定、依赖和磁盘版本均未改。本轮没有真实材料或学校请求、远端 CI、Windows/Linux 原生验收和发布操作。原生运行器仍输出应用置前提示，五项断言均完成。

2026-11-01 日程 1d 导出修复以 `ac21375644395bc426e579ad1f08fe6ec8358b48` 为基线完成 `just check-changed base=ac213756 mode=full`，退出码 0。严格 Rust/CLI/脚本检查、Core 496 项单元测试（保留 1 项既有手动基准 ignored）、八包 Flutter 1,635 项、macOS 五项原生集成及 FRB 生成零漂移全部通过。新候选的完整 Core 单元测试总耗时为 15.15 秒。

2026-11-01，1d 独立审查发现的两个 P2 已修复：非重复 UID 仅使用已有 UUID，重复单次移动继续保留原发生身份；内容行改为线性流式转义与折行，保留原输出容量、同次读取事务及账号关闭语义。新增解析回归覆盖事件/全天改时、待办截止与无日期转换、重复形态转换和不同事项/发生身份区分，以及长字段、UTF-8、转义及空白边界。UID 两项真实失败反例保留后修复，日程聚焦 85 项在 `TZ=UTC` 通过。原超限输入在本机 debug 构建中单独计时为 1.135 秒，返回 Capacity 且无部分正文；该值是完整导出调用耗时，修复前 930.64 秒是完整 Core 测试总耗时。旧折行函数的独立探针由 rustc -O 编译，输入为 24,012/48,012/63,012 字节，各运行 10 次，测量为 0.008400/0.034195/0.056248 秒，只用于证明旧函数二次增长，未测量 release 完整导出。严格检查保留 692 项既有静态分析 info，无 error/warning。macOS 运行器仍提示无法将应用置前，五项断言全部完成。本轮仅使用合成数据，没有学校请求、真实账号材料、远端 CI 或发布验收。修复证据保存在被忽略的 `.ubaa_local/agenda_1d_export_fix/`，失败反例为 `uid_red.log/uid_red.exit`，聚焦为 `agenda_green.log/agenda_green.exit`，完整为 `full.log/full.exit`。CLI 接线继续由后续会话实施，私有监督状态由主聊天维护。

2026-11-01 日程 1c-b 路线切换竞态修复以 `12eecabd` 为基线完成 `just check-changed base=12eecabd mode=full`，退出码 0。严格 Rust/CLI/脚本检查、八包 Flutter 1,635 项、macOS 五项原生集成和 FRB 生成零漂移全部通过。Core 单元测试通过 479 项，保留 1 项既有手动基准为 ignored；静态分析保留 692 项 info，无 error/warning。旧实现的正式回归在 16 项中失败 14 项，证明窗口内立即交付、切换后迟到交付及快速切换的投影缺陷。新增 16 项 App 与 6 项生产宿主 Widget 回归覆盖 Direct/WebVPN 双向、Auto、准备失败回滚、切换前与窗口内投影、快速切换、退出换号、来源未变时恢复及新读取恢复签到动作。App 连同既有路线、首页和日程生命周期聚焦共 75 项通过。证据位于被忽略的 `.ubaa_local/agenda_1c_b_route_fence/`，旧失败为 `app_red.log`，完整通过为 `full.log` 与 `full.exit`。首次完整检查曾因 Shell library 聚合超限停止，最终复用可空投影回调接线，布局规则保持原值。macOS 运行器报告应用置前失败，五项断言均完成。本轮没有读取真实凭据或会话，没有学校请求、远端 CI、其他平台设备或发布验收，候选 `8075e64d` 已由主聊天独立复核放行。

2026-11-01 日程 1c-b 以 `9fb0bdf1` 为基线完成 `just check-changed base=9fb0bdf1 mode=full`，退出码 0。严格 Rust/CLI/脚本检查、八包 Flutter 1,613 项、macOS 五项原生集成和 FRB 生成零漂移全部通过。Core 单元测试通过 479 项，保留 1 项既有手动基准为 ignored；日程聚焦 68 项通过。静态分析为 692 项 info，无 error/warning。App 新增 7 项聚焦，首页 Widget、加载布局和单层返回聚焦分别通过。原生缓存入口经过生产 App 字段适配及真实 FFI，保留原首页九组业务预期，并覆盖本地重新挂起、原始学校状态、目标不符、重复签到来源、时区、午夜及 48 小时边界。失败反例分别证明已提交作业被原 `home_todo` 漏掉、实际考试学期丢失、无缓存签到跨日交付及分钟刷新前的旧按钮动作问题。证据保存在被忽略的 `.ubaa_local/agenda_1c_b/`，完整记录为 `full.log` 与 `full.exit`。macOS 运行器仍报告窗口置前失败，五项断言均完成。本轮没有学校请求、远端 CI、其他平台设备或发布验收。

2026-11-01 日程退出写入顺序修复以 `1a49efa5` 为基线完成 `just check-changed base=1a49efa5 mode=full`，退出码 0。严格 Rust/CLI/脚本检查、八包 Flutter 1,616 项测试、macOS 五项原生集成和 FRB 生成零漂移全部通过。Core 单元测试通过 476 项，保留 1 项既有手动基准为 ignored；日程聚焦 65 项通过。静态分析保留 692 项 info，无 error/warning。新增服务回归覆盖全部持久写入口撤销、同账号重开、切账号、销毁、写失败及宿主重建和安全索引关闭顺序。原生可控门位于测试适配器，创建/清除实际经过生产 Bridge/Core，重建后端后核对 SQLite 持久结果；Core 可控门另验证已进入事务的提交/回滚先于停用。失败反例与完整证据位于被忽略的 `.ubaa_local/agenda_1c_a_write_fence/`。本次没有学校请求、远端 CI、其他设备或发布验收。

2026-10-31 日程明文存储阶段以 `142dee23` 为基线完成 `just check-changed base=142dee23 mode=full`，退出码 0。严格 Rust/CLI/脚本与文档构建、八包 Flutter 1,587 项测试、macOS 原生五项和 FRB 生成零漂移全部通过。Core 单元测试通过 474 项，保留 1 项既有手动基准为 ignored；日程聚焦 63 项在 `TZ=UTC` 通过。静态分析保留 692 项 info，无 error/warning。Flutter 宿主测试有 tap 命中告警，macOS 运行器有窗口置前提示，相关断言完成。日志与退出记录位于被忽略的 `.ubaa_local/agenda_plaintext/full.log` 和同目录 `full.exit`。只读缓存加密实现没有修改，未进行学校、远端 CI 或其他设备验收。

2026-10-31 日程一期 1b 以 `1b3c253c` 为基线完成 `just check-changed base=1b3c253c mode=full`，退出码 0。严格 Rust/CLI/脚本检查、八包 Flutter 的 1,587 项测试（含六张 golden）、macOS 五项原生集成和 FRB 生成零漂移全部通过。Core 单元测试通过 467 项，保留 1 项既有手动性能基准为 ignored；日程聚焦 56 项在 `TZ=UTC` 通过。静态分析保留 692 项 info，无 error/warning。macOS 运行器仍报告窗口置前失败，五项断言均完成。完整证据位于被忽略的 `.ubaa_local/agenda_1b/resume_full.log`，退出状态位于同目录 `resume_full.exit`。先前中断日志未计为完整成功。

2026-10-31 日程一期 1a 以 `dec8097d` 为基线执行 `just check-changed mode=full`，严格 Rust/CLI/脚本检查、八包 Flutter 的 1,587 项测试（含六张 golden）、macOS 五项原生集成和 FRB 生成零漂移全部通过。日程聚焦测试 25 项在普通环境与 `TZ=UTC` 均通过，独立 facade 编译夹具已同步锁文件并通过。依赖审计的 advisories、licenses、bans、sources 全部通过，保留既有 allo-isolate 缺少 manifest 许可证字段的警告。八包格式检查通过，静态分析为 692 项 info，无 error/warning。macOS 运行器未能将窗口置前，但五项断言均完成，未据此记录新增目视验收。

此前启动主题阶段实际重跑 iOS simulator、Android Debug APK、macOS Debug 构建，均通过。OHOS analyze 无问题、两个宿主测试、HUKS/connectivity 合同和无签名 Debug HAP 构建均通过。此前启动主题阶段的日志保存在 `.ubaa_local/supervision/theme_closure_20261031/`，日程 1a 的失败反例与完整检查日志保存在 `.ubaa_local/agenda_1a/`，验证过程写入对应提交说明。

本次收尾没有发送真实学校认证、读取或写入请求。门户与阳光的 Direct/WebVPN 记录保留此前独立验证的范围，不能作为当前 App 的真实账号验收。改动按主题本地提交，未推送，远端 CI、实体设备与发布验收未运行。
