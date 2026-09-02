# 架构概览

当前产品边界是与平台无关的 Rust Core、Rust CLI 宿主和 Flutter/FRB 六平台客户端。`UbaaClient` 是普通聚合 facade，
负责经过校验的路由配置、带缓存的网关可达性探测、独立的 Direct/WebVPN runtime 以及一个
原子双路线会话协调器。`UbaaClient::open` 从一个带 revision 的 schema-v2 快照加载两个槽位，
不会向宿主暴露会话存储。`RouteClient` 是锁定路线的诊断/测试入口，不是普通宿主 API。每次
上游请求前都会应用 Direct 或 WebVPN URL 策略；原始传输既不自动跟随重定向，也不拥有全局
Cookie 存储。

```text
CLI                  Flutter/OHOS
 |                       |
 |                 Dart domain/app/UI
 |                       |
 |                    FRB bridge
 +----------+------------+
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

当前 CLI 与 Rust bridge 的业务调用经 facade，但仍直接依赖部分 Core 公共类型，CLI 输出/退出策略也仍由
Core 暴露；结构治理阶段 04、06C 将关闭这些例外。Dart 与平台宿主只经 bridge 使用 Core，不处理 URL、
Cookie、Session、加密或上游正文；`upstream` 解析/URL 模块为 crate-private。实际 envelope 的
JSON Schema 校验、schema-v2 聚合登录输出、参数错误 envelope、不支持交互式登录步骤的显式
拒绝、脱敏展示、带 revision 的原子双路线会话、Core 所有的 TCP 路由诊断和非交互式本地验证器
均已实现。Flutter 侧的 typed bridge、共享 domain/app/UI、十二项读取页面、十项写入确认和无签名
六平台宿主也已实现并有确定性证据。Direct/WebVPN 的真实 Core-live 只读验证、无签名平台构建、
实体设备、签名发布和真实写入是彼此独立的证据层级；当前不包含服务器中继，真实写入仍须逐操作授权。
