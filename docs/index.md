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
- [唯一写入协调器设计与实施](superpowers/plans/2026-09-05-write-coordinator.md)
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
- [脚本入口与副作用](../scripts/README.md)

### 按修改内容定位

| 修改内容 | 实现入口 | 对应测试 |
|---|---|---|
| 上游协议、解析与业务资格 | [Core 领域](../crates/ubaa-core/src/features/)、[facade](../crates/ubaa-core/src/facade/) | 同领域单元测试、[Core 集成](../crates/ubaa-core/tests/)、[Mock 集成](../crates/ubaa-test-support/tests/) |
| CLI 参数、输出与退出码 | [command](../apps/ubaa-cli/src/command/)、[execute](../apps/ubaa-cli/src/execute/)、[io](../apps/ubaa-cli/src/io/) | [CLI 合同](../apps/ubaa-cli/tests/cli_contract/)、[二进制 E2E](../apps/ubaa-cli/tests/binary_e2e.rs) |
| FRB 公开类型与调用映射 | [手写 bridge API](../crates/ubaa-flutter-bridge/src/api/) | 相邻 Rust 测试、[Bindings 合同](../packages/ubaa_bindings/test/)与 codegen 零漂移 |
| Dart 模型与展示投影 | [domain](../packages/ubaa_domain/lib/src/)、[bridge adapter](../packages/ubaa_app/lib/src/bridge/) | [domain 测试](../packages/ubaa_domain/test/)、[app 测试](../packages/ubaa_app/test/) |
| 应用、写入和会话生命周期 | [controller](../packages/ubaa_app/lib/src/controller/)、[write](../packages/ubaa_app/lib/src/write/) | [协调器](../packages/ubaa_app/test/write_coordinator_test.dart)、[写入生命周期](../packages/ubaa_app/test/app_write_lifecycle_test.dart) |
| 登录、主页、导航与个人页 | [应用页面](../packages/ubaa_ui/lib/src/app/)、[Shell](../packages/ubaa_ui/lib/src/app/shell.dart) | [widget/golden](../packages/ubaa_ui/test/)、[宿主 integration](../apps/ubaa_flutter/integration_test/) |
| 公共查询、详情与分页 | [查询生命周期/提交](../packages/ubaa_ui/lib/src/common/query_controls.dart)、[状态展示](../packages/ubaa_ui/lib/src/common/feature_detail.dart)、[详情筛选/组合](../packages/ubaa_ui/lib/src/common/detail_list.dart)、[分页](../packages/ubaa_ui/lib/src/common/pagination.dart) | [查询](../packages/ubaa_ui/test/widgets/queries.dart)、[详情](../packages/ubaa_ui/test/widgets/feature_details.dart)、[状态](../packages/ubaa_ui/test/widgets/states.dart) |
| 领域查询控件与写按钮 | [课表/考试/成绩/空教室](../packages/ubaa_ui/lib/src/features/academic.dart)、[SPOC/Judge/Signin](../packages/ubaa_ui/lib/src/features/assignments.dart)、[博雅](../packages/ubaa_ui/lib/src/features/bykc.dart)、[图书馆](../packages/ubaa_ui/lib/src/features/libbook.dart)、[场馆](../packages/ubaa_ui/lib/src/features/cgyy.dart)、[阳光打卡](../packages/ubaa_ui/lib/src/features/ygdk.dart)、[评教](../packages/ubaa_ui/lib/src/features/evaluation.dart) | [领域 widget 测试](../packages/ubaa_ui/test/widgets/) |
| 场馆/打卡表单与写确认展示 | [场馆表单](../packages/ubaa_ui/lib/src/write/cgyy_form.dart)、[打卡表单](../packages/ubaa_ui/lib/src/write/ygdk_form.dart)、[确认页](../packages/ubaa_ui/lib/src/write/confirmation.dart) | [写入界面](../packages/ubaa_ui/test/widgets/writes.dart)、[状态/命令接线](../packages/ubaa_ui/test/write_coordination_test.dart) |
| 宿主接线与平台能力 | [共享 host](../packages/ubaa_host/lib/src/)、[platform](../packages/ubaa_platform/lib/src/) | [host 测试](../packages/ubaa_host/test/)、[platform 测试](../packages/ubaa_platform/test/) |

## 迁移、来源与证据

- [冻结参考](migration/references.md)
- [协议来源对照矩阵](migration/source-parity.md)
- [复杂业务模块目录化来源对照](migration/source-parity-code-organization.md)
- [Core 入口职责整理来源对照](migration/source-parity-entry-modules.md)
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
