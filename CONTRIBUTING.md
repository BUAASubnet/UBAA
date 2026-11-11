# 贡献指南

感谢你愿意参与 UBAA。本页写给第一次贡献代码或文档的人，按顺序介绍：提问与反馈、搭建环境、开发、自检、提交 PR。

## 不写代码也能帮忙

- **报告问题**：在 [Issues](https://github.com/BUAASubnet/UBAA/issues) 写清应用版本、设备系统、连接方式（自动、直连或 WebVPN）、操作步骤和错误提示。
- **发现安全漏洞**：不要公开发 Issue，请按[安全策略](SECURITY.md)私下报告。
- **改进使用文档**：用户文档在 [`docs/site/`](docs/site/)，修改后可以本地预览，见[文档站手册](docs/runbooks/docs-site.md)。

> [!WARNING]
> 无论是 Issue、PR 还是截图，都不要包含学号、密码、Cookie、Token、验证码、学校系统的原始响应或其他个人信息。

## 1. 搭建环境

按[快速上手](docs/development/getting-started.md)从 clone 到在本机运行 App，大致是：

```bash
(umask 077; cp -n .env.example .env)   # 然后在 .env 中填写 UBAA_FLUTTER_HOME
just setup                              # 安装锁定版本的工具和依赖
just doctor                             # 只读核对本机工具版本
```

Dart 和 Flutter 命令一律通过 `just dart`、`just flutter` 调用，不直接用 PATH 中的 SDK。完整工具清单和平台要求见[开发环境](docs/development/setup.md)。

## 2. 了解项目

- [架构导读](docs/architecture/overview.md)：Rust Core 负责校园协议和业务，Flutter 负责界面，两者经 flutter_rust_bridge 连接。
- [开发者文档首页](docs/README.md)：按“我要改什么”找到代码和测试入口。
- [术语表](docs/development/glossary.md)：文档里常见的“候选”“门禁”“冻结参考”“路线”等词是什么意思。
- [项目现状](docs/project/status.md)：哪些功能已经实现、在哪里验证过。

## 3. 开发

**分支**：从 `dev` 拉出分支开发，PR 提交到 `dev`。`main` 只接收验收过的发布候选。旧版 v1.x 代码在 `ubaa1` 分支，维护旧版时单独向该分支提交。详见[分支与提交](docs/development/conventions.md#分支与提交)。

**先写失败的测试**：修复缺陷或改变行为时，先写一个能复现问题的测试，再做最小改动让它通过。纯文案、样式和文档改动可以复用已有测试。测试分层和 golden 更新方法见[测试策略](docs/development/testing.md)。

**协议改动要先做来源对照**：改认证、读取或写入学校系统的代码之前，必须把同一操作在两个冻结参考（旧版 UBAA 和 buaa-api）中的行为逐项对比，并记录到 [`docs/protocol/`](docs/protocol/README.md)。规则见 [AGENTS.md 来源对照门禁](AGENTS.md#来源对照门禁)。这是本项目最重要的约束：上游字段、URL 和加密参数都必须有证据，不能凭经验补齐。

**测试数据**：Fixture 只保留最小的协议结构，并使用明显虚构的值。不要把学校的原始响应复制成 Fixture。

**生成文件**：FRB 生成的绑定文件只能用锁定版本的生成器更新，不要手改。

**真实账号**：普通开发不需要也不应该请求学校系统。需要用真实账号验证时，规则见 [AGENTS.md 真实账号与验收范围](AGENTS.md#真实账号与验收范围)。

## 4. 自检

提交前运行按改动选择的检查，`<基线>` 是你开始工作时的提交：

```bash
just check-plan base=<基线>      # 先看会执行哪些检查
just check-changed base=<基线>   # 执行这些检查
```

改动涉及安全、协议、并发、存储或跨语言边界时，需要完整验收（`mode=full`）。各种改动对应哪些检查，见[开发命令](docs/development/commands.md#检查选择与完成条件)。

## 5. 提交与 PR

- 用明确的路径暂存，例如 `git add crates/ubaa_core/src/foo.rs`，不要用 `git add .`。
- 暂存后运行 `just check-sensitive`，并亲自检查一遍暂存内容。根目录 `.env` 永远不要提交。
- 提交信息用中文，说明为什么改。机械移动、行为修改、生成文件刷新分开提交，方便审查；行为代码和它的测试可以放在同一个提交里。
- PR 描述写清改了什么、怎么验证的、还有什么没验证。

## 给 agent 的说明

AI agent 在本仓库工作时必须遵守 [AGENTS.md](AGENTS.md)。该文件也是安全边界、来源对照门禁和真实账号授权规则的权威出处，人类贡献者同样适用。
