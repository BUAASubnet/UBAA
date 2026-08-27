# 贡献指南

Use focused branches and conventional, reviewable commits. Every behavior change starts with a failing test and includes its contract or migration documentation update.

提交审查前请运行 `just refs` 和 `just check`。认证变更还必须通过明确的本地真实验证门禁；CI 永远不会接收真实凭据。

Fixture 必须使用明确虚构的身份以及占位 Cookie/令牌值。不得通过提交原始上游响应生成 fixture。只保留最小协议结构，并扫描暂存改动中的账号资料、凭据、Cookie、令牌和验证码内容。

未来校园功能必须置于 `ubaa-core` 的 feature/facade 边界之后。实现前先在迁移状态中记录权威旧实现和测试。宿主不得直接调用 upstream 模块。
