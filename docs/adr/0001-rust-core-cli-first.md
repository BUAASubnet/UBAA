# ADR 0001：优先采用 Rust Core 与 CLI

日期：2026-08-17

状态：已接受

UBAA 2 将协议正确性放在与平台无关的 Rust Core 中，并使用 Rust CLI 作为首个宿主和集成验证器。
KMP 应用和 Ktor 中继仅作为冻结参考，不作为运行时依赖。这样可确保未来各宿主的 Direct/WebVPN
认证、Cookie 处理、重定向、解析和稳定错误保持一致。

Flutter 绑定、MCP、服务器中继和业务 API 延后实现。宿主只消费稳定的 facade DTO，不得深入上游实现模块。
