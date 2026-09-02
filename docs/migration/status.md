# 当前迁移与交付状态

更新日期：2026-09-03

本页只呈现当前有效结论。2026-09-02 及以前的逐次修复、失败、重跑与 CI 流水已原样归档到
[历史状态流水](history/status-through-2026-09-02.md)；不得用历史阶段中的“未完成”覆盖本页终态，也不得用
历史成功替代当前候选重新验证。

## HEAD 证据边界

| 类型 | 提交 | 含义 |
|---|---|---|
| implementation HEAD | `0a0bb71` | 最近一次产品实现/测试变更：响应式主题、无障碍与长列表回归；后续至本轮结构治理前均为文档提交 |
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

- 当前结构治理中的未提交或后续提交尚未形成新的 verified HEAD。
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
