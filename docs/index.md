# 文档索引

用户网站入口见 [UBAA 使用指南](site/index.md)，构建和 GitHub Pages 配置见[网站维护手册](runbooks/docs-site.md)。本索引与工程文档保留在仓库中。

## 日常开发入口

- [Agent 长期规则](../AGENTS.md)、[当前阶段目标](../goal.md)、[长期路线图](../UBAA2.md)
- [贡献指南](../CONTRIBUTING.md)、[安全策略](../SECURITY.md)
- [当前实现与验证状态](migration/status.md)
- [项目概览](../README.md)
- [现行代码组织](architecture/code-organization.md)
- [架构与协议边界](architecture/overview.md)
- [开发命令](development/commands.md)、[测试策略](development/testing.md)、[工程规范](development/engineering-standards.md)、[开发约定](development/conventions.md)、[目录命名](development/directories.md)
- [开发环境](development/setup.md)、[脚本副作用](../scripts/README.md)

## 按修改内容定位

| 修改内容 | 生产入口 | 普通测试 |
|---|---|---|
| 协议、解析和资格 | [Core features](../crates/ubaa_core/src/features/)、[facade](../crates/ubaa_core/src/facade/) | Core tests、ubaa-test-support |
| CLI 参数与输出 | [CLI](../apps/ubaa_cli/src/) | CLI tests 的合同和 binary E2E |
| FRB DTO 与句柄 | [Bridge API](../crates/ubaa_flutter_bridge/src/api/) | Rust Bridge、Bindings 与 codegen |
| 领域投影/读取适配 | [Dart Bridge 领域](../packages/ubaa_app/lib/src/bridge/features/) | [App 领域](../packages/ubaa_app/test/features/) |
| 会话、恢复和缓存 | [Controller](../packages/ubaa_app/lib/src/controller/) | [session](../packages/ubaa_app/test/session/)、[recovery](../packages/ubaa_app/test/recovery/)、[cache](../packages/ubaa_app/test/cache/) |
| 写入与回读 | [唯一协调器](../packages/ubaa_app/lib/src/write/)、[Controller write](../packages/ubaa_app/lib/src/controller/write/) | [App write](../packages/ubaa_app/test/write/) |
| 领域 UI | [UI features](../packages/ubaa_ui/lib/src/features/) | [UI 领域](../packages/ubaa_ui/test/features/) |
| 导航、查询与展示 | [UI app](../packages/ubaa_ui/lib/src/app/)、[common](../packages/ubaa_ui/lib/src/common/) | [query](../packages/ubaa_ui/test/query/)、[navigation](../packages/ubaa_ui/test/navigation/)、[visual](../packages/ubaa_ui/test/visual/) |
| 平台与宿主接线 | [Host](../packages/ubaa_host/lib/)、[Platform](../packages/ubaa_platform/lib/) | 各包 test；[原生能力清单](../scripts/integration-tests.json)和[覆盖边界](development/testing.md) |

## 稳定合同

- [认证与用户](contracts/auth-and-user.md)、[连接与会话](contracts/connection-and-session.md)、[路由策略](contracts/route-policy.md)
- [只读功能](contracts/readonly-features.md)、[Flutter Bridge](contracts/flutter-bridge.md)、[CLI JSON Schema](contracts/cli-json.schema.json)
- [离线缓存与恢复](contracts/offline-cache-and-recovery.md)
- [冻结参考](migration/references.md)、[来源对照矩阵及后续专项](migration/source-parity.md)

界面设计依据见 [Flutter UI 规格](design/flutter-ui-spec.md)、[配色](design/color-system.md)和[首页](design/home-layout.md)，具体实现与验收按当前候选记录。

## 架构决策与平台

- [Core 边界](architecture/core-boundaries.md)
- [Flutter 平台矩阵](architecture/flutter-platforms.md)、[本地适配清单](architecture/platform-adapters.md)
- [ADR 0001：Core/CLI](adr/0001-rust-core-cli-first.md)
- [ADR 0002：Serde 与 transport](adr/0002-serde-and-injectable-transport.md)
- [ADR 0003：URL、Cookie 与凭据](adr/0003-url-crypto-cookie-session.md)
- [ADR 0004：HTTP/HTML 依赖](adr/0004-verified-http-and-html-parser.md)
- [ADR 0005：六平台宿主](adr/0005-flutter-frb-six-platforms.md)
- [ADR 0006：显式 Dart 模块](adr/0006-explicit-dart-modules.md)
- [ADR 0007：操作作用域与验证闭包](adr/0007-operation-scopes-and-verification.md)
- [历史决策索引](migration/decision-log.md)

## 验证与运行

- [本地诊断](runbooks/local-diagnostics.md)、[真实认证](runbooks/live-auth-verification.md)、[真实只读](runbooks/live-readonly-verification.md)
- [发布流程](runbooks/flutter-release.md)
- [UI 证据规则](design/evidence/README.md)、[历史采集批次](design/evidence/batches.md)

## 近期实施与历史记录

- [2026-10-29 首页业务并发](migration/source-parity-home-concurrency-2026-10-29.md)、[首页传输性能](migration/source-parity-home-performance-2026-10-29.md)
- [2026-10-28 界面回归](migration/history/ui-regression-2026-10-28.md)、[2026-10-27 集成测试修复（历史快照）](migration/history/integration-repair-2026-10-27.md)
- [2026-10-21 认证修复](migration/history/auth-repair-2026-10-21.md)、[2026-10-29 文档站迁移](migration/history/docs-site-2026-10-29.md)
- [全部来源对照专项](migration/source-parity.md#全部来源对照专项)、[持续决策记录](migration/decision-log.md)

- [独立工程审查](migration/history/engineering-quality-independent-review-2026-10-07.md)、[完整整改实施](migration/history/engineering-quality-implementation-2026-10-07.md)

- [2026-10-07 可持续开发性审查](migration/history/maintainability-audit-2026-10-07.md)、[实施与验证](migration/history/maintainability-implementation-2026-10-07.md)
- [2026-10-01 项目整合快照](migration/history/project-audit-2026-10-01.md)
- [原代码组织设计](migration/history/code-organization-2026-09-05.md)、[旧测试指南](migration/history/testing-before-2026-10-07.md)
- [整理前状态](migration/history/status-before-maintainability-2026-10-07.md)、[此前项目收尾合同](migration/history/goal-2026-10-07-before-maintainability.md)
- [旧版功能迁移矩阵](migration/full-feature-matrix.md)、[旧版能力盘点](migration/legacy-feature-inventory.md)

历史提交、计数和验收结果只描述对应候选；不能代替当前确定性、原生、设备、真实只读或发布证据。

## 文档分工与归档

| 位置 | 维护内容 |
|---|---|
| architecture / contracts / development / runbooks | 现行架构、兼容行为、工程规则与操作入口。 |
| design | 持续维护的界面、配色与首页规格，历史设计和执行清单归档。 |
| migration | 当前状态、来源对照、决策入口及按候选登记的专项结果。 |
| migration/history | 已取代的目标、快照、设计、审计和计划，含原 superpowers 内容；见[历史说明](migration/history/README.md)。 |
| migration/evidence | 迁移、协议和阶段验收的脱敏文字证据与映射。 |
| design/evidence | UI 原型、采集元数据、批次与外部媒体索引。3967 个 JSON 保留原位，内部历史链接按既定约定处理。 |

历史内部链接按原提交追溯，现行文档指向归档的文件和锚点仍纳入[断链门禁](development/commands.md#文档链接范围)。历史材料不能充当当前任务授权。
