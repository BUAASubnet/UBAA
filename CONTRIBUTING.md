# 贡献指南

[AGENTS.md](AGENTS.md) 是长期规则入口，适用于维护者和 agent。[goal.md](goal.md) 只列当前阶段目标，[迁移状态](docs/migration/status.md)记录已验证的事实。贡献前阅读[工程规范](docs/development/engineering-standards.md)、[开发约定](docs/development/conventions.md)及[开发环境](docs/development/setup.md)。

当前结构依据为[代码组织](docs/architecture/code-organization.md)、[ADR 0006](docs/adr/0006-explicit-dart-modules.md)与[ADR 0007](docs/adr/0007-operation-scopes-and-verification.md)。历史实施计划仅保留追溯用途。

## 开发与提交

按 [AGENTS 开发循环](AGENTS.md#开发循环)保留工作区、确认冻结引用、先证明行为问题，再做最小实现。纯文案、文档和机械变更复用已有覆盖。测试合并须保留所有独立断言并登记替代覆盖，不能仅按名字或数量判定重复。

日常检查选择、完整验收、原生专项与 CI 的实际范围统一见[开发命令](docs/development/commands.md)，本页不维护另一份门禁清单。测试分层和 golden 更新要求见[测试策略](docs/development/testing.md)。FRB 机械生成文件只能由锁定生成器更新，不能手改。

使用明确 pathspec 暂存并人工审阅暂存区。禁止 `git add .`，每个阶段独立提交，提交信息使用中文并说明意图。机械移动、行为实现、生成刷新和证据文档应便于分别审查，行为代码与相应测试可以同一提交。分支与发布规则见[开发约定](docs/development/conventions.md#分支与提交)。

## 安全与协议

[AGENTS 安全边界](AGENTS.md#安全边界)、[来源对照门禁](AGENTS.md#来源对照门禁)和[真实账号规则](AGENTS.md#真实账号与验收范围)全部适用。冻结输入统一位于 `examples/ubaa_old/` 与 `examples/buaa-api/`，固定提交由[冻结参考](docs/migration/references.md)定义。

Fixture 只保留最小协议结构并使用明确虚构值，不得把原始上游响应复制为 fixture。Rust Core 是协议与路线的唯一所有者，生产宿主通过 facade/bridge 使用能力，不能依赖内部协议或测试注入。真实写入的具体授权和发送后禁止自动重试要求不能由确认参数或 Mock 结果替代。
