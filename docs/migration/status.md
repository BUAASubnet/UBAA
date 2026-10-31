# 当前实现与验证状态

更新：2026-10-31。本文只维护当前快照，不记录单轮验证流水。整改阶段 1–7、Rust Core 精简、审查修复与签名配置的逐轮记录见[状态流水](history/2026-10-30-status-log-through-signing.md)，更早的时间线见[阶段 4 整理前状态](history/2026-10-30-status-before-quality-phase4.md)，历史决定见[决策索引](decision-log.md)。[阶段目标](../../goal.md)定义本轮范围，门禁清单只在[开发命令](../development/commands.md#检查选择与完成条件)维护。

## 当前实现

日程一期 1a、1b 已增加 Rust Core 自建事项、标准重复展开、教学周规则转换、账号独立持久化、八类学校来源投影、课程逐节展开和本地合并查询，入口见[日程 Core 合同](../contracts/agenda.md)。日程 schema v2 使用逐记录明文 SQLite，无需密钥，不随只读缓存淘汰或重建，退出后保留，同账号登录后显式激活。学校投影沿现有首页规则并保留原始状态，合并查询叠加本地完成、隐藏与备注，返回各缓存范围时间和缺失信息。未同步删除标记一律保留。CLI、Bridge、Flutter、导出与同步尚未接入，既有 CLI v12 与 Bridge v43 保持原合同。日程已改为事项/覆盖各一行，仅更新变化记录并去除整账号密文上限。旧版、未知版和损坏库拒绝且保留，不自动迁移或重建。只读缓存继续加密，缓存 schema v7 和密钥管理保持原合同。

Rust Core 统一拥有认证、Direct/WebVPN/Auto 路线、会话、校园领域读写和加密缓存。CLI 与 Bridge 通过 facade 使用 Core，Flutter/OHOS 宿主通过 Bridge 与共享 Dart/UI 接线。当前公开合同为 CLI JSON schema v12 与 Flutter bridge contract v43，独立于 Session v2、配置 v1、业务缓存 v7。产品展示版本与合同版本分别治理，取值与发布规则见[版本约定](../development/conventions.md#版本号与依赖)。

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

## 当前未解决与未验证事项

- 远端 CI 尚未运行。阶段 3 已修改 workflow，本地静态检查与监督复核通过；本轮未 push。
- Android 应用外观同步和冷启动背景尚无本轮设备验证；macOS、iOS 和 OHOS 也未新增启动外观目视验收。iOS 原生启动图仍按系统外观绘制，Android 12 以下原生背景跟随系统资源，Flutter 首帧使用应用偏好。
- 保留原生集合的 Linux Secret Service 和 iOS/iPad 方向握手专项尚未在本轮运行。本轮平台构建结果见下节，历史 Android 签名测试结果见[状态流水](history/2026-10-30-status-log-through-signing.md)，正式发布与真实账号验收仍未运行。
- [原生删减登记](history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)中的以下项目已无自动化覆盖：原生登录到查询完整路径、十二领域连续导航、十项写操作连续流程、原生软键盘专项、真实账号原生 UI 巡检、真实账号原生恢复、真实账号原生启动性能测量、Flutter 到 Android 的真实课表组件通道、常驻原生合成预览及 bindings 默认 driver。登记表逐项列出仍保留的 App/Host/Widget/Core 等分层覆盖。已删除流程的旧失败随入口移除，不计作修复通过。
- OHOS 原生 `AppScope/app.json5` 仍为 `1.0.0`/`1000000`，两个 Flutter 应用仍为 `0.1.0+1`。版本号仍需在发布前与旧正式包核对，平台标识已统一。OHOS fork 与官方 Pub workspace 保持独立，原因和锁文件边界见决策记录。
- Rust 阶段已完成。feature 专属 SSO service URL 未合并，避免改变参数编码、重定向和 Cookie 作用域。监督者决定本轮继续保留历史 `mod.rs` 中的协议实现和 Bridge 离线泛型化，列为后续待办；补充来源或私有观察无法由当前克隆复现的记录仍按[来源对照边界](source-parity.md)保留，不补造证据。
- 最终逐项 UI/设备、异常生命周期、离线性能和发布验收仍有缺口；历史真实只读结果仅属于对应候选，不能继承为当前验收或真实写入授权。

## 最近一次完整验证

2026-10-31 日程明文存储阶段以 `142dee23` 为基线完成 `just check-changed base=142dee23 mode=full`，退出码 0。严格 Rust/CLI/脚本与文档构建、八包 Flutter 1,587 项测试、macOS 原生五项和 FRB 生成零漂移全部通过。Core 单元测试通过 474 项，保留 1 项既有手动基准为 ignored；日程聚焦 63 项在 `TZ=UTC` 通过。静态分析保留 692 项 info，无 error/warning。Flutter 宿主测试有 tap 命中告警，macOS 运行器有窗口置前提示，相关断言完成。日志与退出记录位于被忽略的 `.ubaa_local/agenda_plaintext/full.log` 和同目录 `full.exit`。只读缓存加密实现没有修改，未进行学校、远端 CI 或其他设备验收。

2026-10-31 日程一期 1b 以 `1b3c253c` 为基线完成 `just check-changed base=1b3c253c mode=full`，退出码 0。严格 Rust/CLI/脚本检查、八包 Flutter 的 1,587 项测试（含六张 golden）、macOS 五项原生集成和 FRB 生成零漂移全部通过。Core 单元测试通过 467 项，保留 1 项既有手动性能基准为 ignored；日程聚焦 56 项在 `TZ=UTC` 通过。静态分析保留 692 项 info，无 error/warning。macOS 运行器仍报告窗口置前失败，五项断言均完成。完整证据位于被忽略的 `.ubaa_local/agenda_1b/resume_full.log`，退出状态位于同目录 `resume_full.exit`。先前中断日志未计为完整成功。

2026-10-31 日程一期 1a 以 `dec8097d` 为基线执行 `just check-changed mode=full`，严格 Rust/CLI/脚本检查、八包 Flutter 的 1,587 项测试（含六张 golden）、macOS 五项原生集成和 FRB 生成零漂移全部通过。日程聚焦测试 25 项在普通环境与 `TZ=UTC` 均通过，独立 facade 编译夹具已同步锁文件并通过。依赖审计的 advisories、licenses、bans、sources 全部通过，保留既有 allo-isolate 缺少 manifest 许可证字段的警告。八包格式检查通过，静态分析为 692 项 info，无 error/warning。macOS 运行器未能将窗口置前，但五项断言均完成，未据此记录新增目视验收。

此前启动主题阶段实际重跑 iOS simulator、Android Debug APK、macOS Debug 构建，均通过。OHOS analyze 无问题、两个宿主测试、HUKS/connectivity 合同和无签名 Debug HAP 构建均通过。此前启动主题阶段的日志保存在 `.ubaa_local/supervision/theme_closure_20261031/`，日程 1a 的失败反例与完整检查日志保存在 `.ubaa_local/agenda_1a/`，验证过程写入对应提交说明。

本次收尾没有发送真实学校认证、读取或写入请求。门户与阳光的 Direct/WebVPN 记录保留此前独立验证的范围，不能作为当前 App 的真实账号验收。改动按主题本地提交，未推送，远端 CI、实体设备与发布验收未运行。
