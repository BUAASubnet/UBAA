# ADR 0002：Serde 合同与可注入原始传输

日期：2026-08-17

状态：已接受

Core 合同使用 `serde` 和 `serde_json`，因为冻结的用户中心协议是 JSON `code/data` 包装，CLI
必须暴露带版本的 JSON 信封。Rust 字段名保持惯用写法，通过显式 camelCase 重命名维持 CLI 合同，
并保留 `schoolid` 作为旧版 DTO 的兼容别名。

认证代码使用可注入的原始 `HttpTransport`，不使用隐式处理重定向或 Cookie 的客户端。这样测试可以
断言精确请求 URL 和响应形状，同时由 Core 负责重定向策略、Cookie 过滤和会话失效。`async-trait`
使端口对 CLI 和确定性 Mock 传输保持对象安全；生产传输在连接阶段接入。
