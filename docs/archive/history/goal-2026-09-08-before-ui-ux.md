# 可维护性治理活动合同

状态：本地可维护性治理完成，独立复审无未解决高、中风险问题。制定与完成日期：2026-09-07，Asia/Shanghai。

本文件是当前活动合同，覆盖错误语义、可追溯诊断、确定性门禁和可共享交接证据的维护修复。设计见[可维护性治理设计](docs/superpowers/specs/2026-09-07-maintainability-design.md)，实施步骤见[可维护性治理计划](docs/superpowers/plans/2026-09-07-maintainability.md)。

此前 macOS 真实 App 专项合同及其观察、修复和暂停事实已原样归档至[2026-09-07 macOS 真实 App 合同](docs/migration/history/goal-2026-09-07-macos-real-app.md)；不得将归档中的历史结果回填为本轮维护修复的验收结果。

## 已确认现状

- 冻结引用仍为 `ubaa_old` `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 与 `examples/buaa-api` `efb7976bf513f38364b88aeb83d704586cff9b2a`。认证和只读行为变更继续先做逐操作来源对照。
- 稳定公开合同保持 CLI JSON schema v10、Flutter Bridge v9、`session.json` v2 和 `config.toml` v1。本轮不得借维护治理改变上游请求、TLS、写入次数、重试策略或公开 Rust 错误。
- `0bd866c9ff5f205f2b1604bf5e72640a3e735018` 是 2026-09-05 代码组织历史验收所记录的源码 SHA。其脱敏计数和公开 CI 链接已整理到[仓库内历史摘要](docs/migration/evidence/2026-09-05-code-organization-summary.md)，仅表示当日证据，未在本轮重新在线核验。
- macOS 主动联网权限修复源码提交为 `cf5d431338d22d18c0e24245bb0ad1fd16709dde`。此前合同记录了用户确认的基础登录和随后暂停的真实测试；本轮只将其作为历史来源，不读取凭据、会话、实时响应或个人数据。

## 范围与约束

- 保持真实 App 和 Core-live 暂停，只进行本地确定性开发、测试和文档记录；不读取 `.env.local`、运行时会话、验证码或实时上游响应。
- 不执行任何学校业务写入、签名发布、设备安装、上传诊断或自动重试上游请求。
- 生产宿主只能经 Core `facade` 使用协议能力；不向宿主暴露 URL、Cookie、token、原始响应或 `upstream` 内部类型。
- 每个行为修复先留下脱敏 RED 证据，再做最小实现与 GREEN 复验。涉及认证或只读行为时，先补来源对照；参考冲突或缺少证据时停止在边界，不猜测协议字段。
- 仓库内只保存安全摘要和可复现的确定性证据。不得提交凭据、Cookie、token、原始响应、验证码、个人资料或其截图。

## 本轮工作与验收

1. 恢复 Bridge 到 Dart 的既有错误字段传播，并让应用层只保留一个展示映射入口。
2. 增加有界、仅内存且不含原始异常文本的本地诊断，覆盖控制器、写入协调器和安全 UI 呈现。
3. 为 Reqwest 传输增加私有安全分类；补齐严格 ShellCheck 入口和 macOS 实际签名权限检查。
4. 维护本页、[当前状态](docs/migration/status.md)、来源对照、排障资料和仓库内脱敏证据，使新 clone 不依赖个人绝对路径。

本轮最终实现内容已提交为 `541981ea51a79044043b74cec3af0a32b5c35308`。严格 Rust/Shell、CLI、396 项 Flutter、FRB 零漂移、7 项脱敏 macOS integration，以及 macOS/Android/iOS simulator/OHOS 本机构建与产物门禁通过，见[验收记录](docs/migration/evidence/2026-09-07-maintainability.md)。后续文档提交只记录结果，不冒充新增源码或远端验证。

## 未完成的真实验收边界

- macOS 真实 App 的 Direct/WebVPN、会话恢复、用户中心和十二领域读取矩阵仍未完成。
- 任何真实业务写入、写后读取核对、正式签名、公证、商店上传、实体设备和原生安全存储验证均未在本合同下执行。
- 历史 Core-live、CI、Fixture、Mock、golden、无签名构建和宿主集成的成功不能代替本轮或真实 App 验收。
