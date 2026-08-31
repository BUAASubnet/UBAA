# 架构概览

当前产品边界是与平台无关的 Rust Core 加 Rust CLI 宿主。`UbaaClient` 是普通聚合 facade，
负责经过校验的路由配置、带缓存的网关可达性探测、独立的 Direct/WebVPN runtime 以及一个
原子双路线会话协调器。`UbaaClient::open` 从一个带 revision 的 schema-v2 快照加载两个槽位，
不会向宿主暴露会话存储。`RouteClient` 是锁定路线的诊断/测试入口，不是普通宿主 API。每次
上游请求前都会应用 Direct 或 WebVPN URL 策略；原始传输既不自动跟随重定向，也不拥有全局
Cookie 存储。

```text
CLI / 未来绑定
        |
  稳定 facade
        |
 认证 + 功能/用户
        |
私有运行时 + 会话
        |
上游解析器和已验证 URL
        |
连接与端口（HTTP、持久化）
```

CLI 宿主只能通过 facade 访问 Core；`upstream` 解析/URL 模块为 crate-private。实际 envelope 的
JSON Schema 校验、schema-v2 聚合登录输出、参数错误 envelope、不支持交互式登录步骤的显式
拒绝、脱敏展示、带 revision 的原子双路线会话、Core 所有的 TCP 路由诊断和非交互式本地验证器
均已实现。标准和扩展业务解析器及 facade 方法均有确定性 Fixture 覆盖；当前 Direct/WebVPN/
auto 证据仍是独立的实时门禁。Flutter、MCP、服务器中继和真实写验证不属于本周期交付。
