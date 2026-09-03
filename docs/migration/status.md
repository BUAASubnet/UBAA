# 当前迁移与交付状态

更新日期：2026-09-04

本页只呈现当前有效结论。2026-09-02 及以前的逐次修复、失败、重跑与 CI 流水已原样归档到
[历史状态流水](history/status-through-2026-09-02.md)；不得用历史阶段中的“未完成”覆盖本页终态，也不得用
历史成功替代当前候选重新验证。

## HEAD 证据边界

| 类型 | 提交 | 含义 |
|---|---|---|
| implementation HEAD | `0a16276` | 代码组织阶段 11B：博雅退选资格由 Core typed action 贯通 Bridge/Domain/App/UI，并以课程本体 ID 在 prepare/commit fail-closed 复核目标、路线与资格 |
| verified HEAD | `4eaf1dd` | 完整无签名门禁、Direct/WebVPN 只读矩阵、五平台 Flutter CI 与合同 CI 绑定的已验证提交 |
| evidence HEAD | `11a2969` | 对 `4eaf1dd` 最终无签名门禁和发布证据的最后一次状态固化；不表示签名、设备或真实写入已完成 |

当前代码组织治理以 [代码与目录组织设计](../architecture/code-organization.md) 和
[实施计划](../superpowers/plans/2026-09-03-code-organization.md) 为权威。结构治理提交在阶段 14 绑定新的
verified HEAD 前，不继承 `4eaf1dd` 的“当前候选已验证”身份。

## 当前能力

| 能力 | 实现状态 | 当前证据 | 结论 |
|---|---|---|---|
| Rust Core/facade | 认证、路线、双会话、读取与写入协议已实现 | Rust/Test Support 确定性测试；`4eaf1dd` 门禁 | 已实现并通过确定性验证 |
| CLI | schema v2、人类输出、Direct/WebVPN 诊断与写操作确认入口已实现 | CLI contract、binary E2E、Core-live/Shell 合同 | 已实现并通过确定性验证 |
| 用户中心与十二项业务读取 | Core/CLI/FRB/Flutter typed 链路与页面已实现 | `4eaf1dd` 的 Direct/WebVPN Core-live 全量读取均退出码 0；页面/查询/widget/integration 使用脱敏 backend 验证 | Core 实时只读已验证；真实 App 账号链路未验证 |
| 十项用户可见写入 | Core/CLI 协议、typed bridge、一次性确认、防重复、未知结果和读取核对流程已实现 | Fixture/Mock/向量、Dart/app/widget、macOS 脱敏宿主 integration | 无签名确定性闭环已验证；本周期未执行真实写入 |
| Windows/Linux/macOS/Android/iOS | 官方 Flutter 共享应用与原生宿主已实现 | Flutter CI `33628444289` 的五个无签名 Debug job；合同 CI `33628444204` | 无签名构建/结构证据通过，不是签名或设备证据 |
| HarmonyOS | 锁定 OHOS fork、API26 runner、arm64 Rust bridge 与无签名 HAP 已实现 | `UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug` 在 `4eaf1dd` 通过 | 无签名静态/包结构通过，不是签名 HAP 或设备证据 |
| 发布准备 | SBOM、锁文件/许可证审计、产物结构检查和回滚 runbook 已实现 | `just release-preflight` 与发布 runbook | 无签名 RC 准备已验证，不是正式发布 |

`Cgyy purposes` 的实时结果仍明确标记 `source=static_fallback`，表示采用已记录的冻结回退，不冒充上游用途接口
实时成功。SPOC/博雅详情只有在同批次父列表为空时才可记为 `NOT_APPLICABLE`。

## 已验证

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

以上证据只绑定 `4eaf1dd`。当前结构治理完成后必须在最终候选 HEAD 重新运行计划规定的全部门禁，不能直接
沿用这些 PASS。

## 未验证

- 阶段 11B2、11C–14 尚未完成，当前结构治理仍未形成新的 verified HEAD。
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
