# 贡献指南

## 基本原则

- 使用聚焦分支和单一主题、可审查的提交；机械移动、行为修改、生成刷新和证据文档不要混在同一提交。
- 每项行为变更先增加会失败的脱敏测试并观察预期失败，再做最小实现。
- 认证、读取或写入协议变更必须先完成 `docs/migration/source-parity.md` 规定的两个冻结来源逐操作对照；
  没有证据的 URL、字段、Header、加密常量和错误语义不得从经验补全。
- Rust Core 是协议与路线的唯一所有者；新增生产代码只能通过 facade/bridge 稳定合同使用能力，现有公共类型
  与 CLI 输出策略例外按结构治理实施计划关闭。

当前代码结构目标、阶段顺序与提交边界见[代码与目录组织设计](docs/architecture/code-organization.md)和
[实施计划](docs/superpowers/plans/2026-09-03-code-organization.md)。

## 安全边界

以下输入只读且不得暂存或提交：`ubaa_old/`、`examples/`、`.env.local`、运行时 Session、Cookie、Token、
验证码图片、真实响应、个人资料、签名密钥和构建产物。Fixture 必须只保留最小协议结构，使用明确虚构值；
不得把原始上游响应复制成 fixture。

真实写入不属于普通开发或 CI。即使实现和 Mock 已通过，每次真实操作仍需对具体目标、操作、路线和时间
单独授权；写请求可能到达上游后禁止自动重试。

## 开发循环

1. 运行 `git status --short --branch` 与 `just refs`，确认冻结引用和现有工作树。
2. 更新来源对照、合同或当前状态，说明本次事实边界。
3. 增加 focused 失败测试并保留预期失败证据。
4. 实现最小改动，先运行 focused test，再运行适用的完整门禁。
5. 使用明确 pathspec 暂存；禁止 `git add .`。
6. 检查 `git diff --cached --name-only` 与 `git diff --cached`，随后运行敏感扫描再提交。

## 提交前门禁

至少运行：

```bash
just refs
just check-sensitive
just check
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
just flutter-check
git diff --check
```

只修改 Rust/CLI 的聚焦阶段仍需确认 Flutter/FRB schema 没有被意外改变；修改 Flutter、bridge、平台宿主或
生成输入时必须运行对应 package、golden/integration 与平台构建门禁。认证或只读行为变化在确定性门禁通过
后，还要串行完成 Direct 与 WebVPN 真实只读验证。CI 永远不接收真实凭据，也不执行真实写入。

FRB 机械生成文件只能由锁定 codegen 更新，不得手改；golden 只能在有意视觉变更时更新，并必须在不更新
模式再次通过。
