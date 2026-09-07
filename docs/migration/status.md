# 当前迁移与交付状态

更新日期：2026-09-07，Asia/Shanghai。

## 当前活动阶段：可维护性治理

当前活动合同为[可维护性治理](../../goal.md)，设计和实施计划分别见[设计](../superpowers/specs/2026-09-07-maintainability-design.md)与[计划](../superpowers/plans/2026-09-07-maintainability.md)。本阶段处理错误传播、本地安全诊断、传输诊断、严格门禁和可共享交接证据。

本轮本地可维护性治理已完成，最终实现内容为 `541981ea51a79044043b74cec3af0a32b5c35308`，详见[验收记录](evidence/2026-09-07-maintainability.md)。真实 App 与 Core-live 保持暂停。本轮不读取 `.env.local`、会话或实时响应，不执行真实学校写入、签名发布、设备安装或诊断上传。

## 已确认的合同与历史事实

| 项目 | 当前事实 | 边界 |
|---|---|---|
| 冻结引用 | `ubaa_old` `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`；`examples/buaa-api` `efb7976bf513f38364b88aeb83d704586cff9b2a` | 认证和只读行为变更仍须逐操作来源对照。 |
| 稳定版本 | CLI JSON schema v10；Flutter bridge contract v9；`session.json` v2；`config.toml` v1 | 本轮不得静默变更公开合同。 |
| 历史源码验收 | `0bd866c9ff5f205f2b1604bf5e72640a3e735018` | 这是 2026-09-05 的历史 verified 源码 SHA；摘要在[仓库内证据](evidence/2026-09-05-code-organization-summary.md)，本轮未重新在线核验。 |
| macOS 历史修复 | `cf5d431338d22d18c0e24245bb0ad1fd16709dde` 补齐 DebugProfile/Release 的主动联网权限 | 来源为归档合同；基础登录有用户确认，完整真实 App 验收仍暂停。 |

历史源码 SHA 与证据记录必须分开解释：`0bd866c9` 是 2026-09-05 验收报告对应的源码；该报告的脱敏内容被本仓库摘要引用，不把随后任何文档提交写成已重新验证的源码候选。

## 本轮已验证

- 错误字段完整传播、单一展示模板、结果未知禁止通用重试；有界本地诊断可从登录失败页与个人页主动查看/复制。
- Reqwest 真实回环、保守失败分类与 Bridge 安全 DEBUG 日志接线；CLI 默认 JSON stderr 合同保持。
- `just check-strict` 通过，实际运行 ShellCheck 0.11.0；CLI 128 项、Bridge 110 项、Flutter 396 项、维护 Shell 16 项及版本 Shell 7 项通过。
- FRB 重生成零漂移、macOS 脱敏宿主 integration 7 项通过；macOS 生产 Debug、Android 四种架构 APK、iOS simulator、OHOS API26 无签名 HAP 与本地产物检查通过。
- 结构门禁零例外、敏感扫描通过，独立复审无未解决高、中风险问题。源码验证内容和后续文档记录分别记账。

本轮未推送，未运行远端 CI，也未重验 Windows/Linux 原生运行器。历史 CI 成功不能继承。

## 真实产品验收仍未完成

- macOS 真实 App 的 Direct/WebVPN、会话恢复、用户中心和十二领域读取矩阵。
- 真实业务写入及写后读取核对。
- 正式签名、公证、商店上传、实体设备安装、原生安全存储和设备权限。

Fixture、Mock、golden、无签名构建、宿主集成、历史 Core-live 和历史 CI 各自只证明其记录范围，不能替代以上真实产品验收。

## 历史归档

- [2026-09-07 维护治理前状态全文](history/status-2026-09-07-before-maintainability.md)
- [2026-09-07 macOS 真实 App 活动合同全文](history/goal-2026-09-07-macos-real-app.md)
- [2026-09-02 及以前状态流水](history/status-through-2026-09-02.md)

归档保留当时的失败、修复、用户确认、暂停和计数，不以历史成功覆盖当前候选或本轮未执行项。
