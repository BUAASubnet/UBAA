# 贡献指南

## 基本原则

- 使用聚焦分支和单一主题、可审查的提交；机械移动、行为修改、生成刷新和证据文档不要混在同一提交。
- 行为变更先用会失败的脱敏反例观察问题，再做最小实现；纯文案、文档与可逆机械改动复用已有覆盖，不为凑数量增加琐碎测试。
- 认证、读取或写入协议变更必须先完成 `docs/migration/source-parity.md` 规定的两个冻结来源逐操作对照；
  没有证据的 URL、字段、Header、加密常量和错误语义不得从经验补全。
- Rust Core 是协议与路线的唯一所有者；生产宿主只能通过 facade/bridge 稳定合同使用能力。CLI 自有
  `command/backend/execute/io` 负责参数、输出和退出策略；Core 测试注入只在显式 `test-contract` 下开放。

当前代码结构目标、阶段顺序与提交边界见[代码与目录组织设计](docs/architecture/code-organization.md)和
[实施计划](docs/superpowers/plans/2026-09-03-code-organization.md)。

## 安全边界

以下输入只读且不得暂存或提交：`ubaa_old/`、`examples/`、`.env.local`、运行时 Session、Cookie、Token、
验证码图片、真实响应、个人资料、签名密钥和构建产物。Fixture 必须只保留最小协议结构，使用明确虚构值；
不得把原始上游响应复制成 fixture。

真实写入不属于普通开发或 CI。即使实现和 Mock 已通过，每次真实操作仍需对具体目标、操作、路线和时间
单独授权；写请求可能到达上游后禁止自动重试。

## 开发循环

仅当本机缺少冻结引用时先显式运行一次 `just refs-bootstrap`。该命令允许联网创建引用；普通开发循环、提交门禁
和发布前置一律只运行纯只读的 `just refs`。

1. 运行 `git status --short --branch` 与 `just refs`，确认冻结引用和现有工作树。
2. 更新来源对照、合同或当前状态，说明本次事实边界。
3. 按改动风险选择既有聚焦用例；行为修复先保留预期失败证据。
4. 实现最小改动，运行聚焦检查，再用 `just check-plan` 审阅影响，`just check-changed` 执行；已提交分支使用 `base=<基线>`。
5. 使用明确 pathspec 暂存；禁止 `git add .`。
6. 检查 `git diff --cached --name-only` 与 `git diff --cached`，随后运行敏感扫描再提交。

## 分层验证

- 日常修改：`just check-changed` 读取暂存、未暂存、未跟踪和删除路径；`base=origin/ubaa2` 还包含分支已提交改动。纯文档仅检查引用、敏感材料与 diff；测试只改本包时运行本包；生产 Dart 改动包括所有直接/间接消费者及测试依赖。
- Core/Bridge/工具链、包配置、检查脚本、未知路径保守执行完整相关检查。`just check-plan` 只展示计划；干净工作树没有本地改动不代表已验证分支。
- PR/CI 与测试门禁整理：运行 `just refs`、`just check-sensitive`、`just check`、`just flutter-check`。FRB 输入或生成工具变化增加 `just flutter-codegen-check`；平台能力变化增加对应原生验证，最终候选保留发布准入门禁。
- 原生与真实验证：纯文档不触发五平台构建；平台相关变更按矩阵验证，认证或读取协议变更串行完成 Direct/WebVPN。真实写入仍须具体授权。

不把同一状态机仅换别名重复测试；合并必须保留所有独立断言。API 常规签名由实际消费者编译检查，敏感字段与序列化等否定性边界单独保留。Golden 按不同布局选代表性 typed 脱敏数据，跨尺寸操作行为由领域 Widget 测试负责；保留精确比较，更新后必须在非更新模式通过。

FRB 机械生成文件只能由锁定 codegen 更新，不得手改。CI 永不接收真实凭据，也不执行真实写入。
