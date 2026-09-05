# 当前迁移与交付状态

更新日期：2026-09-05

本页只呈现当前有效结论。2026-09-02 及以前的逐次修复、失败、重跑与 CI 流水已原样归档到
[历史状态流水](history/status-through-2026-09-02.md)；不得用历史阶段中的“未完成”覆盖本页终态，也不得用
历史成功替代当前候选重新验证。

## HEAD 证据边界

| 类型 | 提交 | 含义 |
|---|---|---|
| typed 业务实现 | `4b0dcb0` | 阶段 11J 完成 Evaluation 批量四态结果、expected-route 提交与 caller-pinned 回读；当前 CLI schema v10、bridge v9 |
| 唯一写入协调器 | `b6ff2c7` | 阶段 11K 完成 immutable state、安全回读和宿主生命周期；完整 Rust/Flutter、FRB、macOS integration、本机三平台及 OHOS API26 无签名门禁通过 |
| UI 目录与 Core 入口 | `1f63127e`、`7202fcf9` | 阶段 12/12B 按职责拆分 UI、HTTP helper 与 Reqwest adapter；AST/原文等价、完整 Rust/Flutter/FRB、macOS integration 及独立复审通过 |
| 前次结构治理候选 | `d43c177` | 19 项本地门禁与五平台原生 CI 通过；合同 CI 失败，不能作为最终通过证据 |
| 阶段 14A CLI 修复 | `4017edd7` | 稳定文件句柄替代 Windows 不稳定 API；本地完整 `just check` 与 CLI 全目标 127 项通过，Windows CI 仍待新候选复验 |
| 阶段 14A 工具链修复 | `7b8eed3a` | 完整消费 Flutter stdout；六项隔离 Shell 合同、完整 `just check` 及两个改动脚本的 ShellCheck 0.11.0 通过 |
| 阶段 14A Shell 门禁修复 | `23066064`、`c21a12dd` | OHOS 路径引用、source 静态解析、失败返回和断言已修复；全仓 ShellCheck 0.11.0、完整 `just check` 及独立复审通过 |
| 第二轮候选 | `bef16ee5` | 五平台原生 CI 成功，合同 CI 的冷启动输出与 Windows 名称夹具失败；两轮本地 01–16 项通过，实时 Cgyy 上游错误未通过 |
| 阶段 14B 冷启动与夹具修复 | `f0daed09`、`38ef75cf` | CLI 128 项、工具链八项、完整 `just check`、真实隔离冷 SDK 及独立复审通过；新候选完整门禁待绑定 |
| 第三轮候选 | `a19cc7f2` | 本地 19 项、五平台原生 CI 与 Windows/macOS Rust CI 通过；合同 CI 的引用 Shell 测试失败，整体未通过 |
| 阶段 14C 引用合同修复 | `fbcbbdb9` | Just 1.58 真实 RED、1.58/1.51 GREEN、完整 `just check` 与独立复审通过；显式退出消除 Bash 3.2 的断言漏报 |
| 结构治理最终候选 | 本页所属提交 | 包含全部代码拆分、阶段 14A/14B/14C 修复及记录；重新以完整 SHA 绑定全部本地门禁和两条远端 CI，不预填 PASS |
| 历史 verified HEAD | `4eaf1dd` | 整理前的完整无签名门禁、Direct/WebVPN 只读矩阵、五平台 Flutter CI 与合同 CI；只证明该历史提交 |
| 历史 evidence HEAD | `11a2969` | 固化 `4eaf1dd` 的旧证据，不证明整理后候选，也不表示签名、设备或真实写入已完成 |

当前代码组织治理以 [代码与目录组织设计](../architecture/code-organization.md) 和
[实施计划](../superpowers/plans/2026-09-03-code-organization.md) 为权威。结构治理提交在阶段 14 绑定新的
verified HEAD 前，不继承 `4eaf1dd` 或 `d43c177` 的历史成功状态。

当前公开版本为 CLI JSON schema v10；Flutter bridge contract v9。阶段 11K 及随后机械整理保持该版本和生成
绑定。阶段 14 的执行记录在仓库外保存完整候选 SHA、每项命令退出码、两条 live 安全摘要、两套 CI run URL
与各 job 终态；最终交付消息链接该记录。失败需要修复时，修复与记录产生新候选并重新执行完整门禁。
最终通过后不再仅为回填 PASS 修改仓库，避免产生未经同等验证的新 HEAD。

## 结构整理结果

原审查的 15 个超千行手写文件、2 个超 16 直属源码文件目录均已消除，结构 baseline 为空。最终扫描范围有
494 个手写文件、107029 行、135 个直属源码目录；FRB 生成和锁定 Cargokit 排除，冻结输入不作整理对象。
`widgets.dart` 已从行为收敛后的 3883 行变成 27 行入口，21 个实现 part 按页面、共享组件、业务、写入表单
定位，最大 UI 实现 484 行。独立 Rust/Dart 审查没有遗留高/中结构问题。

Core 领域、路线状态、会话存储、端口实现与 facade 边界分开；CLI 输出/退出策略由 CLI 自己拥有；bridge
生成区与手写 DTO/方法/映射分开；Dart 应用、单一写入协调器、UI 和共享宿主各有明确职责。入口只保留合同、
组合和稳定导出。具体修 bug、加领域与改 UI 的路径见 [开发定位索引](../index.md)，完整树见
[代码组织设计](../architecture/code-organization.md#5-目标目录结构)。

## 当前能力

| 能力 | 实现状态 | 当前证据 | 结论 |
|---|---|---|---|
| Rust Core/facade | Evaluation fresh typed authority、批量四态结果与 expected-route/caller-pinned 链路已实现 | Core 默认与 test-contract 两种配置、架构合同与完整 `just check` 通过 | 本地阶段通过；最终候选绑定待完成 |
| CLI | schema v10 envelope、人类输出、Direct/WebVPN 诊断与写操作确认入口已实现；磁盘 `session.json` 仍为 schema v2 | `4017edd7` 修复不稳定 API，`f0daed09` 修复 Windows 文件夹具；本地 CLI 全目标 128 项与完整 `just check` 通过 | 新候选完整门禁与 Windows CI 待复验 |
| 用户中心与十二项业务读取 | Core/CLI/FRB/Flutter typed 链路与页面已实现 | `d43c177` 的 19 项本地门禁含 Direct/WebVPN Core-live；页面/查询/widget/integration 使用脱敏 backend 验证 | 旧候选 Core 实时只读通过；新候选需重验，真实 App 账号链路未验证 |
| 十项用户可见写入 | Evaluation typed target、批量顺序/停止规则及原路线回读已闭合 | Bridge 108 项、Flutter 跨层完整门禁与 macOS integration 7 项通过 | 本地阶段通过；本周期未执行真实写入 |
| Windows/Linux/macOS/Android/iOS | 官方 Flutter 共享应用与原生宿主已实现 | `d43c177` 的原生 CI `33962021922` 五个 job 全部成功；同候选合同 CI `33962021960` 未通过 | 旧候选无签名构建/结构通过，新候选仍需复验；不是签名或设备证据 |
| HarmonyOS | 锁定 OHOS fork、API26 runner、arm64 Rust bridge 与无签名 HAP 已实现 | `d43c177` 的本地门禁含 API26 无签名 HAP 与 arm64 内容检查 | 旧候选静态/包结构通过，新候选仍需复验；不是签名 HAP 或设备证据 |
| 发布准备 | SBOM、锁文件/许可证审计、产物结构检查和回滚 runbook 已实现 | `d43c177` 的 `just release-preflight` 通过并保存报告 | 旧候选无签名 RC 准备通过，新候选需重生成；不是正式发布 |

`Cgyy purposes` 的实时结果仍明确标记 `source=static_fallback`，表示采用已记录的冻结回退，不冒充上游用途接口
实时成功。SPOC/博雅详情只有在同批次父列表为空时才可记为 `NOT_APPLICABLE`。

## 本地阶段证据

- `9fbb83a` 上的阶段 10A 已通过 `just refs`、`just layout-check`、`just check-sensitive`、
  `just flutter-codegen-check`、`just flutter-check`、完整 `just check` 与独立代码审查；结构 baseline 只剩
  `packages/ubaa_ui/lib/src/widgets.dart`。该结果是当前本地确定性证据，不等同于阶段 14 的最终候选验证。
- `324979e` 上的阶段 10B 新增共享宿主、两个 27 行平台入口及完整 callback/lifecycle 竞态测试；本机重新通过
  FRB 零漂移、完整 Flutter 工作区、`just check`、macOS integration 6 项、macOS/Android APK/iOS simulator
  Debug 构建与产物结构检查、OHOS API26 arm64 无签名 HAP，并经两轮独立复审给出 Ready。该 HAP 仍不是签名或
  实体设备证据。
- `c76a81a` 上的阶段 11A 将博雅选课资格固化为 `allowed/denied/unknown` typed contract；缺少可解析开课时间、
  详情目标错配或提交前资格变化均 fail-closed，且 intent 被消费后不发送写请求。Core 162 项双配置测试、CLI
  binary E2E 16 项、CLI contract 32 项、只读 61 项、认证 28 项、Bridge 19 项、Flutter Domain 9 项、App 55
  项、UI 51 项、Host 10 项、官方 App 2 项、macOS integration 6 项、FRB 零漂移、`just check`、refs、layout、
  sensitive 与独立复审均通过；这是本地确定性阶段证据，不是新的 live/签名/设备证据。
- `0a16276` 上的阶段 11B 以已选课程的内层 `courseInfo.id` 作为退选目标，拒绝误用外层选择记录 ID；
  `selected=false`、缺失/非法开课时间、目标错配及提交前资格漂移均按已记录来源 fail-closed。Core 163 项
  双配置测试、CLI binary E2E 16 项、CLI contract 32 项、只读 61 项、认证 28 项、Bridge 24 项、Flutter
  Domain 9 项、App 55 项、UI 51 项、Bindings 11 项、Host 10 项与官方 App 2 项通过；refs、layout、682 文件
  sensitive、完整 `just check`、完整 `just flutter-check`、FRB 零漂移和两侧独立复审均通过。macOS integration
  首轮课表 typed 查询出现一次不可复现的 `null`，同一单例随后 1/1、完整套件随后 6/6 通过；没有证据把该
  波动归因于本阶段 Bykc 变更。这仍只是本地确定性阶段证据，不是新的 live、签名或设备证据。
- `a147132` 上的阶段 11B2 将 Bridge 写入层从 893 行生产文件与 925 行测试文件拆为职责模块；最大生产文件
  294 行、最大测试叶 425 行。14 个公开类型、11 个公开异步方法、20 个写测试叶及其行为集合保持不变，
  Bridge 24 项、完整 `just check`、完整 `just flutter-check`、连续两次 FRB 零漂移、refs、layout、689 文件
  sensitive 与两侧独立复审均通过；生成绑定只发生一行私有 helper 忽略注释的可解释变化。
- `0a110b5` 上的阶段 11C 将 Bykc 签到/签退资格完整迁移为 `allowed/denied/unknown` typed action，并在
  prepare 与 commit 重读当前学期、课程与签到点配置；最终 POST 使用不可重放发送边界，发送后的 transport、
  Cookie、响应形状或会话竞态不会被误报为可重试失败。CLI envelope 显式升为 schema v3，磁盘 session
  仍为 schema v2。Core Bykc 12 项、Bridge 35 项、CLI E2E 16 项、CLI contract 33 项、Flutter Domain 10 项、
  Platform 37 项、App 65 项、UI 58 项、Bindings 11 项、Host 11 项与官方 App 2 项通过；`just refs`、
  `just layout-check`、694 文件敏感扫描、完整 `just check`、FRB 零漂移、完整 `just flutter-check` 和独立
  Rust/Dart 复审均通过。该证据不包含原生位置 handler、真实签到、签名或设备验证。
- `b988ae1` 上的阶段 11D 将 Signin `signStatus` 显式建模为可空 `i32`，由 Core 统一映射
  `allowed/denied/unknown`、稳定安排目标和确定业务结果；prepare/commit 均重读当天唯一目标，最终 POST
  只越过一次不可重放发送边界。Flutter 只消费 typed action，CLI envelope 升为 schema v4，bridge contract
  升为 v3，磁盘 session 仍为 schema v2。Core 默认模式 173 项、Signin integration 9 项、Bridge 42 项、
  CLI binary E2E 16 项、CLI contract 38 项、Flutter Domain 11 项、Platform 38 项、App 65 项、UI 61 项、
  Bindings 11 项、Host 11 项、官方 App 2 项及 macOS 宿主 integration 7 项通过；`just refs`、
  `just layout-check`、697 文件敏感扫描、完整 `just check`、FRB 零漂移、完整 `just flutter-check` 和独立
  终审均通过。该证据未执行真实账号写入，不包含签名、实体设备或真实写后核对。
- `445240d` 上的阶段 11E 将 LibBook 座位 `status` 显式建模为可空 `i32`，由 Core 严格映射
  `allowed/denied/unknown`、稳定座位目标，并在 prepare/commit 中按目标日期、唯一时段和唯一座位重读
  fresh authority；最终 confirm 只越过一次不可重放发送边界。冻结 `Accept`、`User-Agent`、Authorization、
  XHR 与按路线转换的 Origin/Referer 均有 Direct/WebVPN 合成传输断言。Flutter 只消费 typed action，CLI
  envelope 升为 schema v5，bridge contract 升为 v4，磁盘 session 仍为 schema v2。Core 默认模式 176 项、
  LibBook integration 11 项、Bridge 50 项、CLI binary E2E 16 项、CLI contract 45 项、Flutter Domain 12 项、
  Platform 38 项、App 67 项、UI 65 项、Bindings 12 项、Host 11 项、官方 App 2 项及 macOS 脱敏宿主
  integration 7 项通过；`just refs`、`just layout-check`、702 文件敏感扫描、完整 `just check`、FRB 零漂移、
  完整 `just flutter-check` 与独立终审均通过。该证据未执行真实预约，不包含签名、实体设备或真实写后核对。
- `ef63d0a` 上的阶段 11F 将 LibBook booking `status` 显式建模为可空 `i32`，由 Core 严格映射
  `allowed/denied/unknown` 与稳定取消目标；typed action 保存 `id/page/limit`，prepare 与 commit 都重读
  同一页，要求响应显式给出无冲突 canonical 正数分页并唯一匹配目标。最终 cancel wire 只有 `{id}` 且只发送
  一次；成功、确定 false、终态和 authority 错误均使用固定安全文案，发送后歧义为不可重试
  `outcome_unknown`。CLI envelope 升为 schema v6，bridge contract 升为 v5。Core 默认模式 176 项、LibBook
  integration 25 项、Bridge 61 项、CLI binary E2E 16 项、CLI contract 50 项、Flutter Domain 13 项、Platform
  38 项、App 72 项、UI 66 项、Bindings 13 项、Host 11 项、官方 App 2 项及 macOS 脱敏宿主 integration 7 项
  通过；`just refs`、`just layout-check`、705 文件敏感扫描、完整 `just check`、FRB 零漂移、完整
  `just flutter-check` 与两轮独立安全/正确性复核均通过。该证据未执行真实取消，不包含签名、实体设备或真实
  写后核对。
- `40b7b4e` 上的阶段 11G 将 Cgyy 时段的 canonical 状态显式建模为可空值，由 Core 严格派生
  `allowed/denied/unknown` 与完整稳定目标；prepare 与 commit 均对精确日期和目标执行 fresh
  authority，只允许一到两个同空间且按原始序号相邻的时段。captcha 最多三轮且全部位于最终发送前，
  submit 只越过一次不可重放边界；结果仅返回固定安全文案和可选正订单编号收据，发送后歧义为不可重试
  `outcome_unknown`。CLI envelope 升为 schema v7，bridge contract 升为 v6，Flutter 只消费 typed
  action。Core 默认模式 178 项、Cgyy integration 22 项、Bridge 67 项、CLI binary E2E 16 项、CLI contract
  56 项、Flutter Domain 14 项、Platform 38 项、App 74 项、UI 69 项、Bindings 13 项、Host 11 项、
  官方 App 2 项及 macOS 脱敏宿主 integration 7 项通过；`just refs`、`just layout-check`、713 文件
  敏感扫描、完整 `just check`、FRB 零漂移、完整 `just flutter-check` 和独立终审均通过。该证据未执行
  真实场馆预约，不包含签名、实体设备或真实写后核对。
- `f4e3137` 上的阶段 11H 将 Cgyy 订单取消资格统一收归 Core：只有 canonical 同 ID、允许状态与
  `Asia/Shanghai` 四小时截止点同时成立才产生 typed target；prepare/commit 双 fresh，最终 POST 在 Core
  单次路线解析所得 runtime 上只越过一次不可重放边界。成功或 `outcome_unknown` 后固定在 intent 原路线读取
  0-based 首页列表与同 ID 详情，只有两个本次局部结果都携带 strict `cancelledTarget` 才标记已核对。
  CLI envelope 升为 schema v8，bridge contract 升为 v7。Core 333 项、Bridge 81 项、CLI binary E2E
  16 项与 contract 66 项、Flutter Domain 15 项、Platform 38 项、App 79 项、UI 72 项、Bindings 15 项、
  Host 11 项、官方 App 2 项和 macOS 脱敏宿主 integration 7 项通过；`just refs`、`just layout-check`、
  719 文件敏感扫描、完整 `just check`、FRB 零漂移、完整 `just flutter-check` 及独立代码终审通过。
  Flutter 全量与宿主 integration 的首轮失败分别暴露两个测试 backend 未声明 caller-pinned 能力，以及取消
  后订单视图仍被误当作预约视图；修复测试宿主接口与操作顺序后均全量复跑通过。本阶段未执行真实场馆取消，
  不包含签名、实体设备或真实写后核对。
- `d8484ad` 上的阶段 11I 将 Ygdk 分类与项目收归 Core fresh typed authority；prepare 不上传，commit 在
  expected-route 原子入口中固定路线、Session/credential generation，并依次执行 fresh authority、最多一次
  upload 与最多一次 final。任何 upload 失败均不自动重传且不进入 final；final 发送后歧义固定为不可重试
  `outcome_unknown`。确定成功与 unknown 都只在 intent 原路线独立执行一次 caller-pinned overview/records
  回读，且不得把 unknown 升级。CLI envelope 升为 schema v9，bridge contract 升为 v8。Core 364 项、Bridge
  93 项、CLI 116 项、Flutter Domain 16 项、Platform 42 项、App 98 项、UI 83 项、Bindings 15 项、Host 14 项、
  官方 App 2 项及 macOS 脱敏宿主 integration 7 项通过；`just refs`、`just layout-check`、完整 `just check`、
  FRB 零漂移、完整 `just flutter-check`、敏感信息扫描和独立终审均通过。结构拆分后除 Phase 12 待处理的
  `widgets.dart` 精确 baseline 外没有其它超长文件或拥挤目录。本阶段未执行真实照片上传或账号写入，不包含
  签名、实体设备或真实写后核对。
- `4b0dcb0` 上的阶段 11J 完成 Evaluation typed 提交链，CLI schema v10、bridge v9。独立审查补齐冲突课程行仍参与同目标
  去重的 RED/GREEN，并修复架构门禁沿实际 `mod`/`#[path]` 声明识别领域测试的缺口；未引用测试文件不作证据。
  Core 单元 215 项双配置、架构合同 22 项、Evaluation 集成 20 项、CLI binary E2E 16 项、CLI contract 94 项、
  Bridge 108 项、Flutter Domain 18、Platform 42、App 111、UI 91、Bindings 15、Host 15、官方 App 2 项与
  macOS 脱敏 integration 7 项通过。refs、layout、敏感扫描、完整 `just check`、完整 `just flutter-check`、
  FRB 零漂移与差异检查通过；不将此本地阶段证据视为阶段 14 的最终候选或真实写入证据。
- `b6ff2c7` 的阶段 11K 将生产写状态统一到 AppController 持有的 `WriteCoordinator`，旧 `WriteFlowController` 为同一
  类型别名。UI 只消费 immutable state 与三个安全命令；准备、取消、提交、回读的失效/销毁、同步通知重入、
  backend 替换以及位置/照片等待期间注销均有确定性覆盖。最终 Flutter Domain 25、Platform 42、App 177、
  UI 95、Bindings 15、Host 18、官方 App 2，共 374 项通过，macOS integration 7 项通过；14 个原 UI 测试叶
  只改构造名称，26 张 golden 的名称、长度与 SHA-256 不变。refs、layout、敏感扫描、完整 `just check`、
  FRB 零漂移、完整 `just flutter-check`、macOS/Android APK/iOS simulator Debug 构建及产物结构、OHOS API26
  arm64 无签名 HAP 和独立复审通过；新文档遗漏 `--locked` 曾被 CLI 合同拦截，修正后完整复跑通过。
  该阶段留下的 3883 行 `widgets.dart` 已由后续 Phase 12 纯拆分；本阶段未执行真实写入。

- `1f63127e` 和 `7202fcf9` 完成 UI 与 Core 入口的最后两组机械整理。UI 公共路径、23 类/295 成员、回调与
  布局 AST 等价，26 张 golden 字节不变；Core 7 组源码/测试块逐字相同，Reqwest 3 项、认证 28 项、只读
  61 项定向测试通过。Flutter 374 项、FRB 零漂移、refs、零例外 layout、敏感扫描与完整 `just check` 通过。
  macOS integration 首轮页面切换等待超时，完整复跑 7 项通过；旧 Debug 缓存下的首次 Rust 全量因启动
  延迟主动终止（143），保留日志及缓存后从头复跑全量（0）。两份中断/失败记录均保留，不计为 PASS。

## 阶段 14A 与前次候选

`d43c177284e4be4beb63643b3cc79ec2ce8ff820` 完成 19 项串行本地门禁，包含完整 Rust/CLI、Flutter/FRB、
发布报告、macOS integration、三平台构建与产物检查、OHOS API26、Direct/WebVPN 只读及最终差异检查。
其[五平台原生 CI 33962021922](https://github.com/BUAASubnet/UBAA/actions/runs/33962021922) 五个 job 全部成功，
但[合同 CI 33962021960](https://github.com/BUAASubnet/UBAA/actions/runs/33962021960) 未通过，不能标记整轮完成。

合同 CI 暴露两项跨平台缺口：Flutter 版本命令的 stdout 被 `head` 提前关闭，触发 Broken pipe；Windows
stable 无法编译尚不稳定的 `MetadataExt` 文件标识方法。阶段 14A 已实现完整消费工具链输出和 CLI 本地照片的
稳定句柄身份检查，并增加隔离假 SDK 与同尺寸文件替换回归；Unix 原有设备/inode 检查继续保留。修复不改变
上游协议、CLI schema v10、bridge v9、生成绑定或真实写入边界，具体裁决见[决策记录](decision-log.md)。

CLI 修复已提交 `4017edd7`：本地完整 `just check` 退出码 0，CLI 全目标 127 项通过，包含输入单元 12 项、
Core-live 参数 3 项、binary E2E 16 项、CLI contract 94 项及 Core-live runtime 2 项。该结果只证明本地
阶段验证，不把 Unix 测试通过写成 Windows stable 已验收。

工具链修复已提交 `7b8eed3a`：六项隔离假 SDK 合同、完整 `just check` 通过，两个新增/修改的 Shell 脚本
已实际通过 ShellCheck 0.11.0。新候选的 19 项本地验收须把该工具加入 PATH，使全仓 Shell 门禁实际执行，
不能用缺少工具时的 SKIP 替代本轮静态证据。

全仓 ShellCheck 继续发现并推动修复了 OHOS 可执行路径引用、source 解析、根目录定位失败返回和两处
测试失败断言。`23066064` 与 `c21a12dd` 完成这些定点修复；全仓 ShellCheck 0.11.0、完整 `just check`
及独立复审通过，没有扩大真实运行副作用或关闭整类诊断。

## 阶段 14B 与冷启动验证

`bef16ee53b065df350ba9b8681422ea3e47444b2` 的
[原生 CI 33966609636](https://github.com/BUAASubnet/UBAA/actions/runs/33966609636) 五个 job 全部成功，
但[合同 CI 33966609776](https://github.com/BUAASubnet/UBAA/actions/runs/33966609776) 失败：固定 SDK
冷启动的 curl 进度先于版本输出，Windows 测试夹具则因非法名称在创建文件时失败；Windows 编译与 Clippy 已通过。

`38ef75cf` 完整读取 stdout 后只接受首条独立版本行并精确比较版本 token，八项回归与真实隔离无缓存 SDK
验证通过。`f0daed09` 保留所有平台的危险名称策略及 CLI 实文件检查连接，本地 CLI 全目标 128 项通过。
完整 `just check`、ShellCheck 0.11.0 及独立复审通过。详细来源和测试边界见[决策记录](decision-log.md)。

前次本地两轮均通过第 01–16 项，但 Cgyy 只读出现超时及 HTTP 502；一次定向恢复成功不能覆盖后续失败。
两条路线实际主机与 runtime 均匹配，未依据错误改动协议。新候选仍需在上游可用时完整复验。

本页所属提交是修复后的新候选。定向测试不替代新候选的 19 项完整本地门禁、Windows stable Rust job 及两条
同 SHA CI；前次尝试的成功、失败和日志均保留，不合并成新候选的 PASS。

## 阶段 14C 与引用合同验证

`a19cc7f2f60fd82dec86e9d606e1fde564956118` 在 2026-09-05 21:15–21:22 完整通过本地 19 项门禁，
Direct/WebVPN 各为 39 PASS、1 NOT_APPLICABLE、0 FAIL，Cgyy 上游已恢复。
[原生 CI 33968790269](https://github.com/BUAASubnet/UBAA/actions/runs/33968790269) 五个 job 全部成功；
[合同 CI 33968790247](https://github.com/BUAASubnet/UBAA/actions/runs/33968790247) 的 Windows/macOS
Rust job 成功，但引用 Shell 合同失败，不能标记该候选整体通过。

`fbcbbdb9` 完整捕获 Just dry-run 的 stdout/stderr，并把六个原条件改为显式失败退出，消除 Bash 3.2
裸 `[[ ]]` 的漏报。Just 1.58.0 真实 RED、1.58/1.51 GREEN、ShellCheck 0.11.0、完整 `just check`
及独立复审通过。新候选显式使用 Just 1.58.0 与 ShellCheck 0.11.0 从头验收；详细边界见[决策记录](decision-log.md)。

## 整理前的历史完整验收

以下证据只绑定 `4eaf1dd`，不能沿用为本次结构治理的最终候选 PASS：

- `4eaf1dd` 上的 `just refs`、`just check-sensitive`、`just check`、`just flutter-codegen-check`、
  `just flutter-check`、`just release-preflight` 与 `git diff --check` 均有通过记录。
- 同一 verified HEAD 的 Direct 与 WebVPN Core-live 在营业窗口内串行运行，认证、用户、课表、考试、成绩、
  空教室、SPOC、Judge、课堂签到、阳光打卡、图书馆、博雅、场馆和评教必需读取均为 `PASS`；允许的详情
  `NOT_APPLICABLE` 均有同批次空父集合依据。
- Flutter 原生 CI `33628444289` 的 Linux、Windows、macOS、iOS simulator、Android APK 无签名 Debug job
  全部成功；合同 CI `33628444204` 的 contract-gates、macOS Rust、Windows Rust 全部成功。
- OHOS API26 无签名 HAP 包含 arm64 Rust bridge；产物未签名、未安装、未上传。
- 十二项详情 golden、响应式/明暗主题、状态矩阵、typed 查询、十项写入确认/防重复/读后核对和未知结果
  确定性回归均有记录。

## 未验证

- 本页冻结最终候选时不预填阶段 14 的 PASS；最终完整验收以仓库外执行记录及同 SHA 的 CI 终态为准。
- 阶段 14A/14B/14C 修复后的候选尚需完整重新验收；旧候选的部分成功不能覆盖其合同 CI 或实时上游失败。
- Windows、Linux、Android、iOS 与 HarmonyOS 上使用真实账号的 App→FRB→Core 全链路没有实体设备证据。
- 本周期没有执行十项真实写入，也没有真实上游写后读取核对；历史单次授权探针不自动证明当前实现。
- Flutter 原生 CI 证明无签名 Debug 构建和结构，不证明安装、升级、卸载、签名、公证或商店审核。
- 公共 GitHub CI 记录不包含 OHOS API26 构建；OHOS 证据来自受控本机门禁。

## 后置 BLOCKED

以下事项不计入已完成的无签名执行目标，但在正式发布前必须单独闭合：

- Windows/macOS/iOS/Android/Linux/HarmonyOS 的正式签名、证书、公证与商店上传；
- 实体设备安装、启动、权限、前后台生命周期、升级与卸载；
- Keychain、Keystore、Credential Manager、Secret Service 与 HUKS 原生 handler 及硬件安全存储验证；
- 受逐操作、逐目标、逐路线、逐时间授权约束的真实写入与写后核对。

任何无签名 HAP/APK/App、Mock、golden、Fixture、CI 构建或历史实时成功都不得改写为上述事项已完成。
