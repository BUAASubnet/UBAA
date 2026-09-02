# 文档索引

## 首先阅读

- [项目概览与当前范围](../README.md)
- [当前迁移与交付状态](migration/status.md)
- [当前执行合同](../goal.md)
- [代码与目录组织设计](architecture/code-organization.md)
- [代码组织实施计划](superpowers/plans/2026-09-03-code-organization.md)
- [贡献指南](../CONTRIBUTING.md)

## 架构与决策

- [架构概览](architecture/overview.md)
- [Core 边界](architecture/core-boundaries.md)
- [Flutter 六平台版本与验收矩阵](architecture/flutter-platforms.md)
- [ADR 0001：优先采用 Rust Core 与 CLI](adr/0001-rust-core-cli-first.md)
- [ADR 0002：Serde 合同与可注入原始传输](adr/0002-serde-and-injectable-transport.md)
- [ADR 0003：URL、WebVPN 加密、Cookie 与会话依赖](adr/0003-url-crypto-cookie-session.md)
- [ADR 0004：已验证的 HTTP 与 HTML 解析依赖](adr/0004-verified-http-and-html-parser.md)
- [ADR 0005：Flutter + FRB 六平台宿主](adr/0005-flutter-frb-six-platforms.md)

## 稳定合同与产品规格

- [认证与用户合同](contracts/auth-and-user.md)
- [连接与会话合同](contracts/connection-and-session.md)
- [路由策略合同](contracts/route-policy.md)
- [只读功能合同](contracts/readonly-features.md)
- [Flutter Bridge 合同](contracts/flutter-bridge.md)
- [CLI JSON Schema](contracts/cli-json.schema.json)
- [Flutter UI 规格](design/flutter-ui-spec.md)

## 开发与测试

- [开发环境设置](development/setup.md)
- [开发命令](development/commands.md)
- [测试策略](development/testing.md)
- [工程规范](development/engineering-standards.md)

## 迁移、来源与证据

- [冻结参考](migration/references.md)
- [协议来源对照矩阵](migration/source-parity.md)
- [旧版完整功能迁移矩阵](migration/full-feature-matrix.md)
- [旧版功能盘点与迁移缺口](migration/legacy-feature-inventory.md)
- [决策记录](migration/decision-log.md)
- [当前迁移与交付状态](migration/status.md)
- [2026-09-02 及以前状态流水归档](migration/history/status-through-2026-09-02.md)
- [只读功能证据矩阵（历史快照）](migration/readonly-feature-matrix.md)

## 运行手册

- [实时认证验证](runbooks/live-auth-verification.md)
- [真实只读验证](runbooks/live-readonly-verification.md)
- [Flutter 六平台发布流程](runbooks/flutter-release.md)

## 历史执行记录

- [2026-08-31 Cgyy 路由与真实只读入口执行记录](superpowers/plans/2026-08-31-cgyy-parity-debug.md)

状态标签必须按证据层级解释：实现、Fixture/Mock、确定性集成、真实只读、无签名构建、实体设备与正式发布
彼此不能替代。无签名执行目标已完成不等于正式发布完成；真实写入仍受逐操作授权约束。
